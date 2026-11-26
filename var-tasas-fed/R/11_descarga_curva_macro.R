# 11_descarga_curva_macro.R ---------------------------------------------
# SE CORRE EN LA PC DE LA OFICINA (Terminal Bloomberg abierta y con sesión).
# Plazos adicionales para ajustar la curva (Nelson-Siegel) y variables macro para el
# modelo de factores de la curva (Diebold, Rudebusch y Aruoba 2006).
#
# Cómo correrlo: abre este archivo en RStudio y presiona "Source". Al final copia
# los comandos de Git que imprime.
# Salida: data/raw/bloomberg_curva_macro.csv, data/raw/log_tickers_curva_macro.csv

local({
  cand <- c("R/utils.R", "var-tasas-fed/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/var-tasas-fed/R/utils.R")
  source(cand[file.exists(cand)][1])
})
if (!requireNamespace("Rblpapi", quietly = TRUE)) install.packages("Rblpapi")
library(Rblpapi)

tickers <- data.frame(
  ticker = c("USGG3YR Index", "USGG7YR Index", "USGG20YR Index",          # plazos de la curva
             "CPI XYOY Index", "PCE CYOY Index",                          # inflación subyacente
             "NFP T Index", "CPTICHNG Index"),                            # empleo y uso de capacidad
  var = c("y3y", "y7y", "y20y", "core_cpi_a", "core_pce_a", "nfp", "capu"),
  frecuencia = c("DAILY", "DAILY", "DAILY", "MONTHLY", "MONTHLY", "MONTHLY", "MONTHLY"),
  stringsAsFactors = FALSE)

con <- blpConnect()
val <- do.call(rbind, lapply(tickers$ticker, function(t)
  tryCatch(bdp(t, "NAME"), error = function(e) data.frame(NAME = NA_character_, row.names = t))))
tickers$nombre <- val[tickers$ticker, "NAME"]
tickers$estado <- ifelse(is.na(tickers$nombre) | tickers$nombre == "", "FALLA", "OK")
print(tickers, row.names = FALSE)
write.csv(tickers, ruta("data", "raw", "log_tickers_curva_macro.csv"), row.names = FALSE)

datos <- do.call(rbind, lapply(seq_len(nrow(tickers)), function(i) {
  t <- tickers[i, ]; if (t$estado != "OK") return(NULL)
  message("  bdh: ", t$ticker)
  opt <- c("periodicitySelection" = t$frecuencia, "nonTradingDayFillOption" = "ACTIVE_DAYS_ONLY")
  d <- tryCatch(bdh(t$ticker, "PX_LAST", start.date = as.Date("1988-01-01"), end.date = Sys.Date(), options = opt),
                error = function(e) { message("    error: ", conditionMessage(e)); NULL })
  if (is.null(d) || !nrow(d)) return(NULL)
  data.frame(fecha = as.Date(d$date), ticker = t$ticker, var = t$var, nombre = t$nombre, frecuencia = t$frecuencia,
             valor = as.numeric(d$PX_LAST), fecha_descarga = as.character(Sys.Date()))
}))
datos <- datos[!is.na(datos$valor), ]
archivo <- ruta("data", "raw", "bloomberg_curva_macro.csv")
write.csv(datos, archivo, row.names = FALSE)
print(do.call(rbind, lapply(split(datos, datos$var), function(d)
  data.frame(var = d$var[1], n = nrow(d), desde = min(d$fecha), hasta = max(d$fecha), ultimo = tail(d$valor, 1)))),
  row.names = FALSE)
blpDisconnect(con)

cat("\nListo. Archivo guardado en:\n  ", archivo, "\n\n",
    "Ahora, en la ventana de comandos (desde la carpeta var-tasas-fed):\n\n",
    "  git pull\n  git add data/raw\n  git commit -m \"Curva y macro Bloomberg\"\n  git push\n\n", sep = "")
