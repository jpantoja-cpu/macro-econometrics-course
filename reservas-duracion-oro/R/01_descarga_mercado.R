# 01_descarga_mercado.R -------------------------------------------------
# SE CORRE EN LA PC DE LA OFICINA (Terminal Bloomberg abierta y con sesión).
# Datos de mercado para (a) el análisis de duración vs retorno y (b) el oro.
# Solo datos de mercado públicos: aquí NO se descargan posiciones del BCB.
#
# Cómo correrlo: abre este archivo en RStudio y presiona "Source".
# Después: doble clic en subir_datos.bat (carpeta reservas-duracion-oro).
# Salida: data/raw/bloomberg_mercado.csv, data/raw/log_tickers_mercado.csv

local({
  # Busca el utils.R de ESTA carpeta (reservas-duracion-oro), sin importar dónde esté parado RStudio
  cand <- c(if (file.exists("reservas-duracion-oro.Rproj")) "R/utils.R", "reservas-duracion-oro/R/utils.R", "../reservas-duracion-oro/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/reservas-duracion-oro/R/utils.R")
  source(cand[file.exists(cand)][1])
})
if (!requireNamespace("Rblpapi", quietly = TRUE)) install.packages("Rblpapi")
library(Rblpapi)

tickers <- data.frame(
  ticker = c(# Oro y sus determinantes
             "XAU Curncy", "GOLDLNPM Index", "USGGT10Y Index", "USGGT05Y Index", "DXY Curncy", "GVZ Index",
             # Índices de letras del Tesoro (candidatos; el log muestra cuál es cuál)
             "LD12TRUU Index", "G0O1 Index", "G0QA Index"),
  var = c("oro", "oro_lbma", "real10", "real5", "dxy", "vol_oro", "tr_letras_bbg", "tr_letras_ice", "tr_0_1_ice"),
  stringsAsFactors = FALSE)

con <- blpConnect()
val <- do.call(rbind, lapply(tickers$ticker, function(t)
  tryCatch(bdp(t, "NAME"), error = function(e) data.frame(NAME = NA_character_, row.names = t))))
tickers$nombre <- val[tickers$ticker, "NAME"]
tickers$estado <- ifelse(is.na(tickers$nombre) | tickers$nombre == "", "FALLA", "OK")
print(tickers, row.names = FALSE)
write.csv(tickers, ruta("data", "raw", "log_tickers_mercado.csv"), row.names = FALSE)

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
write.csv(datos, ruta("data", "raw", "bloomberg_mercado.csv"), row.names = FALSE)
print(do.call(rbind, lapply(split(datos, datos$var), function(d)
  data.frame(var = d$var[1], n = nrow(d), desde = min(d$fecha), hasta = max(d$fecha), ultimo = tail(d$valor, 1)))),
  row.names = FALSE)
blpDisconnect(con)

cat("\nListo. Datos guardados en data/raw/.\n",
    "Para subirlos a GitHub: doble clic en subir_datos.bat (carpeta reservas-duracion-oro).\n\n", sep = "")
