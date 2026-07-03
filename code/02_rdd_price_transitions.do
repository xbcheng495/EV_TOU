* RDiT and Donut RD analysis around TOU price-transition thresholds.
* Run from the repository root.

clear all
set more off
set scheme s1color

global DATA    "data"
global FIGURES "outputs/figures"
global TABLES  "outputs/tables"

import delimited "${DATA}/transition_panel.csv", clear varnames(1)

destring total_kwh_per_minute relative_minute transition_type, replace force
drop if missing(total_kwh_per_minute, relative_minute, transition_type)

gen double running_time = relative_minute
gen byte post = running_time >= 0
gen double post_x_time = post * running_time
gen double running_time_sq = running_time^2
gen double post_x_time_sq = post * running_time_sq

capture confirm numeric variable date_id
if _rc {
    gen date_id = date(date, "YMD")
    format date_id %td
}

capture confirm numeric variable station_id
if _rc {
    encode station_name, gen(station_id)
}

capture confirm numeric variable hour_id
if _rc {
    gen hour_id = floor((running_time + 30) / 60)
}

label define transition_label 1 "High to low" 2 "Low to high", replace
label values transition_type transition_label

local outcomes "total_kwh_per_minute"

foreach t in 1 2 {
    preserve
        keep if transition_type == `t'

        local tag = cond(`t' == 1, "high_to_low", "low_to_high")

        rdrobust total_kwh_per_minute running_time, c(0) p(1)
        estimates store rd_linear_`t'

        rdrobust total_kwh_per_minute running_time, c(0) p(2)
        estimates store rd_quadratic_`t'

        reghdfe total_kwh_per_minute post c.running_time c.post_x_time, ///
            absorb(station_id date_id) vce(cluster station_id)
        estimates store ols_fe_linear_`t'

        reghdfe total_kwh_per_minute post c.running_time c.post_x_time ///
            c.running_time_sq c.post_x_time_sq, ///
            absorb(station_id date_id) vce(cluster station_id)
        estimates store ols_fe_quadratic_`t'

        reghdfe total_kwh_per_minute post c.running_time c.post_x_time ///
            c.running_time_sq c.post_x_time_sq if abs(running_time) > 5, ///
            absorb(station_id date_id) vce(cluster station_id)
        estimates store donut_5min_`t'

        reghdfe total_kwh_per_minute post c.running_time c.post_x_time ///
            c.running_time_sq c.post_x_time_sq if abs(running_time) > 10, ///
            absorb(station_id date_id) vce(cluster station_id)
        estimates store donut_10min_`t'

        twoway ///
            (scatter total_kwh_per_minute running_time, msize(vsmall) mcolor(gs10)) ///
            (lfit total_kwh_per_minute running_time if running_time < 0, lcolor(navy)) ///
            (lfit total_kwh_per_minute running_time if running_time >= 0, lcolor(maroon)), ///
            xline(0, lpattern(dash) lcolor(black)) ///
            xtitle("Minutes relative to tariff transition") ///
            ytitle("Charging load per station-minute (kWh)") ///
            legend(off)
        graph export "${FIGURES}/rdd_`tag'.pdf", replace as(pdf)

        esttab ols_fe_linear_`t' ols_fe_quadratic_`t' donut_5min_`t' donut_10min_`t' ///
            using "${TABLES}/rdd_`tag'.rtf", replace ///
            keep(post running_time post_x_time running_time_sq post_x_time_sq) ///
            b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
            title("RDiT estimates: `tag'")
    restore
}

