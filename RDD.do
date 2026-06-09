clear all
set more off
set scheme s1color

* =========================================================================
* 1. 数据导入与预处理
* =========================================================================

import delimited "D:\transition_data_selective_filtered.csv", clear

* 强制转换为数值
destring total_ele_amount_per_min relative_minute transition_type, replace force

global Y "total_ele_amount_per_min"
global X "relative_minute"

* --- 生成固定效应变量 ---
gen date_num = date(date, "YMD")
gen dow = dow(date_num)      
gen moy = month(date_num)    
encode charstation_name, gen(station_id)

* 手动生成虚拟变量 (解决 rdrobust 报错问题)
quietly tab dow, gen(dum_dow_)
quietly tab moy, gen(dum_moy_)
drop dum_dow_1 dum_moy_1

* 参数化变量准备
gen D = ($X >= 0)
gen X_D = $X * D
gen X_sq = $X^2
gen X_sq_D = X_sq * D

* =========================================================================
* 2. 分组 RDD 分析
* =========================================================================

label define type_lab 1 "High_to_Low" 2 "Low_to_High"
label values transition_type type_lab

levelsof transition_type, local(types)

foreach t in `types' {
    display " "
    display "==================================================="
    display ">>> Processing Transition Type: `t' <<<"
    display "==================================================="
    
    * 每次循环开始，保存一份全局数据状态
    preserve
    
    keep if transition_type == `t'
    tempfile current_full_data
    save `current_full_data', replace
    
    * 设置图表标题
    local title_text : label type_lab `t'
    
    * -------------------------------------------------------
    * [Step 1] 可视化检查: rdplot 原始散点 + 二次拟合线
    * -------------------------------------------------------
    display "--- Generating RD Plot ---"
    
    * 抽样 10 万条画图（不会卡死，且足够平滑）
    set seed 12345 
    sample 100000, count 

    * 使用 numbins(30 30) 强制修复离散时间变量引发的 bin 算法崩溃
    rdplot $Y $X, c(0) p(2) numbins(30 30) kernel(triangular) ///
        graph_options(title("RD Plot: `title_text'") ///
        ytitle("Average Charging Amount (kWh/min)") ///
        xtitle("Minutes Relative to Transition") ///
        graphregion(color(white)))
    graph export "RDplot_Type_`t'.pdf", replace
    
    * -------------------------------------------------------
    * [Step 2] 回归模型 (5 Models)
    * -------------------------------------------------------
    * 画完图后，把抽样破坏的数据重新读回来！
    use `current_full_data', clear
    
    * Model 1: NP-Linear (非参数局部线性, rdrobust)
    rdrobust $Y $X, c(0) p(1) kernel(triangular) ///
        vce(cluster $X) covs(dum_dow_* dum_moy_*)
    eststo model_`t'_rd1
    
    * Model 2: NP-Quadratic (非参数局部二次, rdrobust)
    rdrobust $Y $X, c(0) p(2) kernel(triangular) ///
        vce(cluster $X) covs(dum_dow_* dum_moy_*)
    eststo model_`t'_rd2
    
    * Model 3: OLS Base (全局参数化二次多项式)
    reg $Y D $X X_sq X_D X_sq_D i.dow i.moy, cluster($X)
    eststo model_`t'_ols_base
    
    * Model 4: OLS FE (全局参数化二次多项式 + 高维固定效应)
    reghdfe $Y D $X X_sq X_D X_sq_D, absorb(station_id dow moy) vce(cluster $X)
    eststo model_`t'_ols_fe
    
    * Model 5: Donut RDD (甜甜圈断点)
    * 【核心修复】：不用 preserve/drop 导致报错了，直接用 if !inrange 条件过滤！
    reghdfe $Y D $X X_sq X_D X_sq_D if !inrange($X, -5, 4), absorb(station_id dow moy) vce(cluster $X)
    eststo model_`t'_donut
    
    * -------------------------------------------------------
    * [Step 3] 连续性检验 (Density Test / McCrary Test)
    * -------------------------------------------------------
    display "--- Performing Manipulation Density Test ---"
    
    * 移除了定死的 y 轴范围，防止画出空白图
    rddensity $X, c(0) plot graph_opt( ///
        title("Manipulation Density Test: `title_text'") ///
        ytitle("Density of Charging Activity") ///
        xtitle("Minutes Relative to Transition") ///
        graphregion(color(white)) ///
        legend(off) ///
    )
    graph export "Density_Test_Type_`t'.pdf", replace
    
    * 恢复最开始的原始全集数据，准备进入下一个 Transition Type 循环
    restore
}

* =========================================================================
* 3. 结果汇总输出 (输出为 Excel/Word 可读的 rtf 格式)
* =========================================================================

* Type 1: High to Low
esttab model_1_rd1 model_1_rd2 model_1_ols_base model_1_ols_fe model_1_donut ///
    using "RDD_Results_HighToLow.rtf", ///
    replace title("RDD Results: High to Low (Price Drop)") ///
    cells(b(star fmt(4)) se(par fmt(4))) ///
    mtitles("RD-Lin" "RD-Quad" "OLS-Quad" "OLS-FE-Quad" "Donut-FE") ///
    label star(* 0.1 ** 0.05 *** 0.01) ///
    stats(N r2_a, labels("Observations" "Adj. R-squared"))

* Type 2: Low to High
esttab model_2_rd1 model_2_rd2 model_2_ols_base model_2_ols_fe model_2_donut ///
    using "RDD_Results_LowToHigh.rtf", ///
    replace title("RDD Results: Low to High (Price Rise)") ///
    cells(b(star fmt(4)) se(par fmt(4))) ///
    mtitles("RD-Lin" "RD-Quad" "OLS-Quad" "OLS-FE-Quad" "Donut-FE") ///
    label star(* 0.1 ** 0.05 *** 0.01) ///
    stats(N r2_a, labels("Observations" "Adj. R-squared"))

display "==================================================="
display "✅ Done! 所有模型跑完，图表和回归表格已保存。"
display "==================================================="
