clear all
set more off
set scheme s1color

import delimited "D:\transition_data_selective_filtered.csv", clear

destring total_ele_amount_per_min relative_minute transition_type, replace force

global Y "total_ele_amount_per_min"
global X "relative_minute"

gen date_num = date(date, "YMD")
gen dow = dow(date_num)      
gen moy = month(date_num)    
encode charstation_name, gen(station_id)

quietly tab dow, gen(dum_dow_)
quietly tab moy, gen(dum_moy_)
drop dum_dow_1 dum_moy_1

label define type_lab 1 "High_to_Low" 2 "Low_to_High"
label values transition_type type_lab

levelsof transition_type, local(types)

foreach t in `types' {
    display " "
    display ">>> Processing Transition Type: `t' <<<"
    
    preserve
    keep if transition_type == `t'
    tempfile current_full_data
    save `current_full_data'
    
    display "--- Generating Enhanced Scatter Plot with Fit Lines ---"
    
    * set seed 12345 
    * sample 10000000, count 
    local title_text : label type_lab `t'

    rdplot $Y $X, c(0) p(2) kernel(triangular) graph_options(title("RD Plot: `title_text'") ///
        ytitle("Charging Quantity") xtitle("Minutes") graphregion(color(white)))
    graph export "RDplot_Standard_`t'.pdf", replace
    */

    use `current_full_data', clear
    
    * Model 1: NP-Linear
    rdrobust $Y $X, c(0) p(1) kernel(triangular) ///
        vce(cluster relative_minute) covs(dum_dow_* dum_moy_*)
    eststo model_`t'_rd1
    
    * Model 2: NP-Quadratic
    rdrobust $Y $X, c(0) p(2) kernel(triangular) ///
        vce(cluster relative_minute) covs(dum_dow_* dum_moy_*)
    eststo model_`t'_rd2
    
    gen D = ($X >= 0)
    gen X_D = $X * D
    gen X_sq = $X^2
    gen X_sq_D = X_sq * D
    
    reg $Y D $X X_sq X_D X_sq_D i.dow i.moy, cluster($X)
    eststo model_`t'_ols_base
    
    * Model 4: OLS FE
    reghdfe $Y D $X X_sq X_D X_sq_D, absorb(station_id dow moy) vce(cluster $X)
    eststo model_`t'_ols_fe
    
    display "--- Performing Manipulation Test ---"
    
    rddensity $X, c(0) plot graph_opt( ///
        title("Manipulation Testing Plot (`title_text')") ///
        ytitle("Density") ///
        xtitle("Minutes Relative to Transition") ///
        ylabel(0(0.01)0.05) /// 
        yscale(range(0 0.05)) /// 
        graphregion(color(white)) ///
        legend(off) ///
    )
    
    graph export "Density_Test_Type_`t'.pdf", replace
    
    restore
}

esttab model_1_rd1 model_1_rd2 model_1_ols_base model_1_ols_fe ///
    using "RDD_Results_HighToLow.rtf", ///
    replace title("RDD Results: High to Low (Price Drop)") ///
    cells(b(star fmt(4)) se(par fmt(4))) ///
    mtitles("RD-Lin" "RD-Quad" "OLS-Quad" "OLS-FE-Quad") ///
    label star(* 0.1 ** 0.05 *** 0.01) ///
    stats(N r2_a, labels("Observations" "Adj. R-squared"))

esttab model_2_rd1 model_2_rd2 model_2_ols_base model_2_ols_fe ///
    using "RDD_Results_LowToHigh.rtf", ///
    replace title("RDD Results: Low to High (Price Rise)") ///
    cells(b(star fmt(4)) se(par fmt(4))) ///
    mtitles("RD-Lin" "RD-Quad" "OLS-Quad" "OLS-FE-Quad") ///
    label star(* 0.1 ** 0.05 *** 0.01) ///
    stats(N r2_a, labels("Observations" "Adj. R-squared"))

display "Done! All graphs and tables generated."
