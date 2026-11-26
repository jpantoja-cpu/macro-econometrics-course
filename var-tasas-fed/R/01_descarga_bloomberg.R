# 01_descarga_bloomberg.R -----------------------------------------------
# SE CORRE EN LA PC DE LA OFICINA (Terminal Bloomberg abierta y con sesión).
#
# Cómo correrlo:
#   1. En RStudio: File > Open Project > .../macro-econometrics-course/var-tasas-fed/var-tasas-fed.Rproj
#      (o simplemente abre este archivo; utils.R encuentra la carpeta solo).
#   2. Abre este archivo y presiona "Source" (Ctrl+Shift+S).
#   3. Al final, copia los comandos de Git que imprime en la Terminal de RStudio.
#
# Qué hace:
#   - Valida cada ticker con bdp(ticker, "NAME") y guarda data/raw/log_tickers.csv.
#   - Descarga con bdh() desde 1988-01-01: tasas en frecuencia diaria, macro en mensual.
#   - Guarda data/raw/bloomberg_tasas.csv en formato largo
#     (fecha, ticker, nombre, frecuencia, valor, fecha_descarga).
# Si un ticker falla, sigue con los demás y lo reporta al final.

local({
  cand <- c("R/utils.R", "var-tasas-fed/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/var-tasas-fed/R/utils.R")
  source(cand[file.exists(cand)][1])
})

if (!requireNamespace("Rblpapi", quietly = TRUE)) install.packages("Rblpapi")
library(Rblpapi)

INICIO <- as.Date("1988-01-01")
FIN    <- Sys.Date()

# ticker, nombre corto en el proyecto, frecuencia de descarga, obligatorio
tickers <- data.frame(
  ticker = c(
    # Política monetaria
    "FEDL01 Index", "FDTR Index",
    # Curva del Tesoro (rendimientos genéricos)
    "USGG3M Index", "USGG6M Index", "USGG12M Index", "USGG2YR Index",
    "USGG5YR Index", "USGG10YR Index", "USGG30YR Index",
    # Macro
    "IP Index", "CPI INDX Index", "BCOM Index", "USURTOT Index",
    # Opcional: índices total return del Tesoro (Bloomberg). Candidatos;
    # el log de validación muestra qué es cada uno. Si fallan, no pasa nada.
    "LUATTRUU Index", "LT01TRUU Index", "LT02TRUU Index", "LT03TRUU Index",
    "LT09TRUU Index", "LT11TRUU Index"
  ),
  var = c("ffr", "ffr_meta",
          "y3m", "y6m", "y1y", "y2y", "y5y", "y10y", "y30y",
          "ip", "cpi", "bcom", "unemp",
          "tr_total", "tr_1_3", "tr_3_5", "tr_5_7", "tr_7_10", "tr_20plus"),
  # Tasas y BCOM en diario (luego promedio mensual); IP, IPC y desempleo en mensual
  frecuencia = c(rep("DAILY", 9), "MONTHLY", "MONTHLY", "DAILY", "MONTHLY", rep("DAILY", 6)),
  obligatorio = c(TRUE, FALSE, rep(TRUE, 7), TRUE, TRUE, TRUE, FALSE, rep(FALSE, 6)),
  stringsAsFactors = FALSE
)

con <- blpConnect()

# 1) Validación --------------------------------------------------------
message("Validando tickers...")
val <- tryCatch(bdp(tickers$ticker, c("NAME")), error = function(e) NULL)
if (is.null(val)) {
  # Si la llamada conjunta falla, validar uno por uno
  val <- do.call(rbind, lapply(tickers$ticker, function(t) {
    r <- tryCatch(bdp(t, "NAME"), error = function(e) data.frame(NAME = NA_character_, row.names = t))
    r
  }))
}
tickers$nombre <- val[tickers$ticker, "NAME"]
tickers$estado <- ifelse(is.na(tickers$nombre) | tickers$nombre == "", "FALLA", "OK")
print(tickers[, c("ticker", "var", "nombre", "estado")], row.names = FALSE)
write.csv(tickers, ruta("data", "raw", "log_tickers.csv"), row.names = FALSE)

# 2) Descarga ----------------------------------------------------------
bajar <- function(i) {
  t <- tickers[i, ]
  if (t$estado != "OK") return(NULL)
  message("  bdh: ", t$ticker, " (", t$frecuencia, ")")
  opt <- c("periodicitySelection" = t$frecuencia, "nonTradingDayFillOption" = "ACTIVE_DAYS_ONLY")
  d <- tryCatch(bdh(t$ticker, "PX_LAST", start.date = INICIO, end.date = FIN, options = opt),
                error = function(e) { message("    error: ", conditionMessage(e)); NULL })
  if (is.null(d) || !nrow(d)) return(NULL)
  data.frame(fecha = as.Date(d$date), ticker = t$ticker, var = t$var, nombre = t$nombre,
             frecuencia = t$frecuencia, valor = as.numeric(d$PX_LAST),
             fecha_descarga = as.character(Sys.Date()), stringsAsFactors = FALSE)
}
datos <- do.call(rbind, lapply(seq_len(nrow(tickers)), bajar))
datos <- datos[!is.na(datos$valor), ]

archivo <- ruta("data", "raw", "bloomberg_tasas.csv")
write.csv(datos, archivo, row.names = FALSE)

# 3) Resumen -----------------------------------------------------------
res <- do.call(rbind, lapply(split(datos, datos$var), function(d)
  data.frame(var = d$var[1], ticker = d$ticker[1], n = nrow(d),
             desde = min(d$fecha), hasta = max(d$fecha), ultimo = tail(d$valor, 1))))
print(res, row.names = FALSE)

faltan_oblig <- tickers$var[tickers$obligatorio & !(tickers$var %in% datos$var)]
if (length(faltan_oblig)) {
  warning("Faltan series obligatorias: ", paste(faltan_oblig, collapse = ", "),
          ". Revisa data/raw/log_tickers.csv y avísale a Claude.")
}

blpDisconnect(con)

cat("\nListo. Archivo guardado en:\n  ", archivo, "\n\n",
    "Ahora, en la pestaña Terminal de RStudio (desde la carpeta del repo):\n\n",
    "  git add var-tasas-fed/data/raw\n",
    "  git commit -m \"Datos Bloomberg ", as.character(Sys.Date()), "\"\n",
    "  git push\n\n", sep = "")
