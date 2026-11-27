# 01_descarga_transmision.R -------------------------------------------------
# SE CORRE EN LA PC DE LA OFICINA (Terminal Bloomberg abierta y con sesión).
# Datos para el mecanismo de transmisión Fed -> mercados -> economía real y tecnología:
# acciones (total, tecnología, semiconductores, bancos), spreads de crédito y un
# índice de condiciones financieras. Solo datos de mercado públicos.
#
# Cómo correrlo: abre este archivo en RStudio y presiona "Source".
# Después: doble clic en subir_datos.bat (carpeta mecanismo-transmision).
# Salida: data/raw/bloomberg_transmision.csv, data/raw/log_tickers_transmision.csv

local({
  # Busca el utils.R de ESTA carpeta (mecanismo-transmision), sin importar dónde esté parado RStudio
  cand <- c(if (file.exists("mecanismo-transmision.Rproj")) "R/utils.R", "mecanismo-transmision/R/utils.R", "../mecanismo-transmision/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/mecanismo-transmision/R/utils.R")
  source(cand[file.exists(cand)][1])
})
if (!requireNamespace("Rblpapi", quietly = TRUE)) install.packages("Rblpapi")
library(Rblpapi)

tickers <- data.frame(
  ticker = c(# Acciones
             "SPX Index", "NDX Index", "S5INFT Index", "SOX Index", "BKX Index",
             # Crédito
             "LUACOAS Index", "LF98OAS Index",
             # Condiciones financieras
             "BFCIUS Index"),
  var = c("sp500", "nasdaq100", "sp500_tec", "semis", "bancos", "spread_ig", "spread_hy", "cond_fin"),
  stringsAsFactors = FALSE)

con <- blpConnect()
val <- do.call(rbind, lapply(tickers$ticker, function(t)
  tryCatch(bdp(t, "NAME"), error = function(e) data.frame(NAME = NA_character_, row.names = t))))
tickers$nombre <- val[tickers$ticker, "NAME"]
tickers$estado <- ifelse(is.na(tickers$nombre) | tickers$nombre == "", "FALLA", "OK")
print(tickers, row.names = FALSE)
write.csv(tickers, ruta("data", "raw", "log_tickers_transmision.csv"), row.names = FALSE)

opt <- c("periodicitySelection" = "DAILY", "nonTradingDayFillOption" = "ACTIVE_DAYS_ONLY")
datos <- do.call(rbind, lapply(which(tickers$estado == "OK"), function(i) {
  message("  bdh: ", tickers$ticker[i])
  d <- tryCatch(bdh(tickers$ticker[i], "PX_LAST", start.date = as.Date("1988-01-01"), end.date = Sys.Date(), options = opt),
                error = function(e) { message("    error: ", conditionMessage(e)); NULL })
  if (is.null(d) || !nrow(d)) return(NULL)
  data.frame(fecha = as.Date(d$date), ticker = tickers$ticker[i], var = tickers$var[i], nombre = tickers$nombre[i],
             valor = as.numeric(d$PX_LAST), fecha_descarga = as.character(Sys.Date()))
}))
datos <- datos[!is.na(datos$valor), ]
write.csv(datos, ruta("data", "raw", "bloomberg_transmision.csv"), row.names = FALSE)
print(do.call(rbind, lapply(split(datos, datos$var), function(d)
  data.frame(var = d$var[1], n = nrow(d), desde = min(d$fecha), hasta = max(d$fecha), ultimo = tail(d$valor, 1)))),
  row.names = FALSE)
blpDisconnect(con)

cat("\nListo. Datos guardados en data/raw/.\n",
    "Para subirlos a GitHub: doble clic en subir_datos.bat (carpeta mecanismo-transmision).\n\n", sep = "")
