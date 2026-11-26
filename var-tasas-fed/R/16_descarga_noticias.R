# 16_descarga_noticias.R ------------------------------------------------
# SE CORRE EN LA PC DE LA OFICINA (Terminal Bloomberg abierta y con sesión).
# Datos macro de EE.UU. con fecha de publicación y mediana de la encuesta de
# Bloomberg, para medir sorpresas (dato publicado − mediana esperada), y
# expectativas de inflación de mercado (breakeven y forward 5y5y), diarias.
#
# Campos que se piden por cada indicador (no todos existen para todos):
#   ECO_RELEASE_DT     fecha de publicación
#   ACTUAL_RELEASE     valor publicado ese día (primera publicación, sin revisiones)
#   BN_SURVEY_MEDIAN   mediana de la encuesta de Bloomberg
#   PX_LAST            valor actual (revisado), como respaldo
# Al final imprime cuántos datos llegaron por indicador y campo.
#
# Cómo correrlo: abre este archivo en RStudio y presiona "Source"; luego los comandos de Git.
# Salida: data/raw/bloomberg_noticias.csv, data/raw/bloomberg_breakeven.csv,
#         data/raw/log_tickers_noticias.csv

local({
  cand <- c("R/utils.R", "var-tasas-fed/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/var-tasas-fed/R/utils.R")
  source(cand[file.exists(cand)][1])
})
if (!requireNamespace("Rblpapi", quietly = TRUE)) install.packages("Rblpapi")
library(Rblpapi)

ind <- data.frame(
  ticker = c("CPI CHNG Index", "CPUPXCHG Index", "NFP TCH Index", "USURTOT Index", "AHE MOM% Index",
             "RSTAMOM Index", "NAPMPMI Index", "GDP CQOQ Index", "INJCJC Index"),
  var = c("ipc", "ipc_sub", "nominas", "desempleo", "salarios", "ventas", "ism", "pib", "reclamos"),
  descripcion = c("IPC general, % m/m", "IPC subyacente, % m/m", "Nóminas no agrícolas, cambio (miles)",
                  "Tasa de desempleo (%)", "Salario por hora, % m/m", "Ventas minoristas, % m/m",
                  "ISM manufacturero", "PIB, % t/t anualizado (avance)", "Solicitudes de subsidio por desempleo (miles)"),
  periodicidad = c(rep("MONTHLY", 7), "QUARTERLY", "WEEKLY"),
  stringsAsFactors = FALSE)
campos <- c("ECO_RELEASE_DT", "ACTUAL_RELEASE", "BN_SURVEY_MEDIAN", "PX_LAST")

con <- blpConnect()
val <- do.call(rbind, lapply(ind$ticker, function(t)
  tryCatch(bdp(t, "NAME"), error = function(e) data.frame(NAME = NA_character_, row.names = t))))
ind$nombre <- val[ind$ticker, "NAME"]
ind$estado <- ifelse(is.na(ind$nombre) | ind$nombre == "", "FALLA", "OK")
print(ind[, c("ticker", "var", "nombre", "estado")], row.names = FALSE)

bajar_campo <- function(t, campo, per) {
  opt <- c("periodicitySelection" = per)
  d <- tryCatch(bdh(t, campo, start.date = as.Date("1990-01-01"), end.date = Sys.Date(), options = opt),
                error = function(e) { message("    ", t, " / ", campo, ": ", conditionMessage(e)); NULL })
  if (is.null(d) || !nrow(d)) return(NULL)
  data.frame(fecha_obs = as.Date(d$date), campo = campo, valor = as.character(d[[campo]]), stringsAsFactors = FALSE)
}
datos <- do.call(rbind, lapply(which(ind$estado == "OK"), function(i) {
  message("  ", ind$ticker[i])
  x <- do.call(rbind, lapply(campos, function(cp) bajar_campo(ind$ticker[i], cp, ind$periodicidad[i])))
  if (is.null(x)) return(NULL)
  cbind(ticker = ind$ticker[i], var = ind$var[i], x)
}))
datos <- datos[!is.na(datos$valor) & datos$valor != "", ]
datos$fecha_descarga <- as.character(Sys.Date())
write.csv(datos, ruta("data", "raw", "bloomberg_noticias.csv"), row.names = FALSE)

# Diagnóstico: cuántos datos por indicador y campo, y desde cuándo
diag <- aggregate(fecha_obs ~ var + campo, data = datos, FUN = function(x) c(n = length(x), desde = as.character(min(x))))
diag <- do.call(data.frame, diag); names(diag)[3:4] <- c("n", "desde")
ind$campos_ok <- sapply(ind$var, function(v) paste(diag$campo[diag$var == v], collapse = ", "))
write.csv(ind, ruta("data", "raw", "log_tickers_noticias.csv"), row.names = FALSE)
cat("\n== Datos recibidos por indicador y campo ==\n"); print(diag, row.names = FALSE)
cat("\n== Ejemplo (IPC, últimas filas) ==\n")
ej <- datos[datos$var == "ipc", ]; ej <- reshape(ej[, c("fecha_obs", "campo", "valor")], idvar = "fecha_obs", timevar = "campo", direction = "wide")
print(tail(ej[order(ej$fecha_obs), ], 4), row.names = FALSE)

# Expectativas de inflación de mercado (diarias)
be <- data.frame(ticker = c("USGGBE10 Index", "FWISUS55 Index"), var = c("be10", "fwd5y5y"), stringsAsFactors = FALSE)
bed <- do.call(rbind, lapply(seq_len(nrow(be)), function(i) {
  d <- tryCatch(bdh(be$ticker[i], "PX_LAST", start.date = as.Date("1997-01-01"), end.date = Sys.Date(),
                    options = c("periodicitySelection" = "DAILY")), error = function(e) { message("  ", be$ticker[i], ": ", conditionMessage(e)); NULL })
  if (is.null(d) || !nrow(d)) return(NULL)
  data.frame(fecha = as.Date(d$date), ticker = be$ticker[i], var = be$var[i], valor = as.numeric(d$PX_LAST),
             fecha_descarga = as.character(Sys.Date()))
}))
if (!is.null(bed)) {
  write.csv(bed, ruta("data", "raw", "bloomberg_breakeven.csv"), row.names = FALSE)
  cat("\n== Breakeven / 5y5y ==\n")
  print(do.call(rbind, lapply(split(bed, bed$var), function(d) data.frame(var = d$var[1], n = nrow(d), desde = min(d$fecha), ultimo = tail(d$valor, 1)))), row.names = FALSE)
}
blpDisconnect(con)

# Mensaje final (se omite cuando corre dentro de actualizar_datos.R)
if (!isTRUE(getOption("vtf_lote")))
  cat("\nListo. Datos guardados en data/raw/.\n",
      "Para subirlos a GitHub: doble clic en subir_datos.bat (carpeta var-tasas-fed).\n\n", sep = "")
