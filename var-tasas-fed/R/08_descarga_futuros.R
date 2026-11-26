# 08_descarga_futuros.R -------------------------------------------------
# SE CORRE EN LA PC DE LA OFICINA (Terminal Bloomberg abierta y con sesión).
# Descarga los futuros de fed funds a 30 días (genéricos FF1 a FF6), base de las
# sorpresas de política monetaria (Kuttner 2001; Gürkaynak, Sack y Swanson 2005).
#
# Cómo correrlo: abre este archivo en RStudio y presiona "Source". Al final copia
# los comandos de Git que imprime.
# Salida: data/raw/bloomberg_futuros.csv (fecha, ticker, var, nombre, valor, fecha_descarga)
#         data/raw/log_tickers_futuros.csv

local({
  cand <- c("R/utils.R", "var-tasas-fed/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/var-tasas-fed/R/utils.R")
  source(cand[file.exists(cand)][1])
})
if (!requireNamespace("Rblpapi", quietly = TRUE)) install.packages("Rblpapi")
library(Rblpapi)

tickers <- data.frame(ticker = paste0("FF", 1:6, " Comdty"), var = paste0("ff", 1:6),
                      stringsAsFactors = FALSE)
con <- blpConnect()

val <- do.call(rbind, lapply(tickers$ticker, function(t)
  tryCatch(bdp(t, "NAME"), error = function(e) data.frame(NAME = NA_character_, row.names = t))))
tickers$nombre <- val[tickers$ticker, "NAME"]
tickers$estado <- ifelse(is.na(tickers$nombre) | tickers$nombre == "", "FALLA", "OK")
print(tickers, row.names = FALSE)
write.csv(tickers, ruta("data", "raw", "log_tickers_futuros.csv"), row.names = FALSE)

opt <- c("periodicitySelection" = "DAILY", "nonTradingDayFillOption" = "ACTIVE_DAYS_ONLY")
datos <- do.call(rbind, lapply(seq_len(nrow(tickers)), function(i) {
  t <- tickers[i, ]; if (t$estado != "OK") return(NULL)
  message("  bdh: ", t$ticker)
  d <- tryCatch(bdh(t$ticker, "PX_LAST", start.date = as.Date("1988-01-01"), end.date = Sys.Date(), options = opt),
                error = function(e) { message("    error: ", conditionMessage(e)); NULL })
  if (is.null(d) || !nrow(d)) return(NULL)
  data.frame(fecha = as.Date(d$date), ticker = t$ticker, var = t$var, nombre = t$nombre,
             valor = as.numeric(d$PX_LAST), fecha_descarga = as.character(Sys.Date()))
}))
datos <- datos[!is.na(datos$valor), ]
archivo <- ruta("data", "raw", "bloomberg_futuros.csv")
write.csv(datos, archivo, row.names = FALSE)

print(do.call(rbind, lapply(split(datos, datos$var), function(d)
  data.frame(var = d$var[1], n = nrow(d), desde = min(d$fecha), hasta = max(d$fecha), ultimo = tail(d$valor, 1)))),
  row.names = FALSE)
blpDisconnect(con)

cat("\nListo. Archivo guardado en:\n  ", archivo, "\n\n",
    "Ahora, en la ventana de comandos (desde la carpeta var-tasas-fed):\n\n",
    "  git pull\n  git add data/raw\n  git commit -m \"Futuros fed funds Bloomberg\"\n  git push\n\n", sep = "")
