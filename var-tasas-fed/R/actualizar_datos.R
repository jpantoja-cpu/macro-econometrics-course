# actualizar_datos.R ----------------------------------------------------
# SE CORRE EN LA PC DE LA OFICINA (Terminal Bloomberg abierta y con sesión).
# Corre todas las descargas de Bloomberg del proyecto, una tras otra:
#   01 tasas, curva y macro · 08 futuros de fed funds · 11 plazos y macro adicionales
#   13 VIX y MOVE · 14 prima por plazo ACM · 16 noticias macro y breakevens
# Si una descarga falla, sigue con las demás y lo informa al final.
#
# Cómo correrlo: abre este archivo en RStudio y presiona "Source" (tarda unos 5 minutos).
# Después: doble clic en subir_datos.bat (carpeta var-tasas-fed) para subir los datos.

local({
  cand <- c("R/utils.R", "var-tasas-fed/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/var-tasas-fed/R/utils.R")
  source(cand[file.exists(cand)][1])
})

descargas <- c("01_descarga_bloomberg.R" = "Tasas, curva y macro",
               "08_descarga_futuros.R" = "Futuros de fed funds",
               "11_descarga_curva_macro.R" = "Plazos 3Y/7Y/20Y y macro adicional",
               "13_descarga_vix.R" = "VIX y MOVE",
               "14_descarga_acm.R" = "Prima por plazo ACM",
               "16_descarga_noticias.R" = "Noticias macro y breakevens")

options(vtf_lote = TRUE)
t0 <- Sys.time()
resultado <- sapply(names(descargas), function(s) {
  message("\n==== ", descargas[[s]], " (", s, ") ====")
  ok <- tryCatch({ source(ruta("R", s), local = new.env()); TRUE },
                 error = function(e) { message("  ERROR: ", conditionMessage(e)); FALSE })
  ok
})
options(vtf_lote = NULL)

cat("\n================ Resumen ================\n")
for (s in names(descargas)) cat(sprintf("  %-38s %s\n", descargas[[s]], if (resultado[[s]]) "OK" else "FALLÓ"))
cat(sprintf("\nTiempo: %.1f minutos.\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
if (all(resultado)) {
  cat("\nTodo descargado. Ahora: doble clic en subir_datos.bat (carpeta var-tasas-fed).\n\n")
} else {
  cat("\nAlguna descarga falló: copia los mensajes de ERROR de arriba y pégaselos a Claude.\n",
      "Las que salieron OK ya están guardadas; puedes subirlas igual con subir_datos.bat.\n\n", sep = "")
}
