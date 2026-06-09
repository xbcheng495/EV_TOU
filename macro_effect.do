clear all
set more off

* ---------------------------------------------------------
* 步骤 0：唤醒数据与模型记忆 (CRITICAL)
* ---------------------------------------------------------
display "📂 正在加载带有固定效应特征的面板数据..."
use "D:\1-研究数据\EV充电\Panel_Ready_for_Predict.dta", clear

display "🧠 正在激活 PPMLHDFE 异质性模型系数..."
estimates use "D:\1-研究数据\EV充电\Unified_PPML_Hetero_Advanced.ster"
* =========================================================
* 模块 4：反事实平行世界构建 (Counterfactual Flat Pricing)
* =========================================================
display "🔮 正在进行反事实模拟：测算【站点级别】收益中性单一电价..."

* 1. 测算每个充电站专属的"收益中性"单一电价
capture drop actual_revenue actual_demand
gen actual_revenue = ele_amount * expected_price if choice == 1
gen actual_demand = ele_amount if choice == 1

capture drop station_revenue station_demand
bysort charstation_name: egen station_revenue = sum(actual_revenue)
bysort charstation_name: egen station_demand = sum(actual_demand)

capture drop flat_p_local
gen flat_p_local = station_revenue / station_demand
drop actual_revenue actual_demand station_revenue station_demand

* 2. 预测现实平行世界 (现行 TOU 分时电价下的期望负荷)
* (注意：由于刚才最后跑的是 PPML_Hetero，这里的 predict 默认使用带异质性的模型系数)
display "⏳ 正在预测真实分时电价下的精准期望负荷..."
capture drop expected_kwh_tou
predict expected_kwh_tou, mu

* 3. 篡改现实：强制将价格替换为该站点的专属单一电价
display "⏳ 正在篡改价格矩阵，预测反事实负荷..."
capture drop ln_price_backup
gen ln_price_backup = ln_price
replace ln_price = ln(flat_p_local) 

* 4. 预测平行世界 (单一电价 Flat Rate 下的期望负荷)
capture drop expected_kwh_flat
predict expected_kwh_flat, mu

* 5. 恢复数据纯洁性
replace ln_price = ln_price_backup


* =========================================================
* 模块 5：宏观负荷曲线还原与震撼出图 (Continuous Grid Load)
* =========================================================
display "📸 正在平摊充电时长，还原全社会真实物理电网日均负荷..."
preserve

* 【核心升级 1】在丢弃其他变量前，先动态获取数据集包含的总天数
quietly tab date_id
local num_days = r(r)
display "📅 数据集共包含 `num_days' 天，将用于计算真实的日均负荷..."

* 💡 终极防爆 C 盘手段：在进行耗时的操作前，只保留计算真正需要的这 5 个列！
keep alt_index charge_time actual_kwh expected_kwh_tou expected_kwh_flat

capture drop slots
gen slots = max(1, ceil(charge_time / 30))

* 💡 换装核动力降维引擎：gcollapse
*capture ssc install gtools
display "⏳ 正在使用 C 语言哈希算法极速降维压缩 (gcollapse)..."

* 第一次极速降维：按 (开始时段, 占据时段数) 汇总
gcollapse (sum) actual_kwh expected_kwh_tou expected_kwh_flat, by(alt_index slots)

* 负荷平摊：将该组合下的总电量，平摊到每一个 slot 中
replace actual_kwh = actual_kwh / slots
replace expected_kwh_tou = expected_kwh_tou / slots
replace expected_kwh_flat = expected_kwh_flat / slots

* 时空裂变：根据 slots 数量将每一行复制裂变
expand slots

* 时间轴推移与午夜循环 (Midnight Wraparound)
bysort alt_index slots: gen step = _n - 1
gen grid_slot = mod(alt_index + step, 48)

* 第二次降维：按真正发生物理充电的网格时间汇总
gcollapse (sum) actual_kwh expected_kwh_tou expected_kwh_flat, by(grid_slot)
rename grid_slot alt_index

* 还原为 100% 全社会规模 (5%抽样 -> 乘20)
replace actual_kwh = actual_kwh * 20
replace expected_kwh_tou = expected_kwh_tou * 20
replace expected_kwh_flat = expected_kwh_flat * 20

* 【核心升级 2】除以总天数和 1000，得到"日均需求量 (Average Daily Demand MWh)"
gen mwh_actual = (actual_kwh / 1000) / `num_days'
gen mwh_tou = (expected_kwh_tou / 1000) / `num_days'
gen mwh_flat = (expected_kwh_flat / 1000) / `num_days'

* ---------------------------------------------------------
* 宏观总电量守恒性与模型拟合度审查
* ---------------------------------------------------------
quietly summarize mwh_actual
local daily_act = r(sum)
quietly summarize mwh_tou
local daily_tou = r(sum)
quietly summarize mwh_flat
local daily_flat = r(sum)

local diff_model = (`daily_tou' - `daily_act') / `daily_act' * 100
local diff_policy = (`daily_flat' - `daily_act') / `daily_act' * 100

display ""
display "========================================================="
display "📊 日均充电总负荷审查 (Average Daily Load, 100% Extrapolated)"
display "   ▶ 真实物理日均总负荷 (Actual):         " %12.2f `daily_act' " MWh / Day"
display "   ▶ 模型预测分时日均负荷 (TOU):          " %12.2f `daily_tou' " MWh / Day"
display "   ▶ 反事实单一电价日均负荷 (Flat):       " %12.2f `daily_flat' " MWh / Day"
display "   ------------------------------------------------------"
display "   ▶ [模型准确度] TOU vs 真实日均误差:      " %8.2f `diff_model' " %"
display "   ▶ [反事实对比] Flat单一电价 vs TOU分时:  " %8.2f (`daily_flat' - `daily_tou') / `daily_tou' * 100 " % 需求变化"
display "========================================================="

* ---------------------------------------------------------
* 绘图 1：真实的物理电网【日均】负荷三线图
* ---------------------------------------------------------
quietly twoway (line mwh_actual alt_index, lcolor(green) lwidth(medthick) lpattern(solid)) ///
       (line mwh_tou alt_index, lcolor(blue) lwidth(medthick) lpattern(longdash)) ///
       (line mwh_flat alt_index, lcolor(red) lpattern(shortdash) lwidth(medthick)), ///
       legend(order(1 "True Actual Load" 2 "Predicted TOU Load" 3 "Counterfactual Flat Load") ///
              ring(0) position(2) cols(1) region(lwidth(none) fcolor(none)) size(small)) ///
       title("The Value of TOU Pricing: Preventing Grid Overload") ///
       xtitle("Time of Day (48 Slots)") ///
       ytitle("Average Daily Electricity Demand (MWh)", margin(0 2 0 0)) ///
       xlabel(0 "00:00" 8 "04:00" 16 "08:00" 24 "12:00" 32 "16:00" 40 "20:00" 47 "23:30") ///
       graphregion(color(white)) bgcolor(white) name(counterfactual_load, replace)
graph export "D:\1-研究数据\EV充电\Counterfactual_DailyLoad_MWh.pdf", replace as(pdf)

* ---------------------------------------------------------
* 绘图 2：电网爬坡量冲击 (Daily Average Ramp Shock)
* ---------------------------------------------------------
sort alt_index
gen ramp_actual = mwh_actual - mwh_actual[_n-1]
gen ramp_flat = mwh_flat - mwh_flat[_n-1]
replace ramp_actual = mwh_actual - mwh_actual[48] if alt_index == 0
replace ramp_flat = mwh_flat - mwh_flat[48] if alt_index == 0

quietly twoway (bar ramp_actual alt_index, fcolor(green%50) lcolor(none) barwidth(0.4)) ///
       (bar ramp_flat alt_index, fcolor(red%60) lcolor(none) barwidth(0.4)), ///
       legend(order(1 "True Ramp Shock" 2 "Counterfactual Ramp Shock") ///
              ring(0) position(2) cols(1) region(lwidth(none) fcolor(none)) size(small)) ///
       title("Average Daily 30-Min Ramp Shock") ///
       xtitle("Time of Day") ///
       ytitle("Change in Daily Load Demand (MWh / 30 mins)", margin(0 2 0 0)) ///
       xlabel(0 "00:00" 8 "04:00" 16 "08:00" 24 "12:00" 32 "16:00" 40 "20:00" 47 "23:30") ///
       yline(0, lcolor(black) lwidth(medthick)) ///
       graphregion(color(white)) bgcolor(white) name(ramp_rate_shock, replace)
graph export "D:\1-研究数据\EV充电\Grid_DailyRamp_Shock_MWh.pdf", replace as(pdf)

restore

* =========================================================
* 模块 6：车网互动与新能源消纳分析 (全景双Y轴与四维气泡图)
* =========================================================
display "🌍 正在启动宏观车网互动分析：测算各省绿电匹配度与边际协同效应..."

* 【全局设置】
graph set window fontface "Times New Roman"
graph set eps fontface "Times New Roman"
graph set print fontface "Times New Roman"

quietly tab date_id
local num_days = r(r)

* ---------------------------------------------------------
* 阶段 1：带有省份固定效应的物理负荷均摊 (纯数字哈希防爆版)
* ---------------------------------------------------------
preserve
display "⏳ 正在按【省份】进行物理负荷跨时段均摊 (启动 gcollapse)..."

capture drop prov_id
encode province, gen(prov_id)

keep prov_id alt_index charge_time expected_kwh_tou expected_kwh_flat
gen slots = max(1, ceil(charge_time / 30))

gen tou_kwh_per_slot = expected_kwh_tou / slots        
gen flat_kwh_per_slot = expected_kwh_flat / slots 

gcollapse (sum) tou_kwh_per_slot flat_kwh_per_slot, by(prov_id alt_index slots)
expand slots

bysort prov_id alt_index slots: gen time_shift = _n - 1
gen grid_slot = mod(alt_index + time_shift, 48)

gcollapse (sum) tou_load=tou_kwh_per_slot flat_load=flat_kwh_per_slot, by(prov_id grid_slot)
rename grid_slot alt_index

decode prov_id, gen(province)
drop prov_id

* 转化为 MWh 并得到日均值
gen tou_mwh = (tou_load * 20 / 1000) / `num_days'
gen flat_mwh = (flat_load * 20 / 1000) / `num_days'

* 【核心新增】计算该省的日均总充电负荷，用于决定气泡图的气泡大小
bysort province: egen total_ev_mwh = sum(flat_mwh)

sort province alt_index
tempfile ev_prov_load
save `ev_prov_load', replace
restore

* ---------------------------------------------------------
* 阶段 2：处理外部的风光容量因子 CSV 文件
* ---------------------------------------------------------
preserve
display "☀️ 正在处理风光容量因子 (跨月平均 & 升维至 48时段)..."
import delimited "D:\1-研究数据\EV充电\Monthly_Typical_Day_CF.csv", clear varnames(1)

capture rename Province province
capture rename Hour hour
capture rename Avg_CF_Wind avg_cf_wind
capture rename Avg_CF_PV avg_cf_pv
capture rename avg_cf_wind wind_cf
capture rename avg_cf_pv solar_cf

collapse (mean) wind_cf solar_cf, by(province hour)

expand 2
bysort province hour: gen half = _n - 1
gen alt_index = hour * 2 + half
drop hour half

tempfile cf_macro
save `cf_macro', replace
restore

* ---------------------------------------------------------
* 阶段 3：建立风光装机容量库 (请在此处补全所有省份的数据！)
* ---------------------------------------------------------
preserve
clear
* 定义省份装机容量字典（单位：MW）
input str20 province wind_mw solar_mw
"北京市" 24 108
"天津市" 171 490
"河北省" 3141 5416
"山西省" 2500 2490
"内蒙古自治区" 6962 2366
"辽宁省" 1429 958
"吉林省" 1268 460
"黑龙江省" 1127 565
"上海市" 107 289
"江苏省" 2286 3928
"浙江省" 584 3357
"安徽省" 722 3223
"福建省" 762 875
"江西省" 573 1993
"山东省" 2591 5693
"河南省" 2178 3731
"湖北省" 836 2487
"湖南省" 972 1252
"广东省" 1657 2521
"广西壮族自治区" 1277 1133
"海南省" 31 472
"重庆市" 206 157
"四川省" 770 574
"贵州省" 616 1646
"云南省" 1531 2072
"西藏自治区" 18 257
"陕西省" 1285 2292
"甘肃省" 2614 2540
"青海省" 1185 2561
"宁夏回族自治区" 1464 2137
"新疆维吾尔自治区" 3258 3007

end
tempfile cap_data
save `cap_data', replace
restore

* ---------------------------------------------------------
* 阶段 4：三表大融合与发电量计算
* ---------------------------------------------------------
preserve
display "🔗 正在融合容量因子与装机量，计算绿电绝对出力..."
use `ev_prov_load', clear

* 合并时只保留匹配上的省份（如果你在阶段3没写某个省，它就不会出图）
merge m:1 province alt_index using `cf_macro', keep(match) nogen
merge m:1 province using `cap_data', keep(match) nogen

* 【核心计算】根据容量因子 (0-1) 和装机容量 (MW) 算出真实的绿电出力
gen total_re_mw = (wind_cf * wind_mw) + (solar_cf * solar_mw)

* ---------------------------------------------------------
* 阶段 5：批量计算皮尔逊相关系数并生成【各省双Y轴图】(全英文标签版)
* ---------------------------------------------------------
display "📊 正在自动计算相关系数并批量绘制【双Y轴】顶刊对比图..."

* 在数据集中预留位置，用于保存相关系数供阶段6使用
capture drop r_flat_tot
capture drop r_tou_tot
gen r_flat_tot = .
gen r_tou_tot = .

* =========================================================
* 🌍 建立中英文字典映射 (用于图表标题和文件名)
* =========================================================
capture drop prov_en
gen prov_en = ""
replace prov_en = "Beijing" if province == "北京市"
replace prov_en = "Tianjin" if province == "天津市"
replace prov_en = "Shanghai" if province == "上海市"
replace prov_en = "Chongqing" if province == "重庆市"
replace prov_en = "Hebei" if province == "河北省"
replace prov_en = "Shanxi" if province == "山西省"
replace prov_en = "Liaoning" if province == "辽宁省"
replace prov_en = "Jilin" if province == "吉林省"
replace prov_en = "Jiangsu" if province == "江苏省"
replace prov_en = "Zhejiang" if province == "浙江省"
replace prov_en = "Anhui" if province == "安徽省"
replace prov_en = "Fujian" if province == "福建省"
replace prov_en = "Jiangxi" if province == "江西省"
replace prov_en = "Shandong" if province == "山东省"
replace prov_en = "Henan" if province == "河南省"
replace prov_en = "Hubei" if province == "湖北省"
replace prov_en = "Hunan" if province == "湖南省"
replace prov_en = "Guangdong" if province == "广东省"
replace prov_en = "Hainan" if province == "海南省"
replace prov_en = "Sichuan" if province == "四川省"
replace prov_en = "Guizhou" if province == "贵州省"
replace prov_en = "Yunnan" if province == "云南省"
replace prov_en = "Shaanxi" if province == "陕西省"
replace prov_en = "Gansu" if province == "甘肃省"
replace prov_en = "Inner Mongolia" if province == "内蒙古自治区"
replace prov_en = "Guangxi" if province == "广西壮族自治区"
replace prov_en = "Ningxia" if province == "宁夏回族自治区"
* 兜底：如果没有匹配上，默认使用原中文名
replace prov_en = province if prov_en == ""

* =========================================================
* 导出到 CSV 备查 (带终极防报错机制 & 细分风光相关系数)
* =========================================================
tempfile results_file
* 👑 核心防御：在打开之前，强制关闭之前可能遗留的 rfile 通道！
capture file close rfile  

* 预留数据列：不仅保存总绿电，还保存独立的风/光相关系数
capture drop r_flat_tot
capture drop r_tou_tot
capture drop r_flat_w
capture drop r_tou_w
capture drop r_flat_s
capture drop r_tou_s

gen r_flat_tot = .
gen r_tou_tot = .
gen r_flat_w = .
gen r_tou_w = .
gen r_flat_s = .
gen r_tou_s = .

* 升级 CSV 表头：增加风电和光伏的具体相关系数列
file open rfile using "D:\1-研究数据\EV充电\Correlation_Results_EN.csv", write replace
file write rfile "Province,r_Wind_Flat,r_Wind_TOU,r_Solar_Flat,r_Solar_TOU,r_TotalRE_Flat,r_TotalRE_TOU,Total_EV_MWh,Policy_Effect" _n

* 【核心升级】全自动提取当前存在的所有省份
levelsof province, local(provs)
foreach p of local provs {
    
    * 获取当前省份对应的英文名
    quietly levelsof prov_en if province == "`p'", local(p_en) clean
    
    * -----------------------------------------------------
    * 计算 1：纯自然充电 (Flat) 与 各类电源的相关性
    * -----------------------------------------------------
    * 1.1 与总绿电
    quietly pwcorr flat_mwh total_re_mw if province == "`p'"
    local r_flat_val = round(r(rho), 0.001)
    * 1.2 与纯风电 (直接使用容量因子计算，数学等价于绝对出力)
    quietly pwcorr flat_mwh wind_cf if province == "`p'"
    local r_flat_w_val = round(r(rho), 0.001)
    * 1.3 与纯光伏
    quietly pwcorr flat_mwh solar_cf if province == "`p'"
    local r_flat_s_val = round(r(rho), 0.001)

    * -----------------------------------------------------
    * 计算 2：分时电价干预后 (TOU) 与 各类电源的相关性
    * -----------------------------------------------------
    * 2.1 与总绿电
    quietly pwcorr tou_mwh total_re_mw if province == "`p'"
    local r_tou_val = round(r(rho), 0.001)
    * 2.2 与纯风电
    quietly pwcorr tou_mwh wind_cf if province == "`p'"
    local r_tou_w_val = round(r(rho), 0.001)
    * 2.3 与纯光伏
    quietly pwcorr tou_mwh solar_cf if province == "`p'"
    local r_tou_s_val = round(r(rho), 0.001)
    
    * -----------------------------------------------------
    * 将所有的相关系数写回数据集，供后续可能的可视化使用
    quietly replace r_flat_tot = `r_flat_val' if province == "`p'"
    quietly replace r_tou_tot = `r_tou_val' if province == "`p'"
    quietly replace r_flat_w = `r_flat_w_val' if province == "`p'"
    quietly replace r_tou_w = `r_tou_w_val' if province == "`p'"
    quietly replace r_flat_s = `r_flat_s_val' if province == "`p'"
    quietly replace r_tou_s = `r_tou_s_val' if province == "`p'"
    
    * 获取该省的总负荷大小
    quietly summarize total_ev_mwh if province == "`p'"
    local ev_size = r(mean)
    
    * 以【总绿电】的改善情况作为总体政策评价标准
    local effect "Worse (Duck Curve Expands)"
    if `r_tou_val' > `r_flat_val' {
        local effect "Better (Synergy Achieved)"
    } 
    
    * 写入 CSV (将 6 个相关系数全部写入)
    file write rfile "`p_en',`r_flat_w_val',`r_tou_w_val',`r_flat_s_val',`r_tou_s_val',`r_flat_val',`r_tou_val',`ev_size',`effect'" _n
                  
    * --- 绘制各省双 Y 轴图 (图表本身保持总绿电走势，保证视觉简洁) ---
    quietly twoway ///
        (line total_re_mw alt_index if province=="`p'", yaxis(1) lcolor(forest_green%80) lwidth(thick) lpattern(solid)) ///
        (line flat_mwh alt_index if province=="`p'", yaxis(2) lcolor(red) lpattern(shortdash) lwidth(medthick)) ///
        (line tou_mwh alt_index if province=="`p'", yaxis(2) lcolor(blue) lwidth(medthick)), ///
        title("`p_en': EV Load vs. Renewable Energy Supply", size(medium) color(black)) ///
        subtitle("Correlation without TOU: `r_flat_val'  |  Correlation with TOU: `r_tou_val'", size(small) color(gs5)) ///
        ytitle("Renewable Energy Supply (MW)", axis(1) size(small) color(forest_green)) ///
        ylabel(, axis(1) labsize(small) labcolor(forest_green) format(%9.0fc) nogrid) ///
        ytitle("Average EV Charging Demand (MWh)", axis(2) size(small) color(black)) ///
        ylabel(, axis(2) labsize(small) format(%9.1f) nogrid) ///
        xtitle("Time of Day", size(small)) ///
        xlabel(0 "0:00" 8 "4:00" 16 "8:00" 24 "12:00" 32 "16:00" 40 "20:00" 47 "23:30", labsize(small)) ///
        legend(order(1 "Total RE Supply (Left)" 2 "Flat EV Load (Right)" 3 "TOU EV Load (Right)") ///
               position(6) cols(3) size(vsmall) region(lwidth(none))) ///
        graphregion(color(white)) bgcolor(white) ///
        name(temp_graph, replace) 
            
    * 导出为 PDF
    graph export "D:\1-研究数据\EV充电\TotalRE_Match_`p_en'_DualAxis.pdf", as(pdf) replace
    graph drop temp_graph
}
file close rfile

* ---------------------------------------------------------
* 阶段 6：绘制全国多省资源禀赋与政策效用【等大散点图】(防重叠标签版)
* ---------------------------------------------------------
display "📸 正在提取截面数据，绘制资源与政策错配散点图..."

* 降维提取
collapse (first) wind_mw solar_mw total_ev_mwh r_flat_tot r_tou_tot prov_en, by(province)

gen delta_r = r_tou_tot - r_flat_tot
gen policy_status = 0
replace policy_status = 1 if delta_r > 0   
replace policy_status = -1 if delta_r < 0  

quietly summarize wind_mw
local max_w = r(max)
quietly summarize solar_mw
local max_s = r(max)
local max_axis = max(`max_w', `max_s') * 1.15

* =========================================================
* 🎯 核心防重叠技术：动态标签方位 (Clock Position Variable)
* =========================================================
capture drop lab_pos
gen lab_pos = 3 // 默认所有省份的标签放在圆圈的 3 点钟方向 (正右方)

* 针对左下角和中部的"拥挤区"，手动拨动时钟方位把它弹开：
* (12=正上, 6=正下, 9=正左, 1=右上, 5=右下, 11=左上, 7=左下)
replace lab_pos = 6  if prov_en == "Beijing"    // 北京放左边
replace lab_pos = 12  if prov_en == "Tianjin"    // 天津放下面
replace lab_pos = 12 if prov_en == "Shanghai"   // 上海放上面
replace lab_pos = 9 if prov_en == "Chongqing"  // 重庆放左上
replace lab_pos = 6  if prov_en == "Hainan"     // 海南放右下
replace lab_pos = 12  if prov_en == "Sichuan"    // 四川放右上
replace lab_pos = 6  if prov_en == "Fujian"     // 福建放左下
replace lab_pos = 12  if prov_en == "Jilin"      // 吉林放上边
replace lab_pos = 12  if prov_en == "Liaoning"   // 辽宁放上边
replace lab_pos = 6 if prov_en == "Hunan"      // 湖南放下面
replace lab_pos = 12  if prov_en == "Guizhou"    // 贵州放上边
replace lab_pos = 6  if prov_en == "Shanxi"    // 山西放下边
replace lab_pos = 12  if prov_en == "Gansu"    // 甘肃放上边
replace lab_pos = 9  if prov_en == "Henan"    // 河南放左边
replace lab_pos = 12  if prov_en == "Yunnan"    // 云南放上边
replace lab_pos = 12  if prov_en == "Jiangsu"    // 江苏放上边
* =========================================================
* 终极画图执行 
* =========================================================
quietly twoway ///
    /* 图层 1：红色散点 (恶化) */ ///
    (scatter wind_mw solar_mw if policy_status == -1, ///
        msymbol(O) mcolor(red%60) msize(medlarge) mlwidth(none)) ///
    ///
    /* 图层 2：绿色散点 (改善) */ ///
    (scatter wind_mw solar_mw if policy_status == 1, ///
        msymbol(O) mcolor(forest_green%60) msize(medlarge) mlwidth(none)) ///
    ///
    /* 图层 3：黑色散点 (不变) */ ///
    (scatter wind_mw solar_mw if policy_status == 0, ///
        msymbol(O) mcolor(black%60) msize(medlarge) mlwidth(none)) ///
    ///
    /* 图层 4：全英文智能标签！*/ ///
    /* ⚠️ 核心修改：使用 mlabvposition(lab_pos) 替代固定的 mlabposition(3) */ ///
    (scatter wind_mw solar_mw, mlabel(prov_en) mlabvposition(lab_pos) mlabgap(vsmall) mlabsize(tiny) mlabcolor(gs3) msymbol(i)) ///
    ///
    /* 图层 5：对角线 */ ///
    (function y = x, range(0 `max_axis') lcolor(gs10) lpattern(shortdash)) ///
    ///
    , ///
    title("Resource Endowment vs. Policy Mismatch", size(medlarge) color(black)) ///
    subtitle("Color: Policy Impact (Red=Worse, Green=Better, Black=Unchanged)", size(small) color(gs5)) ///
    xtitle("Installed Solar Capacity (MW)", size(small)) ///
    ytitle("Installed Wind Capacity (MW)", size(small)) ///
    legend(order(1 "Mismatch Generated (Δr < 0)" 2 "Synergy Achieved (Δr > 0)" 3 "No Effect (Δr = 0)") ///
           ring(0) position(11) cols(1) size(small) region(lwidth(none))) ///
    graphregion(color(white)) bgcolor(white) ///
    name(scatter_plot, replace)

graph export "D:\1-研究数据\EV充电\Province_Endowment_Scatter_English.pdf", as(pdf) replace
display "🎉 动态防重叠版散点图绘制完成！"

restore

* =========================================================
* 模块 7：湖北省自然实验评估与车网协同验证 (防爆 C 盘 / 极低内存版)
* =========================================================
display "🚀 正在提取湖北省真实样本，评估 5 月午间深谷政策冲击与绿电协同效应..."

* 【核心优化】：绝对不备份全国总数据！直接在当前内存里砍掉其他省份。
* 这样数据集体积瞬间缩小 95% 以上，再存临时文件就不会撑爆 C 盘了。
keep if province == "湖北省"

* 此时内存里只有极小的湖北数据，安全保存到临时文件
tempfile hubei_ev_data
quietly save `hubei_ev_data', replace

* ---------------------------------------------------------
* 步骤 A：独立获取湖北省风光发电量曲线 
* ---------------------------------------------------------
display "☀️ 正在独立加载湖北省风光数据..."
import delimited "D:\1-研究数据\EV充电\Monthly_Typical_Day_CF.csv", clear varnames(1)

capture rename Province province
capture rename Hour hour
capture rename Avg_CF_Wind avg_cf_wind
capture rename Avg_CF_PV avg_cf_pv

keep if province == "湖北省"
collapse (mean) avg_cf_wind avg_cf_pv, by(hour)

expand 2
bysort hour: gen half = _n - 1
gen alt_index = hour * 2 + half
drop hour half

* 结合真实装机量 (湖北: 风电 836 MW, 光伏 2487 MW) 算出绝对出力
gen total_re_mw = (avg_cf_wind * 836) + (avg_cf_pv * 2487)
keep alt_index total_re_mw

tempfile hubei_re_data
quietly save `hubei_re_data', replace

* ---------------------------------------------------------
* 步骤 B：处理充电负荷数据 (加载刚才存的湖北专属小数据集)
* ---------------------------------------------------------
use `hubei_ev_data', clear

* 2. 精准打上"政策时间标签" 
capture drop date_str
capture drop charge_date
capture drop true_charge_date
capture drop post_policy
gen date_str = substr(begin_time, 1, 10)
gen charge_date = date(date_str, "YMD")
bysort id: egen true_charge_date = max(charge_date)
* 核心：划分新旧政策
gen post_policy = (true_charge_date >= mdy(5, 1, 2024))

* 3. 核心预测：用底层模型参数预测真实概率
display "🧠 正在预测真实价格下的充电概率..."

* 强制重新唤醒模型记忆
quietly estimates use "D:\1-研究数据\EV充电\Unified_PPML_Hetero_Advanced.ster"

foreach v in exp_V_predict sum_exp_V_predict p_predict {
    capture drop `v'
}

* 【👑 终极神级替换】：直接用 predict 算出期望值，完美等价于 exp(V)，彻底告别手动写 _b[]！
quietly predict exp_V_predict, mu

* 按用户 id 汇总计算概率占比 (Logit/Poisson 核心转换)
bysort id: egen sum_exp_V_predict = sum(exp_V_predict)
gen p_predict = exp_V_predict / sum_exp_V_predict

* 4. 物理电量均摊与极速降维
display "⏳ 正在进行物理负荷跨时段哈希均摊..."
foreach v in kwh_predict slots kwh_per_slot {
    capture drop `v'
}
gen kwh_predict = p_predict * ele_amount
gen slots = max(1, ceil(charge_time / 30))
gen kwh_per_slot = kwh_predict / slots

keep post_policy alt_index slots kwh_per_slot 
fcollapse (sum) kwh_per_slot, by(post_policy alt_index slots)
expand slots

bysort post_policy alt_index slots: gen time_shift = _n - 1
gen real_time_index = alt_index + time_shift
replace real_time_index = real_time_index - 48 if real_time_index > 47

* 得到新旧政策分别的绝对物理总负荷
fcollapse (sum) final_load=kwh_per_slot, by(post_policy real_time_index)
rename real_time_index alt_index

* 转化为"负荷分布占比 (%)"
bysort post_policy: egen period_total_kwh = sum(final_load)
gen load_share = (final_load / period_total_kwh) * 100

* 数据塑形：宽表转换
keep post_policy alt_index load_share
reshape wide load_share, i(alt_index) j(post_policy)
rename load_share0 share_before_may
rename load_share1 share_after_may

* ---------------------------------------------------------
* 步骤 C：合并绿电数据并绘制终极叠图
* ---------------------------------------------------------
* 合并步骤 A 中准备好的湖北省独立绿电数据
merge 1:1 alt_index using `hubei_re_data', nogen

display "📸 正在绘制湖北省【政策改革 vs 绿电协同】绝杀图..."

* 获取绿电峰值用于文字定位
quietly summarize total_re_mw
local re_max = r(max)
local text_y_re = `re_max' * 0.95

twoway ///
    /* 图层 1：可再生能源出力背景 (浅绿色面积图，右轴) */ ///
    (area total_re_mw alt_index, yaxis(2) color(forest_green%20) base(0)) ///
    ///
    /* 图层 2：旧政策负荷占比 (灰色虚线，左轴) */ ///
    (line share_before_may alt_index, yaxis(1) lcolor(gs8) lpattern(dash) lwidth(thick)) ///
    ///
    /* 图层 3：新政策负荷占比 (红色实线，左轴) */ ///
    (line share_after_may alt_index, yaxis(1) lcolor(red) lwidth(thick)), ///
    ///
    title("Hubei Province: Shifting EV Load to Match Nature", size(medlarge) color(black)) ///
    subtitle("Natural Experiment: Implementation of Mid-day Valley Pricing (May 2024)", size(small) color(gs5)) ///
    xtitle("Time of Day") ///
    ytitle("Share of Daily Charging Load (%)", axis(1) size(medium) color(black)) ///
    ytitle("Renewable Energy Supply (MW)", axis(2) size(medium) color(forest_green)) ///
    xlabel(0 "00:00" 8 "04:00" 16 "08:00" 24 "12:00" 32 "16:00" 40 "20:00" 47 "23:30") ///
    /* 核心标注：午间深谷时段 12:00 (index 24) - 14:00 (index 28) */ ///
    xline(24, lcolor(orange) lpattern(shortdash)) xline(28, lcolor(orange) lpattern(shortdash)) /// 
    text(`text_y_re' 26 "Solar Peak & New Valley", yaxis(2) color(orange) place(n) size(small)) ///
    legend(order(2 "Old Policy (Night Valley)" 3 "New Policy (Mid-day Valley)" 1 "Total RE Supply") ///
           region(lwidth(none)) size(small) position(6) cols(3)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(hubei_policy_re_match, replace)

graph export "D:\1-研究数据\EV充电\Hubei_Actual_Policy_RE_Match.pdf", as(pdf) replace

display "🎉 绝杀出图！再也不用担心 C 盘爆炸了！"

* =========================================================
* 附加计算：湖北省自然实验前后的车网协同相关系数
* =========================================================
display "📊 正在计算湖北省自然实验前后的微观匹配度..."

* 计算旧政策 (深夜谷电) 与 绿电出力的相关性
quietly pwcorr share_before_may total_re_mw
local r_old = round(r(rho), 0.001)

* 计算新政策 (午间深谷) 与 绿电出力的相关性
quietly pwcorr share_after_may total_re_mw
local r_new = round(r(rho), 0.001)

* 计算变化量
local r_diff = `r_new' - `r_old'

display "========================================================="
display "🎯 湖北省自然实验核心结论 (相关系数对比)："
display "   ▶ 改革前 (深夜谷电) 与绿电相关系数:  " `r_old'
display "   ▶ 改革后 (午间深谷) 与绿电相关系数:  " `r_new'
display "   ▶ 政策净效应提升 (Delta r):          +" `r_diff'
display "========================================================="
