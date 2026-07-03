* Grid ramping shock, renewable mismatch, EGA, and carbon-emission outcomes.
* Run from the repository root after `04_counterfactual_flat_pricing.do`.

clear all
set more off

global DATA    "data"
global FIGURES "outputs/figures"
global TABLES  "outputs/tables"

use "${DATA}/counterfactual_predictions.dta", clear

capture confirm variable province
if _rc {
    capture confirm variable province_id
    if !_rc tostring province_id, gen(province)
}

capture confirm string variable province
if _rc {
    tostring province, replace force
}

drop if missing(province, station_id, date_id, alt_index)
gen int halfhour = alt_index
quietly summarize halfhour, meanonly
if r(min) == 1 {
    gen int hour = floor((halfhour - 1) / 2)
}
else {
    gen int hour = floor(halfhour / 2)
}

collapse ///
    (sum) load_tou=expected_kwh_tou load_flat=expected_kwh_flat actual_load=actual_kwh_chosen ///
    (count) n_alternatives=id, ///
    by(province station_id date_id halfhour hour)

bysort province station_id date_id (halfhour): gen double ramp_tou = load_tou - load_tou[_n-1]
bysort province station_id date_id (halfhour): gen double ramp_flat = load_flat - load_flat[_n-1]
replace ramp_tou = . if halfhour == 0
replace ramp_flat = . if halfhour == 0

save "${DATA}/station_halfhour_loads.dta", replace

preserve
    collapse (mean) load_tou load_flat actual_load ramp_tou ramp_flat, by(halfhour)
    twoway ///
        (bar ramp_tou halfhour, color(navy%35) yaxis(1)) ///
        (bar ramp_flat halfhour, color(maroon%30) yaxis(1)) ///
        (line load_tou halfhour, lcolor(navy) yaxis(2)) ///
        (line load_flat halfhour, lcolor(maroon) lpattern(dash) yaxis(2)), ///
        xtitle("Half-hour of day") ///
        ytitle("Ramping shock (kWh / half-hour)", axis(1)) ///
        ytitle("Charging load (kWh)", axis(2)) ///
        legend(order(1 "TOU ramp" 2 "Flat ramp" 3 "TOU load" 4 "Flat load") rows(2))
    graph export "${FIGURES}/load_and_ramping_shocks.pdf", replace as(pdf)
restore

* Merge hourly renewable profiles.
preserve
    import delimited "${DATA}/renewable_hourly_profiles.csv", clear varnames(1)
    keep province hour renewable_cf wind_cf solar_cf
    duplicates drop province hour, force
    save "${DATA}/_renewable_hourly_profiles_tmp.dta", replace
restore

merge m:1 province hour using "${DATA}/_renewable_hourly_profiles_tmp.dta", nogen keep(match master)

* Merge hourly average emission factors.
preserve
    import delimited "${DATA}/hourly_emission_factors.csv", clear varnames(1)
    keep province hour emission_factor_kg_per_kwh
    duplicates drop province hour, force
    save "${DATA}/_hourly_emission_factors_tmp.dta", replace
restore

merge m:1 province hour using "${DATA}/_hourly_emission_factors_tmp.dta", nogen keep(match master)

gen double ega_tou = load_tou * renewable_cf
gen double ega_flat = load_flat * renewable_cf
gen double co2_tou = load_tou * emission_factor_kg_per_kwh
gen double co2_flat = load_flat * emission_factor_kg_per_kwh

preserve
    collapse (sum) load_tou load_flat ega_tou ega_flat co2_tou co2_flat ///
        (mean) renewable_cf emission_factor_kg_per_kwh, by(province station_id date_id)

    collapse (mean) load_tou load_flat ega_tou ega_flat co2_tou co2_flat, by(province)

    gen double delta_load = load_tou - load_flat
    gen double delta_ega = ega_tou - ega_flat
    gen double delta_co2 = co2_tou - co2_flat

    order province load_tou load_flat delta_load ega_tou ega_flat delta_ega co2_tou co2_flat delta_co2
    export delimited using "${TABLES}/province_grid_renewable_emissions.csv", replace
restore

preserve
    collapse (sum) load_tou load_flat renewable_supply=renewable_cf, by(province hour)

    tempfile correlations
    postfile corr_handle str40 province double corr_tou corr_flat using `correlations', replace

    levelsof province, local(provinces)
    foreach p of local provinces {
        quietly corr load_tou renewable_supply if province == "`p'"
        local tou_corr = r(rho)

        quietly corr load_flat renewable_supply if province == "`p'"
        local flat_corr = r(rho)

        post corr_handle ("`p'") (`tou_corr') (`flat_corr')
    }

    postclose corr_handle
    use `correlations', clear
    gen double corr_change = corr_tou - corr_flat
    export delimited using "${TABLES}/renewable_mismatch_correlations.csv", replace
restore

preserve
    collapse (mean) load_tou load_flat renewable_cf, by(hour)
    twoway ///
        (area renewable_cf hour, color(gs12) yaxis(2)) ///
        (line load_tou hour, lcolor(navy) lwidth(medthick) yaxis(1)) ///
        (line load_flat hour, lcolor(maroon) lpattern(dash) lwidth(medthick) yaxis(1)), ///
        xtitle("Hour of day") ///
        ytitle("Charging load", axis(1)) ///
        ytitle("Renewable capacity factor", axis(2)) ///
        legend(order(2 "TOU load" 3 "Flat load" 1 "Renewable supply") rows(1))
    graph export "${FIGURES}/renewable_mismatch_load_profiles.pdf", replace as(pdf)
restore

erase "${DATA}/_renewable_hourly_profiles_tmp.dta"
erase "${DATA}/_hourly_emission_factors_tmp.dta"
