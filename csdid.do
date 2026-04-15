* ==============================================================================
* 电动汽车充电行为 TOU 政策评估实证代码整合版 (湖北 & 四川)
* 终极修复版：修正文本竖排参数 (orientation(vertical)) + 国际标准术语
* ==============================================================================
clear all
set more off

disp ">>> 正在读取原始 CSV 数据，请稍候..."
import delimited "D:\Data_cxb\电动汽车充电订单数据\did_panel_station_hourly.csv", clear

encode charstation_name, gen(station_id)
gen date_num = date(date, "YMD")
egen station_hour_fe = group(station_id hour)
egen date_hour_fe = group(date_num hour)

* 统一准备 X 轴刻度宏 (0 到 23，并额外增加 24 点闭环)
local xlab_str ""
forvalues i = 0/23 {
    local label_id = `i' + 1
    local xlab_str "`xlab_str' `label_id' "`i'" "
}
local xlab_str "`xlab_str' 25 `"24"'"

tempfile fulldata
save `fulldata', replace

* ==============================================================================
* 模块一：湖北省 (2024-05 政策变更)
* ==============================================================================
disp ">>> 开始处理湖北省数据..."
use `fulldata', clear

local target_prov "湖北省"
local event_month "2024-05"
local window_start "2024-03"  
local window_end   "2024-06"  
local control_pool "江苏省 上海市 广东省 山东省 河北省 天津市 山西省 海南省 陕西省 甘肃省 青海省 宁夏回族自治区 新疆维吾尔自治区 西藏自治区 辽宁省 吉林省 黑龙江省 内蒙古自治区 重庆市"

gen to_keep = 0
replace to_keep = 1 if province == "`target_prov'"
foreach p of local control_pool {
    replace to_keep = 1 if province == "`p'"
}
keep if to_keep == 1
keep if ym >= "`window_start'" & ym <= "`window_end'"

gen treated = (province == "`target_prov'")
gen post = (ym >= "`event_month'")
gen did = treated * post

preserve
keep if post == 0
gen plot_var = treated
reghdfe hourly_kwh c.plot_var#i.hour, absorb(date_hour_fe) vce(cluster station_id)
est store pre_model
restore

preserve
keep if post == 1
gen plot_var = treated
reghdfe hourly_kwh c.plot_var#i.hour, absorb(date_hour_fe) vce(cluster station_id)
est store post_model
restore

preserve
gen plot_var = did
reghdfe hourly_kwh c.plot_var#i.hour, absorb(station_hour_fe date_hour_fe) vce(cluster station_id)
est store did_model
restore

* ------------------------------------------
* 湖北省核心绘图
* ------------------------------------------
#delimit ;
coefplot 
    (pre_model, 
        offset(0.35)  
        label("Pre-policy Gap") 
        recast(connected) lcolor(ebblue%70) mcolor(ebblue%70) msymbol(Oh) lpattern(dash)
        ciopts(recast(rspike) color(ebblue%40) lwidth(thin)) )
        
    (post_model, 
        offset(0.65)  
        label("Post-policy Gap") 
        recast(connected) lcolor(cranberry%70) mcolor(cranberry%70) msymbol(Th) lpattern(dash)
        ciopts(recast(rspike) color(cranberry%40) lwidth(thin)) )
        
    (did_model, 
        offset(0.5)   
        label("Treatment Effect (DiD)") 
        recast(connected) lcolor(black) mcolor(black) lwidth(medthick) msymbol(O)
        ciopts(recast(rspike) color(gs6) lwidth(medthick)) ),
        
    keep(*.hour#c.plot_var) 
    vertical 
    
    title("Hubei: Evaluation of TOU change (May 2024 Policy)")
    ytitle("Difference / Treatment Effect (kWh)")
    xtitle("Hour of Day")
    graphregion(color(white))
    plotregion(margin(t=0 b=0))
	xsize(5.5) ysize(4.5)
    
    yline(0, lcolor(black) lpattern(solid) lwidth(medthick))
    
    yscale(range(-300 500)) 
    ylabel(-300(100)500, angle(0) nogrid)
    
    xscale(range(1 25))
    xlabel(`xlab_str', nogrid)
    legend(pos(6) cols(3) region(lwidth(none) fcolor(none)))
    
    /* 分隔虚线 */
    xline(13 15 19 24, lcolor(gs10) lpattern(shortdash) lwidth(thin))
    
    /* -------------------------------------------------------------
       【核心修复】：使用 orientation(vertical) 强制竖排
       ------------------------------------------------------------- */
    text(380 7.5 "Valley->Shoulder", size(vsmall) color(cranberry) orientation(vertical))
    text(380 11.5 "Peak->Shoulder", size(vsmall) color(ebblue) orientation(vertical))
    text(380 14 "Peak->Valley", size(vsmall) color(ebblue) orientation(vertical))
    text(380 15.5 "Peak->Shoulder", size(vsmall) color(ebblue) orientation(vertical))
    text(380 18 "Shoulder->Peak", size(vsmall) color(cranberry) orientation(vertical))
    text(380 20 "Shoulder->Super-peak", size(vsmall) color(cranberry) orientation(vertical))
    text(380 22 "Super-peak->Peak", size(vsmall) color(ebblue) orientation(vertical))
    text(380 23.5 "Shoulder->Peak", size(vsmall) color(cranberry) orientation(vertical))
    text(380 24.5 "Valley->Peak", size(vsmall) color(cranberry) orientation(vertical))
    
    addplot(
        (scatteri -300 7 -300 8 500 8 500 7, recast(area) fcolor("239 138 98%15") lwidth(none)) 
        (scatteri -300 10 -300 16 500 16 500 10, recast(area) fcolor("103 169 207%15") lwidth(none)) 
        (scatteri -300 17 -300 21 500 21 500 17, recast(area) fcolor("239 138 98%15") lwidth(none)) 
        (scatteri -300 21 -300 23 500 23 500 21, recast(area) fcolor("103 169 207%15") lwidth(none)) 
        (scatteri -300 23 -300 25 500 25 500 23, recast(area) fcolor("239 138 98%15") lwidth(none)) 
    )
;
#delimit cr
graph export "Hubei_TOU_Evaluation_Final.pdf", as(pdf) replace


* ==============================================================================
* 模块二：四川省 (2023-06 政策变更)
* ==============================================================================
disp ">>> 开始处理四川省数据..."
use `fulldata', clear

local target_prov "四川省"
local event_month "2023-06"
local window_start "2023-03"  
local window_end   "2023-09"  
local control_pool "江苏省 上海市 广东省 山东省 河北省 天津市 山西省 海南省 陕西省 甘肃省 青海省 宁夏回族自治区 新疆维吾尔自治区 西藏自治区 辽宁省 吉林省 黑龙江省 内蒙古自治区 重庆市"

gen to_keep = 0
replace to_keep = 1 if province == "`target_prov'"
foreach p of local control_pool {
    replace to_keep = 1 if province == "`p'"
}
keep if to_keep == 1
keep if ym >= "`window_start'" & ym <= "`window_end'"

gen treated = (province == "`target_prov'")
gen post = (ym >= "`event_month'")
gen did = treated * post

preserve
keep if post == 0
gen plot_var = treated
reghdfe hourly_kwh c.plot_var#i.hour, absorb(date_hour_fe) vce(cluster station_id)
est store pre_model
restore

preserve
keep if post == 1
gen plot_var = treated
reghdfe hourly_kwh c.plot_var#i.hour, absorb(date_hour_fe) vce(cluster station_id)
est store post_model
restore

preserve
gen plot_var = did
reghdfe hourly_kwh c.plot_var#i.hour, absorb(station_hour_fe date_hour_fe) vce(cluster station_id)
est store did_model
restore

* ------------------------------------------
* 四川省核心绘图
* ------------------------------------------
#delimit ;
coefplot 
    (pre_model, 
        offset(0.35)
        label("Pre-policy Gap") 
        recast(connected) lcolor(ebblue%70) mcolor(ebblue%70) msymbol(Oh) lpattern(dash)
        ciopts(recast(rspike) color(ebblue%40) lwidth(thin)) )
        
    (post_model, 
        offset(0.65)
        label("Post-policy Gap") 
        recast(connected) lcolor(cranberry%70) mcolor(cranberry%70) msymbol(Th) lpattern(dash)
        ciopts(recast(rspike) color(cranberry%40) lwidth(thin)) )
        
    (did_model, 
        offset(0.5)
        label("Treatment Effect (DiD)") 
        recast(connected) lcolor(black) mcolor(black) lwidth(medthick) msymbol(O)
        ciopts(recast(rspike) color(gs6) lwidth(medthick)) ),
        
    keep(*.hour#c.plot_var) 
    vertical 
    
    title("Sichuan: Evaluation of TOU change (June 2023 Policy)")
    ytitle("Difference / Treatment Effect (kWh)")
    xtitle("Hour of Day")
    graphregion(color(white))
    plotregion(margin(t=0 b=0))
	xsize(5.5) ysize(4.5)
    
    yline(0, lcolor(black) lpattern(solid) lwidth(medthick))
    
    yscale(range(-100 300)) 
    ylabel(-100(50)300, angle(0) nogrid)
    
    xscale(range(1 25))
    xlabel(`xlab_str', nogrid)
    legend(pos(6) cols(3) region(lwidth(none) fcolor(none)))
    
    /* 区分 15-16 与 16-18 */
    
    /* -------------------------------------------------------------
       【核心修复】：使用 orientation(vertical) 强制竖排
       ------------------------------------------------------------- */
    text(220 11.5 "Shoulder->Peak", size(vsmall) color(cranberry) orientation(vertical))
    text(220 15.5 "Peak->Shoulder", size(vsmall) color(ebblue) orientation(vertical))
    
    addplot(
        (scatteri -100 11 -100 12 300 12 300 11, recast(area) fcolor("239 138 98%15") lwidth(none)) 
        (scatteri -100 15 -100 16 300 16 300 15, recast(area) fcolor("103 169 207%15") lwidth(none)) 
    )
;
#delimit cr
graph export "Sichuan_TOU_Evaluation_Final.pdf", as(pdf) replace

disp ">>> 全部任务执行完毕！请查收您的顶级图表。"
