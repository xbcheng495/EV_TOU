* Install user-written Stata packages used in the analysis.
* Run this script once before executing the Stata workflow.

cap which reghdfe
if _rc ssc install reghdfe, replace

cap which ftools
if _rc ssc install ftools, replace

cap which ppmlhdfe
if _rc ssc install ppmlhdfe, replace

cap which rdrobust
if _rc ssc install rdrobust, replace

cap which rddensity
if _rc ssc install rddensity, replace

cap which esttab
if _rc ssc install estout, replace

cap which gtools
if _rc ssc install gtools, replace

