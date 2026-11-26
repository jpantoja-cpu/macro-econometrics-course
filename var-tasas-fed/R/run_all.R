# run_all.R -------------------------------------------------------------
# Corre todo el análisis a partir de data/raw/bloomberg_tasas.csv.
# (La descarga, 01_descarga_bloomberg.R, se corre aparte en la PC con Bloomberg.)

local({
  cand <- c("R/utils.R", "var-tasas-fed/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/var-tasas-fed/R/utils.R")
  source(cand[file.exists(cand)][1])
})
t0 <- Sys.time()
scripts <- c("02_base_mensual.R", "03_inspeccion.R", "04_var_base.R",
             "05_asimetria_lp.R", "06_precios_bonos.R", "07_robustez.R")
# Sorpresas de futuros y proxy SVAR: solo si ya se descargaron los futuros (script 08)
if (file.exists(ruta("data", "raw", "bloomberg_futuros.csv")))
  scripts <- c(scripts, "09_sorpresas_eventos.R", "10_proxy_svar.R", "12_factores_curva.R",
               if (file.exists(ruta("data", "raw", "bloomberg_acm.csv"))) "15_prima_plazo.R",
               if (file.exists(ruta("data", "raw", "bloomberg_noticias.csv"))) "17_noticias_macro.R")
for (s in scripts) {
  message("\n==== ", s, " ====")
  source(ruta("R", s), echo = FALSE)
}
message(sprintf("\nListo en %.1f minutos. Resultados en output/figuras y output/tablas.",
                as.numeric(difftime(Sys.time(), t0, units = "mins"))))
