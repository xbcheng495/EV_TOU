* ==========================================
* 模块化实证：湖北省 (2024-05 政策变更)
* ==========================================
clear all
import delimited "D:\Data_cxb\电动汽车充电订单数据\did_panel_station_hourly.csv", clear

* ------------------------------------------
* 步骤 1: 设定靶点省份和时间窗口
* ------------------------------------------
local target_prov "湖北省"
local event_month "2024-05"
local window_start "2024-03"  
local window_end   "2024-06"  

* ------------------------------------------
* 步骤 2: 构建 Treated + Never-Treated 样本
* ------------------------------------------
local control_pool "江苏省 上海市 广东省 山东省 河北省 天津市 山西省 海南省 陕西省 甘肃省 青海省 宁夏回族自治区 新疆维吾尔自治区 西藏自治区 辽宁省 吉林省 黑龙江省 内蒙古自治区 重庆市"

gen to_keep = 0
replace to_keep = 1 if province == "`target_prov'"
foreach p of local control_pool {
    replace to_keep = 1 if province == "`p'"
}
keep if to_keep == 1
drop to_keep 
keep if ym >= "`window_start'" & ym <= "`window_end'"

* ------------------------------------------
* 步骤 3: 生成变量与固定效应
* ------------------------------------------
gen treated = (province == "`target_prov'")
gen post = (ym >= "`event_month'")
gen did = treated * post

encode charstation_name, gen(station_id)
gen date_num = date(date, "YMD")
egen station_hour_fe = group(station_id hour)
egen date_hour_fe = group(date_num hour)

* ==========================================
* 第一部分：主回归 —— 24 小时逐时效应图
* ==========================================
reghdfe hourly_kwh c.did#i.hour, absorb(station_hour_fe date_hour_fe) vce(cluster station_id)

* 准备 xlabel 宏
local xlab_str ""
forvalues i = 0/23 {
    local label_id = `i' + 1
    local xlab_str "`xlab_str' `label_id' "`i'" "
}

* ==========================================
* 核心绘图：湖北版 (标签横置 + 精准贴边)
* ==========================================
#delimit ;
coefplot, 
    keep(*.hour#c.did) 
    vertical 
    recast(connected) 
    lcolor(gs4) mcolor(gs4) lwidth(medthick)
    ciopts(recast(rcap) color(gs10))
    
    title("Hubei: Evaluation of TOU change (May 2024 Policy)")
    ytitle("Treatment Effect on Charging Load (kWh)")
    xtitle("Hour of Day")
    graphregion(color(white))
    plotregion(margin(t=0 b=0)) /* 消除上下多余的默认留白 */
    
    yline(0, lcolor(black) lpattern(solid) lwidth(medthick))
    
    /* 湖北 Y 轴：严格 -300 到 200，步长 100，标签横向显示 */
    yscale(range(-300 200)) 
    ylabel(-300(100)200, angle(0) nogrid)
    
    xlabel(`xlab_str', nogrid)
    legend(off)
    
    addplot(
        /* 阴影 Y 坐标严格匹配 Y 轴极值：-300 和 200 */
        (scatteri -300 13 -300 15 200 15 200 13, recast(area) fcolor("103 169 207%25") lwidth(none)) 
        (scatteri -300 24 -300 25 200 25 200 24, recast(area) fcolor("239 138 98%25") lwidth(none)) 
    )
;
#delimit cr

graph export "Hubei_TOU_Evaluation.pdf", as(pdf) replace


* ==========================================
* 模块化实证：四川省 (2023-06 极简平移版，忽略尖峰干扰)
* ==========================================
clear all
import delimited "D:\Data_cxb\电动汽车充电订单数据\did_panel_station_hourly.csv", clear

local target_prov "四川省"
local event_month "2023-06"
local window_start "2023-03"  
local window_end   "2023-09"  

* ------------------------------------------
* 步骤 2 & 3: 数据准备与变量生成
* ------------------------------------------
local control_pool "江苏省 上海市 广东省 山东省 河北省 天津市 山西省 海南省 陕西省 甘肃省 青海省 宁夏回族自治区 新疆维吾尔自治区 西藏自治区 辽宁省 吉林省 黑龙江省 内蒙古自治区 重庆市"
gen to_keep = 0
replace to_keep = 1 if province == "`target_prov'"
foreach p of local control_pool {
    replace to_keep = 1 if province == "`p'"
}
keep if to_keep == 1
drop to_keep 
keep if ym >= "`window_start'" & ym <= "`window_end'"

gen treated = (province == "`target_prov'")
gen post = (ym >= "`event_month'")
gen did = treated * post

encode charstation_name, gen(station_id)
gen date_num = date(date, "YMD")
egen station_hour_fe = group(station_id hour)
egen date_hour_fe = group(date_num hour)

* ==========================================
* 第一部分：主回归与绘图
* ==========================================
reghdfe hourly_kwh c.did#i.hour, absorb(station_hour_fe date_hour_fe) vce(cluster station_id)

local xlab_str ""
forvalues i = 0/23 {
    local label_id = `i' + 1
    local xlab_str "`xlab_str' `label_id' "`i'" "
}

* ==========================================
* 核心绘图：四川版 (标签横置 + 精准贴边)
* ==========================================
#delimit ;
coefplot, 
    keep(*.hour#c.did) 
    vertical 
    recast(connected) 
    lcolor(gs4) mcolor(gs4) lwidth(medthick)
    ciopts(recast(rcap) color(gs10))
    
    title("Sichuan: Evaluation of TOU change (June 2023 Policy)")
    ytitle("Treatment Effect on Charging Load (kWh)")
    xtitle("Hour of Day")
    graphregion(color(white))
    plotregion(margin(t=0 b=0)) /* 消除上下多余的默认留白 */
    
    yline(0, lcolor(black) lpattern(solid) lwidth(medthick))
    
    /* 四川 Y 轴：严格 -60 到 60，步长 20，标签横向显示 */
    /* (注：你的数据极值在40左右，用 -60 到 60 视觉张力最好) */
    yscale(range(-40 120)) 
    ylabel(-40(40)120, angle(0) nogrid)
    
    xlabel(`xlab_str', nogrid)
    legend(off)
    
    addplot(
        /* 阴影 Y 坐标严格匹配 Y 轴极值：-60 和 60 */
        (scatteri -40 11 -40 12 120 12 120 11, recast(area) fcolor("239 138 98%20") lwidth(none)) 
        (scatteri -40 15 -40 16 120 16 120 15, recast(area) fcolor("103 169 207%20") lwidth(none)) 
    )
;
#delimit cr

graph export "Sichuan_TOU_Evaluation.pdf", as(pdf) replace