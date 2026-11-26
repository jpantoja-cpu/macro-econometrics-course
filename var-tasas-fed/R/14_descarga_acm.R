# 14_descarga_acm.R ---------------------------------------------
# SE CORRE EN LA PC DE LA OFICINA (Terminal Bloomberg abierta y con sesión).
# Descomposición de la curva de Adrian, Crump y Moench (2013), publicada por la Fed de
# Nueva York: rendimiento ajustado = rendimiento neutral al riesgo (expectativas de la
# tasa corta) + prima por plazo. Plazos 2, 5 y 10 años. Si algún ticker falla, el log
# lo indica y el análisis usa los que estén disponibles.
#
# Cómo correrlo: abre este archivo en RStudio y presiona "Source". Al final copia
# los comandos de Git que imprime.
# Salida: data/raw/bloomberg_acm.csv, data/raw/log_tickers_acm.csv

local({
  # Busca el utils.R de ESTA carpeta (var-tasas-fed), sin importar dónde esté parado RStudio
  cand <- c(if (file.exists("var-tasas-fed.Rproj")) "R/utils.R", "var-tasas-fed/R/utils.R", "../var-tasas-fed/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/var-tasas-fed/R/utils.R")
  source(cand[file.exists(cand)][1])
})
if (!requireNamespace("Rblpapi", quietly = TRUE)) install.packages("Rblpapi")
library(Rblpapi)

pl <- c("02", "05", "10")
tickers <- data.frame(
  ticker = c(paste0("ACMTP", pl, " Index"), paste0("ACMRNY", pl, " Index"), paste0("ACMY", pl, " Index")),
  var = c(paste0("tp", as.integer(pl)), paste0("rny", as.integer(pl)), paste0("acmy", as.integer(pl))),
  frecuencia = "DAILY", stringsAsFactors = FALSE)

con <- blpConnect()
val <- do.call(rbind, lapply(tickers$ticker, function(t)
  tryCatch(bdp(t, "NAME"), error = function(e) data.frame(NAME = NA_character_, row.names = t))))
tickers$nombre <- val[tickers$ticker, "NAME"]
tickers$estado <- ifelse(is.na(tickers$nombre) | tickers$nombre == "", "FALLA", "OK")
print(tickers, row.names = FALSE)
write.csv(tickers, ruta("data", "raw", "log_tickers_acm.csv"), row.names = FALSE)

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
archivo <- ruta("data", "raw", "bloomberg_acm.csv")
write.csv(datos, archivo, row.names = FALSE)
print(do.call(rbind, lapply(split(datos, datos$var), function(d)
  data.frame(var = d$var[1], n = nrow(d), desde = min(d$fecha), hasta = max(d$fecha), ultimo = tail(d$valor, 1)))),
  row.names = FALSE)
blpDisconnect(con)

# Mensaje final (se omite cuando corre dentro de actualizar_datos.R)
if (!isTRUE(getOption("vtf_lote")))
  cat("\nListo. Datos guardados en data/raw/.\n",
      "Para subirlos a GitHub: doble clic en subir_datos.bat (carpeta var-tasas-fed).\n\n", sep = "")
