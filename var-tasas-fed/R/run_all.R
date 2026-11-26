# run_all.R -------------------------------------------------------------
# Corre todo el análisis a partir de data/raw/bloomberg_tasas.csv.
# (La descarga, 01_descarga_bloomberg.R, se corre aparte en la PC con Bloomberg.)

local({
  cand <- c("R/utils.R", "var-tasas-fed/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/var-tasas-fed/R/utils.R")
  source(cand[file.exists(cand)][1])
})
t0 <- Sys.time()
for (s in c("02_base_mensual.R", "03_inspeccion.R", "04_var_base.R",
            "05_asimetria_lp.R", "06_precios_bonos.R", "07_robustez.R")) {
  message("\n==== ", s, " ====")
  source(ruta("R", s), echo = FALSE)
}
message(sprintf("\nListo en %.1f minutos. Resultados en output/figuras y output/tablas.",
                as.numeric(difftime(Sys.time(), t0, units = "mins"))))
