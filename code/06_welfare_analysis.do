* Welfare and time-cost decomposition.
* Run from the repository root after `04_counterfactual_flat_pricing.do`.

clear all
set more off

global DATA    "data"
global FIGURES "outputs/figures"
global TABLES  "outputs/tables"

use "${DATA}/counterfactual_predictions.dta", clear
estimates use "${DATA}/ppml_expected_kwh_model.ster"

drop if missing(expected_price, flat_price_station, expected_kwh_tou, expected_kwh_flat)

capture drop current_elasticity
gen double current_elasticity = _b[ln_price]
capture replace current_elasticity = current_elasticity + _b[c.ln_price#c.begin_soc] * begin_soc
capture replace current_elasticity = current_elasticity + _b[1.is_fast_charge#c.ln_price] if is_fast_charge == 1
capture replace current_elasticity = current_elasticity + _b[1.zone_id#c.ln_price] if zone_id == 1
capture replace current_elasticity = current_elasticity + _b[2.zone_id#c.ln_price] if zone_id == 2
capture replace current_elasticity = current_elasticity + _b[3.zone_id#c.ln_price] if zone_id == 3
capture replace current_elasticity = current_elasticity + _b[4.zone_id#c.ln_price] if zone_id == 4

gen double price_change = expected_price - flat_price_station
gen double demand_change = expected_kwh_tou - expected_kwh_flat

* Mechanical price effect: holding predicted flat-rate demand fixed.
gen double mechanical_price_effect = - price_change * expected_kwh_flat

* Quantity-response effect: welfare contribution from total demand adjustment.
gen double quantity_response_effect = - price_change * demand_change

* Timing effect: residual welfare contribution from shifting charging across time.
gen double total_welfare_change = mechanical_price_effect + quantity_response_effect
gen double timing_response_effect = total_welfare_change - mechanical_price_effect - quantity_response_effect

* Approximate time inconvenience cost. If saved time fixed effects exist, they
* are converted into monetary units using the marginal price coefficient.
capture confirm variable province_time_fe
if !_rc {
    gen double time_cost_index = -province_time_fe / abs(current_elasticity)
    bysort alt_index: egen double time_cost_hourly = mean(time_cost_index)
}
else {
    gen double time_cost_hourly = .
}

preserve
    collapse (mean) mechanical_price_effect quantity_response_effect ///
        timing_response_effect total_welfare_change time_cost_hourly, by(alt_index)

    twoway ///
        (bar mechanical_price_effect alt_index, color(navy%45)) ///
        (bar quantity_response_effect alt_index, color(maroon%45)) ///
        (bar timing_response_effect alt_index, color(orange%45)) ///
        (line total_welfare_change alt_index, lcolor(black) lwidth(medthick)), ///
        xtitle("Half-hour of day") ///
        ytitle("Welfare change") ///
        legend(order(1 "Mechanical price effect" 2 "Quantity response" ///
                     3 "Timing response" 4 "Total") rows(2))
    graph export "${FIGURES}/welfare_decomposition.pdf", replace as(pdf)

    export delimited using "${TABLES}/welfare_decomposition_by_time.csv", replace
restore

preserve
    collapse (mean) total_welfare_change mechanical_price_effect ///
        quantity_response_effect timing_response_effect, by(province)
    export delimited using "${TABLES}/province_welfare_decomposition.csv", replace
restore

