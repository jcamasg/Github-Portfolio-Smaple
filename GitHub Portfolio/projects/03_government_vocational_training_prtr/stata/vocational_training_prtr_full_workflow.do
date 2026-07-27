/********************************************************************************
* VOCATIONAL TRAINING, YOUTH EMPLOYMENT AND PRTR: CONSOLIDATED STATA WORKFLOW
* Author: Jose Camas Garrdiow
*
* Public portfolio copy. Original absolute computer paths were replaced by the
* PROJECT_ROOT global. Each named section below originated as an independent
* do-file and retains its original analytical sequence.
********************************************************************************/

if "${PROJECT_ROOT}" == "" {
    global PROJECT_ROOT "."
}


/********************************************************************************
* SECTION 1: Do_file_EPA.do
********************************************************************************/



clear all
if "${PROJECT_ROOT}" == "" {
    global PROJECT_ROOT "."
}
set more off

*--- Carpeta y lista de ficheros (ajusta root si hace falta)
local root "${PROJECT_ROOT}\98.IMPACTO DEL PLAN\1. FP\epa\dta"
local files epa_2021t1.dta epa_2021t2.dta epa_2021t3.dta epa_2021t4.dta ///
             epa_2022t1.dta epa_2022t2.dta epa_2022t3.dta epa_2022t4.dta ///
             epa_2023t1.dta epa_2023t2.dta epa_2023t3.dta epa_2023t4.dta ///
             epa_2024t1.dta epa_2024t2.dta epa_2024t3.dta epa_2024t4.dta ///
             epa_2025t1.dta epa_2025t2.dta epa_2025t3.dta epa_2025t4.dta ///
			 epa_2026t1.dta
*--- ¿Usar pesos muestrales (FACTOREL)?
local useweights 1

tempfile acum_ccaa
clear
save `acum_ccaa', emptyok

foreach f of local files {
    di as result ">>> Procesando: `f'"
    quietly {
        local full = "`root'/`f'"
        capture confirm file "`full'"
        if _rc {
            di as error "   (No existe) `full' -> salto"
            continue
        }

        use "`full'", clear

        *------------------------------------------------------
        * 1. Asegurar tipos numéricos mínimos
        *------------------------------------------------------
        foreach v in CCAA PROV EDAD1 AOI FACTOREL CICLO {
            capture confirm numeric variable `v'
            if _rc!=0 destring `v', replace ignore(" .")
        }

        *------------------------------------------------------
        * 2. Filtrar jóvenes (<30)
        *------------------------------------------------------
        keep if EDAD1 < 25
	
        drop if missing(AOI) | missing(CCAA)

        *------------------------------------------------------
        * 3. Clasificar situación laboral (AOI)
        *------------------------------------------------------
        gen byte grupo_actividad = .
        replace grupo_actividad = 1 if inlist(AOI,3,4)      // Ocupados
        replace grupo_actividad = 2 if inlist(AOI,5,6)      // Parados
        replace grupo_actividad = 3 if inlist(AOI,7,8,9)    // Inactivos

        *------------------------------------------------------
        * 4. Identificadores temporales
        *------------------------------------------------------
        capture assert !missing(CICLO)
        if !_rc {
            gen anio = 2021 + floor((CICLO-194)/4)
            gen trim = mod(CICLO-194,4) + 1
        }
        else {
            local base = subinstr("`f'",".dta","",.)
            local yy = real(substr("`base'",5,4))
            local tt = real(substr("`base'",10,1))
            gen anio = `yy'
            gen trim = `tt'
        }
        gen str7 periodo = string(anio)+"T"+string(trim)
        gen tq = yq(anio,trim)
        format tq %tq

        *------------------------------------------------------
        * 5. Pesos y agregación por CCAA
        *------------------------------------------------------
        gen double w = cond(`useweights', FACTOREL, 1)
        gen double w_ocup = w if grupo_actividad==1
        gen double w_paro = w if grupo_actividad==2

        * Agregar ponderadamente a nivel CCAA × tiempo
        collapse (sum) w_ocup w_paro, by(CCAA anio trim periodo tq)

        *------------------------------------------------------
        * 6. Calcular tasas
        *------------------------------------------------------
        rename w_ocup ocupados
        rename w_paro parados
        gen double activos = ocupados + parados
        gen double tasa_ocup_joven = ocupados/activos if activos>0

        label var ocupados        "Ocupados <25 (ponderado)"
        label var parados         "Parados <25 (ponderado)"
        label var activos         "Activos <25 (ponderado)"
        label var tasa_ocup_joven "Tasa ocupación juvenil: Ocup/Activos"

        keep CCAA anio trim periodo tq ocupados parados activos tasa_ocup_joven
        append using `acum_ccaa'
        save `acum_ccaa', replace
    }
}

*------------------------------------------------------
* 7. Guardar y exportar resultados
*------------------------------------------------------





use `acum_ccaa', clear
order anio trim periodo tq CCAA ocupados parados activos tasa_ocup_joven
sort anio trim CCAA

save "EPA_tasa_ocupacion_joven_CCAA_2021T1_2025T2.dta", replace
export excel using "EPA_tasa_ocupacion_joven_CCAA_2021T1_2025T2.xlsx", replace firstrow(variables)

di as result "✅ Panel CCAA de tasa de ocupación juvenil generado correctamente."


*--- Generar tasa de paro juvenil
gen double tasa_paro_joven = .
replace tasa_paro_joven = parados / activos if activos > 0

label var tasa_paro_joven "Tasa de paro juvenil: Parados / Activos"

********************************************************************************************


*==============================
* 1) Código CCAA desde PROV
*==============================
gen byte ccaa_cod = CCAA

* Etiquetas y nombre CCAA
label define lbl_ccaa 1 "Andalucía" 2 "Aragón" 3 "Asturias, Principado de" ///
    4 "Balears, Illes" 5 "Canarias" 6 "Cantabria" 7 "Castilla y León" ///
    8 "Castilla - La Mancha" 9 "Cataluña" 10 "Comunitat Valenciana" ///
    11 "Extremadura" 12 "Galicia" 13 "Madrid, Comunidad de" 14 "Murcia, Región de" ///
    15 "Navarra, Comunidad Foral de" 16 "País Vasco" 17 "Rioja, La" ///
    18 "Ceuta" 19 "Melilla", replace
label values ccaa_cod lbl_ccaa
decode ccaa_cod, gen(ccaa_nombre)


*--------------------------------------------------------------
* Asegúrate de que las tasas están en porcentaje
replace tasa_ocup_joven = tasa_ocup_joven * 100
replace tasa_paro_joven = tasa_paro_joven * 100

*--------------------------------------------------------------
* Gráfico: evolución de tasas juveniles por CCAA (2021T1–2025T2)
twoway ///
    (line tasa_ocup_joven tq, lcolor(blue) lwidth(medthick)) ///
    (line tasa_paro_joven tq, lcolor(red) lpattern(dash) lwidth(medthick)), ///
    by(ccaa_nombre, cols(4) note("") title("Evolución temporal de tasas juveniles por CCAA")) ///
    legend(order(1 "Tasa de ocupación" 2 "Tasa de paro") pos(6) ring(0)) ///
    ylabel(0(20)100, angle(0) grid) ///
    xtitle("Trimestre") ///
    ytitle("Porcentaje (%)") ///
    graphregion(color(white)) bgcolor(white)
	
*-------------------------------------------------------------
* Gráfico por separado
* Gráfico 1: Tasa de ocupación juvenil por CCAA
twoway ///
    (line tasa_ocup_joven tq, lcolor(blue) lwidth(medthick)), ///
    by(ccaa_nombre, cols(4) note("") title("Evolución de la tasa de ocupación juvenil (2021T1–2026T1)")) ///
    ylabel(0(20)100, angle(0) grid) ///
    xtitle("Trimestre") ///
    ytitle("Porcentaje (%)") ///
    graphregion(color(white)) bgcolor(white) ///
    xtick(, valuelabel angle(45)) ///
    name(g_ocup, replace)

* Gráfico 2: Tasa de paro juvenil por CCAA
twoway ///
    (line tasa_paro_joven tq, lcolor(red) lwidth(medthick) lpattern(dash)), ///
    by(ccaa_nombre, cols(4) note("") title("Evolución de la tasa de paro juvenil (2021T1–2026T1)")) ///
    ylabel(0(20)100, angle(0) grid) ///
    xtitle("Trimestre") ///
    ytitle("Porcentaje (%)") ///
    graphregion(color(white)) bgcolor(white) ///
    xtick(, valuelabel angle(45)) ///
    name(g_paro, replace)

	
	
* Mejorar visibilidad general
twoway ///
    (line tasa_paro_joven tq, lcolor(red) lwidth(medthick) lpattern(line)), ///
    by(ccaa_nombre, cols(4) note("") title("Evolución de la tasa de paro juvenil (2021T1–2026T1)")) ///
    ylabel(10(10)60, angle(0) grid) ///
    xtitle("Trimestre") ///
    ytitle("Porcentaje (%)") ///
    graphregion(color(white)) bgcolor(white) ///
    xtick(, valuelabel angle(45) labsize(small)) ///
    ylabel(, labsize(small)) ///
    plotregion(margin(2 2 2 2)) ///
    name(g1, replace)

	

replace ccaa_nombre = subinstr(ccaa_nombre, ",", "", .)

		
		
twoway connected tasa_paro_joven tq, ///
    by(ccaa_nombre, cols(5) compact note("") ///
        title("Tasa de paro juvenil por CCAA (trimestral)", size(medsmall)) /// ///
        imargin(2 2 2 2) ///
        legend(off) ///
        bgcolor(255 255 153)) ///  <-- amarillo claro en los encabezados de las CCAA
    ylabel(10(10)60, angle(0) grid labsize(small)) ///
    xtitle("TrimestPe", size(small)) ///
    ytitle("% de Parados", size(small)) ///
    graphregion(color(white)) bgcolor(white)
	
*----------------------------------------------------------------------------------------

*------------------------------------------------------
* 8) Agregación ANUAL por CCAA
*    Opción B (RECOMENDADA): recomponer tasas desde totales
*    (equivale a media ponderada por el tamaño de activos)
*------------------------------------------------------
preserve
collapse (sum) ocupados parados activos, by(CCAA anio)
gen double tasa_ocup_joven_anual = 100 * ocupados/activos if activos>0
gen double tasa_paro_joven_anual = 100 * parados/activos if activos>0

* Añadir nombres de CCAA (si no los tienes en memoria)
gen byte ccaa_cod = CCAA
label define lbl_ccaa 1 "Andalucía" 2 "Aragón" 3 "Asturias, Principado de" ///
    4 "Balears, Illes" 5 "Canarias" 6 "Cantabria" 7 "Castilla y León" ///
    8 "Castilla - La Mancha" 9 "Cataluña" 10 "Comunitat Valenciana" ///
    11 "Extremadura" 12 "Galicia" 13 "Madrid, Comunidad de" 14 "Murcia, Región de" ///
    15 "Navarra, Comunidad Foral de" 16 "País Vasco" 17 "Rioja, La" ///
    18 "Ceuta" 19 "Melilla", replace
label values ccaa_cod lbl_ccaa
decode ccaa_cod, gen(ccaa_nombre)

order anio CCAA ccaa_nombre ocupados parados activos tasa_ocup_joven_anual tasa_paro_joven_anual
sort anio CCAA

save "EPA_CCaa_ANUAL_recompuesto_2021_2025.dta", replace
export excel using "EPA_CCaa_ANUAL_recompuesto_2021_2026.xlsx", replace firstrow(variables)

* Small multiples anual (parado)
twoway connected tasa_paro_joven_anual anio, ///
    by(ccaa_nombre, cols(4) note("") ///
        title("Tasa de paro juvenil por CCAA (media anual)", size(medsmall)) ///
        imargin(tiny) legend(off)) ///
    ylabel(10(10)60, angle(0) grid labsize(small)) ///
    xtick(2021(1)2025, labsize(small)) ///
    xtitle("Año", size(small)) ///
    ytitle("% (media anual ponderada)", size(small)) ///
    graphregion(color(white)) bgcolor(white)
graph export "tasa_paro_juvenil_CCAA_anual_recompuesto.png", width(2800) replace
restore


/********************************************************************************
* SECTION 2: Do_file_intermedio.do
********************************************************************************/

clear all
if "${PROJECT_ROOT}" == "" {
    global PROJECT_ROOT "."
}
set more off

********************************************************************************
* 0) RUTAS Y PARÁMETROS
********************************************************************************

local root "${PROJECT_ROOT}\98.IMPACTO DEL PLAN\1. FP\epa\dta"

local out  "${PROJECT_ROOT}\98.IMPACTO DEL PLAN\1. FP\epa\resultados_fp_paro"
capture mkdir "`out'"

local files epa_2021t1.dta epa_2021t2.dta epa_2021t3.dta epa_2021t4.dta ///
            epa_2022t1.dta epa_2022t2.dta epa_2022t3.dta epa_2022t4.dta ///
            epa_2023t1.dta epa_2023t2.dta epa_2023t3.dta epa_2023t4.dta ///
            epa_2024t1.dta epa_2024t2.dta epa_2024t3.dta epa_2024t4.dta ///
            epa_2025t1.dta epa_2025t2.dta epa_2025t3.dta epa_2025t4.dta ///
            epa_2026t1.dta

* Jóvenes menores de 25
local edad_max 25

* Usar pesos EPA
local useweights 1

* Código de estar cursando FP en NFORMA
local fp_code "SP"


********************************************************************************
* 1) CONSTRUIR PANEL CCAA × TRIMESTRE
********************************************************************************

tempfile acum_ccaa
clear
save `acum_ccaa', emptyok

foreach f of local files {

    di as result ">>> Procesando: `f'"

    local full "`root'/`f'"

    capture confirm file "`full'"
    if _rc {
        di as error "    No existe: `full'. Se salta."
        continue
    }

    use "`full'", clear

    *------------------------------------------------------
    * 1.1 Asegurar variables básicas
    *------------------------------------------------------

    foreach v in CCAA PROV EDAD1 AOI FACTOREL ACT1 CICLO {
        capture confirm variable `v'
        if !_rc {
            capture confirm numeric variable `v'
            if _rc {
                destring `v', replace ignore(" .")
            }
        }
    }

    *------------------------------------------------------
    * 1.2 Filtrar jóvenes y FP
    *------------------------------------------------------

    keep if EDAD1 < `edad_max'

    capture confirm variable NFORMA
    if _rc {
        di as error "    NFORMA no existe en `f'. Se salta."
        continue
    }

    capture confirm string variable NFORMA
    if !_rc {
        replace NFORMA = upper(strtrim(NFORMA))
        keep if NFORMA == "`fp_code'"
    }
    else {
        capture decode NFORMA, gen(NFORMA_str)
        if _rc {
            di as error "    NFORMA es numérica sin etiqueta decodificable. Se salta `f'."
            continue
        }
        replace NFORMA_str = upper(strtrim(NFORMA_str))
        keep if NFORMA_str == "`fp_code'"
    }

    drop if missing(AOI) | missing(CCAA)

    *------------------------------------------------------
    * 1.3 Clasificar situación laboral
    *------------------------------------------------------

    gen byte grupo_actividad = .
    replace grupo_actividad = 1 if inlist(AOI, 3, 4)      // Ocupados
    replace grupo_actividad = 2 if inlist(AOI, 5, 6)      // Parados
    replace grupo_actividad = 3 if inlist(AOI, 7, 8, 9)   // Inactivos

    drop if missing(grupo_actividad)

    *------------------------------------------------------
    * 1.4 Identificadores temporales
    *------------------------------------------------------

    capture assert !missing(CICLO)

    if !_rc {
        gen anio = 2021 + floor((CICLO - 194) / 4)
        gen trim = mod(CICLO - 194, 4) + 1
    }
    else {
        local base = subinstr("`f'", ".dta", "", .)
        local yy = real(substr("`base'", 5, 4))
        local tt = real(substr("`base'", 10, 1))

        gen anio = `yy'
        gen trim = `tt'
    }

    gen str7 periodo = string(anio) + "T" + string(trim)
    gen tq = yq(anio, trim)
    format tq %tq

    *------------------------------------------------------
    * 1.5 Pesos
    *------------------------------------------------------

    gen double w = 1

    if `useweights' == 1 {
        capture confirm variable FACTOREL
        if _rc {
            di as error "    FACTOREL no existe en `f'. Se salta."
            continue
        }
        replace w = FACTOREL
    }

    drop if missing(w)

    *------------------------------------------------------
    * 1.6 Totales ponderados
    *------------------------------------------------------

    gen double w_total = w
    gen double w_ocup  = cond(grupo_actividad == 1, w, 0)
    gen double w_paro  = cond(grupo_actividad == 2, w, 0)
    gen double w_inact = cond(grupo_actividad == 3, w, 0)

    collapse ///
        (sum) w_total w_ocup w_paro w_inact, ///
        by(CCAA anio trim periodo tq)

    rename w_total total_jovenes_fp
    rename w_ocup  ocupados
    rename w_paro  parados
    rename w_inact inactivos

    gen double activos = ocupados + parados

    *------------------------------------------------------
    * 1.7 Tasas trimestrales
    *------------------------------------------------------

    gen double tasa_paro_joven = 100 * parados / activos if activos > 0

    * Esta es la que venías usando: ocupados / activos.
    * No es tasa de empleo estándar, sino ocupados entre activos.
    gen double tasa_ocup_activos = 100 * ocupados / activos if activos > 0

    * Esta sí es la tasa de empleo juvenil estándar: ocupados / población joven FP.
    gen double tasa_empleo_joven = 100 * ocupados / total_jovenes_fp if total_jovenes_fp > 0

    gen double tasa_actividad_joven = 100 * activos / total_jovenes_fp if total_jovenes_fp > 0

    label var total_jovenes_fp      "Total jóvenes <25 cursando FP, ponderado"
    label var ocupados             "Ocupados <25 FP, ponderado"
    label var parados              "Parados <25 FP, ponderado"
    label var inactivos            "Inactivos <25 FP, ponderado"
    label var activos              "Activos <25 FP, ponderado"
    label var tasa_paro_joven      "Tasa de paro juvenil FP: parados / activos"
    label var tasa_ocup_activos    "Ocupados sobre activos jóvenes FP"
    label var tasa_empleo_joven    "Tasa de empleo juvenil FP: ocupados / total jóvenes FP"
    label var tasa_actividad_joven "Tasa de actividad juvenil FP: activos / total jóvenes FP"

    keep CCAA anio trim periodo tq total_jovenes_fp ocupados parados inactivos activos ///
         tasa_paro_joven tasa_ocup_activos tasa_empleo_joven tasa_actividad_joven

    append using `acum_ccaa'
    save `acum_ccaa', replace
}


********************************************************************************
* 2) CARGAR PANEL FINAL Y AÑADIR NOMBRES DE CCAA
********************************************************************************

use `acum_ccaa', clear

order anio trim periodo tq CCAA total_jovenes_fp ocupados parados inactivos activos ///
      tasa_paro_joven tasa_ocup_activos tasa_empleo_joven tasa_actividad_joven

sort CCAA tq

gen byte ccaa_cod = CCAA

label define lbl_ccaa ///
    1  "Andalucía" ///
    2  "Aragón" ///
    3  "Asturias, Principado de" ///
    4  "Balears, Illes" ///
    5  "Canarias" ///
    6  "Cantabria" ///
    7  "Castilla y León" ///
    8  "Castilla - La Mancha" ///
    9  "Cataluña" ///
    10 "Comunitat Valenciana" ///
    11 "Extremadura" ///
    12 "Galicia" ///
    13 "Madrid, Comunidad de" ///
    14 "Murcia, Región de" ///
    15 "Navarra, Comunidad Foral de" ///
    16 "País Vasco" ///
    17 "Rioja, La" ///
    18 "Ceuta" ///
    19 "Melilla", replace

label values ccaa_cod lbl_ccaa
decode ccaa_cod, gen(ccaa_nombre)

replace ccaa_nombre = subinstr(ccaa_nombre, ",", "", .)

save "`out'\EPA_FP_joven_CCAA_trimestral_2021T1_2026T1.dta", replace
export excel using "`out'\EPA_FP_joven_CCAA_trimestral_2021T1_2026T1.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 3) MEDIA MÓVIL DE 4 TRIMESTRES RECOMPONIENDO DESDE TOTALES
********************************************************************************

xtset CCAA tq

gen double parados_4q         = parados + L1.parados + L2.parados + L3.parados
gen double ocupados_4q        = ocupados + L1.ocupados + L2.ocupados + L3.ocupados
gen double activos_4q         = activos + L1.activos + L2.activos + L3.activos
gen double total_jovenes_fp_4q = total_jovenes_fp + L1.total_jovenes_fp + L2.total_jovenes_fp + L3.total_jovenes_fp

gen double tasa_paro_joven_4q = 100 * parados_4q / activos_4q if activos_4q > 0

gen double tasa_ocup_activos_4q = 100 * ocupados_4q / activos_4q if activos_4q > 0

gen double tasa_empleo_joven_4q = 100 * ocupados_4q / total_jovenes_fp_4q ///
    if total_jovenes_fp_4q > 0

gen double tasa_actividad_joven_4q = 100 * activos_4q / total_jovenes_fp_4q ///
    if total_jovenes_fp_4q > 0

label var tasa_paro_joven_4q      "Tasa de paro juvenil FP, media móvil 4T"
label var tasa_ocup_activos_4q    "Ocupados/activos jóvenes FP, media móvil 4T"
label var tasa_empleo_joven_4q    "Tasa de empleo juvenil FP, media móvil 4T"
label var tasa_actividad_joven_4q "Tasa de actividad juvenil FP, media móvil 4T"


********************************************************************************
* 4) AJUSTE ALTERNATIVO POR EFECTOS FIJOS DE TRIMESTRE
********************************************************************************

* Esta opción estima un componente estacional común de T1, T2, T3 y T4,
* controlando por CCAA y por tendencia temporal lineal.

gen double tq_num = tq

reg tasa_paro_joven i.CCAA c.tq_num ib1.trim [aw = activos]

gen double seasonal_paro_raw = 0
capture replace seasonal_paro_raw = _b[2.trim] if trim == 2
capture replace seasonal_paro_raw = _b[3.trim] if trim == 3
capture replace seasonal_paro_raw = _b[4.trim] if trim == 4

summ seasonal_paro_raw [aw = activos]
gen double seasonal_paro_centered = seasonal_paro_raw - r(mean)

gen double tasa_paro_joven_sa_fe = tasa_paro_joven - seasonal_paro_centered

label var tasa_paro_joven_sa_fe "Tasa de paro juvenil FP ajustada por FE de trimestre"


********************************************************************************
* 5) GUARDAR PANEL CON VARIABLES SUAVIZADAS / AJUSTADAS
********************************************************************************

save "`out'\EPA_FP_joven_CCAA_trimestral_con_4T_y_FE.dta", replace
export excel using "`out'\EPA_FP_joven_CCAA_trimestral_con_4T_y_FE.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 6) GRÁFICOS PRINCIPALES
********************************************************************************

*------------------------------------------------------
* 6.1 Tasa de paro juvenil FP: original vs media móvil 4T
*------------------------------------------------------

twoway ///
    (line tasa_paro_joven tq, lcolor(red) lpattern(dash) lwidth(thin)) ///
    (line tasa_paro_joven_4q tq, lcolor(red) lwidth(medthick)), ///
    by(ccaa_nombre, cols(4) note("") ///
        title("Tasa de paro juvenil FP por CCAA: trimestral vs media móvil 4T", size(medsmall))) ///
    legend(order(1 "Trimestral" 2 "Media móvil 4T") pos(6) ring(0)) ///
    ylabel(0(10)70, angle(0) grid labsize(small)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("% de activos", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_paro_original_4q, replace)

graph export "`out'\grafico_paro_FP_CCAA_trimestral_vs_media_movil_4T.png", ///
    width(3200) replace

graph save "`out'\grafico_paro_FP_CCAA_trimestral_vs_media_movil_4T.gph", replace


*------------------------------------------------------
* 6.2 Tasa de paro juvenil FP: original vs FE trimestre
*------------------------------------------------------

twoway ///
    (line tasa_paro_joven tq, lcolor(red) lpattern(dash) lwidth(thin)) ///
    (line tasa_paro_joven_sa_fe tq, lcolor(blue) lwidth(medthick)), ///
    by(ccaa_nombre, cols(4) note("") ///
        title("Tasa de paro juvenil FP por CCAA: original vs ajuste por trimestre", size(medsmall))) ///
    legend(order(1 "Original" 2 "Ajustada por FE de trimestre") pos(6) ring(0)) ///
    ylabel(0(10)70, angle(0) grid labsize(small)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("% de activos", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_paro_sa_fe, replace)

graph export "`out'\grafico_paro_FP_CCAA_original_vs_FE_trimestre.png", ///
    width(3200) replace

graph save "`out'\grafico_paro_FP_CCAA_original_vs_FE_trimestre.gph", replace


*------------------------------------------------------
* 6.3 Ocupados/activos y paro, ambos con media móvil 4T
*     OJO: son complementarios. Suman aproximadamente 100.
*------------------------------------------------------

twoway ///
    (line tasa_ocup_activos_4q tq, lcolor(blue) lwidth(medthick)) ///
    (line tasa_paro_joven_4q tq, lcolor(red) lpattern(dash) lwidth(medthick)), ///
    by(ccaa_nombre, cols(4) note("") ///
        title("Jóvenes FP activos: ocupación y paro, media móvil 4T", size(medsmall))) ///
    legend(order(1 "Ocupados / activos" 2 "Parados / activos") pos(6) ring(0)) ///
    ylabel(0(20)100, angle(0) grid labsize(small)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("% de activos", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_ocup_paro_4q, replace)

graph export "`out'\grafico_ocupacion_y_paro_FP_CCAA_media_movil_4T.png", ///
    width(3200) replace

graph save "`out'\grafico_ocupacion_y_paro_FP_CCAA_media_movil_4T.gph", replace


*------------------------------------------------------
* 6.4 Tasa de empleo juvenil FP real: ocupados / total jóvenes FP
*------------------------------------------------------

twoway ///
    (line tasa_empleo_joven tq, lcolor(gs8) lpattern(dash) lwidth(thin)) ///
    (line tasa_empleo_joven_4q tq, lcolor(blue) lwidth(medthick)), ///
    by(ccaa_nombre, cols(4) note("") ///
        title("Tasa de empleo juvenil FP por CCAA: trimestral vs media móvil 4T", size(medsmall))) ///
    legend(order(1 "Trimestral" 2 "Media móvil 4T") pos(6) ring(0)) ///
    ylabel(0(10)80, angle(0) grid labsize(small)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("% sobre total jóvenes FP", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_empleo_4q, replace)

graph export "`out'\grafico_empleo_FP_CCAA_trimestral_vs_media_movil_4T.png", ///
    width(3200) replace

graph save "`out'\grafico_empleo_FP_CCAA_trimestral_vs_media_movil_4T.gph", replace


********************************************************************************
* 7) AGREGACIÓN ANUAL RECOMPUESTA DESDE TOTALES
********************************************************************************

preserve

collapse ///
    (sum) ocupados parados inactivos activos total_jovenes_fp ///
    (count) n_trim = tq, ///
    by(CCAA anio ccaa_nombre)

* Evitar años incompletos, por ejemplo 2026 si solo tienes T1
keep if n_trim == 4

gen double tasa_paro_joven_anual = 100 * parados / activos if activos > 0

gen double tasa_ocup_activos_anual = 100 * ocupados / activos if activos > 0

gen double tasa_empleo_joven_anual = 100 * ocupados / total_jovenes_fp ///
    if total_jovenes_fp > 0

gen double tasa_actividad_joven_anual = 100 * activos / total_jovenes_fp ///
    if total_jovenes_fp > 0

label var tasa_paro_joven_anual      "Tasa de paro juvenil FP anual"
label var tasa_ocup_activos_anual    "Ocupados/activos jóvenes FP anual"
label var tasa_empleo_joven_anual    "Tasa de empleo juvenil FP anual"
label var tasa_actividad_joven_anual "Tasa de actividad juvenil FP anual"

order anio CCAA ccaa_nombre n_trim total_jovenes_fp ocupados parados inactivos activos ///
      tasa_paro_joven_anual tasa_ocup_activos_anual tasa_empleo_joven_anual ///
      tasa_actividad_joven_anual

sort CCAA anio

save "`out'\EPA_FP_joven_CCAA_anual_recompuesto.dta", replace
export excel using "`out'\EPA_FP_joven_CCAA_anual_recompuesto.xlsx", ///
    replace firstrow(variables)


*------------------------------------------------------
* 7.1 Gráfico anual de paro juvenil FP
*------------------------------------------------------

twoway connected tasa_paro_joven_anual anio, ///
    by(ccaa_nombre, cols(4) note("") ///
        title("Tasa de paro juvenil FP por CCAA, anual recompuesta", size(medsmall)) ///
        imargin(tiny)) ///
    ylabel(0(10)70, angle(0) grid labsize(small)) ///
    xlabel(2021(1)2025, labsize(small)) ///
    xtitle("Año", size(small)) ///
    ytitle("% de activos", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_paro_anual, replace)

graph export "`out'\grafico_paro_FP_CCAA_anual_recompuesto.png", ///
    width(3200) replace

graph save "`out'\grafico_paro_FP_CCAA_anual_recompuesto.gph", replace

restore


********************************************************************************
* 8) MENSAJE FINAL
********************************************************************************

di as result "============================================================"
di as result "Proceso completado."
di as result "Resultados guardados en:"
di as result "`out'"
di as result "============================================================"


/********************************************************************************
* SECTION 3: Do_file_comparación_FP_noFP(1).do
********************************************************************************/

clear all
if "${PROJECT_ROOT}" == "" {
    global PROJECT_ROOT "."
}
set more off

********************************************************************************
* 0) RUTAS Y PARÁMETROS
********************************************************************************

local root "${PROJECT_ROOT}\98.IMPACTO DEL PLAN\1. FP\epa\dta"

local files epa_2021t1.dta epa_2021t2.dta epa_2021t3.dta epa_2021t4.dta ///
             epa_2022t1.dta epa_2022t2.dta epa_2022t3.dta epa_2022t4.dta ///
             epa_2023t1.dta epa_2023t2.dta epa_2023t3.dta epa_2023t4.dta ///
             epa_2024t1.dta epa_2024t2.dta epa_2024t3.dta epa_2024t4.dta ///
             epa_2025t1.dta epa_2025t2.dta epa_2025t3.dta epa_2025t4.dta ///
             epa_2026t1.dta

local useweights 1

tempfile acum_ccaa
clear
save `acum_ccaa', emptyok


********************************************************************************
* 1) CONSTRUIR PANEL CCAA × TRIMESTRE × FP/NO FP
********************************************************************************

foreach f of local files {

    di as result ">>> Procesando: `f'"

    quietly {

        local full = "`root'/`f'"

        capture confirm file "`full'"
        if _rc {
            di as error "   No existe: `full' -> salto"
            continue
        }

        use "`full'", clear

        *------------------------------------------------------
        * 1.1 Asegurar tipos numéricos mínimos
        *------------------------------------------------------

        foreach v in CCAA PROV EDAD1 AOI FACTOREL CICLO {
            capture confirm numeric variable `v'
            if _rc != 0 {
                destring `v', replace ignore(" .")
            }
        }

        *------------------------------------------------------
        * 1.2 Filtrar jóvenes menores de 25
        *------------------------------------------------------

        keep if EDAD1 < 25

        drop if missing(AOI) | missing(CCAA)

        *------------------------------------------------------
        * 1.3 Crear grupo FP vs no FP
        *------------------------------------------------------

        capture confirm variable NFORMA
        if _rc {
            di as error "   NFORMA no existe en `f' -> salto"
            continue
        }

        capture confirm string variable NFORMA

        if !_rc {
            gen str20 nforma_str = upper(strtrim(NFORMA))
        }
        else {
            capture decode NFORMA, gen(nforma_str)
            if _rc {
                tostring NFORMA, gen(nforma_str) force
            }
            replace nforma_str = upper(strtrim(nforma_str))
        }

        gen byte fp_group = .
        replace fp_group = 1 if nforma_str == "SP"
        replace fp_group = 0 if nforma_str != "SP" & !missing(nforma_str)

        /*
        IMPORTANTE:
        Con esta definición, "no FP" significa jóvenes con NFORMA observada
        pero distinta de "SP".

        Si en tu EPA los missing de NFORMA significan "no cursa estudios" y quieres
        incluirlos dentro de "no FP", activa esta línea:

        replace fp_group = 0 if missing(nforma_str)
        */

        drop if missing(fp_group)

        label define lbl_fp_group 0 "No FP" 1 "FP", replace
        label values fp_group lbl_fp_group

        *------------------------------------------------------
        * 1.4 Clasificar situación laboral AOI
        *------------------------------------------------------

        gen byte grupo_actividad = .
        replace grupo_actividad = 1 if inlist(AOI, 3, 4)      // Ocupados
        replace grupo_actividad = 2 if inlist(AOI, 5, 6)      // Parados
        replace grupo_actividad = 3 if inlist(AOI, 7, 8, 9)   // Inactivos

        drop if missing(grupo_actividad)

        *------------------------------------------------------
        * 1.5 Identificadores temporales
        *------------------------------------------------------

        capture assert !missing(CICLO)

        if !_rc {
            gen anio = 2021 + floor((CICLO - 194) / 4)
            gen trim = mod(CICLO - 194, 4) + 1
        }
        else {
            local base = subinstr("`f'", ".dta", "", .)
            local yy = real(substr("`base'", 5, 4))
            local tt = real(substr("`base'", 10, 1))

            gen anio = `yy'
            gen trim = `tt'
        }

        gen str7 periodo = string(anio) + "T" + string(trim)
        gen tq = yq(anio, trim)
        format tq %tq

        *------------------------------------------------------
        * 1.6 Pesos
        *------------------------------------------------------

        gen double w = cond(`useweights', FACTOREL, 1)

        gen double w_total = w
        gen double w_ocup  = cond(grupo_actividad == 1, w, 0)
        gen double w_paro  = cond(grupo_actividad == 2, w, 0)
        gen double w_inact = cond(grupo_actividad == 3, w, 0)

        *------------------------------------------------------
        * 1.7 Agregar por CCAA × trimestre × FP/no FP
        *------------------------------------------------------

        collapse ///
            (sum) w_total w_ocup w_paro w_inact, ///
            by(CCAA anio trim periodo tq fp_group)

        rename w_total total_jovenes
        rename w_ocup  ocupados
        rename w_paro  parados
        rename w_inact inactivos

        gen double activos = ocupados + parados

        gen double tasa_paro_joven = 100 * parados / activos if activos > 0
        gen double tasa_ocup_activos = 100 * ocupados / activos if activos > 0

        label var total_jovenes      "Total jóvenes <25 ponderado"
        label var ocupados           "Ocupados <25 ponderado"
        label var parados            "Parados <25 ponderado"
        label var inactivos          "Inactivos <25 ponderado"
        label var activos            "Activos <25 ponderado"
        label var tasa_paro_joven    "Tasa de paro juvenil: parados / activos"
        label var tasa_ocup_activos  "Ocupados / activos jóvenes"

        keep CCAA anio trim periodo tq fp_group total_jovenes ocupados parados ///
             inactivos activos tasa_paro_joven tasa_ocup_activos

        append using `acum_ccaa'
        save `acum_ccaa', replace
    }
}


********************************************************************************
* 2) CARGAR PANEL FINAL Y AÑADIR NOMBRES DE CCAA
********************************************************************************

use `acum_ccaa', clear

sort CCAA fp_group tq

gen byte ccaa_cod = CCAA

label define lbl_ccaa ///
    1  "Andalucía" ///
    2  "Aragón" ///
    3  "Asturias, Principado de" ///
    4  "Balears, Illes" ///
    5  "Canarias" ///
    6  "Cantabria" ///
    7  "Castilla y León" ///
    8  "Castilla - La Mancha" ///
    9  "Cataluña" ///
    10 "Comunitat Valenciana" ///
    11 "Extremadura" ///
    12 "Galicia" ///
    13 "Madrid, Comunidad de" ///
    14 "Murcia, Región de" ///
    15 "Navarra, Comunidad Foral de" ///
    16 "País Vasco" ///
    17 "Rioja, La" ///
    18 "Ceuta" ///
    19 "Melilla", replace

label values ccaa_cod lbl_ccaa
decode ccaa_cod, gen(ccaa_nombre)

replace ccaa_nombre = subinstr(ccaa_nombre, ",", "", .)

label define lbl_fp_group 0 "No FP" 1 "FP", replace
label values fp_group lbl_fp_group

save "EPA_joven_FP_vs_noFP_CCAA_trimestral_long.dta", replace

export excel using "EPA_joven_FP_vs_noFP_CCAA_trimestral_long.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 3) MEDIA MÓVIL 4T RECOMPUESTA DESDE TOTALES
********************************************************************************

egen panel_id = group(CCAA fp_group)
xtset panel_id tq

gen double parados_4q  = parados  + L1.parados  + L2.parados  + L3.parados
gen double ocupados_4q = ocupados + L1.ocupados + L2.ocupados + L3.ocupados
gen double activos_4q  = activos  + L1.activos  + L2.activos  + L3.activos

gen double tasa_paro_joven_4q = 100 * parados_4q / activos_4q if activos_4q > 0
gen double tasa_ocup_activos_4q = 100 * ocupados_4q / activos_4q if activos_4q > 0

label var tasa_paro_joven_4q "Tasa de paro juvenil, media móvil 4T"
label var tasa_ocup_activos_4q "Ocupados / activos jóvenes, media móvil 4T"

save "EPA_joven_FP_vs_noFP_CCAA_trimestral_long_con_4T.dta", replace


********************************************************************************
* 4) PASAR A FORMATO WIDE PARA COMPARAR FP VS NO FP
********************************************************************************

preserve

keep CCAA ccaa_nombre anio trim periodo tq fp_group ///
     total_jovenes ocupados parados inactivos activos ///
     tasa_paro_joven tasa_ocup_activos tasa_paro_joven_4q tasa_ocup_activos_4q

reshape wide total_jovenes ocupados parados inactivos activos ///
             tasa_paro_joven tasa_ocup_activos tasa_paro_joven_4q tasa_ocup_activos_4q, ///
             i(CCAA ccaa_nombre anio trim periodo tq) j(fp_group)

* Variables con sufijo 1 = FP
* Variables con sufijo 0 = No FP

label var tasa_paro_joven1 "Tasa de paro juvenil FP"
label var tasa_paro_joven0 "Tasa de paro juvenil no FP"

label var tasa_paro_joven_4q1 "Tasa de paro juvenil FP, media móvil 4T"
label var tasa_paro_joven_4q0 "Tasa de paro juvenil no FP, media móvil 4T"


********************************************************************************
* 5) DIFERENCIAS DE NIVEL: FP - NO FP
********************************************************************************

gen double gap_paro_fp_nofp = tasa_paro_joven1 - tasa_paro_joven0

gen double gap_paro_fp_nofp_4q = tasa_paro_joven_4q1 - tasa_paro_joven_4q0

label var gap_paro_fp_nofp "Brecha paro juvenil: FP - no FP"
label var gap_paro_fp_nofp_4q "Brecha paro juvenil: FP - no FP, media móvil 4T"


********************************************************************************
* 6) REDUCCIÓN DESDE 2021T1
********************************************************************************

local base = yq(2021, 1)

bysort CCAA: egen base_paro_fp = max(cond(tq == `base', tasa_paro_joven1, .))
bysort CCAA: egen base_paro_nofp = max(cond(tq == `base', tasa_paro_joven0, .))

gen double reduccion_paro_fp = base_paro_fp - tasa_paro_joven1
gen double reduccion_paro_nofp = base_paro_nofp - tasa_paro_joven0

gen double diferencia_reduccion_fp_nofp = reduccion_paro_fp - reduccion_paro_nofp

label var reduccion_paro_fp "Reducción paro juvenil FP desde 2021T1"
label var reduccion_paro_nofp "Reducción paro juvenil no FP desde 2021T1"
label var diferencia_reduccion_fp_nofp "Diferencia en reducción del paro: FP - no FP"

* Interpretación:
* diferencia_reduccion_fp_nofp > 0  => el paro FP ha caído más que el no FP
* diferencia_reduccion_fp_nofp < 0  => el paro no FP ha caído más que el FP


********************************************************************************
* 7) REDUCCIÓN DESDE 2021T4 USANDO MEDIA MÓVIL 4T
********************************************************************************

local base4 = yq(2021, 4)

bysort CCAA: egen base_paro_fp_4q = max(cond(tq == `base4', tasa_paro_joven_4q1, .))
bysort CCAA: egen base_paro_nofp_4q = max(cond(tq == `base4', tasa_paro_joven_4q0, .))

gen double reduccion_paro_fp_4q = base_paro_fp_4q - tasa_paro_joven_4q1
gen double reduccion_paro_nofp_4q = base_paro_nofp_4q - tasa_paro_joven_4q0

gen double diferencia_reduccion_fp_nofp_4q = reduccion_paro_fp_4q - reduccion_paro_nofp_4q

label var reduccion_paro_fp_4q "Reducción paro juvenil FP desde 2021T4, media móvil 4T"
label var reduccion_paro_nofp_4q "Reducción paro juvenil no FP desde 2021T4, media móvil 4T"
label var diferencia_reduccion_fp_nofp_4q "Diferencia en reducción del paro: FP - no FP, media móvil 4T"


********************************************************************************
* 8) GUARDAR BASE COMPARATIVA
********************************************************************************

save "EPA_joven_FP_vs_noFP_CCAA_comparacion_wide.dta", replace

export excel using "EPA_joven_FP_vs_noFP_CCAA_comparacion_wide.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 9) GRÁFICO 1: TASA DE PARO FP VS NO FP
********************************************************************************

twoway ///
    (line tasa_paro_joven1 tq, lcolor(red) lwidth(medthick)) ///
    (line tasa_paro_joven0 tq, lcolor(blue) lpattern(dash) lwidth(medthick)), ///
    by(ccaa_nombre, cols(4) note("") ///
        title("Tasa de paro juvenil: FP vs no FP", size(medsmall))) ///
    legend(order(1 "FP" 2 "No FP") pos(6) ring(0)) ///
    ylabel(15(5)55, angle(0) grid labsize(small)) ///
    yscale(range(15 55)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("% de activos", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_paro_fp_vs_nofp, replace)

graph export "grafico_paro_joven_FP_vs_noFP_CCAA_15_55.png", ///
    width(3200) replace

graph save "grafico_paro_joven_FP_vs_noFP_CCAA_15_55.gph", replace


********************************************************************************
* 10) GRÁFICO 2: TASA DE PARO FP VS NO FP, MEDIA MÓVIL 4T
********************************************************************************

twoway ///
    (line tasa_paro_joven_4q1 tq, lcolor(red) lwidth(medthick)) ///
    (line tasa_paro_joven_4q0 tq, lcolor(blue) lpattern(dash) lwidth(medthick)), ///
    by(ccaa_nombre, cols(4) note("") ///
        title("Tasa de paro juvenil: FP vs no FP, media móvil 4T", size(medsmall))) ///
    legend(order(1 "FP" 2 "No FP") pos(6) ring(0)) ///
    ylabel(15(5)55, angle(0) grid labsize(small)) ///
    yscale(range(15 55)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("% de activos", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_paro_fp_vs_nofp_4q, replace)

graph export "grafico_paro_joven_FP_vs_noFP_CCAA_media_movil_4T_15_55.png", ///
    width(3200) replace

graph save "grafico_paro_joven_FP_vs_noFP_CCAA_media_movil_4T_15_55.gph", replace


********************************************************************************
* 11) GRÁFICO 3: BRECHA FP - NO FP
********************************************************************************

twoway ///
    (line gap_paro_fp_nofp_4q tq, lcolor(black) lwidth(medthick)), ///
    by(ccaa_nombre, cols(4) note("") ///
        title("Brecha de paro juvenil: FP - no FP, media móvil 4T", size(medsmall))) ///
    yline(0, lcolor(gs8) lpattern(dash)) ///
    ylabel(-20(5)20, angle(0) grid labsize(small)) ///
    yscale(range(-20 20)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("Puntos porcentuales", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_gap_fp_nofp_4q, replace)

graph export "grafico_brecha_paro_joven_FP_menos_noFP_CCAA_4T.png", ///
    width(3200) replace

graph save "grafico_brecha_paro_joven_FP_menos_noFP_CCAA_4T.gph", replace


********************************************************************************
* 12) GRÁFICO 4: DIFERENCIA EN REDUCCIÓN DEL PARO
********************************************************************************

twoway ///
    (line diferencia_reduccion_fp_nofp_4q tq, lcolor(black) lwidth(medthick)), ///
    by(ccaa_nombre, cols(4) note("") ///
        title("Diferencia en reducción del paro juvenil: FP - no FP", size(medsmall))) ///
    yline(0, lcolor(gs8) lpattern(dash)) ///
    ylabel(-20(5)20, angle(0) grid labsize(small)) ///
    yscale(range(-20 20)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("Puntos porcentuales desde 2021T4", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_diff_reduccion_fp_nofp_4q, replace)

graph export "grafico_diferencia_reduccion_paro_joven_FP_vs_noFP_CCAA_4T.png", ///
    width(3200) replace

graph save "grafico_diferencia_reduccion_paro_joven_FP_vs_noFP_CCAA_4T.gph", replace

restore

di as result "Proceso completado correctamente."


use "EPA_joven_FP_vs_noFP_CCAA_trimestral_long.dta", clear

*------------------------------------------------------
* 1) Agregar a nivel nacional por trimestre y grupo FP/no FP
*------------------------------------------------------
collapse (sum) total_jovenes ocupados parados inactivos activos, by(anio trim periodo tq fp_group)

* Recalcular tasas nacionales
gen double tasa_paro_joven = 100 * parados / activos if activos > 0
gen double tasa_ocup_activos = 100 * ocupados / activos if activos > 0

label define lbl_fp_group 0 "No FP" 1 "FP", replace
label values fp_group lbl_fp_group

sort fp_group tq

save "EPA_joven_FP_vs_noFP_NACIONAL_trimestral_long.dta", replace


*------------------------------------------------------
* 2) Media móvil 4T recompuesta desde totales
*------------------------------------------------------
egen panel_id = group(fp_group)
xtset panel_id tq

gen double parados_4q  = parados  + L1.parados  + L2.parados  + L3.parados
gen double ocupados_4q = ocupados + L1.ocupados + L2.ocupados + L3.ocupados
gen double activos_4q  = activos  + L1.activos  + L2.activos  + L3.activos

gen double tasa_paro_joven_4q = 100 * parados_4q / activos_4q if activos_4q > 0
gen double tasa_ocup_activos_4q = 100 * ocupados_4q / activos_4q if activos_4q > 0

label var tasa_paro_joven_4q "Tasa de paro juvenil nacional, media móvil 4T"
label var tasa_ocup_activos_4q "Ocupados/activos jóvenes nacional, media móvil 4T"


*------------------------------------------------------
* 3) Pasar a formato wide para comparar FP vs no FP
*------------------------------------------------------

drop panel_id

reshape wide total_jovenes ocupados parados inactivos activos ///
             tasa_paro_joven tasa_ocup_activos ///
             parados_4q ocupados_4q activos_4q ///
             tasa_paro_joven_4q tasa_ocup_activos_4q, ///
             i(anio trim periodo tq) j(fp_group)

* sufijo 1 = FP
* sufijo 0 = No FP

label var tasa_paro_joven1 "Tasa de paro juvenil FP"
label var tasa_paro_joven0 "Tasa de paro juvenil no FP"
label var tasa_paro_joven_4q1 "Tasa de paro juvenil FP, media móvil 4T"
label var tasa_paro_joven_4q0 "Tasa de paro juvenil no FP, media móvil 4T"


*------------------------------------------------------
* 4) Brecha FP - No FP
*------------------------------------------------------
gen double gap_paro_fp_nofp = tasa_paro_joven1 - tasa_paro_joven0
gen double gap_paro_fp_nofp_4q = tasa_paro_joven_4q1 - tasa_paro_joven_4q0

label var gap_paro_fp_nofp "Brecha nacional de paro juvenil: FP - no FP"
label var gap_paro_fp_nofp_4q "Brecha nacional de paro juvenil: FP - no FP, media móvil 4T"


*------------------------------------------------------
* 5) Diferencia en reducción del paro desde 2021T4
*    (mejor usar base 2021T4 porque ahí ya existe media móvil 4T)
*------------------------------------------------------
local base4 = yq(2021,4)

egen base_paro_fp_4q   = max(cond(tq == `base4', tasa_paro_joven_4q1, .))
egen base_paro_nofp_4q = max(cond(tq == `base4', tasa_paro_joven_4q0, .))

gen double reduccion_paro_fp_4q   = base_paro_fp_4q   - tasa_paro_joven_4q1
gen double reduccion_paro_nofp_4q = base_paro_nofp_4q - tasa_paro_joven_4q0

gen double diferencia_reduccion_fp_nofp_4q = reduccion_paro_fp_4q - reduccion_paro_nofp_4q

label var diferencia_reduccion_fp_nofp_4q ///
    "Diferencia en reducción del paro nacional: FP - no FP, media móvil 4T"

save "EPA_joven_FP_vs_noFP_NACIONAL_wide.dta", replace


*------------------------------------------------------
* 6) GRÁFICO 1: tasas nacionales FP vs no FP
*------------------------------------------------------
twoway ///
    (line tasa_paro_joven_4q1 tq, lcolor(red) lwidth(medthick)) ///
    (line tasa_paro_joven_4q0 tq, lcolor(blue) lpattern(dash) lwidth(medthick)), ///
    legend(order(1 "FP" 2 "No FP") pos(6) ring(0)) ///
    ylabel(15(5)55, angle(0) grid) ///
    yscale(range(15 55)) ///
    xlabel(, angle(45)) ///
    xtitle("Trimestre") ///
    ytitle("% de activos") ///
    title("España: tasa de paro juvenil FP vs no FP", size(medium)) ///
    subtitle("Media móvil de 4 trimestres", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_nacional_fp_nofp, replace)

graph export "grafico_nacional_paro_FP_vs_noFP_4T.png", width(2400) replace
graph save   "grafico_nacional_paro_FP_vs_noFP_4T.gph", replace


*------------------------------------------------------
* 7) GRÁFICO 2: brecha FP - no FP
*------------------------------------------------------
twoway ///
    (line gap_paro_fp_nofp_4q tq, lcolor(black) lwidth(medthick)), ///
    yline(0, lcolor(gs8) lpattern(dash)) ///
    ylabel(-15(5)15, angle(0) grid) ///
    yscale(range(-15 15)) ///
    xlabel(, angle(45)) ///
    xtitle("Trimestre") ///
    ytitle("Puntos porcentuales") ///
    title("España: brecha de paro juvenil FP - no FP", size(medium)) ///
    subtitle("Media móvil de 4 trimestres", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_gap_nacional, replace)

graph export "grafico_nacional_brecha_FP_menos_noFP_4T.png", width(2400) replace
graph save   "grafico_nacional_brecha_FP_menos_noFP_4T.gph", replace


*------------------------------------------------------
* 8) GRÁFICO 3: diferencia en reducción del paro
*------------------------------------------------------
twoway ///
    (line diferencia_reduccion_fp_nofp_4q tq, lcolor(black) lwidth(medthick)), ///
    yline(0, lcolor(gs8) lpattern(dash)) ///
    ylabel(-15(5)15, angle(0) grid) ///
    yscale(range(-15 15)) ///
    xlabel(, angle(45)) ///
    xtitle("Trimestre") ///
    ytitle("Puntos porcentuales desde 2021T4") ///
    title("España: diferencia en la reducción del paro juvenil", size(medium)) ///
    subtitle("FP - no FP, media móvil de 4 trimestres", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_diff_red_nacional, replace)

graph export "grafico_nacional_diferencia_reduccion_FP_vs_noFP_4T.png", width(2400) replace
graph save   "grafico_nacional_diferencia_reduccion_FP_vs_noFP_4T.gph", replace


/********************************************************************************
* SECTION 4: Do_file_fp_vs_secundaria_fp_vs_unviersitarios_25_05_2026.do
********************************************************************************/

clear all
if "${PROJECT_ROOT}" == "" {
    global PROJECT_ROOT "."
}
set more off

********************************************************************************
* 0) RUTAS Y PARÁMETROS
********************************************************************************

local root "${PROJECT_ROOT}\98.IMPACTO DEL PLAN\1. FP\epa\dta"

local files epa_2021t1.dta epa_2021t2.dta epa_2021t3.dta epa_2021t4.dta ///
             epa_2022t1.dta epa_2022t2.dta epa_2022t3.dta epa_2022t4.dta ///
             epa_2023t1.dta epa_2023t2.dta epa_2023t3.dta epa_2023t4.dta ///
             epa_2024t1.dta epa_2024t2.dta epa_2024t3.dta epa_2024t4.dta ///
             epa_2025t1.dta epa_2025t2.dta epa_2025t3.dta epa_2025t4.dta ///
             epa_2026t1.dta

local useweights 1


********************************************************************************
* LOOP PRINCIPAL: FP VS SECUNDARIA O INFERIOR / FP VS UNIVERSITARIOS
********************************************************************************

foreach comparacion in secundaria_inferior universitarios {

    if "`comparacion'" == "secundaria_inferior" {
        local comp_label "Secundaria o inferior"
        local comp_title "secundaria o inferior"
        local comp_file  "secundaria_inferior"
    }

    if "`comparacion'" == "universitarios" {
        local comp_label "Universitarios"
        local comp_title "universitarios"
        local comp_file  "universitarios"
    }

    di as result "============================================================"
    di as result " Ejecutando comparación: FP vs `comp_label'"
    di as result "============================================================"

    tempfile acum_ccaa
    clear
    save `acum_ccaa', emptyok


    ********************************************************************************
    * 1) CONSTRUIR PANEL CCAA × TRIMESTRE × FP/COMPARADOR
    ********************************************************************************

    foreach f of local files {

        di as result ">>> Procesando: `f'"

        quietly {

            local full = "`root'/`f'"

            capture confirm file "`full'"
            if _rc {
                di as error "   No existe: `full' -> salto"
                continue
            }

            use "`full'", clear

            foreach v in CCAA PROV EDAD1 AOI FACTOREL CICLO {
                capture confirm numeric variable `v'
                if _rc != 0 {
                    destring `v', replace ignore(" .")
                }
            }

            keep if EDAD1 < 25
            drop if missing(AOI) | missing(CCAA)

            capture confirm variable NFORMA
            if _rc {
                di as error "   NFORMA no existe en `f' -> salto"
                continue
            }

            capture confirm string variable NFORMA
            if !_rc {
                gen str20 nforma_str = upper(strtrim(NFORMA))
            }
            else {
                capture decode NFORMA, gen(nforma_str)
                if _rc {
                    tostring NFORMA, gen(nforma_str) force
                }
                replace nforma_str = upper(strtrim(nforma_str))
            }

            gen byte fp_group = .

            replace fp_group = 1 if nforma_str == "SP"

            if "`comparacion'" == "secundaria_inferior" {
                replace fp_group = 0 if inlist(nforma_str, "AN", "P1", "P2", "S1", "SG")
            }

            if "`comparacion'" == "universitarios" {
                replace fp_group = 0 if nforma_str == "SU"
            }

            drop if missing(fp_group)

            label define lbl_fp_group 0 "`comp_label'" 1 "FP", replace
            label values fp_group lbl_fp_group

            gen byte grupo_actividad = .
            replace grupo_actividad = 1 if inlist(AOI, 3, 4)
            replace grupo_actividad = 2 if inlist(AOI, 5, 6)
            replace grupo_actividad = 3 if inlist(AOI, 7, 8, 9)

            drop if missing(grupo_actividad)

            capture assert !missing(CICLO)

            if !_rc {
                gen anio = 2021 + floor((CICLO - 194) / 4)
                gen trim = mod(CICLO - 194, 4) + 1
            }
            else {
                local base = subinstr("`f'", ".dta", "", .)
                local yy = real(substr("`base'", 5, 4))
                local tt = real(substr("`base'", 10, 1))

                gen anio = `yy'
                gen trim = `tt'
            }

            gen str7 periodo = string(anio) + "T" + string(trim)
            gen tq = yq(anio, trim)
            format tq %tq

            gen double w = cond(`useweights', FACTOREL, 1)

            gen double w_total = w
            gen double w_ocup  = cond(grupo_actividad == 1, w, 0)
            gen double w_paro  = cond(grupo_actividad == 2, w, 0)
            gen double w_inact = cond(grupo_actividad == 3, w, 0)

            collapse ///
                (sum) w_total w_ocup w_paro w_inact, ///
                by(CCAA anio trim periodo tq fp_group)

            rename w_total total_jovenes
            rename w_ocup  ocupados
            rename w_paro  parados
            rename w_inact inactivos

            gen double activos = ocupados + parados

            gen double tasa_paro_joven = 100 * parados / activos if activos > 0
            gen double tasa_ocup_activos = 100 * ocupados / activos if activos > 0

            keep CCAA anio trim periodo tq fp_group total_jovenes ocupados parados ///
                 inactivos activos tasa_paro_joven tasa_ocup_activos

            append using `acum_ccaa'
            save `acum_ccaa', replace
        }
    }


    ********************************************************************************
    * 2) PANEL FINAL CCAA
    ********************************************************************************

    use `acum_ccaa', clear

    sort CCAA fp_group tq

    gen byte ccaa_cod = CCAA

    label define lbl_ccaa ///
        1  "Andalucía" ///
        2  "Aragón" ///
        3  "Asturias, Principado de" ///
        4  "Balears, Illes" ///
        5  "Canarias" ///
        6  "Cantabria" ///
        7  "Castilla y León" ///
        8  "Castilla - La Mancha" ///
        9  "Cataluña" ///
        10 "Comunitat Valenciana" ///
        11 "Extremadura" ///
        12 "Galicia" ///
        13 "Madrid, Comunidad de" ///
        14 "Murcia, Región de" ///
        15 "Navarra, Comunidad Foral de" ///
        16 "País Vasco" ///
        17 "Rioja, La" ///
        18 "Ceuta" ///
        19 "Melilla", replace

    label values ccaa_cod lbl_ccaa
    decode ccaa_cod, gen(ccaa_nombre)
    replace ccaa_nombre = subinstr(ccaa_nombre, ",", "", .)

    label define lbl_fp_group 0 "`comp_label'" 1 "FP", replace
    label values fp_group lbl_fp_group

    save "EPA_joven_FP_vs_`comp_file'_CCAA_trimestral_long.dta", replace

    export excel using "EPA_joven_FP_vs_`comp_file'_CCAA_trimestral_long.xlsx", ///
        replace firstrow(variables)


    ********************************************************************************
    * 3) MEDIA MÓVIL 4T CCAA
    ********************************************************************************

    egen panel_id = group(CCAA fp_group)
    xtset panel_id tq

    gen double parados_4q  = parados  + L1.parados  + L2.parados  + L3.parados
    gen double ocupados_4q = ocupados + L1.ocupados + L2.ocupados + L3.ocupados
    gen double activos_4q  = activos  + L1.activos  + L2.activos  + L3.activos

    gen double tasa_paro_joven_4q = 100 * parados_4q / activos_4q if activos_4q > 0
    gen double tasa_ocup_activos_4q = 100 * ocupados_4q / activos_4q if activos_4q > 0

    save "EPA_joven_FP_vs_`comp_file'_CCAA_trimestral_long_con_4T.dta", replace


    ********************************************************************************
    * 4) FORMATO WIDE CCAA
    ********************************************************************************

    preserve

    keep CCAA ccaa_nombre anio trim periodo tq fp_group ///
         total_jovenes ocupados parados inactivos activos ///
         tasa_paro_joven tasa_ocup_activos tasa_paro_joven_4q tasa_ocup_activos_4q

    reshape wide total_jovenes ocupados parados inactivos activos ///
                 tasa_paro_joven tasa_ocup_activos tasa_paro_joven_4q tasa_ocup_activos_4q, ///
                 i(CCAA ccaa_nombre anio trim periodo tq) j(fp_group)

    gen double gap_paro_fp_comp = tasa_paro_joven1 - tasa_paro_joven0
    gen double gap_paro_fp_comp_4q = tasa_paro_joven_4q1 - tasa_paro_joven_4q0

    local base = yq(2021, 1)

    bysort CCAA: egen base_paro_fp = max(cond(tq == `base', tasa_paro_joven1, .))
    bysort CCAA: egen base_paro_comp = max(cond(tq == `base', tasa_paro_joven0, .))

    gen double reduccion_paro_fp = base_paro_fp - tasa_paro_joven1
    gen double reduccion_paro_comp = base_paro_comp - tasa_paro_joven0
    gen double diferencia_reduccion_fp_comp = reduccion_paro_fp - reduccion_paro_comp

    local base4 = yq(2021, 4)

    bysort CCAA: egen base_paro_fp_4q = max(cond(tq == `base4', tasa_paro_joven_4q1, .))
    bysort CCAA: egen base_paro_comp_4q = max(cond(tq == `base4', tasa_paro_joven_4q0, .))

    gen double reduccion_paro_fp_4q = base_paro_fp_4q - tasa_paro_joven_4q1
    gen double reduccion_paro_comp_4q = base_paro_comp_4q - tasa_paro_joven_4q0
    gen double diferencia_reduccion_fp_comp_4q = reduccion_paro_fp_4q - reduccion_paro_comp_4q

    save "EPA_joven_FP_vs_`comp_file'_CCAA_comparacion_wide.dta", replace

    export excel using "EPA_joven_FP_vs_`comp_file'_CCAA_comparacion_wide.xlsx", ///
        replace firstrow(variables)


    ********************************************************************************
    * 5) GRÁFICOS CCAA
    ********************************************************************************

    twoway ///
        (line tasa_paro_joven1 tq, lcolor(red) lwidth(medthick)) ///
        (line tasa_paro_joven0 tq, lcolor(blue) lpattern(dash) lwidth(medthick)), ///
        by(ccaa_nombre, cols(4) note("") ///
            title("Tasa de paro juvenil: FP vs `comp_title'", size(medsmall))) ///
        legend(order(1 "FP" 2 "`comp_label'") pos(6) ring(0)) ///
        ylabel(15(5)55, angle(0) grid labsize(small)) ///
        yscale(range(15 55)) ///
        xlabel(, angle(45) labsize(vsmall)) ///
        xtitle("Trimestre", size(small)) ///
        ytitle("Tasa de paro juvenil", size(small)) ///
        graphregion(color(white)) bgcolor(white) ///
        name(g1, replace)

    graph export "grafico_paro_joven_FP_vs_`comp_file'_CCAA_15_55.png", width(3200) replace
    graph save   "grafico_paro_joven_FP_vs_`comp_file'_CCAA_15_55.gph", replace


    twoway ///
        (line tasa_paro_joven_4q1 tq, lcolor(red) lwidth(medthick)) ///
        (line tasa_paro_joven_4q0 tq, lcolor(blue) lpattern(dash) lwidth(medthick)), ///
        by(ccaa_nombre, cols(4) note("") ///
            title("Tasa de paro juvenil: FP vs `comp_title', media móvil 4T", size(medsmall))) ///
        legend(order(1 "FP" 2 "`comp_label'") pos(6) ring(0)) ///
        ylabel(15(5)55, angle(0) grid labsize(small)) ///
        yscale(range(15 55)) ///
        xlabel(, angle(45) labsize(vsmall)) ///
        xtitle("Trimestre", size(small)) ///
        ytitle("Tasa de paro juvenil", size(small)) ///
        graphregion(color(white)) bgcolor(white) ///
        name(g2, replace)

    graph export "grafico_paro_joven_FP_vs_`comp_file'_CCAA_media_movil_4T_15_55.png", width(3200) replace
    graph save   "grafico_paro_joven_FP_vs_`comp_file'_CCAA_media_movil_4T_15_55.gph", replace


    twoway ///
        (line gap_paro_fp_comp_4q tq, lcolor(black) lwidth(medthick)), ///
        by(ccaa_nombre, cols(4) note("") ///
            title("Brecha de paro juvenil: FP - `comp_title', media móvil 4T", size(medsmall))) ///
        yline(0, lcolor(gs8) lpattern(dash)) ///
        ylabel(-20(5)20, angle(0) grid labsize(small)) ///
        yscale(range(-20 20)) ///
        xlabel(, angle(45) labsize(vsmall)) ///
        xtitle("Trimestre", size(small)) ///
        ytitle("Puntos porcentuales", size(small)) ///
        graphregion(color(white)) bgcolor(white) ///
        name(g3, replace)

    graph export "grafico_brecha_paro_joven_FP_menos_`comp_file'_CCAA_4T.png", width(3200) replace
    graph save   "grafico_brecha_paro_joven_FP_menos_`comp_file'_CCAA_4T.gph", replace


    twoway ///
        (line diferencia_reduccion_fp_comp_4q tq, lcolor(black) lwidth(medthick)), ///
        by(ccaa_nombre, cols(4) note("") ///
            title("Diferencia en reducción del paro juvenil: FP - `comp_title'", size(medsmall))) ///
        yline(0, lcolor(gs8) lpattern(dash)) ///
        ylabel(-20(5)20, angle(0) grid labsize(small)) ///
        yscale(range(-20 20)) ///
        xlabel(, angle(45) labsize(vsmall)) ///
        xtitle("Trimestre", size(small)) ///
        ytitle("Puntos porcentuales desde 2021T4", size(small)) ///
        graphregion(color(white)) bgcolor(white) ///
        name(g4, replace)

    graph export "grafico_diferencia_reduccion_paro_joven_FP_vs_`comp_file'_CCAA_4T.png", width(3200) replace
    graph save   "grafico_diferencia_reduccion_paro_joven_FP_vs_`comp_file'_CCAA_4T.gph", replace

    restore


    ********************************************************************************
    * 6) ANÁLISIS NACIONAL
    ********************************************************************************

    use "EPA_joven_FP_vs_`comp_file'_CCAA_trimestral_long.dta", clear

    collapse (sum) total_jovenes ocupados parados inactivos activos, ///
        by(anio trim periodo tq fp_group)

    gen double tasa_paro_joven = 100 * parados / activos if activos > 0
    gen double tasa_ocup_activos = 100 * ocupados / activos if activos > 0

    label define lbl_fp_group 0 "`comp_label'" 1 "FP", replace
    label values fp_group lbl_fp_group

    sort fp_group tq

    save "EPA_joven_FP_vs_`comp_file'_NACIONAL_trimestral_long.dta", replace

    egen panel_id = group(fp_group)
    xtset panel_id tq

    gen double parados_4q  = parados  + L1.parados  + L2.parados  + L3.parados
    gen double ocupados_4q = ocupados + L1.ocupados + L2.ocupados + L3.ocupados
    gen double activos_4q  = activos  + L1.activos  + L2.activos  + L3.activos

    gen double tasa_paro_joven_4q = 100 * parados_4q / activos_4q if activos_4q > 0
    gen double tasa_ocup_activos_4q = 100 * ocupados_4q / activos_4q if activos_4q > 0

    drop panel_id

    reshape wide total_jovenes ocupados parados inactivos activos ///
                 tasa_paro_joven tasa_ocup_activos ///
                 parados_4q ocupados_4q activos_4q ///
                 tasa_paro_joven_4q tasa_ocup_activos_4q, ///
                 i(anio trim periodo tq) j(fp_group)

    gen double gap_paro_fp_comp = tasa_paro_joven1 - tasa_paro_joven0
    gen double gap_paro_fp_comp_4q = tasa_paro_joven_4q1 - tasa_paro_joven_4q0

    local base4 = yq(2021, 4)

    egen base_paro_fp_4q = max(cond(tq == `base4', tasa_paro_joven_4q1, .))
    egen base_paro_comp_4q = max(cond(tq == `base4', tasa_paro_joven_4q0, .))

    gen double reduccion_paro_fp_4q = base_paro_fp_4q - tasa_paro_joven_4q1
    gen double reduccion_paro_comp_4q = base_paro_comp_4q - tasa_paro_joven_4q0
    gen double diferencia_reduccion_fp_comp_4q = reduccion_paro_fp_4q - reduccion_paro_comp_4q

    save "EPA_joven_FP_vs_`comp_file'_NACIONAL_wide.dta", replace

    export excel using "EPA_joven_FP_vs_`comp_file'_NACIONAL_wide.xlsx", ///
        replace firstrow(variables)


    ********************************************************************************
    * 7) GRÁFICOS NACIONALES
    ********************************************************************************

    twoway ///
        (line tasa_paro_joven_4q1 tq, lcolor(red) lwidth(medthick)) ///
        (line tasa_paro_joven_4q0 tq, lcolor(blue) lpattern(dash) lwidth(medthick)), ///
        legend(order(1 "FP" 2 "`comp_label'") pos(6) ring(0)) ///
        ylabel(15(5)55, angle(0) grid) ///
        yscale(range(15 55)) ///
        xlabel(, angle(45)) ///
        xtitle("Trimestre") ///
        ytitle("Tasa de paro juvenil") ///
        title("España: tasa de paro juvenil FP vs `comp_title'", size(medium)) ///
        subtitle("Media móvil de 4 trimestres", size(small)) ///
        graphregion(color(white)) bgcolor(white) ///
        name(gn1, replace)

    graph export "grafico_nacional_paro_FP_vs_`comp_file'_4T.png", width(2400) replace
    graph save   "grafico_nacional_paro_FP_vs_`comp_file'_4T.gph", replace


    twoway ///
        (line gap_paro_fp_comp_4q tq, lcolor(black) lwidth(medthick)), ///
        yline(0, lcolor(gs8) lpattern(dash)) ///
        ylabel(-15(5)15, angle(0) grid) ///
        yscale(range(-15 15)) ///
        xlabel(, angle(45)) ///
        xtitle("Trimestre") ///
        ytitle("Puntos porcentuales") ///
        title("España: brecha de paro juvenil FP - `comp_title'", size(medium)) ///
        subtitle("Media móvil de 4 trimestres", size(small)) ///
        graphregion(color(white)) bgcolor(white) ///
        name(gn2, replace)

    graph export "grafico_nacional_brecha_FP_menos_`comp_file'_4T.png", width(2400) replace
    graph save   "grafico_nacional_brecha_FP_menos_`comp_file'_4T.gph", replace


    twoway ///
        (line diferencia_reduccion_fp_comp_4q tq, lcolor(black) lwidth(medthick)), ///
        yline(0, lcolor(gs8) lpattern(dash)) ///
        ylabel(-15(5)15, angle(0) grid) ///
        yscale(range(-15 15)) ///
        xlabel(, angle(45)) ///
        xtitle("Trimestre") ///
        ytitle("Puntos porcentuales desde 2021T4") ///
        title("España: diferencia en la reducción del paro juvenil", size(medium)) ///
        subtitle("FP - `comp_title', media móvil de 4 trimestres", size(small)) ///
        graphregion(color(white)) bgcolor(white) ///
        name(gn3, replace)

    graph export "grafico_nacional_diferencia_reduccion_FP_vs_`comp_file'_4T.png", width(2400) replace
    graph save   "grafico_nacional_diferencia_reduccion_FP_vs_`comp_file'_4T.gph", replace
}

di as result "Proceso completado correctamente para ambas comparaciones."


/********************************************************************************
* SECTION 5: Do_file_por rama_de_Actividad(1).do
********************************************************************************/

clear all
if "${PROJECT_ROOT}" == "" {
    global PROJECT_ROOT "."
}
set more off

********************************************************************************
* EPA 2021T1-2026T1 | Jóvenes <25 | Ocupación por ACT1
*
* Objetivos:
* 1) Niveles absolutos de ocupación juvenil por actividad económica.
* 2) Índice de evolución: 2021 = 100.
* 3) Peso de cada actividad sobre el total de ocupados jóvenes.
* 4) Comparación FP vs No FP.
*
* IMPORTANTE:
* ACT1 tiene códigos agregados 0-9. No es CNAE detallado.
********************************************************************************


********************************************************************************
* 0) RUTAS Y PARÁMETROS
********************************************************************************

local root "${PROJECT_ROOT}\98.IMPACTO DEL PLAN\1. FP\epa\dta"

local out "${PROJECT_ROOT}\98.IMPACTO DEL PLAN\1. FP\epa\resultados_ACT1_ocupacion_indices"
capture mkdir "`out'"

local files epa_2021t1.dta epa_2021t2.dta epa_2021t3.dta epa_2021t4.dta ///
             epa_2022t1.dta epa_2022t2.dta epa_2022t3.dta epa_2022t4.dta ///
             epa_2023t1.dta epa_2023t2.dta epa_2023t3.dta epa_2023t4.dta ///
             epa_2024t1.dta epa_2024t2.dta epa_2024t3.dta epa_2024t4.dta ///
             epa_2025t1.dta epa_2025t2.dta epa_2025t3.dta epa_2025t4.dta ///
             epa_2026t1.dta

local useweights 1
local edad_max 25

* Si quieres que No FP incluya también los missing de NFORMA, déjalo en 1.
local include_missing_nofp 1


********************************************************************************
* 1) TEMPFILES
********************************************************************************

tempfile acum_denom acum_act1

clear
save `acum_denom', emptyok

clear
save `acum_act1', emptyok


********************************************************************************
* 2) LOOP PRINCIPAL
********************************************************************************

foreach f of local files {

    di as result ">>> Procesando: `f'"

    local full "`root'/`f'"

    capture confirm file "`full'"
    if _rc {
        di as error "   No existe: `full' -> salto"
        continue
    }

    use "`full'", clear

    *------------------------------------------------------
    * 2.1 Asegurar tipos numéricos
    *------------------------------------------------------

    foreach v in CCAA PROV EDAD1 AOI FACTOREL CICLO ACT1 {
        capture confirm variable `v'
        if !_rc {
            capture confirm numeric variable `v'
            if _rc {
                destring `v', replace ignore(" .")
            }
        }
    }

    capture confirm variable ACT1
    if _rc {
        di as error "   Falta ACT1 en `f' -> salto"
        continue
    }

    gen double act1 = ACT1

    *------------------------------------------------------
    * 2.2 Filtrar jóvenes menores de 25
    *------------------------------------------------------

    keep if EDAD1 < `edad_max'

    drop if missing(AOI) | missing(CCAA)

    *------------------------------------------------------
    * 2.3 Crear grupo FP vs No FP
    *------------------------------------------------------

    capture confirm variable NFORMA
    if _rc {
        di as error "   NFORMA no existe en `f' -> salto"
        continue
    }

    capture confirm string variable NFORMA

    if !_rc {
        gen str30 nforma_str = upper(strtrim(NFORMA))
    }
    else {
        capture decode NFORMA, gen(nforma_str)
        if _rc {
            tostring NFORMA, gen(nforma_str) force
        }
        replace nforma_str = upper(strtrim(nforma_str))
    }

    replace nforma_str = "" if nforma_str == "."

    gen byte fp_group = .
    replace fp_group = 1 if nforma_str == "SP"
    replace fp_group = 0 if nforma_str != "SP" & nforma_str != ""

    if `include_missing_nofp' == 1 {
        replace fp_group = 0 if nforma_str == ""
    }

    drop if missing(fp_group)

    label define lbl_fp_group 0 "No FP" 1 "FP", replace
    label values fp_group lbl_fp_group

    *------------------------------------------------------
    * 2.4 Clasificar situación laboral
    *------------------------------------------------------

    gen byte grupo_actividad = .
    replace grupo_actividad = 1 if inlist(AOI, 3, 4)      // Ocupados
    replace grupo_actividad = 2 if inlist(AOI, 5, 6)      // Parados
    replace grupo_actividad = 3 if inlist(AOI, 7, 8, 9)   // Inactivos

    drop if missing(grupo_actividad)

    *------------------------------------------------------
    * 2.5 Identificadores temporales
    *------------------------------------------------------

    capture assert !missing(CICLO)

    if !_rc {
        gen anio = 2021 + floor((CICLO - 194) / 4)
        gen trim = mod(CICLO - 194, 4) + 1
    }
    else {
        local base = subinstr("`f'", ".dta", "", .)
        local yy = real(substr("`base'", 5, 4))
        local tt = real(substr("`base'", 10, 1))

        gen anio = `yy'
        gen trim = `tt'
    }

    gen str7 periodo = string(anio) + "T" + string(trim)
    gen tq = yq(anio, trim)
    format tq %tq

    *------------------------------------------------------
    * 2.6 Pesos
    *------------------------------------------------------

    gen double w = 1

    if `useweights' == 1 {
        capture confirm variable FACTOREL
        if _rc {
            di as error "   FACTOREL no existe en `f' -> salto"
            continue
        }

        replace w = FACTOREL
    }

    drop if missing(w)

    *------------------------------------------------------
    * 2.7 Denominadores CCAA × trimestre × FP/no FP
    *------------------------------------------------------

    preserve

        gen double w_total = w
        gen double w_ocup  = cond(grupo_actividad == 1, w, 0)
        gen double w_paro  = cond(grupo_actividad == 2, w, 0)
        gen double w_inact = cond(grupo_actividad == 3, w, 0)
        gen double w_act   = cond(inlist(grupo_actividad, 1, 2), w, 0)

        collapse ///
            (sum) total_jovenes = w_total ///
                  ocupados_total = w_ocup ///
                  parados = w_paro ///
                  inactivos = w_inact ///
                  activos = w_act, ///
            by(CCAA anio trim periodo tq fp_group)

        append using `acum_denom'
        save `acum_denom', replace

    restore

    *------------------------------------------------------
    * 2.8 Ocupados por ACT1
    *------------------------------------------------------

    preserve

        keep if grupo_actividad == 1

        * Si algún ocupado no tiene ACT1 válido, lo dejamos como 99.
        replace act1 = 99 if missing(act1) | act1 < 0 | act1 > 9

        gen double w_occ = w

        collapse ///
            (sum) ocupados_act1 = w_occ, ///
            by(CCAA anio trim periodo tq fp_group act1)

        append using `acum_act1'
        save `acum_act1', replace

    restore
}


********************************************************************************
* 3) BASE DE DENOMINADORES CCAA
********************************************************************************

use `acum_denom', clear

gen byte ccaa_cod = CCAA

label define lbl_ccaa ///
    1  "Andalucía" ///
    2  "Aragón" ///
    3  "Asturias, Principado de" ///
    4  "Balears, Illes" ///
    5  "Canarias" ///
    6  "Cantabria" ///
    7  "Castilla y León" ///
    8  "Castilla - La Mancha" ///
    9  "Cataluña" ///
    10 "Comunitat Valenciana" ///
    11 "Extremadura" ///
    12 "Galicia" ///
    13 "Madrid, Comunidad de" ///
    14 "Murcia, Región de" ///
    15 "Navarra, Comunidad Foral de" ///
    16 "País Vasco" ///
    17 "Rioja, La" ///
    18 "Ceuta" ///
    19 "Melilla", replace

label values ccaa_cod lbl_ccaa
decode ccaa_cod, gen(ccaa_nombre)

replace ccaa_nombre = subinstr(ccaa_nombre, ",", "", .)

label define lbl_fp_group 0 "No FP" 1 "FP", replace
label values fp_group lbl_fp_group

tempfile denom_ccaa
save `denom_ccaa', replace

save "`out'\EPA_joven_FP_vs_noFP_CCAA_denom.dta", replace

export excel using "`out'\EPA_joven_FP_vs_noFP_CCAA_denom.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 4) CREAR BASE DE CATEGORÍAS ACT1 CON NOMBRES MANUALES
********************************************************************************

clear
set obs 11

gen double act1 = _n - 1
replace act1 = 99 in 11

gen str90 act1_nombre = ""

replace act1_nombre = "Agricultura, ganadería, silvicultura y pesca" if act1 == 0
replace act1_nombre = "Energía y agua" if act1 == 1
replace act1_nombre = "Extractivas, refino, química y minerales" if act1 == 2
replace act1_nombre = "Metal, maquinaria y material eléctrico" if act1 == 3
replace act1_nombre = "Otras industrias manufactureras" if act1 == 4
replace act1_nombre = "Construcción" if act1 == 5
replace act1_nombre = "Comercio, hostelería y reparaciones" if act1 == 6
replace act1_nombre = "Transporte y comunicaciones" if act1 == 7
replace act1_nombre = "Finanzas, inmobiliarias y servicios a empresas" if act1 == 8
replace act1_nombre = "Otros servicios" if act1 == 9
replace act1_nombre = "No clasificado" if act1 == 99

tempfile act1_cats
save `act1_cats', replace


********************************************************************************
* 5) CREAR PANEL COMPLETO CCAA × TRIMESTRE × FP/no FP × ACT1
********************************************************************************

use `acum_act1', clear

tempfile act1_raw
save `act1_raw', replace

* Base CCAA × trimestre × FP/no FP
use `denom_ccaa', clear

keep CCAA anio trim periodo tq fp_group
duplicates drop

gen byte _join_key = 1

tempfile base_panel
save `base_panel', replace

* Categorías ACT1 con clave artificial para producto cartesiano
use `act1_cats', clear

gen byte _join_key = 1

tempfile act1_cats_join
save `act1_cats_join', replace

* Producto cartesiano
use `base_panel', clear

joinby _join_key using `act1_cats_join'

drop _join_key

* Añadir ocupados observados
merge 1:1 CCAA anio trim periodo tq fp_group act1 using `act1_raw', nogen

replace ocupados_act1 = 0 if missing(ocupados_act1)

* Añadir denominadores
merge m:1 CCAA anio trim periodo tq fp_group using `denom_ccaa', ///
    nogen keep(match)

* Tasas y shares
gen double tasa_act1_activos = 100 * ocupados_act1 / activos if activos > 0

gen double share_act1_ocupados = 100 * ocupados_act1 / ocupados_total ///
    if ocupados_total > 0

label var ocupados_act1 "Ocupados jóvenes en ACT1"
label var tasa_act1_activos "Ocupados ACT1 / activos jóvenes"
label var share_act1_ocupados "Ocupados ACT1 / ocupados jóvenes"

save "`out'\EPA_joven_FP_vs_noFP_CCAA_ACT1_long_completo.dta", replace

export excel using "`out'\EPA_joven_FP_vs_noFP_CCAA_ACT1_long_completo.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 6) BASE NACIONAL POR ACT1 Y FP/no FP
********************************************************************************

use "`out'\EPA_joven_FP_vs_noFP_CCAA_ACT1_long_completo.dta", clear

collapse ///
    (sum) ocupados_act1 total_jovenes ocupados_total parados inactivos activos, ///
    by(anio trim periodo tq fp_group act1 act1_nombre)

gen double tasa_act1_activos = 100 * ocupados_act1 / activos if activos > 0

gen double share_act1_ocupados = 100 * ocupados_act1 / ocupados_total ///
    if ocupados_total > 0

label define lbl_fp_group 0 "No FP" 1 "FP", replace
label values fp_group lbl_fp_group

save "`out'\EPA_joven_FP_vs_noFP_NACIONAL_ACT1.dta", replace

export excel using "`out'\EPA_joven_FP_vs_noFP_NACIONAL_ACT1.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 7) MEDIA MÓVIL 4T POR ACT1 Y FP/no FP
********************************************************************************

use "`out'\EPA_joven_FP_vs_noFP_NACIONAL_ACT1.dta", clear

sort fp_group act1 tq

egen panel_fp_act1 = group(fp_group act1)

xtset panel_fp_act1 tq

gen double ocupados_act1_4q = ocupados_act1 + L1.ocupados_act1 + L2.ocupados_act1 + L3.ocupados_act1

gen double ocupados_total_4q = ocupados_total + L1.ocupados_total + L2.ocupados_total + L3.ocupados_total

gen double activos_4q = activos + L1.activos + L2.activos + L3.activos

gen double tasa_act1_activos_4q = 100 * ocupados_act1_4q / activos_4q ///
    if activos_4q > 0

gen double share_act1_ocupados_4q = 100 * ocupados_act1_4q / ocupados_total_4q ///
    if ocupados_total_4q > 0

label var ocupados_act1_4q "Ocupados jóvenes ACT1, media móvil 4T"
label var share_act1_ocupados_4q "Peso ACT1 sobre ocupados jóvenes, media móvil 4T"

save "`out'\EPA_joven_FP_vs_noFP_NACIONAL_ACT1_4T.dta", replace

export excel using "`out'\EPA_joven_FP_vs_noFP_NACIONAL_ACT1_4T.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 8) DIAGNÓSTICO: LOS SHARES DEBEN SUMAR 100 POR TRIMESTRE Y GRUPO
********************************************************************************

bysort tq fp_group: egen suma_share = total(share_act1_ocupados)

bysort tq fp_group: egen suma_share_4q = total(share_act1_ocupados_4q)

summ suma_share suma_share_4q

drop suma_share suma_share_4q


********************************************************************************
* 9) BASE TOTAL JÓVENES: FP + NO FP JUNTOS
********************************************************************************

use "`out'\EPA_joven_FP_vs_noFP_NACIONAL_ACT1.dta", clear

collapse ///
    (sum) ocupados_act1 total_jovenes ocupados_total parados inactivos activos, ///
    by(anio trim periodo tq act1 act1_nombre)

gen double tasa_act1_activos = 100 * ocupados_act1 / activos if activos > 0

gen double share_act1_ocupados = 100 * ocupados_act1 / ocupados_total ///
    if ocupados_total > 0

sort act1 tq

egen panel_act1_total = group(act1)

xtset panel_act1_total tq

gen double ocupados_act1_4q = ocupados_act1 + L1.ocupados_act1 + L2.ocupados_act1 + L3.ocupados_act1

gen double ocupados_total_4q = ocupados_total + L1.ocupados_total + L2.ocupados_total + L3.ocupados_total

gen double activos_4q = activos + L1.activos + L2.activos + L3.activos

gen double tasa_act1_activos_4q = 100 * ocupados_act1_4q / activos_4q ///
    if activos_4q > 0

gen double share_act1_ocupados_4q = 100 * ocupados_act1_4q / ocupados_total_4q ///
    if ocupados_total_4q > 0

label var ocupados_act1_4q "Ocupados jóvenes ACT1, media móvil 4T"
label var share_act1_ocupados_4q "Peso ACT1 sobre ocupados jóvenes, media móvil 4T"

save "`out'\EPA_joven_NACIONAL_ACT1_total_4T.dta", replace

export excel using "`out'\EPA_joven_NACIONAL_ACT1_total_4T.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 10) ÍNDICES 2021 = 100 | TOTAL JÓVENES
********************************************************************************

use "`out'\EPA_joven_NACIONAL_ACT1_total_4T.dta", clear

* Base 2021 = media de los cuatro trimestres de 2021.
bysort act1: egen base_ocup_2021 = mean(cond(anio == 2021, ocupados_act1, .))

gen double indice_ocup_act1_2021_100 = 100 * ocupados_act1 / base_ocup_2021 ///
    if base_ocup_2021 > 0

* Para la media móvil 4T, solo hay un valor no missing en 2021: 2021T4.
bysort act1: egen base_ocup_4q_2021 = mean(cond(anio == 2021, ocupados_act1_4q, .))

gen double indice_ocup_act1_4q_2021_100 = 100 * ocupados_act1_4q / base_ocup_4q_2021 ///
    if base_ocup_4q_2021 > 0

gen double ocupados_act1_miles = ocupados_act1 / 1000

gen double ocupados_act1_4q_miles = ocupados_act1_4q / 1000

label var indice_ocup_act1_2021_100 "Índice ocupación juvenil ACT1, 2021=100"
label var indice_ocup_act1_4q_2021_100 "Índice ocupación juvenil ACT1, media móvil 4T, 2021=100"
label var ocupados_act1_miles "Ocupados jóvenes, miles"
label var ocupados_act1_4q_miles "Ocupados jóvenes, miles, media móvil 4T"

save "`out'\EPA_joven_NACIONAL_ACT1_total_indices_2021_100.dta", replace

export excel using "`out'\EPA_joven_NACIONAL_ACT1_total_indices_2021_100.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 11) GRÁFICO A: NIVELES ABSOLUTOS DE OCUPACIÓN JUVENIL POR ACT1
********************************************************************************

twoway ///
    (line ocupados_act1_4q_miles tq if act1 <= 9, lwidth(medthick)), ///
    by(act1_nombre, cols(3) note("") ///
        title("España: empleo juvenil por actividad económica", size(medsmall)) ///
        subtitle("Ocupados jóvenes <25, miles, media móvil 4T", size(small))) ///
    ylabel(, angle(0) grid labsize(small)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("Miles de ocupados jóvenes", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_niveles_act1_total_4q, replace)

graph export "`out'\grafico_nacional_niveles_ocupacion_juvenil_ACT1_4T.png", ///
    width(3400) replace

graph save "`out'\grafico_nacional_niveles_ocupacion_juvenil_ACT1_4T.gph", replace


********************************************************************************
* 12) GRÁFICO B: ÍNDICE 2021 = 100 POR ACT1
********************************************************************************

twoway ///
    (line indice_ocup_act1_4q_2021_100 tq if act1 <= 9, lwidth(medthick)), ///
    by(act1_nombre, cols(3) note("") ///
        title("España: evolución relativa del empleo juvenil por actividad económica", size(medsmall)) ///
        subtitle("Índice 2021 = 100, media móvil 4T", size(small))) ///
    yline(100, lcolor(gs8) lpattern(dash)) ///
    ylabel(, angle(0) grid labsize(small)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("Índice 2021 = 100", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_indice_act1_total_4q, replace)

graph export "`out'\grafico_nacional_indice_ocupacion_juvenil_ACT1_2021_100_4T.png", ///
    width(3400) replace

graph save "`out'\grafico_nacional_indice_ocupacion_juvenil_ACT1_2021_100_4T.gph", replace


********************************************************************************
* 13) GRÁFICO C: PESO DE CADA ACT1 SOBRE OCUPADOS JÓVENES
*     Las ramas suman 100% en cada trimestre.
********************************************************************************

twoway ///
    (line share_act1_ocupados_4q tq if act1 <= 9, lwidth(medthick)), ///
    by(act1_nombre, cols(3) note("") ///
        title("España: composición sectorial del empleo juvenil", size(medsmall)) ///
        subtitle("Peso de cada ACT1 sobre ocupados jóvenes; suma total = 100%", size(small))) ///
    ylabel(, angle(0) grid labsize(small)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("% de ocupados jóvenes", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_share_act1_total_4q, replace)

graph export "`out'\grafico_nacional_share_ocupacion_juvenil_ACT1_4T.png", ///
    width(3400) replace

graph save "`out'\grafico_nacional_share_ocupacion_juvenil_ACT1_4T.gph", replace


********************************************************************************
* 14) GRÁFICO D: COMPOSICIÓN ÚLTIMO TRIMESTRE
********************************************************************************

preserve

    keep if !missing(share_act1_ocupados_4q)

    quietly summarize tq
    local last = r(max)

    keep if tq == `last' & act1 <= 9

    graph hbar share_act1_ocupados_4q, ///
        over(act1_nombre, sort(1) descending label(labsize(vsmall))) ///
        blabel(bar, format(%4.1f)) ///
        ytitle("% de ocupados jóvenes") ///
        title("España: composición del empleo juvenil por actividad económica", size(medium)) ///
        subtitle("Último trimestre disponible, media móvil 4T", size(small)) ///
        graphregion(color(white)) bgcolor(white) ///
        name(g_share_ultimo_act1, replace)

    graph export "`out'\grafico_nacional_composicion_ocupacion_juvenil_ACT1_ultimo_4T.png", ///
        width(2600) replace

    graph save "`out'\grafico_nacional_composicion_ocupacion_juvenil_ACT1_ultimo_4T.gph", replace

restore


********************************************************************************
* 15) ÍNDICES 2021 = 100 | FP VS NO FP POR ACT1
********************************************************************************

use "`out'\EPA_joven_FP_vs_noFP_NACIONAL_ACT1_4T.dta", clear

bysort fp_group act1: egen base_ocup_fpact_2021 = mean(cond(anio == 2021, ocupados_act1, .))

gen double indice_ocup_fpact_2021_100 = 100 * ocupados_act1 / base_ocup_fpact_2021 ///
    if base_ocup_fpact_2021 > 0

bysort fp_group act1: egen base_ocup_fpact_4q_2021 = mean(cond(anio == 2021, ocupados_act1_4q, .))

gen double indice_ocup_fpact_4q_2021_100 = 100 * ocupados_act1_4q / base_ocup_fpact_4q_2021 ///
    if base_ocup_fpact_4q_2021 > 0

gen double ocupados_act1_miles = ocupados_act1 / 1000

gen double ocupados_act1_4q_miles = ocupados_act1_4q / 1000

save "`out'\EPA_joven_FP_vs_noFP_NACIONAL_ACT1_indices_2021_100.dta", replace

export excel using "`out'\EPA_joven_FP_vs_noFP_NACIONAL_ACT1_indices_2021_100.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 16) GRÁFICO E: NIVELES ABSOLUTOS FP VS NO FP POR ACT1
********************************************************************************

twoway ///
    (line ocupados_act1_4q_miles tq if fp_group == 1 & act1 <= 9, ///
        lcolor(red) lwidth(medthick)) ///
    (line ocupados_act1_4q_miles tq if fp_group == 0 & act1 <= 9, ///
        lcolor(blue) lpattern(dash) lwidth(medthick)), ///
    by(act1_nombre, cols(3) note("") ///
        title("España: empleo juvenil por actividad económica", size(medsmall)) ///
        subtitle("FP vs No FP | Miles de ocupados jóvenes, media móvil 4T", size(small))) ///
    legend(order(1 "FP" 2 "No FP") pos(6) ring(0)) ///
    ylabel(, angle(0) grid labsize(small)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("Miles de ocupados jóvenes", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_niveles_act1_fp_nofp_4q, replace)

graph export "`out'\grafico_nacional_niveles_ocupacion_juvenil_ACT1_FP_vs_NoFP_4T.png", ///
    width(3400) replace

graph save "`out'\grafico_nacional_niveles_ocupacion_juvenil_ACT1_FP_vs_NoFP_4T.gph", replace


********************************************************************************
* 17) GRÁFICO F: ÍNDICE 2021 = 100, FP VS NO FP POR ACT1
********************************************************************************

twoway ///
    (line indice_ocup_fpact_4q_2021_100 tq if fp_group == 1 & act1 <= 9, ///
        lcolor(red) lwidth(medthick)) ///
    (line indice_ocup_fpact_4q_2021_100 tq if fp_group == 0 & act1 <= 9, ///
        lcolor(blue) lpattern(dash) lwidth(medthick)), ///
    by(act1_nombre, cols(3) note("") ///
        title("España: evolución relativa del empleo juvenil por actividad económica", size(medsmall)) ///
        subtitle("FP vs No FP | Índice 2021 = 100, media móvil 4T", size(small))) ///
    legend(order(1 "FP" 2 "No FP") pos(6) ring(0)) ///
    yline(100, lcolor(gs8) lpattern(dash)) ///
    ylabel(, angle(0) grid labsize(small)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("Índice 2021 = 100", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_indice_act1_fp_nofp_4q, replace)

graph export "`out'\grafico_nacional_indice_ocupacion_juvenil_ACT1_FP_vs_NoFP_2021_100_4T.png", ///
    width(3400) replace

graph save "`out'\grafico_nacional_indice_ocupacion_juvenil_ACT1_FP_vs_NoFP_2021_100_4T.gph", replace


********************************************************************************
* 18) GRÁFICO G: PESO ACT1 SOBRE OCUPADOS JÓVENES, FP VS NO FP
*     Dentro de cada grupo, las ramas suman 100%.
********************************************************************************

twoway ///
    (line share_act1_ocupados_4q tq if fp_group == 1 & act1 <= 9, ///
        lcolor(red) lwidth(medthick)) ///
    (line share_act1_ocupados_4q tq if fp_group == 0 & act1 <= 9, ///
        lcolor(blue) lpattern(dash) lwidth(medthick)), ///
    by(act1_nombre, cols(3) note("") ///
        title("España: composición sectorial del empleo juvenil", size(medsmall)) ///
        subtitle("FP vs No FP | Peso sobre ocupados jóvenes, media móvil 4T", size(small))) ///
    legend(order(1 "FP" 2 "No FP") pos(6) ring(0)) ///
    ylabel(, angle(0) grid labsize(small)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("% de ocupados jóvenes del grupo", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_share_act1_fp_nofp_4q, replace)

graph export "`out'\grafico_nacional_share_ocupacion_juvenil_ACT1_FP_vs_NoFP_4T.png", ///
    width(3400) replace

graph save "`out'\grafico_nacional_share_ocupacion_juvenil_ACT1_FP_vs_NoFP_4T.gph", replace


********************************************************************************
* 19) TABLA: CAMBIO ABSOLUTO Y RELATIVO DESDE 2021
********************************************************************************

use "`out'\EPA_joven_NACIONAL_ACT1_total_indices_2021_100.dta", clear

quietly summarize tq
local last = r(max)

bysort act1: egen ocupados_base_2021 = max(base_ocup_2021)

bysort act1: egen ocupados_ultimo = max(cond(tq == `last', ocupados_act1, .))

bysort act1: egen indice_ultimo = max(cond(tq == `last', indice_ocup_act1_2021_100, .))

bysort act1: egen share_ultimo = max(cond(tq == `last', share_act1_ocupados, .))

bysort act1: egen share_base_2021 = mean(cond(anio == 2021, share_act1_ocupados, .))

gen double cambio_abs_ocupados = ocupados_ultimo - ocupados_base_2021

gen double cambio_pct_ocupados = indice_ultimo - 100

gen double cambio_share_pp = share_ultimo - share_base_2021

keep act1 act1_nombre ocupados_base_2021 ocupados_ultimo ///
     cambio_abs_ocupados indice_ultimo cambio_pct_ocupados ///
     share_base_2021 share_ultimo cambio_share_pp

duplicates drop

gsort -cambio_abs_ocupados

save "`out'\tabla_cambio_ocupacion_juvenil_ACT1_2021_ultimo.dta", replace

export excel using "`out'\tabla_cambio_ocupacion_juvenil_ACT1_2021_ultimo.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 20) MENSAJE FINAL
********************************************************************************

di as result "============================================================"
di as result "Proceso completado correctamente."
di as result ""
di as result "Carpeta de salida:"
di as result "`out'"
di as result ""
di as result "Gráficos generados:"
di as result "A) Niveles absolutos de ocupación juvenil por ACT1"
di as result "B) Índice 2021 = 100 por ACT1"
di as result "C) Peso de cada ACT1 sobre ocupados jóvenes; suma = 100%"
di as result "D) Composición sectorial último trimestre"
di as result "E) Niveles absolutos FP vs No FP por ACT1"
di as result "F) Índice 2021 = 100, FP vs No FP por ACT1"
di as result "G) Peso sectorial FP vs No FP por ACT1"
di as result ""
di as result "Tabla generada:"
di as result "tabla_cambio_ocupacion_juvenil_ACT1_2021_ultimo.xlsx"
di as result "============================================================"


/********************************************************************************
* SECTION 6: Do file_completo por cnae.do
********************************************************************************/

clear all
if "${PROJECT_ROOT}" == "" {
    global PROJECT_ROOT "."
}
set more off

********************************************************************************
* EPA 2021T1-2026T1 | Jóvenes <25 | Ocupación por ACT1
*
* Objetivos:
* 1) Niveles absolutos de ocupación juvenil por actividad económica.
* 2) Índice de evolución: 2021 = 100.
* 3) Peso de cada actividad sobre el total de ocupados jóvenes.
* 4) Comparación FP vs No FP.
* 5) Proxy Digital/TIC: ACT1 == 7, Transporte y comunicaciones.
* 6) Evolución de la proxy Digital/TIC por CCAA, FP vs No FP.
*
* IMPORTANTE:
* ACT1 tiene códigos agregados 0-9. No es CNAE detallado.
********************************************************************************


********************************************************************************
* 0) RUTAS Y PARÁMETROS
********************************************************************************

local root "${PROJECT_ROOT}\98.IMPACTO DEL PLAN\1. FP\epa\dta"

local out "${PROJECT_ROOT}\98.IMPACTO DEL PLAN\1. FP\epa\resultados_ACT1_ocupacion_indices"
capture mkdir "`out'"

local files epa_2021t1.dta epa_2021t2.dta epa_2021t3.dta epa_2021t4.dta ///
             epa_2022t1.dta epa_2022t2.dta epa_2022t3.dta epa_2022t4.dta ///
             epa_2023t1.dta epa_2023t2.dta epa_2023t3.dta epa_2023t4.dta ///
             epa_2024t1.dta epa_2024t2.dta epa_2024t3.dta epa_2024t4.dta ///
             epa_2025t1.dta epa_2025t2.dta epa_2025t3.dta epa_2025t4.dta ///
             epa_2026t1.dta

local useweights 1
local edad_max 25

* Si quieres que No FP incluya también los missing de NFORMA, déjalo en 1.
local include_missing_nofp 1

* Proxy de digitalización
local digital_act1 6


********************************************************************************
* 1) TEMPFILES
********************************************************************************

tempfile acum_denom acum_act1

clear
save `acum_denom', emptyok

clear
save `acum_act1', emptyok


********************************************************************************
* 2) LOOP PRINCIPAL
********************************************************************************

foreach f of local files {

    di as result ">>> Procesando: `f'"

    local full "`root'/`f'"

    capture confirm file "`full'"
    if _rc {
        di as error "   No existe: `full' -> salto"
        continue
    }

    use "`full'", clear

    *------------------------------------------------------
    * 2.1 Asegurar tipos numéricos
    *------------------------------------------------------

    foreach v in CCAA PROV EDAD1 AOI FACTOREL CICLO ACT1 {
        capture confirm variable `v'
        if !_rc {
            capture confirm numeric variable `v'
            if _rc {
                destring `v', replace ignore(" .")
            }
        }
    }

    capture confirm variable ACT1
    if _rc {
        di as error "   Falta ACT1 en `f' -> salto"
        continue
    }

    gen double act1 = ACT1

    *------------------------------------------------------
    * 2.2 Filtrar jóvenes menores de 25
    *------------------------------------------------------

    keep if EDAD1 < `edad_max'

    drop if missing(AOI) | missing(CCAA)

    *------------------------------------------------------
    * 2.3 Crear grupo FP vs No FP
    *------------------------------------------------------

    capture confirm variable NFORMA
    if _rc {
        di as error "   NFORMA no existe en `f' -> salto"
        continue
    }

    capture confirm string variable NFORMA

    if !_rc {
        gen str30 nforma_str = upper(strtrim(NFORMA))
    }
    else {
        capture decode NFORMA, gen(nforma_str)
        if _rc {
            tostring NFORMA, gen(nforma_str) force
        }
        replace nforma_str = upper(strtrim(nforma_str))
    }

    replace nforma_str = "" if nforma_str == "."

    gen byte fp_group = .
    replace fp_group = 1 if nforma_str == "SP"
    replace fp_group = 0 if nforma_str != "SP" & nforma_str != ""

    if `include_missing_nofp' == 1 {
        replace fp_group = 0 if nforma_str == ""
    }

    drop if missing(fp_group)

    label define lbl_fp_group 0 "No FP" 1 "FP", replace
    label values fp_group lbl_fp_group

    *------------------------------------------------------
    * 2.4 Clasificar situación laboral
    *------------------------------------------------------

    gen byte grupo_actividad = .
    replace grupo_actividad = 1 if inlist(AOI, 3, 4)      // Ocupados
    replace grupo_actividad = 2 if inlist(AOI, 5, 6)      // Parados
    replace grupo_actividad = 3 if inlist(AOI, 7, 8, 9)   // Inactivos

    drop if missing(grupo_actividad)

    *------------------------------------------------------
    * 2.5 Identificadores temporales
    *------------------------------------------------------

    capture assert !missing(CICLO)

    if !_rc {
        gen anio = 2021 + floor((CICLO - 194) / 4)
        gen trim = mod(CICLO - 194, 4) + 1
    }
    else {
        local base = subinstr("`f'", ".dta", "", .)
        local yy = real(substr("`base'", 5, 4))
        local tt = real(substr("`base'", 10, 1))

        gen anio = `yy'
        gen trim = `tt'
    }

    gen str7 periodo = string(anio) + "T" + string(trim)
    gen tq = yq(anio, trim)
    format tq %tq

    *------------------------------------------------------
    * 2.6 Pesos
    *------------------------------------------------------

    gen double w = 1

    if `useweights' == 1 {
        capture confirm variable FACTOREL
        if _rc {
            di as error "   FACTOREL no existe en `f' -> salto"
            continue
        }

        replace w = FACTOREL
    }

    drop if missing(w)

    *------------------------------------------------------
    * 2.7 Denominadores CCAA × trimestre × FP/no FP
    *------------------------------------------------------

    preserve

        gen double w_total = w
        gen double w_ocup  = cond(grupo_actividad == 1, w, 0)
        gen double w_paro  = cond(grupo_actividad == 2, w, 0)
        gen double w_inact = cond(grupo_actividad == 3, w, 0)
        gen double w_act   = cond(inlist(grupo_actividad, 1, 2), w, 0)

        collapse ///
            (sum) total_jovenes = w_total ///
                  ocupados_total = w_ocup ///
                  parados = w_paro ///
                  inactivos = w_inact ///
                  activos = w_act, ///
            by(CCAA anio trim periodo tq fp_group)

        append using `acum_denom'
        save `acum_denom', replace

    restore

    *------------------------------------------------------
    * 2.8 Ocupados por ACT1
    *------------------------------------------------------

    preserve

        keep if grupo_actividad == 1

        * Si algún ocupado no tiene ACT1 válido, lo dejamos como 99.
        replace act1 = 99 if missing(act1) | act1 < 0 | act1 > 9

        gen double w_occ = w

        collapse ///
            (sum) ocupados_act1 = w_occ, ///
            by(CCAA anio trim periodo tq fp_group act1)

        append using `acum_act1'
        save `acum_act1', replace

    restore
}


********************************************************************************
* 3) BASE DE DENOMINADORES CCAA
********************************************************************************

use `acum_denom', clear

gen byte ccaa_cod = CCAA

label define lbl_ccaa ///
    1  "Andalucía" ///
    2  "Aragón" ///
    3  "Asturias, Principado de" ///
    4  "Balears, Illes" ///
    5  "Canarias" ///
    6  "Cantabria" ///
    7  "Castilla y León" ///
    8  "Castilla - La Mancha" ///
    9  "Cataluña" ///
    10 "Comunitat Valenciana" ///
    11 "Extremadura" ///
    12 "Galicia" ///
    13 "Madrid, Comunidad de" ///
    14 "Murcia, Región de" ///
    15 "Navarra, Comunidad Foral de" ///
    16 "País Vasco" ///
    17 "Rioja, La" ///
    18 "Ceuta" ///
    19 "Melilla", replace

label values ccaa_cod lbl_ccaa
decode ccaa_cod, gen(ccaa_nombre)

replace ccaa_nombre = subinstr(ccaa_nombre, ",", "", .)

label define lbl_fp_group 0 "No FP" 1 "FP", replace
label values fp_group lbl_fp_group

tempfile denom_ccaa
save `denom_ccaa', replace

save "`out'\EPA_joven_FP_vs_noFP_CCAA_denom.dta", replace

export excel using "`out'\EPA_joven_FP_vs_noFP_CCAA_denom.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 4) CREAR BASE DE CATEGORÍAS ACT1 CON NOMBRES MANUALES
********************************************************************************

clear
set obs 11

gen double act1 = _n - 1
replace act1 = 99 in 11


gen str120 act1_nombre = ""

replace act1_nombre = "Agricultura, ganadería, silvicultura y pesca" ///
    if act1 == 0

replace act1_nombre = "Alimentación, textil, cuero, madera y papel" ///
    if act1 == 1

replace act1_nombre = "Extractivas, refino, química, energía, agua y metalurgia" ///
    if act1 == 2

replace act1_nombre = "Maquinaria, equipo eléctrico y material de transporte" ///
    if act1 == 3

replace act1_nombre = "Construcción" ///
    if act1 == 4

replace act1_nombre = "Comercio, reparaciones y hostelería" ///
    if act1 == 5

replace act1_nombre = "Transporte, almacenamiento, información y comunicaciones" ///
    if act1 == 6

replace act1_nombre = "Finanzas, inmobiliarias, servicios profesionales y administrativos" ///
    if act1 == 7

replace act1_nombre = "Administración Pública, educación y sanidad" ///
    if act1 == 8

replace act1_nombre = "Otros servicios" ///
    if act1 == 9

replace act1_nombre = "No clasificado" ///
    if act1 == 99
tempfile act1_cats
save `act1_cats', replace


********************************************************************************
* 5) CREAR PANEL COMPLETO CCAA × TRIMESTRE × FP/no FP × ACT1
********************************************************************************

use `acum_act1', clear

tempfile act1_raw
save `act1_raw', replace

* Base CCAA × trimestre × FP/no FP
use `denom_ccaa', clear

keep CCAA anio trim periodo tq fp_group
duplicates drop

gen byte _join_key = 1

tempfile base_panel
save `base_panel', replace

* Categorías ACT1 con clave artificial para producto cartesiano
use `act1_cats', clear

gen byte _join_key = 1

tempfile act1_cats_join
save `act1_cats_join', replace

* Producto cartesiano
use `base_panel', clear

joinby _join_key using `act1_cats_join'

drop _join_key

* Añadir ocupados observados
merge 1:1 CCAA anio trim periodo tq fp_group act1 using `act1_raw', nogen

replace ocupados_act1 = 0 if missing(ocupados_act1)

* Añadir denominadores
merge m:1 CCAA anio trim periodo tq fp_group using `denom_ccaa', ///
    nogen keep(match)

* Tasas y shares
gen double tasa_act1_activos = 100 * ocupados_act1 / activos if activos > 0

gen double share_act1_ocupados = 100 * ocupados_act1 / ocupados_total ///
    if ocupados_total > 0

label var ocupados_act1 "Ocupados jóvenes en ACT1"
label var tasa_act1_activos "Ocupados ACT1 / activos jóvenes"
label var share_act1_ocupados "Ocupados ACT1 / ocupados jóvenes"

save "`out'\EPA_joven_FP_vs_noFP_CCAA_ACT1_long_completo.dta", replace

export excel using "`out'\EPA_joven_FP_vs_noFP_CCAA_ACT1_long_completo.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 6) BASE NACIONAL POR ACT1 Y FP/no FP
********************************************************************************

use "`out'\EPA_joven_FP_vs_noFP_CCAA_ACT1_long_completo.dta", clear

collapse ///
    (sum) ocupados_act1 total_jovenes ocupados_total parados inactivos activos, ///
    by(anio trim periodo tq fp_group act1 act1_nombre)

gen double tasa_act1_activos = 100 * ocupados_act1 / activos if activos > 0

gen double share_act1_ocupados = 100 * ocupados_act1 / ocupados_total ///
    if ocupados_total > 0

label define lbl_fp_group 0 "No FP" 1 "FP", replace
label values fp_group lbl_fp_group

save "`out'\EPA_joven_FP_vs_noFP_NACIONAL_ACT1.dta", replace

export excel using "`out'\EPA_joven_FP_vs_noFP_NACIONAL_ACT1.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 7) MEDIA MÓVIL 4T POR ACT1 Y FP/no FP
********************************************************************************

use "`out'\EPA_joven_FP_vs_noFP_NACIONAL_ACT1.dta", clear

sort fp_group act1 tq

egen panel_fp_act1 = group(fp_group act1)

xtset panel_fp_act1 tq

gen double ocupados_act1_4q = ocupados_act1 + L1.ocupados_act1 + L2.ocupados_act1 + L3.ocupados_act1

gen double ocupados_total_4q = ocupados_total + L1.ocupados_total + L2.ocupados_total + L3.ocupados_total

gen double activos_4q = activos + L1.activos + L2.activos + L3.activos

gen double tasa_act1_activos_4q = 100 * ocupados_act1_4q / activos_4q ///
    if activos_4q > 0

gen double share_act1_ocupados_4q = 100 * ocupados_act1_4q / ocupados_total_4q ///
    if ocupados_total_4q > 0

label var ocupados_act1_4q "Ocupados jóvenes ACT1, media móvil 4T"
label var share_act1_ocupados_4q "Peso ACT1 sobre ocupados jóvenes, media móvil 4T"

save "`out'\EPA_joven_FP_vs_noFP_NACIONAL_ACT1_4T.dta", replace

export excel using "`out'\EPA_joven_FP_vs_noFP_NACIONAL_ACT1_4T.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 8) DIAGNÓSTICO: LOS SHARES DEBEN SUMAR 100 POR TRIMESTRE Y GRUPO
********************************************************************************

bysort tq fp_group: egen suma_share = total(share_act1_ocupados)

bysort tq fp_group: egen suma_share_4q = total(share_act1_ocupados_4q)

replace suma_share_4q = . if tq < yq(2021,4)

summ suma_share suma_share_4q

drop suma_share suma_share_4q


********************************************************************************
* 9) BASE TOTAL JÓVENES: FP + NO FP JUNTOS
********************************************************************************

use "`out'\EPA_joven_FP_vs_noFP_NACIONAL_ACT1.dta", clear

collapse ///
    (sum) ocupados_act1 total_jovenes ocupados_total parados inactivos activos, ///
    by(anio trim periodo tq act1 act1_nombre)

gen double tasa_act1_activos = 100 * ocupados_act1 / activos if activos > 0

gen double share_act1_ocupados = 100 * ocupados_act1 / ocupados_total ///
    if ocupados_total > 0

sort act1 tq

egen panel_act1_total = group(act1)

xtset panel_act1_total tq

gen double ocupados_act1_4q = ocupados_act1 + L1.ocupados_act1 + L2.ocupados_act1 + L3.ocupados_act1

gen double ocupados_total_4q = ocupados_total + L1.ocupados_total + L2.ocupados_total + L3.ocupados_total

gen double activos_4q = activos + L1.activos + L2.activos + L3.activos

gen double tasa_act1_activos_4q = 100 * ocupados_act1_4q / activos_4q ///
    if activos_4q > 0

gen double share_act1_ocupados_4q = 100 * ocupados_act1_4q / ocupados_total_4q ///
    if ocupados_total_4q > 0

label var ocupados_act1_4q "Ocupados jóvenes ACT1, media móvil 4T"
label var share_act1_ocupados_4q "Peso ACT1 sobre ocupados jóvenes, media móvil 4T"

save "`out'\EPA_joven_NACIONAL_ACT1_total_4T.dta", replace

export excel using "`out'\EPA_joven_NACIONAL_ACT1_total_4T.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 10) ÍNDICES 2021 = 100 | TOTAL JÓVENES
********************************************************************************

use "`out'\EPA_joven_NACIONAL_ACT1_total_4T.dta", clear

* Base 2021 = media de los cuatro trimestres de 2021.
bysort act1: egen base_ocup_2021 = mean(cond(anio == 2021, ocupados_act1, .))

gen double indice_ocup_act1_2021_100 = 100 * ocupados_act1 / base_ocup_2021 ///
    if base_ocup_2021 > 0

* Para la media móvil 4T, solo hay un valor no missing en 2021: 2021T4.
bysort act1: egen base_ocup_4q_2021 = mean(cond(anio == 2021, ocupados_act1_4q, .))

gen double indice_ocup_act1_4q_2021_100 = 100 * ocupados_act1_4q / base_ocup_4q_2021 ///
    if base_ocup_4q_2021 > 0

gen double ocupados_act1_miles = ocupados_act1 / 1000

gen double ocupados_act1_4q_miles = ocupados_act1_4q / 1000

label var indice_ocup_act1_2021_100 "Índice ocupación juvenil ACT1, 2021=100"
label var indice_ocup_act1_4q_2021_100 "Índice ocupación juvenil ACT1, media móvil 4T, 2021=100"
label var ocupados_act1_miles "Ocupados jóvenes, miles"
label var ocupados_act1_4q_miles "Ocupados jóvenes, miles, media móvil 4T"

save "`out'\EPA_joven_NACIONAL_ACT1_total_indices_2021_100.dta", replace

export excel using "`out'\EPA_joven_NACIONAL_ACT1_total_indices_2021_100.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 11) GRÁFICO A: NIVELES ABSOLUTOS DE OCUPACIÓN JUVENIL POR ACT1
********************************************************************************

twoway ///
    (line ocupados_act1_4q_miles tq if act1 <= 9, lwidth(medthick)), ///
    by(act1_nombre, cols(3) note("") ///
        title("España: empleo juvenil por actividad económica", size(medsmall)) ///
        subtitle("Ocupados jóvenes <25, miles, media móvil 4T", size(small))) ///
    ylabel(, angle(0) grid labsize(small)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("Miles de ocupados jóvenes", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_niveles_act1_total_4q, replace)

graph export "`out'\grafico_nacional_niveles_ocupacion_juvenil_ACT1_4T.png", ///
    width(3400) replace

graph save "`out'\grafico_nacional_niveles_ocupacion_juvenil_ACT1_4T.gph", replace


********************************************************************************
* 12) GRÁFICO B: ÍNDICE 2021 = 100 POR ACT1
********************************************************************************

twoway ///
    (line indice_ocup_act1_4q_2021_100 tq if act1 <= 9, lwidth(medthick)), ///
    by(act1_nombre, cols(3) note("") ///
        title("España: evolución relativa del empleo juvenil por actividad económica", size(medsmall)) ///
        subtitle("Índice 2021 = 100, media móvil 4T", size(small))) ///
    yline(100, lcolor(gs8) lpattern(dash)) ///
    ylabel(, angle(0) grid labsize(small)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("Índice 2021 = 100", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_indice_act1_total_4q, replace)

graph export "`out'\grafico_nacional_indice_ocupacion_juvenil_ACT1_2021_100_4T.png", ///
    width(3400) replace

graph save "`out'\grafico_nacional_indice_ocupacion_juvenil_ACT1_2021_100_4T.gph", replace


********************************************************************************
* 13) GRÁFICO C: PESO DE CADA ACT1 SOBRE OCUPADOS JÓVENES
*     Las ramas suman 100% en cada trimestre.
********************************************************************************

twoway ///
    (line share_act1_ocupados_4q tq if act1 <= 9, lwidth(medthick)), ///
    by(act1_nombre, cols(3) note("") ///
        title("España: composición sectorial del empleo juvenil", size(medsmall)) ///
        subtitle("Peso de cada ACT1 sobre ocupados jóvenes; suma total = 100%", size(small))) ///
    ylabel(, angle(0) grid labsize(small)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("% de ocupados jóvenes", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_share_act1_total_4q, replace)

graph export "`out'\grafico_nacional_share_ocupacion_juvenil_ACT1_4T.png", ///
    width(3400) replace

graph save "`out'\grafico_nacional_share_ocupacion_juvenil_ACT1_4T.gph", replace


********************************************************************************
* 14) GRÁFICO D: COMPOSICIÓN ÚLTIMO TRIMESTRE
********************************************************************************

preserve

    keep if !missing(share_act1_ocupados_4q)

    quietly summarize tq
    local last = r(max)

    keep if tq == `last' & act1 <= 9

    graph hbar share_act1_ocupados_4q, ///
        over(act1_nombre, sort(1) descending label(labsize(vsmall))) ///
        blabel(bar, format(%4.1f)) ///
        ytitle("% de ocupados jóvenes") ///
        title("España: composición del empleo juvenil por actividad económica", size(medium)) ///
        subtitle("Último trimestre disponible, media móvil 4T", size(small)) ///
        graphregion(color(white)) bgcolor(white) ///
        name(g_share_ultimo_act1, replace)

    graph export "`out'\grafico_nacional_composicion_ocupacion_juvenil_ACT1_ultimo_4T.png", ///
        width(2600) replace

    graph save "`out'\grafico_nacional_composicion_ocupacion_juvenil_ACT1_ultimo_4T.gph", replace

restore


********************************************************************************
* 15) ÍNDICES 2021 = 100 | FP VS NO FP POR ACT1
********************************************************************************

use "`out'\EPA_joven_FP_vs_noFP_NACIONAL_ACT1_4T.dta", clear

bysort fp_group act1: egen base_ocup_fpact_2021 = mean(cond(anio == 2021, ocupados_act1, .))

gen double indice_ocup_fpact_2021_100 = 100 * ocupados_act1 / base_ocup_fpact_2021 ///
    if base_ocup_fpact_2021 > 0

bysort fp_group act1: egen base_ocup_fpact_4q_2021 = mean(cond(anio == 2021, ocupados_act1_4q, .))

gen double indice_ocup_fpact_4q_2021_100 = 100 * ocupados_act1_4q / base_ocup_fpact_4q_2021 ///
    if base_ocup_fpact_4q_2021 > 0

gen double ocupados_act1_miles = ocupados_act1 / 1000

gen double ocupados_act1_4q_miles = ocupados_act1_4q / 1000

save "`out'\EPA_joven_FP_vs_noFP_NACIONAL_ACT1_indices_2021_100.dta", replace

export excel using "`out'\EPA_joven_FP_vs_noFP_NACIONAL_ACT1_indices_2021_100.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 16) GRÁFICO E: NIVELES ABSOLUTOS FP VS NO FP POR ACT1
********************************************************************************

twoway ///
    (line ocupados_act1_4q_miles tq if fp_group == 1 & act1 <= 9, ///
        lcolor(red) lwidth(medthick)) ///
    (line ocupados_act1_4q_miles tq if fp_group == 0 & act1 <= 9, ///
        lcolor(blue) lpattern(dash) lwidth(medthick)), ///
    by(act1_nombre, cols(3) note("") ///
        title("España: empleo juvenil por actividad económica", size(medsmall)) ///
        subtitle("FP vs No FP | Miles de ocupados jóvenes, media móvil 4T", size(small))) ///
    legend(order(1 "FP" 2 "No FP") pos(6) ring(0)) ///
    ylabel(, angle(0) grid labsize(small)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("Miles de ocupados jóvenes", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_niveles_act1_fp_nofp_4q, replace)

graph export "`out'\grafico_nacional_niveles_ocupacion_juvenil_ACT1_FP_vs_NoFP_4T.png", ///
    width(3400) replace

graph save "`out'\grafico_nacional_niveles_ocupacion_juvenil_ACT1_FP_vs_NoFP_4T.gph", replace


********************************************************************************
* 17) GRÁFICO F: ÍNDICE 2021 = 100, FP VS NO FP POR ACT1
********************************************************************************

twoway ///
    (line indice_ocup_fpact_4q_2021_100 tq if fp_group == 1 & act1 <= 9, ///
        lcolor(red) lwidth(medthick)) ///
    (line indice_ocup_fpact_4q_2021_100 tq if fp_group == 0 & act1 <= 9, ///
        lcolor(blue) lpattern(dash) lwidth(medthick)), ///
    by(act1_nombre, cols(3) note("") ///
        title("España: evolución relativa del empleo juvenil por actividad económica", size(medsmall)) ///
        subtitle("FP vs No FP | Índice 2021 = 100, media móvil 4T", size(small))) ///
    legend(order(1 "FP" 2 "No FP") pos(6) ring(0)) ///
    yline(100, lcolor(gs8) lpattern(dash)) ///
    ylabel(, angle(0) grid labsize(small)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("Índice 2021 = 100", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_indice_act1_fp_nofp_4q, replace)

graph export "`out'\grafico_nacional_indice_ocupacion_juvenil_ACT1_FP_vs_NoFP_2021_100_4T.png", ///
    width(3400) replace

graph save "`out'\grafico_nacional_indice_ocupacion_juvenil_ACT1_FP_vs_NoFP_2021_100_4T.gph", replace


********************************************************************************
* 18) GRÁFICO G: PESO ACT1 SOBRE OCUPADOS JÓVENES, FP VS NO FP
*     Dentro de cada grupo, las ramas suman 100%.
********************************************************************************

twoway ///
    (line share_act1_ocupados_4q tq if fp_group == 1 & act1 <= 9, ///
        lcolor(red) lwidth(medthick)) ///
    (line share_act1_ocupados_4q tq if fp_group == 0 & act1 <= 9, ///
        lcolor(blue) lpattern(dash) lwidth(medthick)), ///
    by(act1_nombre, cols(3) note("") ///
        title("España: composición sectorial del empleo juvenil", size(medsmall)) ///
        subtitle("FP vs No FP | Peso sobre ocupados jóvenes, media móvil 4T", size(small))) ///
    legend(order(1 "FP" 2 "No FP") pos(6) ring(0)) ///
    ylabel(, angle(0) grid labsize(small)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("% de ocupados jóvenes del grupo", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_share_act1_fp_nofp_4q, replace)

graph export "`out'\grafico_nacional_share_ocupacion_juvenil_ACT1_FP_vs_NoFP_4T.png", ///
    width(3400) replace

graph save "`out'\grafico_nacional_share_ocupacion_juvenil_ACT1_FP_vs_NoFP_4T.gph", replace


********************************************************************************
* 19) TABLA: CAMBIO ABSOLUTO Y RELATIVO DESDE 2021
********************************************************************************

use "`out'\EPA_joven_NACIONAL_ACT1_total_indices_2021_100.dta", clear

quietly summarize tq
local last = r(max)

bysort act1: egen ocupados_base_2021 = max(base_ocup_2021)

bysort act1: egen ocupados_ultimo = max(cond(tq == `last', ocupados_act1, .))

bysort act1: egen indice_ultimo = max(cond(tq == `last', indice_ocup_act1_2021_100, .))

bysort act1: egen share_ultimo = max(cond(tq == `last', share_act1_ocupados, .))

bysort act1: egen share_base_2021 = mean(cond(anio == 2021, share_act1_ocupados, .))

gen double cambio_abs_ocupados = ocupados_ultimo - ocupados_base_2021

gen double cambio_pct_ocupados = indice_ultimo - 100

gen double cambio_share_pp = share_ultimo - share_base_2021

keep act1 act1_nombre ocupados_base_2021 ocupados_ultimo ///
     cambio_abs_ocupados indice_ultimo cambio_pct_ocupados ///
     share_base_2021 share_ultimo cambio_share_pp

duplicates drop

gsort -cambio_abs_ocupados

save "`out'\tabla_cambio_ocupacion_juvenil_ACT1_2021_ultimo.dta", replace

export excel using "`out'\tabla_cambio_ocupacion_juvenil_ACT1_2021_ultimo.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 20) PROXY DIGITALIZACIÓN NACIONAL
*     ACT1 == 7: Transporte y comunicaciones
********************************************************************************

use "`out'\EPA_joven_FP_vs_noFP_NACIONAL_ACT1_indices_2021_100.dta", clear

keep if act1 == `digital_act1'

save "`out'\EPA_joven_FP_vs_noFP_NACIONAL_proxy_digital_ACT1_7.dta", replace

export excel using "`out'\EPA_joven_FP_vs_noFP_NACIONAL_proxy_digital_ACT1_7.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 20) PROXY DE DIGITALIZACIÓN NACIONAL
*     ACT1 == 7: Transporte y comunicaciones
********************************************************************************

use "`out'\EPA_joven_FP_vs_noFP_NACIONAL_ACT1_indices_2021_100.dta", clear

keep if act1 == `digital_act1'

save "`out'\EPA_joven_FP_vs_noFP_NACIONAL_proxy_digitalizacion_ACT1_7.dta", replace

export excel using "`out'\EPA_joven_FP_vs_noFP_NACIONAL_proxy_digitalizacion_ACT1_7.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 20.1) GRÁFICO NACIONAL: NIVELES PROXY DE DIGITALIZACIÓN, FP VS NO FP
********************************************************************************

twoway ///
    (line ocupados_act1_4q_miles tq if fp_group == 1, ///
        lcolor(red) lwidth(medthick)) ///
    (line ocupados_act1_4q_miles tq if fp_group == 0, ///
        lcolor(blue) lpattern(dash) lwidth(medthick)), ///
    legend(order(1 "FP" 2 "No FP") pos(6) ring(0)) ///
    ylabel(, angle(0) grid) ///
    xlabel(, angle(45)) ///
    xtitle("Trimestre") ///
    ytitle("Miles de ocupados jóvenes") ///
    title("España: ocupación juvenil en la proxy de digitalización", size(medium)) ///
    subtitle("ACT1=6: Transporte, almacenamiento, información y comunicaciones | Media móvil 4T", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_ndig1, replace)

graph export "`out'\grafico_nacional_proxy_digitalizacion_niveles_FP_vs_NoFP_4T.png", ///
    width(2600) replace

graph save "`out'\grafico_nacional_proxy_digitalizacion_niveles_FP_vs_NoFP_4T.gph", ///
    replace


********************************************************************************
* 20.2) GRÁFICO NACIONAL: ÍNDICE 2021 = 100 PROXY DE DIGITALIZACIÓN
********************************************************************************

twoway ///
    (line indice_ocup_fpact_4q_2021_100 tq if fp_group == 1, ///
        lcolor(red) lwidth(medthick)) ///
    (line indice_ocup_fpact_4q_2021_100 tq if fp_group == 0, ///
        lcolor(blue) lpattern(dash) lwidth(medthick)), ///
    legend(order(1 "FP" 2 "No FP") pos(6) ring(0)) ///
    yline(100, lcolor(gs8) lpattern(dash)) ///
    ylabel(50(25)250, angle(0) grid) ///
    yscale(range(50 250)) ///
    xlabel(, angle(45)) ///
    xtitle("Trimestre") ///
    ytitle("Índice 2021 = 100") ///
    title("España: evolución relativa de la proxy de digitalización", size(medium)) ///
    subtitle("ACT1=6: Transporte, almacenamiento, información y comunicaciones | FP vs No FP", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_ndig2, replace)

graph export "`out'\grafico_nacional_proxy_digitalizacion_indice_2021_100_FP_vs_NoFP_4T.png", ///
    width(2600) replace

graph save "`out'\grafico_nacional_proxy_digitalizacion_indice_2021_100_FP_vs_NoFP_4T.gph", ///
    replace


********************************************************************************
* 20.3) GRÁFICO NACIONAL: SHARE PROXY DE DIGITALIZACIÓN, FP VS NO FP
********************************************************************************

twoway ///
    (line share_act1_ocupados_4q tq if fp_group == 1, ///
        lcolor(red) lwidth(medthick)) ///
    (line share_act1_ocupados_4q tq if fp_group == 0, ///
        lcolor(blue) lpattern(dash) lwidth(medthick)), ///
    legend(order(1 "FP" 2 "No FP") pos(6) ring(0)) ///
    ylabel(0(2)20, angle(0) grid) ///
    yscale(range(0 20)) ///
    xlabel(, angle(45)) ///
    xtitle("Trimestre") ///
    ytitle("% de ocupados jóvenes del grupo") ///
    title("España: peso de la proxy de digitalización en la ocupación juvenil", size(medium)) ///
    subtitle("ACT1=7 sobre ocupados jóvenes | Media móvil 4T", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_ndig3, replace)

graph export "`out'\grafico_nacional_proxy_digitalizacion_share_FP_vs_NoFP_4T.png", ///
    width(2600) replace

graph save "`out'\grafico_nacional_proxy_digitalizacion_share_FP_vs_NoFP_4T.gph", ///
    replace


********************************************************************************
* 20.4) GRÁFICO NACIONAL: BRECHA FP - NO FP EN SHARE DE LA PROXY
********************************************************************************

preserve

    keep anio trim periodo tq fp_group share_act1_ocupados_4q ///
         tasa_act1_activos_4q indice_ocup_fpact_4q_2021_100 ///
         ocupados_act1_4q_miles

    reshape wide share_act1_ocupados_4q tasa_act1_activos_4q ///
                 indice_ocup_fpact_4q_2021_100 ocupados_act1_4q_miles, ///
                 i(anio trim periodo tq) j(fp_group)

    gen double gap_share_dig_fp_nofp = share_act1_ocupados_4q1 - share_act1_ocupados_4q0

    gen double gap_indice_dig_fp_nofp = indice_ocup_fpact_4q_2021_1001 - indice_ocup_fpact_4q_2021_1000

    label var gap_share_dig_fp_nofp "Brecha FP - No FP en peso de la proxy de digitalización"
    label var gap_indice_dig_fp_nofp "Brecha FP - No FP en índice de la proxy de digitalización"

    save "`out'\EPA_joven_NACIONAL_proxy_digitalizacion_brechas_FP_NoFP_4T.dta", replace

    export excel using "`out'\EPA_joven_NACIONAL_proxy_digitalizacion_brechas_FP_NoFP_4T.xlsx", ///
        replace firstrow(variables)

    twoway ///
        (line gap_share_dig_fp_nofp tq, lcolor(black) lwidth(medthick)), ///
        yline(0, lcolor(gs8) lpattern(dash)) ///
        ylabel(-10(2)10, angle(0) grid) ///
        yscale(range(-10 10)) ///
        xlabel(, angle(45)) ///
        xtitle("Trimestre") ///
        ytitle("Puntos porcentuales") ///
        title("España: brecha FP - No FP en la proxy de digitalización", size(medium)) ///
        subtitle("Peso sobre ocupados jóvenes | Media móvil 4T", size(small)) ///
        graphregion(color(white)) bgcolor(white) ///
        name(g_ndig4, replace)

    graph export "`out'\grafico_nacional_proxy_digitalizacion_brecha_share_FP_menos_NoFP_4T.png", ///
        width(2600) replace

    graph save "`out'\grafico_nacional_proxy_digitalizacion_brecha_share_FP_menos_NoFP_4T.gph", ///
        replace

restore


********************************************************************************
* 21) PROXY DE DIGITALIZACIÓN POR CCAA
*     ACT1 == 7: Transporte y comunicaciones
********************************************************************************

use "`out'\EPA_joven_FP_vs_noFP_CCAA_ACT1_long_completo.dta", clear

keep if act1 == `digital_act1'

gen str80 act1_proxy_nombre = "Transporte y comunicaciones"

label define lbl_fp_group 0 "No FP" 1 "FP", replace
label values fp_group lbl_fp_group


********************************************************************************
* 21.1) MEDIA MÓVIL 4T POR CCAA × FP/NO FP
********************************************************************************

sort CCAA fp_group tq

egen panel_dig_ccaa = group(CCAA fp_group)

xtset panel_dig_ccaa tq

gen double ocupados_dig_4q = ocupados_act1 + L1.ocupados_act1 + L2.ocupados_act1 + L3.ocupados_act1

gen double ocupados_total_4q = ocupados_total + L1.ocupados_total + L2.ocupados_total + L3.ocupados_total

gen double activos_4q = activos + L1.activos + L2.activos + L3.activos

gen double share_dig_ocupados_4q = 100 * ocupados_dig_4q / ocupados_total_4q ///
    if ocupados_total_4q > 0

gen double tasa_dig_activos_4q = 100 * ocupados_dig_4q / activos_4q ///
    if activos_4q > 0

gen double ocupados_dig_4q_miles = ocupados_dig_4q / 1000

label var ocupados_dig_4q_miles "Ocupados jóvenes en proxy de digitalización, miles, media móvil 4T"
label var share_dig_ocupados_4q "Peso proxy de digitalización sobre ocupados jóvenes, media móvil 4T"
label var tasa_dig_activos_4q "Ocupados proxy de digitalización / activos jóvenes, media móvil 4T"


********************************************************************************
* 21.2) ÍNDICE 2021 = 100 POR CCAA × FP/NO FP
********************************************************************************

bysort CCAA fp_group: egen base_dig_4q_2021 = mean(cond(anio == 2021, ocupados_dig_4q, .))

gen double indice_dig_4q_2021_100 = 100 * ocupados_dig_4q / base_dig_4q_2021 ///
    if base_dig_4q_2021 > 0

label var indice_dig_4q_2021_100 ///
    "Índice ocupación proxy de digitalización, media móvil 4T, 2021=100"


********************************************************************************
* 21.3) GUARDAR BASE CCAA PROXY DE DIGITALIZACIÓN
********************************************************************************

save "`out'\EPA_joven_FP_vs_noFP_CCAA_proxy_digitalizacion_ACT1_7_4T.dta", replace

export excel using "`out'\EPA_joven_FP_vs_noFP_CCAA_proxy_digitalizacion_ACT1_7_4T.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 21.4) GRÁFICO CCAA 1: NIVELES PROXY DE DIGITALIZACIÓN, FP VS NO FP
********************************************************************************

twoway ///
    (line ocupados_dig_4q_miles tq if fp_group == 1, ///
        lcolor(red) lwidth(medthick)) ///
    (line ocupados_dig_4q_miles tq if fp_group == 0, ///
        lcolor(blue) lpattern(dash) lwidth(medthick)), ///
    by(ccaa_nombre, cols(4) note("") ///
        title("Ocupación juvenil en la proxy de digitalización por CCAA", size(medsmall)) ///
        subtitle("ACT1=6: Transporte, almacenamiento, información y comunicaciones | Media móvil 4T", size(small))) ///
    legend(order(1 "FP" 2 "No FP") pos(6) ring(0)) ///
    ylabel(, angle(0) grid labsize(small)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("Miles de ocupados jóvenes", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_cdig1, replace)

graph export "`out'\grafico_CCAA_proxy_digitalizacion_niveles_FP_vs_NoFP_4T.png", ///
    width(3400) replace

graph save "`out'\grafico_CCAA_proxy_digitalizacion_niveles_FP_vs_NoFP_4T.gph", replace


********************************************************************************
* 21.5) GRÁFICO CCAA 2: ÍNDICE 2021 = 100 PROXY DE DIGITALIZACIÓN, FP VS NO FP
********************************************************************************

twoway ///
    (line indice_dig_4q_2021_100 tq if fp_group == 1, ///
        lcolor(red) lwidth(medthick)) ///
    (line indice_dig_4q_2021_100 tq if fp_group == 0, ///
        lcolor(blue) lpattern(dash) lwidth(medthick)), ///
    by(ccaa_nombre, cols(4) note("") ///
        title("Evolución relativa de la proxy de digitalización por CCAA", size(medsmall)) ///
        subtitle("ACT1=6: Transporte, almacenamiento, información y comunicaciones | Índice 2021=100, media móvil 4T", size(small))) ///
    legend(order(1 "FP" 2 "No FP") pos(6) ring(0)) ///
    yline(100, lcolor(gs8) lpattern(dash)) ///
    ylabel(50(25)250, angle(0) grid labsize(small)) ///
    yscale(range(50 250)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("Índice 2021 = 100", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_cdig2, replace)

graph export "`out'\grafico_CCAA_proxy_digitalizacion_indice_2021_100_FP_vs_NoFP_4T.png", ///
    width(3400) replace

graph save "`out'\grafico_CCAA_proxy_digitalizacion_indice_2021_100_FP_vs_NoFP_4T.gph", replace


********************************************************************************
* 21.6) GRÁFICO CCAA 3: SHARE PROXY DE DIGITALIZACIÓN, FP VS NO FP
********************************************************************************

twoway ///
    (line share_dig_ocupados_4q tq if fp_group == 1, ///
        lcolor(red) lwidth(medthick)) ///
    (line share_dig_ocupados_4q tq if fp_group == 0, ///
        lcolor(blue) lpattern(dash) lwidth(medthick)), ///
    by(ccaa_nombre, cols(4) note("") ///
        title("Peso de la proxy de digitalización en la ocupación juvenil por CCAA", size(medsmall)) ///
        subtitle("ACT1=7 sobre ocupados jóvenes del grupo | Media móvil 4T", size(small))) ///
    legend(order(1 "FP" 2 "No FP") pos(6) ring(0)) ///
    ylabel(0(5)30, angle(0) grid labsize(small)) ///
    yscale(range(0 30)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("% de ocupados jóvenes del grupo", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_cdig3, replace)

graph export "`out'\grafico_CCAA_proxy_digitalizacion_share_FP_vs_NoFP_4T.png", ///
    width(3400) replace

graph save "`out'\grafico_CCAA_proxy_digitalizacion_share_FP_vs_NoFP_4T.gph", replace


********************************************************************************
* 21.7) GRÁFICO CCAA 4: BRECHA FP - NO FP EN SHARE PROXY DE DIGITALIZACIÓN
********************************************************************************

preserve

    keep CCAA ccaa_nombre anio trim periodo tq fp_group ///
         share_dig_ocupados_4q tasa_dig_activos_4q ///
         indice_dig_4q_2021_100 ocupados_dig_4q_miles

    reshape wide share_dig_ocupados_4q tasa_dig_activos_4q ///
                 indice_dig_4q_2021_100 ocupados_dig_4q_miles, ///
                 i(CCAA ccaa_nombre anio trim periodo tq) j(fp_group)

    gen double gap_share_dig_fp_nofp = share_dig_ocupados_4q1 - share_dig_ocupados_4q0

    gen double gap_indice_dig_fp_nofp = indice_dig_4q_2021_1001 - indice_dig_4q_2021_1000

    label var gap_share_dig_fp_nofp ///
        "Brecha FP - No FP en peso proxy de digitalización"

    label var gap_indice_dig_fp_nofp ///
        "Brecha FP - No FP en índice proxy de digitalización"

    save "`out'\EPA_joven_CCAA_proxy_digitalizacion_brechas_FP_NoFP_4T.dta", replace

    export excel using "`out'\EPA_joven_CCAA_proxy_digitalizacion_brechas_FP_NoFP_4T.xlsx", ///
        replace firstrow(variables)

    twoway ///
        (line gap_share_dig_fp_nofp tq, lcolor(black) lwidth(medthick)), ///
        by(ccaa_nombre, cols(4) note("") ///
            title("Brecha FP - No FP en proxy de digitalización por CCAA", size(medsmall)) ///
            subtitle("Peso sobre ocupados jóvenes | Media móvil 4T", size(small))) ///
        yline(0, lcolor(gs8) lpattern(dash)) ///
        ylabel(-15(5)15, angle(0) grid labsize(small)) ///
        yscale(range(-15 15)) ///
        xlabel(, angle(45) labsize(vsmall)) ///
        xtitle("Trimestre", size(small)) ///
        ytitle("Puntos porcentuales", size(small)) ///
        graphregion(color(white)) bgcolor(white) ///
        name(g_cdig4, replace)

    graph export "`out'\grafico_CCAA_proxy_digitalizacion_brecha_share_FP_menos_NoFP_4T.png", ///
        width(3400) replace

    graph save "`out'\grafico_CCAA_proxy_digitalizacion_brecha_share_FP_menos_NoFP_4T.gph", replace

restore


********************************************************************************
* 21.8) GRÁFICO CCAA 5: ÍNDICE PROXY DE DIGITALIZACIÓN TOTAL JÓVENES
********************************************************************************

preserve

    collapse ///
        (sum) ocupados_act1 ocupados_total activos, ///
        by(CCAA ccaa_nombre anio trim periodo tq act1_proxy_nombre)

    sort CCAA tq

    egen panel_total_ccaa = group(CCAA)
    xtset panel_total_ccaa tq

    gen double ocupados_dig_total_4q = ocupados_act1 + L1.ocupados_act1 + L2.ocupados_act1 + L3.ocupados_act1

    bysort CCAA: egen base_dig_total_2021 = mean(cond(anio == 2021, ocupados_dig_total_4q, .))

    gen double indice_dig_total_2021_100 = 100 * ocupados_dig_total_4q / base_dig_total_2021 ///
        if base_dig_total_2021 > 0

    twoway ///
        (line indice_dig_total_2021_100 tq, lcolor(blue) lwidth(medthick)), ///
        by(ccaa_nombre, cols(4) note("") ///
            title("Evolución relativa de la proxy de digitalización por CCAA", size(medsmall)) ///
            subtitle("Total jóvenes <25 | Índice 2021=100, media móvil 4T", size(small))) ///
        yline(100, lcolor(gs8) lpattern(dash)) ///
        ylabel(50(25)250, angle(0) grid labsize(small)) ///
        yscale(range(50 250)) ///
        xlabel(, angle(45) labsize(vsmall)) ///
        xtitle("Trimestre", size(small)) ///
        ytitle("Índice 2021 = 100", size(small)) ///
        graphregion(color(white)) bgcolor(white) ///
        name(g_cdig5, replace)

    graph export "`out'\grafico_CCAA_proxy_digitalizacion_indice_total_jovenes_2021_100_4T.png", ///
        width(3400) replace

    graph save "`out'\grafico_CCAA_proxy_digitalizacion_indice_total_jovenes_2021_100_4T.gph", replace

restore


********************************************************************************
* 22) MENSAJE FINAL
********************************************************************************

di as result "============================================================"
di as result "Proceso completado correctamente."
di as result ""
di as result "Proxy de digitalización usada:"
di as result "ACT1 == `digital_act1' -> Transporte y comunicaciones"
di as result ""
di as result "Todos los nombres internos de gráficos se han acortado para evitar r(198)."
di as result "============================================================"


/********************************************************************************
* SECTION 7: do_file_eje_verds(1).do
********************************************************************************/

clear all
if "${PROJECT_ROOT}" == "" {
    global PROJECT_ROOT "."
}
set more off

********************************************************************************
* EPA 2021T1-2026T1 | JÓVENES <25 | EJE VERDE
*
* Objetivo:
* Crear un archivo independiente para analizar empleo juvenil en ramas vinculadas
* a la transición verde, conectable con la expansión de plazas de FP del PRTR.
*
* Variable sectorial:
* ACT1 / TACTIV, códigos agregados 0-9.
*
* Eje verde CORE:
* ACT1 = 2 | Extractivas, refino, química, energía, agua, residuos y metalurgia
* ACT1 = 3 | Maquinaria, equipo eléctrico, material de transporte e instalación
* ACT1 = 4 | Construcción
*
* Eje verde AMPLIO:
* ACT1 = 0, 2, 3, 4, 6, 7
*
* Importante:
* Esto NO mide "empleos verdes" estrictos.
* Mide empleo juvenil en ramas productivas vinculadas a la transición verde.
********************************************************************************


********************************************************************************
* 0) RUTAS Y PARÁMETROS
********************************************************************************

local root "${PROJECT_ROOT}\98.IMPACTO DEL PLAN\1. FP\epa\dta"

local out "${PROJECT_ROOT}\98.IMPACTO DEL PLAN\1. FP\epa\resultados_EJE_VERDE_ACT1"
capture mkdir "`out'"

local files epa_2021t1.dta epa_2021t2.dta epa_2021t3.dta epa_2021t4.dta ///
             epa_2022t1.dta epa_2022t2.dta epa_2022t3.dta epa_2022t4.dta ///
             epa_2023t1.dta epa_2023t2.dta epa_2023t3.dta epa_2023t4.dta ///
             epa_2024t1.dta epa_2024t2.dta epa_2024t3.dta epa_2024t4.dta ///
             epa_2025t1.dta epa_2025t2.dta epa_2025t3.dta epa_2025t4.dta ///
             epa_2026t1.dta

local useweights 1
local edad_max 25

* Si quieres que No FP incluya también missing de NFORMA, déjalo en 1.
local include_missing_nofp 1


********************************************************************************
* 1) TEMPFILES
********************************************************************************

tempfile acum_denom acum_act1

clear
save `acum_denom', emptyok

clear
save `acum_act1', emptyok


********************************************************************************
* 2) LOOP PRINCIPAL: CARGA DE TODAS LAS EPAS
********************************************************************************

foreach f of local files {

    di as result ">>> Procesando: `f'"

    local full "`root'/`f'"

    capture confirm file "`full'"
    if _rc {
        di as error "   No existe: `full' -> salto"
        continue
    }

    use "`full'", clear


    *------------------------------------------------------
    * 2.1 Asegurar tipos numéricos
    *------------------------------------------------------

    foreach v in CCAA PROV EDAD1 AOI FACTOREL CICLO ACT1 TACTIV {
        capture confirm variable `v'
        if !_rc {
            capture confirm numeric variable `v'
            if _rc {
                destring `v', replace ignore(" .")
            }
        }
    }


    *------------------------------------------------------
    * 2.2 Crear variable sectorial ACT1 / TACTIV
    *------------------------------------------------------

    capture confirm variable ACT1
    if !_rc {
        gen double act1 = ACT1
    }
    else {
        capture confirm variable TACTIV
        if !_rc {
            gen double act1 = TACTIV
        }
        else {
            di as error "   No existe ACT1 ni TACTIV en `f' -> salto"
            continue
        }
    }


    *------------------------------------------------------
    * 2.3 Filtrar jóvenes menores de 25
    *------------------------------------------------------

    keep if EDAD1 < `edad_max'

    drop if missing(AOI) | missing(CCAA)


    *------------------------------------------------------
    * 2.4 Crear grupo FP vs No FP
    *------------------------------------------------------

    capture confirm variable NFORMA
    if _rc {
        di as error "   NFORMA no existe en `f' -> salto"
        continue
    }

    capture confirm string variable NFORMA

    if !_rc {
        gen str30 nforma_str = upper(strtrim(NFORMA))
    }
    else {
        capture decode NFORMA, gen(nforma_str)
        if _rc {
            tostring NFORMA, gen(nforma_str) force
        }
        replace nforma_str = upper(strtrim(nforma_str))
    }

    replace nforma_str = "" if nforma_str == "."

    gen byte fp_group = .
    replace fp_group = 1 if nforma_str == "SP"
    replace fp_group = 0 if nforma_str != "SP" & nforma_str != ""

    if `include_missing_nofp' == 1 {
        replace fp_group = 0 if nforma_str == ""
    }

    drop if missing(fp_group)

    label define lbl_fp_group 0 "No FP" 1 "FP", replace
    label values fp_group lbl_fp_group


    *------------------------------------------------------
    * 2.5 Clasificar situación laboral
    *------------------------------------------------------

    gen byte grupo_actividad = .
    replace grupo_actividad = 1 if inlist(AOI, 3, 4)      // Ocupados
    replace grupo_actividad = 2 if inlist(AOI, 5, 6)      // Parados
    replace grupo_actividad = 3 if inlist(AOI, 7, 8, 9)   // Inactivos

    drop if missing(grupo_actividad)


    *------------------------------------------------------
    * 2.6 Identificadores temporales
    *------------------------------------------------------

    capture assert !missing(CICLO)

    if !_rc {
        gen anio = 2021 + floor((CICLO - 194) / 4)
        gen trim = mod(CICLO - 194, 4) + 1
    }
    else {
        local base = subinstr("`f'", ".dta", "", .)
        local yy = real(substr("`base'", 5, 4))
        local tt = real(substr("`base'", 10, 1))

        gen anio = `yy'
        gen trim = `tt'
    }

    gen str7 periodo = string(anio) + "T" + string(trim)
    gen tq = yq(anio, trim)
    format tq %tq


    *------------------------------------------------------
    * 2.7 Pesos
    *------------------------------------------------------

    gen double w = 1

    if `useweights' == 1 {
        capture confirm variable FACTOREL
        if _rc {
            di as error "   FACTOREL no existe en `f' -> salto"
            continue
        }

        replace w = FACTOREL
    }

    drop if missing(w)


    *------------------------------------------------------
    * 2.8 Denominadores CCAA × trimestre × FP/no FP
    *------------------------------------------------------

    preserve

        gen double w_total = w
        gen double w_ocup  = cond(grupo_actividad == 1, w, 0)
        gen double w_paro  = cond(grupo_actividad == 2, w, 0)
        gen double w_inact = cond(grupo_actividad == 3, w, 0)
        gen double w_act   = cond(inlist(grupo_actividad, 1, 2), w, 0)

        collapse ///
            (sum) total_jovenes = w_total ///
                  ocupados_total = w_ocup ///
                  parados = w_paro ///
                  inactivos = w_inact ///
                  activos = w_act, ///
            by(CCAA anio trim periodo tq fp_group)

        append using `acum_denom'
        save `acum_denom', replace

    restore


    *------------------------------------------------------
    * 2.9 Ocupados por ACT1 / TACTIV
    *------------------------------------------------------

    preserve

        keep if grupo_actividad == 1

        replace act1 = 99 if missing(act1) | act1 < 0 | act1 > 9

        gen double w_occ = w

        collapse ///
            (sum) ocupados_act1 = w_occ, ///
            by(CCAA anio trim periodo tq fp_group act1)

        append using `acum_act1'
        save `acum_act1', replace

    restore
}


********************************************************************************
* 3) BASE DE DENOMINADORES CCAA
********************************************************************************

use `acum_denom', clear

gen byte ccaa_cod = CCAA

label define lbl_ccaa ///
    1  "Andalucía" ///
    2  "Aragón" ///
    3  "Asturias, Principado de" ///
    4  "Balears, Illes" ///
    5  "Canarias" ///
    6  "Cantabria" ///
    7  "Castilla y León" ///
    8  "Castilla - La Mancha" ///
    9  "Cataluña" ///
    10 "Comunitat Valenciana" ///
    11 "Extremadura" ///
    12 "Galicia" ///
    13 "Madrid, Comunidad de" ///
    14 "Murcia, Región de" ///
    15 "Navarra, Comunidad Foral de" ///
    16 "País Vasco" ///
    17 "Rioja, La" ///
    18 "Ceuta" ///
    19 "Melilla", replace

label values ccaa_cod lbl_ccaa
decode ccaa_cod, gen(ccaa_nombre)

replace ccaa_nombre = subinstr(ccaa_nombre, ",", "", .)

label define lbl_fp_group 0 "No FP" 1 "FP", replace
label values fp_group lbl_fp_group

tempfile denom_ccaa
save `denom_ccaa', replace

save "`out'\EPA_joven_FP_vs_noFP_CCAA_denom.dta", replace

export excel using "`out'\EPA_joven_FP_vs_noFP_CCAA_denom.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 4) CATEGORÍAS ACT1 / TACTIV Y CLASIFICACIÓN VERDE
********************************************************************************

clear
set obs 11

gen double act1 = _n - 1
replace act1 = 99 in 11

gen str130 act1_nombre = ""

replace act1_nombre = "Agricultura, ganadería, silvicultura y pesca" ///
    if act1 == 0

replace act1_nombre = "Alimentación, textil, cuero, madera y papel" ///
    if act1 == 1

replace act1_nombre = "Extractivas, refino, química, energía, agua y metalurgia" ///
    if act1 == 2

replace act1_nombre = "Maquinaria, equipo eléctrico y material de transporte" ///
    if act1 == 3

replace act1_nombre = "Construcción" ///
    if act1 == 4

replace act1_nombre = "Comercio, reparaciones y hostelería" ///
    if act1 == 5

replace act1_nombre = "Transporte, almacenamiento, información y comunicaciones" ///
    if act1 == 6

replace act1_nombre = "Finanzas, inmobiliarias, servicios profesionales y administrativos" ///
    if act1 == 7

replace act1_nombre = "Administración Pública, educación y sanidad" ///
    if act1 == 8

replace act1_nombre = "Otros servicios" ///
    if act1 == 9

replace act1_nombre = "No clasificado" ///
    if act1 == 99


*------------------------------------------------------
* Clasificación verde
*------------------------------------------------------

gen byte eje_verde_core = 0
replace eje_verde_core = 1 if inlist(act1, 2, 3, 4)

label define lbl_eje_verde_core ///
    0 "Resto de actividades" ///
    1 "Ramas vinculadas a transición verde", replace

label values eje_verde_core lbl_eje_verde_core


gen byte eje_verde_amplio = 0
replace eje_verde_amplio = 1 if inlist(act1, 0, 2, 3, 4, 6, 7)

label define lbl_eje_verde_amplio ///
    0 "Resto de actividades" ///
    1 "Ramas directa o indirectamente vinculadas a transición verde", replace

label values eje_verde_amplio lbl_eje_verde_amplio


gen byte bloque_verde = .
replace bloque_verde = 1 if act1 == 2
replace bloque_verde = 2 if act1 == 3
replace bloque_verde = 3 if act1 == 4
replace bloque_verde = 4 if act1 == 0
replace bloque_verde = 5 if act1 == 6
replace bloque_verde = 6 if act1 == 7

label define lbl_bloque_verde ///
    1 "Energía, agua, residuos e industria básica" ///
    2 "Maquinaria, equipo eléctrico y transporte" ///
    3 "Construcción y rehabilitación" ///
    4 "Agrario, forestal y medio natural" ///
    5 "Transporte, logística e información" ///
    6 "Servicios profesionales y técnicos", replace

label values bloque_verde lbl_bloque_verde


tempfile act1_cats
save `act1_cats', replace


********************************************************************************
* 5) PANEL COMPLETO CCAA × TRIMESTRE × FP/no FP × ACT1
********************************************************************************

use `acum_act1', clear

tempfile act1_raw
save `act1_raw', replace

use `denom_ccaa', clear

keep CCAA ccaa_nombre anio trim periodo tq fp_group
duplicates drop

gen byte _join_key = 1

tempfile base_panel
save `base_panel', replace

use `act1_cats', clear

gen byte _join_key = 1

tempfile act1_cats_join
save `act1_cats_join', replace

use `base_panel', clear

joinby _join_key using `act1_cats_join'

drop _join_key

merge 1:1 CCAA anio trim periodo tq fp_group act1 using `act1_raw', nogen

replace ocupados_act1 = 0 if missing(ocupados_act1)

merge m:1 CCAA anio trim periodo tq fp_group using `denom_ccaa', ///
    nogen keep(match)

gen double tasa_act1_activos = 100 * ocupados_act1 / activos ///
    if activos > 0

gen double share_act1_ocupados = 100 * ocupados_act1 / ocupados_total ///
    if ocupados_total > 0

label var ocupados_act1 "Ocupados jóvenes en ACT1/TACTIV"
label var tasa_act1_activos "Ocupados ACT1 / activos jóvenes"
label var share_act1_ocupados "Ocupados ACT1 / ocupados jóvenes"

save "`out'\EPA_joven_FP_vs_noFP_CCAA_ACT1_long_completo.dta", replace

export excel using "`out'\EPA_joven_FP_vs_noFP_CCAA_ACT1_long_completo.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 6) BASE CCAA × FP/no FP DEL EJE VERDE CORE
*
* IMPORTANTE:
* Aquí NO sumamos denominadores repetidos por ACT1.
* Primero agregamos los ocupados verdes y mantenemos denominadores con mean,
* porque dentro de CCAA × trimestre × FP/no FP los denominadores son iguales
* para cada ACT1.
********************************************************************************

use "`out'\EPA_joven_FP_vs_noFP_CCAA_ACT1_long_completo.dta", clear

keep if eje_verde_core == 1

collapse ///
    (sum) ocupados_verde = ocupados_act1 ///
    (mean) total_jovenes ocupados_total parados inactivos activos, ///
    by(CCAA ccaa_nombre anio trim periodo tq fp_group)

label define lbl_fp_group 0 "No FP" 1 "FP", replace
label values fp_group lbl_fp_group

sort CCAA fp_group tq

egen panel_green_ccaa_fp = group(CCAA fp_group)

xtset panel_green_ccaa_fp tq

gen double ocup_verde_4q_sum = ocupados_verde + L1.ocupados_verde + L2.ocupados_verde + L3.ocupados_verde

gen double ocup_total_4q_sum = ocupados_total + L1.ocupados_total + L2.ocupados_total + L3.ocupados_total

gen double activos_4q_sum = activos + L1.activos + L2.activos + L3.activos

* Para niveles: promedio móvil 4T, no suma.
gen double ocup_verde_4q_avg = ocup_verde_4q_sum / 4

gen double ocup_verde_4q_avg_miles = ocup_verde_4q_avg / 1000

* Para shares/tasas: recomposición desde suma 4T de numerador y denominador.
gen double share_verde_4q = 100 * ocup_verde_4q_sum / ocup_total_4q_sum ///
    if ocup_total_4q_sum > 0

gen double tasa_verde_activos_4q = 100 * ocup_verde_4q_sum / activos_4q_sum ///
    if activos_4q_sum > 0

bysort CCAA fp_group: egen base_verde_2021 = mean(cond(anio == 2021, ocup_verde_4q_sum, .))

gen double indice_verde_2021_100 = 100 * ocup_verde_4q_sum / base_verde_2021 ///
    if base_verde_2021 > 0

label var ocup_verde_4q_avg_miles "Ocupados jóvenes en ramas verdes, miles, media móvil 4T"
label var share_verde_4q "Peso ramas verdes sobre ocupados jóvenes, media móvil 4T"
label var tasa_verde_activos_4q "Ocupados ramas verdes / activos jóvenes, media móvil 4T"
label var indice_verde_2021_100 "Índice ocupación ramas verdes, 2021=100, media móvil 4T"

save "`out'\EPA_joven_FP_vs_noFP_CCAA_eje_verde_core_4T.dta", replace

export excel using "`out'\EPA_joven_FP_vs_noFP_CCAA_eje_verde_core_4T.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 7) BASE NACIONAL FP VS NO FP DEL EJE VERDE CORE
********************************************************************************

use "`out'\EPA_joven_FP_vs_noFP_CCAA_eje_verde_core_4T.dta", clear

collapse ///
    (sum) ocupados_verde ocupados_total activos total_jovenes parados inactivos, ///
    by(anio trim periodo tq fp_group)

label define lbl_fp_group 0 "No FP" 1 "FP", replace
label values fp_group lbl_fp_group

sort fp_group tq

egen panel_green_fp = group(fp_group)

xtset panel_green_fp tq

gen double ocup_verde_4q_sum = ocupados_verde + L1.ocupados_verde + L2.ocupados_verde + L3.ocupados_verde

gen double ocup_total_4q_sum = ocupados_total + L1.ocupados_total + L2.ocupados_total + L3.ocupados_total

gen double activos_4q_sum = activos + L1.activos + L2.activos + L3.activos

gen double ocup_verde_4q_avg = ocup_verde_4q_sum / 4

gen double ocup_verde_4q_avg_miles = ocup_verde_4q_avg / 1000

gen double share_verde_4q = 100 * ocup_verde_4q_sum / ocup_total_4q_sum ///
    if ocup_total_4q_sum > 0

gen double tasa_verde_activos_4q = 100 * ocup_verde_4q_sum / activos_4q_sum ///
    if activos_4q_sum > 0

bysort fp_group: egen base_verde_2021 = mean(cond(anio == 2021, ocup_verde_4q_sum, .))

gen double indice_verde_2021_100 = 100 * ocup_verde_4q_sum / base_verde_2021 ///
    if base_verde_2021 > 0

save "`out'\EPA_joven_FP_vs_noFP_NACIONAL_eje_verde_core_4T.dta", replace

export excel using "`out'\EPA_joven_FP_vs_noFP_NACIONAL_eje_verde_core_4T.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 8) BASE NACIONAL TOTAL JÓVENES DEL EJE VERDE CORE
********************************************************************************

use "`out'\EPA_joven_FP_vs_noFP_CCAA_eje_verde_core_4T.dta", clear

collapse ///
    (sum) ocupados_verde ocupados_total activos total_jovenes parados inactivos, ///
    by(anio trim periodo tq)

sort tq

tsset tq

gen double ocup_verde_4q_sum = ocupados_verde + L1.ocupados_verde + L2.ocupados_verde + L3.ocupados_verde

gen double ocup_total_4q_sum = ocupados_total + L1.ocupados_total + L2.ocupados_total + L3.ocupados_total

gen double activos_4q_sum = activos + L1.activos + L2.activos + L3.activos

gen double ocup_verde_4q_avg = ocup_verde_4q_sum / 4

gen double ocup_verde_4q_avg_miles = ocup_verde_4q_avg / 1000

gen double share_verde_4q = 100 * ocup_verde_4q_sum / ocup_total_4q_sum ///
    if ocup_total_4q_sum > 0

gen double tasa_verde_activos_4q = 100 * ocup_verde_4q_sum / activos_4q_sum ///
    if activos_4q_sum > 0

egen base_verde_2021 = mean(cond(anio == 2021, ocup_verde_4q_sum, .))

gen double indice_verde_2021_100 = 100 * ocup_verde_4q_sum / base_verde_2021 ///
    if base_verde_2021 > 0

save "`out'\EPA_joven_NACIONAL_eje_verde_core_total_4T.dta", replace

export excel using "`out'\EPA_joven_NACIONAL_eje_verde_core_total_4T.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 9) COMPONENTES DEL EJE VERDE: ACT1 2, 3 Y 4
********************************************************************************

use "`out'\EPA_joven_FP_vs_noFP_CCAA_ACT1_long_completo.dta", clear

keep if inlist(act1, 2, 3, 4)

collapse ///
    (sum) ocupados_act1 ocupados_total activos total_jovenes parados inactivos, ///
    by(anio trim periodo tq act1 act1_nombre)

sort act1 tq

egen panel_green_act1 = group(act1)

xtset panel_green_act1 tq

gen double ocup_act1_4q_sum = ocupados_act1 + L1.ocupados_act1 + L2.ocupados_act1 + L3.ocupados_act1

gen double ocup_total_4q_sum = ocupados_total + L1.ocupados_total + L2.ocupados_total + L3.ocupados_total

gen double activos_4q_sum = activos + L1.activos + L2.activos + L3.activos

gen double ocup_act1_4q_avg = ocup_act1_4q_sum / 4

gen double ocup_act1_4q_avg_miles = ocup_act1_4q_avg / 1000

gen double share_act1_4q = 100 * ocup_act1_4q_sum / ocup_total_4q_sum ///
    if ocup_total_4q_sum > 0

bysort act1: egen base_act1_2021 = mean(cond(anio == 2021, ocup_act1_4q_sum, .))

gen double indice_act1_2021_100 = 100 * ocup_act1_4q_sum / base_act1_2021 ///
    if base_act1_2021 > 0

save "`out'\EPA_joven_NACIONAL_componentes_eje_verde_ACT1_4T.dta", replace

export excel using "`out'\EPA_joven_NACIONAL_componentes_eje_verde_ACT1_4T.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 10) GRÁFICO 1: VOLUMEN Y PESO NACIONAL DEL EJE VERDE CORE
********************************************************************************

use "`out'\EPA_joven_NACIONAL_eje_verde_core_total_4T.dta", clear

twoway ///
    (line ocup_verde_4q_avg_miles tq, lcolor(blue) lwidth(medthick) yaxis(1)) ///
    (line share_verde_4q tq, lcolor(green) lpattern(dash) lwidth(medthick) yaxis(2)), ///
    ylabel(, angle(0) grid axis(1)) ///
    ylabel(0(5)50, angle(0) axis(2)) ///
    xlabel(, angle(45)) ///
    xtitle("Trimestre") ///
    ytitle("Miles de ocupados jóvenes", axis(1)) ///
    ytitle("% sobre ocupados jóvenes", axis(2)) ///
    legend(order(1 "Ocupados en ramas verdes" 2 "Peso sobre empleo juvenil") pos(6) ring(0)) ///
    title("España: volumen y peso del eje verde en el empleo juvenil", size(medium)) ///
    subtitle("ACT1=2,3,4 | Jóvenes <25 | Media móvil 4T", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_verde1, replace)

graph export "`out'\grafico_nacional_eje_verde_volumen_y_peso_4T.png", ///
    width(2600) replace

graph save "`out'\grafico_nacional_eje_verde_volumen_y_peso_4T.gph", ///
    replace


********************************************************************************
* 11) GRÁFICO 2: ÍNDICE NACIONAL DEL EJE VERDE CORE
********************************************************************************

twoway ///
    (line indice_verde_2021_100 tq, lcolor(green) lwidth(medthick)), ///
    yline(100, lcolor(gs8) lpattern(dash)) ///
    ylabel(50(25)250, angle(0) grid) ///
    yscale(range(50 250)) ///
    xlabel(, angle(45)) ///
    xtitle("Trimestre") ///
    ytitle("Índice 2021 = 100") ///
    title("España: evolución relativa del empleo joven en ramas verdes", size(medium)) ///
    subtitle("ACT1=2,3,4 | Media móvil 4T", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_verde2, replace)

graph export "`out'\grafico_nacional_eje_verde_indice_2021_100_4T.png", ///
    width(2600) replace

graph save "`out'\grafico_nacional_eje_verde_indice_2021_100_4T.gph", ///
    replace


********************************************************************************
* 12) GRÁFICO 3: EJE VERDE FP VS NO FP - ÍNDICE
********************************************************************************

use "`out'\EPA_joven_FP_vs_noFP_NACIONAL_eje_verde_core_4T.dta", clear

twoway ///
    (line indice_verde_2021_100 tq if fp_group == 1, ///
        lcolor(red) lwidth(medthick)) ///
    (line indice_verde_2021_100 tq if fp_group == 0, ///
        lcolor(blue) lpattern(dash) lwidth(medthick)), ///
    legend(order(1 "FP" 2 "No FP") pos(6) ring(0)) ///
    yline(100, lcolor(gs8) lpattern(dash)) ///
    ylabel(50(25)250, angle(0) grid) ///
    yscale(range(50 250)) ///
    xlabel(, angle(45)) ///
    xtitle("Trimestre") ///
    ytitle("Índice 2021 = 100") ///
    title("España: empleo joven en ramas verdes, FP vs No FP", size(medium)) ///
    subtitle("ACT1=2,3,4 | Media móvil 4T", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_verde3, replace)

graph export "`out'\grafico_nacional_eje_verde_indice_FP_vs_NoFP_4T.png", ///
    width(2600) replace

graph save "`out'\grafico_nacional_eje_verde_indice_FP_vs_NoFP_4T.gph", ///
    replace


********************************************************************************
* 13) GRÁFICO 4: EJE VERDE FP VS NO FP - PESO SOBRE OCUPADOS
********************************************************************************

twoway ///
    (line share_verde_4q tq if fp_group == 1, ///
        lcolor(red) lwidth(medthick)) ///
    (line share_verde_4q tq if fp_group == 0, ///
        lcolor(blue) lpattern(dash) lwidth(medthick)), ///
    legend(order(1 "FP" 2 "No FP") pos(6) ring(0)) ///
    ylabel(0(5)50, angle(0) grid) ///
    yscale(range(0 50)) ///
    xlabel(, angle(45)) ///
    xtitle("Trimestre") ///
    ytitle("% de ocupados jóvenes del grupo") ///
    title("España: peso de ramas verdes en la ocupación juvenil", size(medium)) ///
    subtitle("ACT1=2,3,4 | FP vs No FP | Media móvil 4T", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_verde4, replace)

graph export "`out'\grafico_nacional_eje_verde_share_FP_vs_NoFP_4T.png", ///
    width(2600) replace

graph save "`out'\grafico_nacional_eje_verde_share_FP_vs_NoFP_4T.gph", ///
    replace


********************************************************************************
* 14) GRÁFICO 5: BRECHA FP - NO FP EN PESO DE RAMAS VERDES
********************************************************************************

preserve

    keep anio trim periodo tq fp_group share_verde_4q indice_verde_2021_100 ///
         ocup_verde_4q_avg_miles tasa_verde_activos_4q

    reshape wide share_verde_4q indice_verde_2021_100 ///
                 ocup_verde_4q_avg_miles tasa_verde_activos_4q, ///
                 i(anio trim periodo tq) j(fp_group)

    gen double gap_share_green_fp_nofp = share_verde_4q1 - share_verde_4q0

    gen double gap_indice_green_fp_nofp = indice_verde_2021_1001 - indice_verde_2021_1000

    save "`out'\EPA_joven_NACIONAL_eje_verde_brechas_FP_NoFP_4T.dta", replace

    export excel using "`out'\EPA_joven_NACIONAL_eje_verde_brechas_FP_NoFP_4T.xlsx", ///
        replace firstrow(variables)

    twoway ///
        (line gap_share_green_fp_nofp tq, lcolor(black) lwidth(medthick)), ///
        yline(0, lcolor(gs8) lpattern(dash)) ///
        ylabel(-15(5)15, angle(0) grid) ///
        yscale(range(-15 15)) ///
        xlabel(, angle(45)) ///
        xtitle("Trimestre") ///
        ytitle("Puntos porcentuales") ///
        title("España: brecha FP - No FP en ramas verdes", size(medium)) ///
        subtitle("Peso sobre ocupados jóvenes | Media móvil 4T", size(small)) ///
        graphregion(color(white)) bgcolor(white) ///
        name(g_verde5, replace)

    graph export "`out'\grafico_nacional_eje_verde_brecha_share_FP_menos_NoFP_4T.png", ///
        width(2600) replace

    graph save "`out'\grafico_nacional_eje_verde_brecha_share_FP_menos_NoFP_4T.gph", ///
        replace

restore


********************************************************************************
* 15) GRÁFICO 6: COMPONENTES DEL EJE VERDE - ÍNDICE
********************************************************************************

use "`out'\EPA_joven_NACIONAL_componentes_eje_verde_ACT1_4T.dta", clear

twoway ///
    (line indice_act1_2021_100 tq, lwidth(medthick)), ///
    by(act1_nombre, cols(3) note("") ///
        title("España: evolución del empleo joven en componentes del eje verde", size(medsmall)) ///
        subtitle("ACT1=2,3,4 | Índice 2021=100 | Media móvil 4T", size(small))) ///
    yline(100, lcolor(gs8) lpattern(dash)) ///
    ylabel(50(25)250, angle(0) grid labsize(small)) ///
    yscale(range(50 250)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("Índice 2021 = 100", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_verde6, replace)

graph export "`out'\grafico_nacional_componentes_eje_verde_indice_4T.png", ///
    width(3000) replace

graph save "`out'\grafico_nacional_componentes_eje_verde_indice_4T.gph", ///
    replace


********************************************************************************
* 16) GRÁFICO 7: COMPONENTES DEL EJE VERDE - PESO SOBRE EMPLEO JUVENIL
********************************************************************************

twoway ///
    (line share_act1_4q tq, lwidth(medthick)), ///
    by(act1_nombre, cols(3) note("") ///
        title("España: peso de componentes del eje verde en el empleo juvenil", size(medsmall)) ///
        subtitle("ACT1=2,3,4 | Media móvil 4T", size(small))) ///
    ylabel(0(5)30, angle(0) grid labsize(small)) ///
    yscale(range(0 30)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("% de ocupados jóvenes", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_verde7, replace)

graph export "`out'\grafico_nacional_componentes_eje_verde_share_4T.png", ///
    width(3000) replace

graph save "`out'\grafico_nacional_componentes_eje_verde_share_4T.gph", ///
    replace


********************************************************************************
* 17) CCAA TOTAL JÓVENES: EJE VERDE CORE
********************************************************************************

use "`out'\EPA_joven_FP_vs_noFP_CCAA_eje_verde_core_4T.dta", clear

collapse ///
    (sum) ocupados_verde ocupados_total activos total_jovenes parados inactivos, ///
    by(CCAA ccaa_nombre anio trim periodo tq)

sort CCAA tq

egen panel_green_ccaa = group(CCAA)

xtset panel_green_ccaa tq

gen double ocup_verde_4q_sum = ocupados_verde + L1.ocupados_verde + L2.ocupados_verde + L3.ocupados_verde

gen double ocup_total_4q_sum = ocupados_total + L1.ocupados_total + L2.ocupados_total + L3.ocupados_total

gen double activos_4q_sum = activos + L1.activos + L2.activos + L3.activos

gen double ocup_verde_4q_avg = ocup_verde_4q_sum / 4

gen double ocup_verde_4q_avg_miles = ocup_verde_4q_avg / 1000

gen double share_verde_4q = 100 * ocup_verde_4q_sum / ocup_total_4q_sum ///
    if ocup_total_4q_sum > 0

bysort CCAA: egen base_verde_2021 = mean(cond(anio == 2021, ocup_verde_4q_sum, .))

gen double indice_verde_2021_100 = 100 * ocup_verde_4q_sum / base_verde_2021 ///
    if base_verde_2021 > 0

save "`out'\EPA_joven_CCAA_eje_verde_core_total_4T.dta", replace

export excel using "`out'\EPA_joven_CCAA_eje_verde_core_total_4T.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 18) GRÁFICO 8: PESO DEL EJE VERDE POR CCAA
********************************************************************************

twoway ///
    (line share_verde_4q tq, lcolor(green) lwidth(medthick)), ///
    by(ccaa_nombre, cols(4) note("") ///
        title("Peso de ramas verdes en el empleo juvenil por CCAA", size(medsmall)) ///
        subtitle("ACT1=2,3,4 | Total jóvenes <25 | Media móvil 4T", size(small))) ///
    ylabel(0(5)50, angle(0) grid labsize(small)) ///
    yscale(range(0 50)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("% de ocupados jóvenes", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_verde8, replace)

graph export "`out'\grafico_CCAA_eje_verde_share_total_4T.png", ///
    width(3400) replace

graph save "`out'\grafico_CCAA_eje_verde_share_total_4T.gph", ///
    replace


********************************************************************************
* 19) GRÁFICO 9: ÍNDICE DEL EJE VERDE POR CCAA
********************************************************************************

twoway ///
    (line indice_verde_2021_100 tq, lcolor(blue) lwidth(medthick)), ///
    by(ccaa_nombre, cols(4) note("") ///
        title("Evolución relativa de ramas verdes por CCAA", size(medsmall)) ///
        subtitle("ACT1=2,3,4 | Índice 2021=100 | Media móvil 4T", size(small))) ///
    yline(100, lcolor(gs8) lpattern(dash)) ///
    ylabel(50(25)250, angle(0) grid labsize(small)) ///
    yscale(range(50 250)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("Índice 2021 = 100", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_verde9, replace)

graph export "`out'\grafico_CCAA_eje_verde_indice_total_4T.png", ///
    width(3400) replace

graph save "`out'\grafico_CCAA_eje_verde_indice_total_4T.gph", ///
    replace


********************************************************************************
* 20) RANKING CCAA: PESO DEL EJE VERDE EN ÚLTIMO TRIMESTRE
********************************************************************************

preserve

    keep if !missing(share_verde_4q)

    quietly summarize tq
    local last = r(max)

    keep if tq == `last'

    graph hbar share_verde_4q, ///
        over(ccaa_nombre, sort(1) descending label(labsize(vsmall))) ///
        blabel(bar, format(%4.1f)) ///
        ytitle("% de ocupados jóvenes") ///
        title("Peso de ramas verdes en el empleo juvenil", size(medium)) ///
        subtitle("Por CCAA | Último trimestre disponible | Media móvil 4T", size(small)) ///
        graphregion(color(white)) bgcolor(white) ///
        name(g_verde10, replace)

    graph export "`out'\grafico_ranking_CCAA_eje_verde_share_ultimo_4T.png", ///
        width(2800) replace

    graph save "`out'\grafico_ranking_CCAA_eje_verde_share_ultimo_4T.gph", ///
        replace

restore


********************************************************************************
* 21) CAMBIO CCAA: PESO DEL EJE VERDE DESDE 2021
********************************************************************************

use "`out'\EPA_joven_CCAA_eje_verde_core_total_4T.dta", clear

keep if !missing(share_verde_4q)

quietly summarize tq
local last = r(max)

bysort CCAA: egen share_verde_base_2021 = mean(cond(anio == 2021, share_verde_4q, .))

bysort CCAA: egen share_verde_ultimo = max(cond(tq == `last', share_verde_4q, .))

gen double cambio_share_verde_pp = share_verde_ultimo - share_verde_base_2021

keep CCAA ccaa_nombre share_verde_base_2021 share_verde_ultimo cambio_share_verde_pp

duplicates drop

gsort -cambio_share_verde_pp

save "`out'\tabla_CCAA_cambio_peso_eje_verde_2021_ultimo.dta", replace

export excel using "`out'\tabla_CCAA_cambio_peso_eje_verde_2021_ultimo.xlsx", ///
    replace firstrow(variables)

graph hbar cambio_share_verde_pp, ///
    over(ccaa_nombre, sort(1) descending label(labsize(vsmall))) ///
    yline(0, lcolor(gs8) lpattern(dash)) ///
    blabel(bar, format(%4.1f)) ///
    ytitle("Cambio en puntos porcentuales") ///
    title("Cambio en el peso de ramas verdes", size(medium)) ///
    subtitle("Por CCAA | Desde 2021 hasta último trimestre disponible", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_verde11, replace)

graph export "`out'\grafico_CCAA_cambio_peso_eje_verde_2021_ultimo.png", ///
    width(2800) replace

graph save "`out'\grafico_CCAA_cambio_peso_eje_verde_2021_ultimo.gph", ///
    replace

********************************************************************************
* 22) CCAA FP VS NO FP: ÍNDICE DEL EJE VERDE
********************************************************************************

use "`out'\EPA_joven_FP_vs_noFP_CCAA_eje_verde_core_4T.dta", clear

twoway ///
    (line indice_verde_2021_100 tq if fp_group == 1, ///
        lcolor(red) lwidth(medthick)) ///
    (line indice_verde_2021_100 tq if fp_group == 0, ///
        lcolor(blue) lpattern(dash) lwidth(medthick)), ///
    by(ccaa_nombre, cols(4) note("") ///
        title("Evolución relativa del eje verde por CCAA", size(medsmall)) ///
        subtitle("ACT1=2,3,4 | FP vs No FP | Índice 2021=100 | Media móvil 4T", size(small))) ///
    legend(order(1 "FP" 2 "No FP") pos(6) ring(0)) ///
    yline(100, lcolor(gs8) lpattern(dash)) ///
    ylabel(50(25)250, angle(0) grid labsize(small)) ///
    yscale(range(50 250)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("Índice 2021 = 100", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_verde12, replace)

graph export "`out'\grafico_CCAA_eje_verde_indice_FP_vs_NoFP_4T.png", ///
    width(3400) replace

graph save "`out'\grafico_CCAA_eje_verde_indice_FP_vs_NoFP_4T.gph", ///
    replace


********************************************************************************
* 23) CCAA FP VS NO FP: PESO DEL EJE VERDE
********************************************************************************

twoway ///
    (line share_verde_4q tq if fp_group == 1, ///
        lcolor(red) lwidth(medthick)) ///
    (line share_verde_4q tq if fp_group == 0, ///
        lcolor(blue) lpattern(dash) lwidth(medthick)), ///
    by(ccaa_nombre, cols(4) note("") ///
        title("Peso del eje verde en la ocupación juvenil por CCAA", size(medsmall)) ///
        subtitle("ACT1=2,3,4 | FP vs No FP | Media móvil 4T", size(small))) ///
    legend(order(1 "FP" 2 "No FP") pos(6) ring(0)) ///
    ylabel(0(5)50, angle(0) grid labsize(small)) ///
    yscale(range(0 50)) ///
    xlabel(, angle(45) labsize(vsmall)) ///
    xtitle("Trimestre", size(small)) ///
    ytitle("% de ocupados jóvenes del grupo", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_verde13, replace)

graph export "`out'\grafico_CCAA_eje_verde_share_FP_vs_NoFP_4T.png", ///
    width(3400) replace

graph save "`out'\grafico_CCAA_eje_verde_share_FP_vs_NoFP_4T.gph", ///
    replace


********************************************************************************
* 24) CCAA: BRECHA FP - NO FP EN PESO DEL EJE VERDE
********************************************************************************

preserve

    keep CCAA ccaa_nombre anio trim periodo tq fp_group ///
         share_verde_4q indice_verde_2021_100 ///
         ocup_verde_4q_avg_miles tasa_verde_activos_4q

    reshape wide share_verde_4q indice_verde_2021_100 ///
                 ocup_verde_4q_avg_miles tasa_verde_activos_4q, ///
                 i(CCAA ccaa_nombre anio trim periodo tq) j(fp_group)

    gen double gap_share_green_fp_nofp = share_verde_4q1 - share_verde_4q0

    gen double gap_indice_green_fp_nofp = indice_verde_2021_1001 - indice_verde_2021_1000

    save "`out'\EPA_joven_CCAA_eje_verde_brechas_FP_NoFP_4T.dta", replace

    export excel using "`out'\EPA_joven_CCAA_eje_verde_brechas_FP_NoFP_4T.xlsx", ///
        replace firstrow(variables)

    twoway ///
        (line gap_share_green_fp_nofp tq, lcolor(black) lwidth(medthick)), ///
        by(ccaa_nombre, cols(4) note("") ///
            title("Brecha FP - No FP en ramas verdes por CCAA", size(medsmall)) ///
            subtitle("Peso sobre ocupados jóvenes | Media móvil 4T", size(small))) ///
        yline(0, lcolor(gs8) lpattern(dash)) ///
        ylabel(-15(5)15, angle(0) grid labsize(small)) ///
        yscale(range(-15 15)) ///
        xlabel(, angle(45) labsize(vsmall)) ///
        xtitle("Trimestre", size(small)) ///
        ytitle("Puntos porcentuales", size(small)) ///
        graphregion(color(white)) bgcolor(white) ///
        name(g_verde14, replace)

    graph export "`out'\grafico_CCAA_eje_verde_brecha_share_FP_menos_NoFP_4T.png", ///
        width(3400) replace

    graph save "`out'\grafico_CCAA_eje_verde_brecha_share_FP_menos_NoFP_4T.gph", ///
        replace

restore


********************************************************************************
* 25) TABLA FINAL NACIONAL: CAMBIO DESDE 2021
********************************************************************************

use "`out'\EPA_joven_NACIONAL_eje_verde_core_total_4T.dta", clear

quietly summarize tq
local last = r(max)

egen share_verde_base_2021 = mean(cond(anio == 2021, share_verde_4q, .))

egen share_verde_ultimo = max(cond(tq == `last', share_verde_4q, .))

egen indice_verde_ultimo = max(cond(tq == `last', indice_verde_2021_100, .))

egen ocup_verde_ultimo_miles = max(cond(tq == `last', ocup_verde_4q_avg_miles, .))

gen double cambio_share_verde_pp = share_verde_ultimo - share_verde_base_2021

keep share_verde_base_2021 share_verde_ultimo cambio_share_verde_pp ///
     indice_verde_ultimo ocup_verde_ultimo_miles

duplicates drop

save "`out'\tabla_nacional_resumen_eje_verde_2021_ultimo.dta", replace

export excel using "`out'\tabla_nacional_resumen_eje_verde_2021_ultimo.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 26) MENSAJE FINAL
********************************************************************************

di as result "============================================================"
di as result "Proceso completado correctamente."
di as result ""
di as result "Archivo independiente del EJE VERDE creado."
di as result ""
di as result "Definición principal:"
di as result "Eje verde CORE = ACT1 2, 3 y 4"
di as result "2 = Energía, agua, residuos, química, metalurgia"
di as result "3 = Maquinaria, equipo eléctrico y material de transporte"
di as result "4 = Construcción"
di as result ""
di as result "Nota metodológica:"
di as result "Los niveles en miles usan promedio móvil 4T, no suma 4T."
di as result "Los shares y tasas se recomponen sumando numerador y denominador 4T."
di as result ""
di as result "Carpeta de salida:"
di as result "`out'"
di as result "============================================================"


/********************************************************************************
* SECTION 8: Do_File_conexion_scatters.do
********************************************************************************/

clear all
if "${PROJECT_ROOT}" == "" {
    global PROJECT_ROOT "."
}
set more off

********************************************************************************
* CRUCE PRTR FP VERDE × EPA EMPLEO JOVEN VERDE CON DESFASE t+2
*
* Lógica:
*   Plazas PRTR verdes creadas en 2021 -> cambio EPA entre 2021 y 2023
*   Plazas PRTR verdes creadas en 2022 -> cambio EPA entre 2022 y 2024
*   Plazas PRTR verdes creadas en 2023 -> cambio EPA entre 2023 y 2025
*
* Lectura descriptiva, no causal.
********************************************************************************


********************************************************************************
* 0) RUTAS Y PARÁMETROS
********************************************************************************

local lag 2

local out_green "${PROJECT_ROOT}/98.IMPACTO DEL PLAN/1. FP/epa/resultados_EJE_VERDE_ACT1"

local out_lag "${PROJECT_ROOT}/98.IMPACTO DEL PLAN/1. FP/epa/resultados_CRUCE_PRTR_EPA_EJE_VERDE_LAG`lag'"
capture mkdir "`out_lag'"

local fp_excel "${PROJECT_ROOT}/98.IMPACTO DEL PLAN/1. FP/Base_datos_final.xlsx"

local epa_green_file "`out_green'/EPA_joven_CCAA_eje_verde_core_total_4T.dta"


********************************************************************************
* 1) COMPROBAR QUE EXISTE LA BASE EPA VERDE
********************************************************************************

capture confirm file "`epa_green_file'"

if _rc {
    di as error "No encuentro la base EPA verde:"
    di as error "`epa_green_file'"
    di as error "Ejecuta antes el archivo independiente de EJE VERDE."
    exit 601
}


********************************************************************************
* 2) PREPARAR EPA ANUAL POR CCAA
*
* Partimos de la base EPA trimestral ya creada en el análisis verde.
* Convertimos a dato anual por CCAA promediando los trimestres disponibles.
********************************************************************************

use "`epa_green_file'", clear

* Quitar CCAA sin nombre si las hubiera
drop if missing(ccaa_nombre) | ccaa_nombre == ""

* Quitar Ceuta y Melilla para evitar ruido en el análisis territorial principal
drop if inlist(CCAA, 18, 19, 51, 52)

* Mantener solo observaciones con media móvil disponible
keep if !missing(share_verde_4q)

* Evitar 2026 porque solo tienes 2026T1 y no es comparable como año anual
drop if anio > 2025

* Crear clave de cruce
capture drop ccaa_merge
gen str80 ccaa_merge = upper(strtrim(ccaa_nombre))

replace ccaa_merge = subinstr(ccaa_merge, "Á", "A", .)
replace ccaa_merge = subinstr(ccaa_merge, "É", "E", .)
replace ccaa_merge = subinstr(ccaa_merge, "Í", "I", .)
replace ccaa_merge = subinstr(ccaa_merge, "Ó", "O", .)
replace ccaa_merge = subinstr(ccaa_merge, "Ú", "U", .)
replace ccaa_merge = subinstr(ccaa_merge, "Ü", "U", .)
replace ccaa_merge = subinstr(ccaa_merge, "Ñ", "N", .)
replace ccaa_merge = subinstr(ccaa_merge, ",", "", .)
replace ccaa_merge = subinstr(ccaa_merge, "-", " ", .)
replace ccaa_merge = itrim(ccaa_merge)

* Variable auxiliar para contar trimestres usados
gen byte n_obs = 1

* Si existe ocup_verde_4q_avg_miles, usamos esa variable de nivel.
* Si no existiera, el código se detiene porque es necesaria para el cruce.
capture confirm variable ocup_verde_4q_avg_miles
if _rc {
    di as error "No encuentro ocup_verde_4q_avg_miles en la base EPA verde."
    di as error "Revisa que el archivo independiente de EJE VERDE haya generado esa variable."
    exit 111
}

collapse ///
    (mean) share_verde_anual = share_verde_4q ///
           ocup_verde_miles_anual = ocup_verde_4q_avg_miles ///
           indice_verde_anual = indice_verde_2021_100 ///
           total_jovenes_anual = total_jovenes ///
    (count) n_trim_epa = n_obs, ///
    by(CCAA ccaa_nombre ccaa_merge anio)

label var share_verde_anual "Peso anual del empleo joven verde EPA"
label var ocup_verde_miles_anual "Ocupados jóvenes verdes EPA, miles"
label var indice_verde_anual "Índice empleo joven verde EPA, 2021=100"
label var total_jovenes_anual "Jóvenes <25 EPA, estimación anual"
label var n_trim_epa "Número de trimestres EPA usados"

save "`out_lag'/EPA_CCAA_eje_verde_anual_4T.dta", replace

export excel using "`out_lag'/EPA_CCAA_eje_verde_anual_4T.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 3) CREAR BASE EPA EN t
*
* Esta base contiene el nivel de empleo verde en el mismo año en que se crean
* las plazas PRTR.
********************************************************************************

use "`out_lag'/EPA_CCAA_eje_verde_anual_4T.dta", clear

rename anio anio_prtr

rename share_verde_anual share_verde_t
rename ocup_verde_miles_anual ocup_verde_miles_t
rename indice_verde_anual indice_verde_t
rename total_jovenes_anual total_jovenes_t
rename n_trim_epa n_trim_epa_t

keep ccaa_merge anio_prtr ///
     share_verde_t ocup_verde_miles_t indice_verde_t total_jovenes_t n_trim_epa_t

tempfile epa_t
save `epa_t', replace


********************************************************************************
* 4) CREAR BASE EPA EN t+lag
*
* Si lag = 2:
* EPA 2023 se asigna a PRTR 2021
* EPA 2024 se asigna a PRTR 2022
* EPA 2025 se asigna a PRTR 2023
********************************************************************************

use "`out_lag'/EPA_CCAA_eje_verde_anual_4T.dta", clear

gen anio_epa_resultado = anio
gen anio_prtr = anio_epa_resultado - `lag'

rename share_verde_anual share_verde_tlag
rename ocup_verde_miles_anual ocup_verde_miles_tlag
rename indice_verde_anual indice_verde_tlag
rename total_jovenes_anual total_jovenes_tlag
rename n_trim_epa n_trim_epa_tlag

keep ccaa_merge anio_prtr anio_epa_resultado ///
     share_verde_tlag ocup_verde_miles_tlag indice_verde_tlag ///
     total_jovenes_tlag n_trim_epa_tlag

tempfile epa_tlag
save `epa_tlag', replace


********************************************************************************
* 5) IMPORTAR MICRODATOS PRTR
********************************************************************************

import excel using "`fp_excel'", sheet("Microdatos") firstrow clear


********************************************************************************
* 5.1 LOCALIZAR VARIABLES PRINCIPALES
********************************************************************************

capture confirm variable CCAA_LIMPIA
if _rc {
    di as error "No existe CCAA_LIMPIA en la hoja Microdatos."
    exit 111
}

* Variable de plazas
local plazasvar ""

capture confirm variable PLAZASCREADAS
if !_rc {
    local plazasvar "PLAZASCREADAS"
}
else {
    ds *PLAZAS*
    local plazasvar : word 1 of `r(varlist)'
}

if "`plazasvar'" == "" {
    di as error "No encuentro variable de plazas."
    exit 111
}

if "`plazasvar'" != "PLAZASCREADAS" {
    rename `plazasvar' PLAZASCREADAS
}

* Variable de eje verde
local ejevar ""

capture confirm variable EJE_VERDE
if !_rc {
    local ejevar "EJE_VERDE"
}
else {
    capture confirm variable EJEVERDE
    if !_rc {
        local ejevar "EJEVERDE"
    }
    else {
        ds *VERDE*
        local ejevar : word 1 of `r(varlist)'
    }
}

if "`ejevar'" == "" {
    di as error "No encuentro variable EJE_VERDE / EJEVERDE."
    exit 111
}

if "`ejevar'" != "EJE_VERDE" {
    rename `ejevar' EJE_VERDE
}

* Variable de año PRTR
local yearvar ""

foreach cand in ACMAño2020202120222023 ACMAno2020202120222023 ACMANIO ANIO anio AÑO año {
    capture confirm variable `cand'
    if !_rc & "`yearvar'" == "" {
        local yearvar "`cand'"
    }
}

if "`yearvar'" == "" {
    ds *2020*
    local yearvar : word 1 of `r(varlist)'
}

if "`yearvar'" == "" {
    di as error "No encuentro variable de año PRTR."
    di as error "Busca la variable que contiene 2020/2021/2022/2023 y añádela manualmente."
    exit 111
}

rename `yearvar' anio_prtr_raw


********************************************************************************
* 5.2 ASEGURAR NUMÉRICOS
********************************************************************************

capture confirm numeric variable PLAZASCREADAS
if _rc {
    destring PLAZASCREADAS, replace ignore(" .") dpcomma
}

capture confirm numeric variable EJE_VERDE
if _rc {
    destring EJE_VERDE, replace ignore(" .") dpcomma
}

replace PLAZASCREADAS = 0 if missing(PLAZASCREADAS)
replace EJE_VERDE = 0 if missing(EJE_VERDE)


********************************************************************************
* 5.3 LIMPIAR AÑO PRTR
********************************************************************************

capture confirm numeric variable anio_prtr_raw

if !_rc {
    gen int anio_prtr = floor(anio_prtr_raw)
}
else {
    capture confirm string variable anio_prtr_raw

    if !_rc {
        gen str80 anio_prtr_str = strtrim(anio_prtr_raw)
    }
    else {
        tostring anio_prtr_raw, gen(anio_prtr_str) force
    }

    gen int anio_prtr = .
    replace anio_prtr = real(regexs(0)) if regexm(anio_prtr_str, "20[0-9][0-9]")
}

drop if missing(anio_prtr)

* Con EPA 2021-2025 y lag=2:
* PRTR 2021 -> EPA 2023
* PRTR 2022 -> EPA 2024
* PRTR 2023 -> EPA 2025
keep if inrange(anio_prtr, 2021, 2025 - `lag')


********************************************************************************
* 5.4 CREAR CLAVE DE CCAA
********************************************************************************

gen str80 ccaa_final = strtrim(CCAA_LIMPIA)

gen str80 ccaa_merge = upper(strtrim(CCAA_LIMPIA))

replace ccaa_merge = subinstr(ccaa_merge, "Á", "A", .)
replace ccaa_merge = subinstr(ccaa_merge, "É", "E", .)
replace ccaa_merge = subinstr(ccaa_merge, "Í", "I", .)
replace ccaa_merge = subinstr(ccaa_merge, "Ó", "O", .)
replace ccaa_merge = subinstr(ccaa_merge, "Ú", "U", .)
replace ccaa_merge = subinstr(ccaa_merge, "Ü", "U", .)
replace ccaa_merge = subinstr(ccaa_merge, "Ñ", "N", .)
replace ccaa_merge = subinstr(ccaa_merge, ",", "", .)
replace ccaa_merge = subinstr(ccaa_merge, "-", " ", .)
replace ccaa_merge = itrim(ccaa_merge)

drop if missing(ccaa_merge) | ccaa_merge == ""

drop if inlist(ccaa_merge, "CEUTA", "MELILLA")


********************************************************************************
* 5.5 AGREGAR PLAZAS PRTR POR CCAA × AÑO
********************************************************************************

gen double plazas_verdes_aux = PLAZASCREADAS if EJE_VERDE == 1
replace plazas_verdes_aux = 0 if missing(plazas_verdes_aux)

collapse ///
    (sum) plazas_totales_prtr = PLAZASCREADAS ///
          plazas_verdes_prtr = plazas_verdes_aux, ///
    by(ccaa_merge ccaa_final anio_prtr)

gen double peso_plazas_verdes_prtr = 100 * plazas_verdes_prtr / plazas_totales_prtr ///
    if plazas_totales_prtr > 0

label var plazas_totales_prtr "Plazas PRTR totales creadas"
label var plazas_verdes_prtr "Plazas PRTR verdes creadas"
label var peso_plazas_verdes_prtr "Peso de plazas verdes sobre plazas PRTR totales"

save "`out_lag'/PRTR_plazas_verdes_CCAA_anio.dta", replace

export excel using "`out_lag'/PRTR_plazas_verdes_CCAA_anio.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 6) CRUCE PRTR t × EPA t × EPA t+lag
********************************************************************************

use "`out_lag'/PRTR_plazas_verdes_CCAA_anio.dta", clear

merge m:1 ccaa_merge anio_prtr using `epa_t', gen(_merge_epa_t)

keep if _merge_epa_t == 3
drop _merge_epa_t

merge m:1 ccaa_merge anio_prtr using `epa_tlag', gen(_merge_epa_tlag)

keep if _merge_epa_tlag == 3
drop _merge_epa_tlag

gen int anio_epa_base = anio_prtr

gen double cambio_share_verde_t_tlag_pp = share_verde_tlag - share_verde_t

gen double cambio_ocup_verde_t_tlag_miles = ocup_verde_miles_tlag - ocup_verde_miles_t

gen double indice_ocup_verde_t_tlag = 100 * ocup_verde_miles_tlag / ocup_verde_miles_t ///
    if ocup_verde_miles_t > 0

gen double plazas_verdes_por_1000_jovenes_t = 1000 * plazas_verdes_prtr / total_jovenes_t ///
    if total_jovenes_t > 0

gen str20 ventana = string(anio_prtr) + "->" + string(anio_epa_resultado)

label var cambio_share_verde_t_tlag_pp ///
    "Cambio en peso del empleo joven verde entre t y t+lag, pp"

label var cambio_ocup_verde_t_tlag_miles ///
    "Cambio en ocupados jóvenes verdes entre t y t+lag, miles"

label var indice_ocup_verde_t_tlag ///
    "Índice ocupados jóvenes verdes t+lag, t=100"

label var plazas_verdes_por_1000_jovenes_t ///
    "Plazas verdes PRTR por cada 1.000 jóvenes <25 en t"

save "`out_lag'/PANEL_PRTR_EPA_VERDE_CCAA_ANIO_LAG`lag'.dta", replace

export excel using "`out_lag'/PANEL_PRTR_EPA_VERDE_CCAA_ANIO_LAG`lag'.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 7) BASE CCAA AGREGADA PARA LECTURA DE VENTANA COMPLETA
********************************************************************************

use "`out_lag'/PANEL_PRTR_EPA_VERDE_CCAA_ANIO_LAG`lag'.dta", clear

bysort ccaa_merge: egen anio_prtr_min = min(anio_prtr)
bysort ccaa_merge: egen anio_prtr_max = max(anio_prtr)

bysort ccaa_merge: egen anio_epa_base_window = min(anio_epa_base)
bysort ccaa_merge: egen anio_epa_final_window = max(anio_epa_resultado)

bysort ccaa_merge: egen share_verde_base_window = mean(cond(anio_prtr == anio_prtr_min, share_verde_t, .))
bysort ccaa_merge: egen share_verde_final_window = mean(cond(anio_prtr == anio_prtr_max, share_verde_tlag, .))

bysort ccaa_merge: egen ocup_verde_base_window_miles = mean(cond(anio_prtr == anio_prtr_min, ocup_verde_miles_t, .))
bysort ccaa_merge: egen ocup_verde_final_window_miles = mean(cond(anio_prtr == anio_prtr_max, ocup_verde_miles_tlag, .))

bysort ccaa_merge: egen total_jovenes_base_window = mean(cond(anio_prtr == anio_prtr_min, total_jovenes_t, .))

collapse ///
    (sum) plazas_totales_prtr_lag = plazas_totales_prtr ///
          plazas_verdes_prtr_lag = plazas_verdes_prtr ///
    (mean) anio_prtr_min anio_prtr_max ///
           anio_epa_base_window anio_epa_final_window ///
           share_verde_base_window share_verde_final_window ///
           ocup_verde_base_window_miles ocup_verde_final_window_miles ///
           total_jovenes_base_window, ///
    by(ccaa_merge ccaa_final)

gen double peso_plazas_verdes_prtr_lag = 100 * plazas_verdes_prtr_lag / plazas_totales_prtr_lag ///
    if plazas_totales_prtr_lag > 0

gen double plz_verde_1000j_lag = 1000 * plazas_verdes_prtr_lag / total_jovenes_base_window ///
    if total_jovenes_base_window > 0

gen double cambio_share_verde_lag_pp = share_verde_final_window - share_verde_base_window

gen double cambio_ocup_verde_lag_miles = ocup_verde_final_window_miles - ocup_verde_base_window_miles

gen double indice_ocup_verde_lag = 100 * ocup_verde_final_window_miles / ocup_verde_base_window_miles ///
    if ocup_verde_base_window_miles > 0

gen str20 ventana_total = string(anio_epa_base_window) + "->" + string(anio_epa_final_window)

label var plazas_verdes_prtr_lag "Plazas PRTR verdes acumuladas"
label var peso_plazas_verdes_prtr_lag "% plazas PRTR verdes acumuladas"
label var plz_verde_1000j_lag "Plazas verdes acumuladas por 1.000 jóvenes"
label var cambio_share_verde_lag_pp "Cambio en peso empleo joven verde EPA, pp"
label var cambio_ocup_verde_lag_miles "Cambio en ocupados jóvenes verdes EPA, miles"
label var indice_ocup_verde_lag "Índice empleo joven verde EPA, base t=100"

save "`out_lag'/CRUCE_CCAA_PRTR_EPA_VERDE_LAG`lag'_RESUMEN.dta", replace

export excel using "`out_lag'/CRUCE_CCAA_PRTR_EPA_VERDE_LAG`lag'_RESUMEN.xlsx", ///
    replace firstrow(variables)


********************************************************************************
* 8) ETIQUETAS CORTAS PARA GRÁFICOS
********************************************************************************

use "`out_lag'/CRUCE_CCAA_PRTR_EPA_VERDE_LAG`lag'_RESUMEN.dta", clear

gen str35 ccaa_label = ccaa_final

replace ccaa_label = "Madrid"             if ccaa_final == "Madrid, Comunidad de"
replace ccaa_label = "C. Valenciana"      if ccaa_final == "Comunitat Valenciana"
replace ccaa_label = "Navarra"            if ccaa_final == "Navarra, Comunidad Foral de"
replace ccaa_label = "Murcia"             if ccaa_final == "Murcia, Región de"
replace ccaa_label = "Asturias"           if ccaa_final == "Asturias, Principado de"
replace ccaa_label = "Baleares"           if ccaa_final == "Balears, Illes"
replace ccaa_label = "Castilla-La Mancha" if ccaa_final == "Castilla - La Mancha"
replace ccaa_label = "La Rioja"           if ccaa_final == "Rioja, La"


********************************************************************************
* 9) MEDIANAS PARA CUADRANTES
********************************************************************************

summ peso_plazas_verdes_prtr_lag, detail
local med_peso_prtr = r(p50)

summ plazas_verdes_prtr_lag, detail
local med_plazas_prtr = r(p50)

summ plz_verde_1000j_lag, detail
local med_intensidad_prtr = r(p50)


********************************************************************************
* 10) SCATTER 1 PRINCIPAL: NÚMERO DE PLAZAS VERDES VS CAMBIO ABSOLUTO EPA
*
* Pregunta principal:
* Donde se crean más plazas verdes de FP, ¿aumenta más el número de jóvenes
* ocupados en ramas verdes dos años después?
********************************************************************************

twoway ///
    (scatter cambio_ocup_verde_lag_miles plazas_verdes_prtr_lag, ///
        mlabel(ccaa_label) mlabsize(vsmall) mlabposition(12) ///
        msymbol(circle) msize(medium)) ///
    (lfit cambio_ocup_verde_lag_miles plazas_verdes_prtr_lag, ///
        lcolor(maroon) lwidth(medthick)), ///
    xline(`med_plazas_prtr', lcolor(gs10) lpattern(dash)) ///
    yline(0, lcolor(gs8) lpattern(dash)) ///
    xtitle("Plazas PRTR verdes creadas") ///
    ytitle("Cambio en ocupados jóvenes verdes EPA, miles") ///
    title("Plazas verdes creadas y empleo joven verde después", size(medium)) ///
    subtitle("CCAA | Plazas PRTR acumuladas y cambio EPA con desfase t+`lag' | Lectura descriptiva", size(small)) ///
    legend(order(1 "CCAA" 2 "Tendencia lineal") pos(6) ring(0)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_lag_1, replace)

graph export "`out_lag'/scatter_LAG`lag'_plazas_verdes_vs_cambio_ocupados_EPA_verde.png", ///
    width(3000) replace

graph save "`out_lag'/scatter_LAG`lag'_plazas_verdes_vs_cambio_ocupados_EPA_verde.gph", ///
    replace


********************************************************************************
* 11) SCATTER 2: NÚMERO DE PLAZAS VERDES VS CAMBIO EN PESO EPA
*
* Complementa el gráfico principal: mira composición, no volumen.
********************************************************************************

twoway ///
    (scatter cambio_share_verde_lag_pp plazas_verdes_prtr_lag, ///
        mlabel(ccaa_label) mlabsize(vsmall) mlabposition(12) ///
        msymbol(circle) msize(medium)) ///
    (lfit cambio_share_verde_lag_pp plazas_verdes_prtr_lag, ///
        lcolor(maroon) lwidth(medthick)), ///
    xline(`med_plazas_prtr', lcolor(gs10) lpattern(dash)) ///
    yline(0, lcolor(gs8) lpattern(dash)) ///
    xtitle("Plazas PRTR verdes creadas") ///
    ytitle("Cambio en el peso del empleo joven verde, pp") ///
    title("Plazas verdes creadas y peso del empleo joven verde", size(medium)) ///
    subtitle("CCAA | Cambio EPA con desfase t+`lag' | Lectura descriptiva", size(small)) ///
    legend(order(1 "CCAA" 2 "Tendencia lineal") pos(6) ring(0)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_lag_2, replace)

graph export "`out_lag'/scatter_LAG`lag'_plazas_verdes_vs_cambio_peso_EPA_verde.png", ///
    width(3000) replace

graph save "`out_lag'/scatter_LAG`lag'_plazas_verdes_vs_cambio_peso_EPA_verde.gph", ///
    replace


********************************************************************************
* 12) SCATTER 3: NÚMERO DE PLAZAS VERDES VS ÍNDICE DE EMPLEO EPA
*
* Lectura relativa: empleo joven verde final respecto al año base de cada ventana.
********************************************************************************

twoway ///
    (scatter indice_ocup_verde_lag plazas_verdes_prtr_lag, ///
        mlabel(ccaa_label) mlabsize(vsmall) mlabposition(12) ///
        msymbol(circle) msize(medium)) ///
    (lfit indice_ocup_verde_lag plazas_verdes_prtr_lag, ///
        lcolor(maroon) lwidth(medthick)), ///
    xline(`med_plazas_prtr', lcolor(gs10) lpattern(dash)) ///
    yline(100, lcolor(gs8) lpattern(dash)) ///
    xtitle("Plazas PRTR verdes creadas") ///
    ytitle("Índice empleo joven verde EPA, t=100") ///
    title("Plazas verdes creadas y evolución relativa del empleo", size(medium)) ///
    subtitle("CCAA | Desfase t+`lag' | Lectura descriptiva", size(small)) ///
    legend(order(1 "CCAA" 2 "Tendencia lineal") pos(6) ring(0)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_lag_3, replace)

graph export "`out_lag'/scatter_LAG`lag'_plazas_verdes_vs_indice_EPA_verde.png", ///
    width(3000) replace

graph save "`out_lag'/scatter_LAG`lag'_plazas_verdes_vs_indice_EPA_verde.gph", ///
    replace


********************************************************************************
* 13) PANEL CCAA-AÑO: CADA PUNTO ES UNA CCAA EN UN AÑO PRTR
********************************************************************************

use "`out_lag'/PANEL_PRTR_EPA_VERDE_CCAA_ANIO_LAG`lag'.dta", clear

gen str35 ccaa_label = ccaa_final

replace ccaa_label = "Madrid"             if ccaa_final == "Madrid, Comunidad de"
replace ccaa_label = "C. Valenciana"      if ccaa_final == "Comunitat Valenciana"
replace ccaa_label = "Navarra"            if ccaa_final == "Navarra, Comunidad Foral de"
replace ccaa_label = "Murcia"             if ccaa_final == "Murcia, Región de"
replace ccaa_label = "Asturias"           if ccaa_final == "Asturias, Principado de"
replace ccaa_label = "Baleares"           if ccaa_final == "Balears, Illes"
replace ccaa_label = "Castilla-La Mancha" if ccaa_final == "Castilla - La Mancha"
replace ccaa_label = "La Rioja"           if ccaa_final == "Rioja, La"

gen str45 label_ccaa_anio = ccaa_label + " " + string(anio_prtr)

twoway ///
    (scatter cambio_ocup_verde_t_tlag_miles plazas_verdes_prtr, ///
        mlabel(label_ccaa_anio) mlabsize(tiny) mlabposition(12) ///
        msymbol(circle) msize(small)) ///
    (lfit cambio_ocup_verde_t_tlag_miles plazas_verdes_prtr, ///
        lcolor(maroon) lwidth(medthick)), ///
    yline(0, lcolor(gs8) lpattern(dash)) ///
    xtitle("Plazas PRTR verdes creadas en el año t") ///
    ytitle("Cambio ocupados jóvenes verdes entre t y t+`lag', miles") ///
    title("Cohortes anuales: plazas verdes y empleo joven después", size(medium)) ///
    subtitle("Cada punto es CCAA-año PRTR | Lectura descriptiva", size(small)) ///
    legend(order(1 "CCAA-año" 2 "Tendencia lineal") pos(6) ring(0)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_lag_4, replace)

graph export "`out_lag'/scatter_LAG`lag'_panel_CCAA_anio_plazas_vs_cambio_ocupados_EPA.png", ///
    width(3200) replace

graph save "`out_lag'/scatter_LAG`lag'_panel_CCAA_anio_plazas_vs_cambio_ocupados_EPA.gph", ///
    replace


********************************************************************************
* 14) GRÁFICO DE EVOLUCIÓN POR CCAA
*
* Línea verde: cambio del empleo joven verde entre t y t+lag.
* Línea azul: % de plazas PRTR verdes creadas en t.
********************************************************************************

encode ccaa_label, gen(ccaa_id)

local xlab
levelsof anio_prtr, local(years)
foreach y of local years {
    local y2 = `y' + `lag'
    local xlab `"`xlab' `y' "`y'->`y2'""'
}

twoway ///
    (line cambio_share_verde_t_tlag_pp anio_prtr, ///
        lcolor(green) lwidth(medthick) msymbol(circle) mcolor(green) ///
        yaxis(1)) ///
    (line peso_plazas_verdes_prtr anio_prtr, ///
        lcolor(blue) lpattern(dash) lwidth(medthick) ///
        msymbol(square) mcolor(blue) yaxis(2)), ///
    by(ccaa_id, cols(4) note("") ///
        title("FP verde y empleo joven verde después", size(medsmall)) ///
        subtitle("Verde: cambio EPA t->t+`lag' | Azul: plazas PRTR verdes en t", size(small))) ///
    yline(0, lcolor(gs8) lpattern(dash) axis(1)) ///
    ylabel(-10(5)10, angle(0) grid axis(1) labsize(vsmall)) ///
    ylabel(0(10)50, angle(0) axis(2) labsize(vsmall)) ///
    xlabel(`xlab', angle(30) labsize(tiny)) ///
    xtitle("Año de creación de plazas PRTR y ventana EPA posterior", size(small)) ///
    ytitle("Cambio empleo joven verde, pp", axis(1) size(small)) ///
    ytitle("% plazas PRTR verdes", axis(2) size(small)) ///
    legend(order(1 "Cambio empleo verde t->t+`lag'" 2 "% plazas PRTR verdes en t") ///
           pos(6) ring(0)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_lag_5, replace)

graph export "`out_lag'/evolucion_CCAA_PRTR_verde_y_cambio_EPA_LAG`lag'.png", ///
    width(3600) replace

graph save "`out_lag'/evolucion_CCAA_PRTR_verde_y_cambio_EPA_LAG`lag'.gph", ///
    replace


********************************************************************************
* 15) RANKING 1: CAMBIO EPA POSTERIOR POR CCAA
********************************************************************************

use "`out_lag'/CRUCE_CCAA_PRTR_EPA_VERDE_LAG`lag'_RESUMEN.dta", clear

gen str35 ccaa_label = ccaa_final

replace ccaa_label = "Madrid"             if ccaa_final == "Madrid, Comunidad de"
replace ccaa_label = "C. Valenciana"      if ccaa_final == "Comunitat Valenciana"
replace ccaa_label = "Navarra"            if ccaa_final == "Navarra, Comunidad Foral de"
replace ccaa_label = "Murcia"             if ccaa_final == "Murcia, Región de"
replace ccaa_label = "Asturias"           if ccaa_final == "Asturias, Principado de"
replace ccaa_label = "Baleares"           if ccaa_final == "Balears, Illes"
replace ccaa_label = "Castilla-La Mancha" if ccaa_final == "Castilla - La Mancha"
replace ccaa_label = "La Rioja"           if ccaa_final == "Rioja, La"

graph hbar cambio_share_verde_lag_pp, ///
    over(ccaa_label, sort(1) descending label(labsize(vsmall))) ///
    yline(0, lcolor(gs8) lpattern(dash)) ///
    blabel(bar, format(%4.1f)) ///
    ytitle("Cambio en puntos porcentuales") ///
    title("Cambio posterior del peso del empleo joven verde", size(medium)) ///
    subtitle("Ventana EPA `lag' años después de las plazas PRTR", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_lag_6, replace)

graph export "`out_lag'/ranking_CCAA_cambio_peso_EPA_verde_LAG`lag'.png", ///
    width(3000) replace

graph save "`out_lag'/ranking_CCAA_cambio_peso_EPA_verde_LAG`lag'.gph", ///
    replace


********************************************************************************
* 16) RANKING 2: PESO ACUMULADO DE PLAZAS VERDES PRTR
********************************************************************************

graph hbar peso_plazas_verdes_prtr_lag, ///
    over(ccaa_label, sort(1) descending label(labsize(vsmall))) ///
    blabel(bar, format(%4.1f)) ///
    ytitle("% de plazas PRTR creadas") ///
    title("Peso acumulado de plazas verdes dentro de la expansión de FP", size(medium)) ///
    subtitle("Plazas PRTR acumuladas en los años con ventana EPA disponible", size(small)) ///
    graphregion(color(white)) bgcolor(white) ///
    name(g_lag_7, replace)

graph export "`out_lag'/ranking_CCAA_peso_plazas_PRTR_verdes_LAG`lag'.png", ///
    width(3000) replace

graph save "`out_lag'/ranking_CCAA_peso_plazas_PRTR_verdes_LAG`lag'.gph", ///
    replace


********************************************************************************
* 17) CORRELACIONES DESCRIPTIVAS
********************************************************************************

use "`out_lag'/CRUCE_CCAA_PRTR_EPA_VERDE_LAG`lag'_RESUMEN.dta", clear

pwcorr peso_plazas_verdes_prtr_lag ///
       plazas_verdes_prtr_lag ///
       plz_verde_1000j_lag ///
       cambio_share_verde_lag_pp ///
       cambio_ocup_verde_lag_miles ///
       indice_ocup_verde_lag, sig


********************************************************************************
* 18) TABLA FINAL PARA INFORME
********************************************************************************

gsort -peso_plazas_verdes_prtr_lag

export excel using "`out_lag'/TABLA_FINAL_CRUCE_PRTR_EPA_VERDE_LAG`lag'.xlsx", ///
    replace firstrow(variables)

save "`out_lag'/TABLA_FINAL_CRUCE_PRTR_EPA_VERDE_LAG`lag'.dta", replace


********************************************************************************
* 19) MENSAJE FINAL
********************************************************************************

di as result "============================================================"
di as result "Análisis con desfase t+`lag' completado correctamente."
di as result ""
di as result "Lectura correcta:"
di as result "Plazas PRTR verdes en t se comparan con el cambio EPA entre t y t+`lag'."
di as result ""
di as result "Ejemplo con lag=2:"
di as result "2021 -> 2023"
di as result "2022 -> 2024"
di as result "2023 -> 2025"
di as result ""
di as result "Gráfico más claro para relato:"
di as result "evolucion_CCAA_PRTR_verde_y_cambio_EPA_LAG`lag'.png"
di as result ""
di as result "Archivos principales:"
di as result "1) PANEL_PRTR_EPA_VERDE_CCAA_ANIO_LAG`lag'.xlsx"
di as result "2) CRUCE_CCAA_PRTR_EPA_VERDE_LAG`lag'_RESUMEN.xlsx"
di as result "3) TABLA_FINAL_CRUCE_PRTR_EPA_VERDE_LAG`lag'.xlsx"
di as result ""
di as result "Carpeta:"
di as result "`out_lag'"
di as result "============================================================"


/********************************************************************************
* SECTION 9: Fuzzy_Merge.do
********************************************************************************/

/**********************************************************************************************
* Fuzzy Merge Generalizado de Municipios (España)
* - Corrige nombres de municipios mal escritos usando referencia explosionada (guion y barra)
* - Exporta resultado final y diagnóstico de matches
* Autor: Jose Camas Garrdiow | Última edición: 2024-06


**********************************************************************************************
**********************************************************************************************/
local dir "${PROJECT_ROOT}\2. PERTE\Enero_2026\0.0 BASE PERTE CON MUNICIPIOS"    // CAMBIAR DIRECTORIO
***********************************************************************************************
************************************************************************************************


* Paso 1: Importa el Excel de referencia y guarda como .dta
import excel "`dir'\base_municipio_ref_limpio_exploded.xlsx", firstrow clear
capture confirm variable id_ref
if _rc {
    gen id_ref = _n
}
save "`dir'\base_municipio_ref_limpio_exploded.dta", replace

* Paso 2: ... ahora puedes hacer el reclink sobre el .dta

**********************************************************************************************
**********************************************************************************************/
* 0. DIRECTORIO BASE Y ARCHIVOS (AJUSTA SOLO ESTAS LÍNEAS)

local archivo_malos    "BASE_PERTE_ENERO_2026_2.xlsx"      // CAMBIAR ARCHIVO
local hoja_malos       "Sheet1"                             // CAMBIAR HOJA

**********************************************************************************************
**********************************************************************************************/

local ref_exploded     "`dir'\base_municipio_ref_limpio_exploded.dta"         // BASE REFERENCIA EXPLOSIONADA

* 1. OPCIONAL: CHEQUEO/CREACIÓN DE id_ref EN LA REFERENCIA (hacer solo una vez tras actualizar la referencia)
capture {
    use "`ref_exploded'", clear
    capture confirm variable id_ref
    if _rc {
        gen id_ref = _n
        save "`ref_exploded'", replace
    }
}
* (puedes comentar esto si tu ref_exploded ya lleva id_ref)

********************************************************************************
* 2. IMPORTA Y LIMPIA LA BASE DE MUNICIPIOS MALOS
********************************************************************************

import excel "`dir'\\`archivo_malos'", sheet("`hoja_malos'") firstrow clear
gen id_mal = _n
rename Muncipio municipio_mal

* Limpieza estándar
replace municipio_mal = lower(municipio_mal)
replace municipio_mal = trim(municipio_mal)
replace municipio_mal = subinstr(municipio_mal, " – ", "-", .)
replace municipio_mal = subinstr(municipio_mal, "—", "-", .)
replace municipio_mal = subinstr(municipio_mal, "–", "-", .)
replace municipio_mal = subinstr(municipio_mal, "−", "-", .)
replace municipio_mal = trim(municipio_mal)
replace municipio_mal = substr(municipio_mal, strpos(municipio_mal, "-") + 1, .) if strpos(municipio_mal, "-") > 0
replace municipio_mal = trim(municipio_mal)
replace municipio_mal = ustrnormalize(municipio_mal, "nfd")
replace municipio_mal = ustrregexra(municipio_mal, "[\u0300-\u036f]", "", .)
replace municipio_mal = subinstr(municipio_mal, "á", "a", .)
replace municipio_mal = subinstr(municipio_mal, "é", "e", .)
replace municipio_mal = subinstr(municipio_mal, "í", "i", .)
replace municipio_mal = subinstr(municipio_mal, "ó", "o", .)
replace municipio_mal = subinstr(municipio_mal, "ú", "u", .)
replace municipio_mal = subinstr(municipio_mal, "ü", "u", .)
replace municipio_mal = subinstr(municipio_mal, "ñ", "n", .)
replace municipio_mal = ustrregexra(municipio_mal, "[^a-z0-9 ]", "", .)
replace municipio_mal = lower(municipio_mal)
replace municipio_mal = trim(municipio_mal)

save "`dir'\base_municipio_mal_limpio.dta", replace

list municipio_mal if strpos(lower(municipio_mal), "marcon")


********************************************************************************
* 3. FUZZY MATCH CON RECLINK USANDO LA BASE EXPLOSIONADA
********************************************************************************

use "`dir'\base_municipio_mal_limpio.dta", clear
keep if !missing(municipio_mal) & municipio_mal!=""

reclink municipio_mal using "`ref_exploded'", ///
    idmaster(id_mal) idusing(id_ref) gen(score) minscore(0.96) uvarlist(municipio_ref)
bysort id_mal (score): keep if _n==_N
save "`dir'\match_municipios.dta", replace

********************************************************************************
* 4. ASOCIAR EL MUNICIPIO CORRECTO A LA BASE ORIGINAL
********************************************************************************

import excel "`dir'\\`archivo_malos'", sheet("`hoja_malos'") firstrow clear
gen id_mal = _n
rename Muncipio municipio_mal
merge 1:1 id_mal using "`dir'\match_municipios.dta", keepusing(municipio_oficial municipio_ref score) nogen

order municipio_mal municipio_oficial municipio_ref score

* Exporta resultado final
export excel using "`dir'\BASE_PERTE_MUNCIPIOS_LIMPIOS.xlsx", firstrow(variables) replace

********************************************************************************
* 5. CHEQUEO DE MATCHING Y DIAGNÓSTICO
********************************************************************************

gen municipio_valido = !missing(municipio_mal) & municipio_mal!=""
gen match_exitoso = !missing(municipio_oficial) & municipio_oficial!=""

count if municipio_valido==1
local total = r(N)
count if municipio_valido==1 & match_exitoso==1
local matched = r(N)
count if municipio_valido==1 & match_exitoso==0
local no_match = r(N)

local pct_matched = 100*`matched'/`total'
local pct_no_match = 100*`no_match'/`total'

di as txt "------------------------------------"
di as res "Total municipios válidos: " `total'
di as res "Matcheados: " `matched' " (" %4.2f `pct_matched' "%)"
di as res "NO matcheados: " `no_match' " (" %4.2f `pct_no_match' "%)"
di as txt "------------------------------------"

if `no_match'/`total' > 0.01 {
    di as err "¡ATENCIÓN! Hay más del 1% de municipios sin match."
}

list municipio_mal if municipio_valido==1 & match_exitoso==0

********************************************************************************
* 6. FIN DEL SCRIPT GENERAL
********************************************************************************
