* OLS and PPML elasticity estimation.
* Run from the repository root.

clear all
set more off
set maxvar 32767

global DATA    "data"
global FIGURES "outputs/figures"
global TABLES  "outputs/tables"

use "${DATA}/charging_choice_panel.dta", clear

drop if missing(id, choice, expected_price, ele_amount, alt_index)
drop if expected_price <= 0

capture confirm numeric variable province_id
if _rc encode province, gen(province_id)

capture confirm numeric variable station_id
if _rc encode station_name, gen(station_id)

capture confirm numeric variable zone_id
if _rc encode zone_type, gen(zone_id)

capture confirm numeric variable date_id
if _rc {
    gen date_id = date(date, "YMD")
    format date_id %td
}

capture confirm numeric variable temp_bin
if _rc {
    gen byte temp_bin = .
    replace temp_bin = 1 if temperature < 0
    replace temp_bin = 2 if temperature >= 0  & temperature < 5
    replace temp_bin = 3 if temperature >= 5  & temperature < 10
    replace temp_bin = 4 if temperature >= 10 & temperature < 15
    replace temp_bin = 5 if temperature >= 15 & temperature < 20
    replace temp_bin = 6 if temperature >= 20 & temperature < 25
    replace temp_bin = 7 if temperature >= 25 & temperature < 30
    replace temp_bin = 8 if temperature >= 30 & temperature < .
}

gen double ln_price = ln(expected_price)
gen double actual_kwh = ele_amount * choice
gen double ln_session_kwh = ln(ele_amount) if choice == 1 & ele_amount > 0

* Intensive margin: charging quantity conditional on observed charging.
reghdfe ln_session_kwh c.ln_price if choice == 1, ///
    absorb(station_id date_id alt_index) vce(cluster station_id)
estimates store ols_intensive_base

reghdfe ln_session_kwh c.ln_price##c.begin_soc ///
    i.is_fast_charge#c.ln_price i.zone_id#c.ln_price if choice == 1, ///
    absorb(station_id date_id alt_index) vce(cluster station_id)
estimates store ols_intensive_heterogeneity

* Extensive margin and expected physical load: PPML on order-alternative kWh.
ppmlhdfe actual_kwh c.ln_price##c.begin_soc ///
    i.is_fast_charge#c.ln_price i.zone_id#c.ln_price, ///
    absorb(order_fe=id province_time_fe=province_id#alt_index ///
           temperature_time_fe=temp_bin#alt_index, savefe) ///
    vce(cluster id)
estimates store ppml_expected_kwh

predict expected_kwh_tou, mu

esttab ols_intensive_base ols_intensive_heterogeneity ppml_expected_kwh ///
    using "${TABLES}/elasticity_estimates.rtf", replace ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    title("OLS and PPML price-response estimates")

estimates save "${DATA}/ppml_expected_kwh_model.ster", replace
save "${DATA}/prediction_panel.dta", replace

