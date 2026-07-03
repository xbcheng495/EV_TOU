* Construct a revenue-neutral flat-rate counterfactual.
* Run from the repository root after `03_elasticity_ols_ppml.do`.

clear all
set more off

global DATA    "data"
global FIGURES "outputs/figures"
global TABLES  "outputs/tables"

use "${DATA}/prediction_panel.dta", clear
estimates use "${DATA}/ppml_expected_kwh_model.ster"

drop if missing(expected_price, ele_amount, choice, station_id)

gen double realized_revenue = ele_amount * expected_price if choice == 1
gen double realized_demand  = ele_amount if choice == 1

bysort station_id: egen double station_revenue = total(realized_revenue)
bysort station_id: egen double station_demand  = total(realized_demand)
gen double flat_price_station = station_revenue / station_demand

drop realized_revenue realized_demand station_revenue station_demand

capture drop expected_kwh_tou
predict expected_kwh_tou, mu

tempvar price_original ln_price_original
gen double `price_original' = expected_price
gen double `ln_price_original' = ln_price

replace expected_price = flat_price_station
replace ln_price = ln(expected_price)
predict expected_kwh_flat, mu

replace expected_price = `price_original'
replace ln_price = `ln_price_original'

gen double actual_kwh_chosen = ele_amount if choice == 1

preserve
    keep if choice == 1
    quietly summarize alt_index, meanonly
    if r(min) == 1 {
        gen int hour = floor((alt_index - 1) / 2)
    }
    else {
        gen int hour = floor(alt_index / 2)
    }
    collapse (mean) tou_price=expected_price flat_price=flat_price_station, by(hour)
    twoway ///
        (line tou_price hour, lcolor(navy) lwidth(medthick)) ///
        (line flat_price hour, lcolor(maroon) lpattern(dash) lwidth(medthick)), ///
        xtitle("Hour of day") ytitle("Electricity price") ///
        legend(order(1 "Actual TOU" 2 "Revenue-neutral flat rate") rows(1))
    graph export "${FIGURES}/national_average_price_curve.pdf", replace as(pdf)
    export delimited using "${TABLES}/national_average_price_curve.csv", replace
restore

save "${DATA}/counterfactual_predictions.dta", replace
