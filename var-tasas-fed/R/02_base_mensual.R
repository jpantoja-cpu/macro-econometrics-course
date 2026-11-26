# 02_base_mensual.R -----------------------------------------------------
# Convierte la descarga de Bloomberg (formato largo) en la base mensual del VAR.
#   - Tasas, BCOM e índices total return: promedio mensual de datos diarios.
#   - IP, IPC y desempleo: dato mensual (se fecha al primer día del mes).
#   - IP, IPC, BCOM e índices TR entran en log × 100 (cambios ≈ variaciones %).
#   - Tasas en niveles, en % (un choque de 25 pb = 0.25).
#   - Se descarta el mes en curso de la descarga (promedio incompleto).
# Salida: data/base_mensual.csv

local({
  cand <- c("R/utils.R", "var-tasas-fed/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/var-tasas-fed/R/utils.R")
  source(cand[file.exists(cand)][1])
})

raw <- read.csv(ruta("data", "raw", "bloomberg_tasas.csv"), stringsAsFactors = FALSE)
raw$fecha <- as.Date(raw$fecha)
raw$mes <- as.Date(format(raw$fecha, "%Y-%m-01"))

mes_descarga <- as.Date(format(as.Date(max(raw$fecha_descarga)), "%Y-%m-01"))

mensual <- aggregate(valor ~ var + mes, data = raw, FUN = mean)
# El mes de la descarga solo se descarta para las series diarias
diarias <- unique(raw$var[raw$frecuencia == "DAILY"])
mensual <- mensual[!(mensual$var %in% diarias & mensual$mes >= mes_descarga), ]

base <- reshape(mensual, idvar = "mes", timevar = "var", direction = "wide")
names(base) <- sub("^valor\\.", "", names(base))
names(base)[names(base) == "mes"] <- "fecha"
base <- base[order(base$fecha), ]

en_log <- intersect(c("ip", "cpi", "bcom", grep("^tr_", names(base), value = TRUE)), names(base))
for (v in en_log) base[[v]] <- 100 * log(base[[v]])

# Huecos aislados en series mensuales macro: octubre 2025 no se publicó (cierre del
# gobierno de EE.UU.; el BLS no recolectó el IPC ni la encuesta de hogares de ese mes).
# Se interpola linealmente (en log×100 para el IPC) solo huecos de 1 mes, y se registra.
interp <- data.frame()
for (v in intersect(c("ip", "cpi", "unemp"), names(base))) {
  x <- base[[v]]; na <- which(is.na(x))
  na <- na[na > 1 & na < length(x) & !is.na(x[pmax(na - 1, 1)]) & !is.na(x[pmin(na + 1, length(x))])]
  if (length(na)) {
    x[na] <- (x[na - 1] + x[na + 1]) / 2
    interp <- rbind(interp, data.frame(serie = v, fecha = base$fecha[na], valor_interpolado = x[na]))
    base[[v]] <- x
  }
}
if (nrow(interp)) {
  write.csv(interp, ruta("data", "meses_interpolados.csv"), row.names = FALSE)
  message("Meses interpolados (hueco de 1 mes): ", paste(interp$serie, format(interp$fecha, "%Y-%m"), collapse = "; "))
}

# Fin de muestra: último mes con todas las series núcleo
# (y1y no es núcleo: USGG12M no existe entre 2001-08 y 2008-06 porque el Tesoro suspendió
#  la emisión de letras a 1 año; dejarla como núcleo cortaría la muestra)
nucleo <- c("ffr", "y3m", "y2y", "y5y", "y10y", "y30y", "ip", "cpi", "bcom")
falt <- setdiff(nucleo, names(base))
if (length(falt)) stop("Faltan series núcleo en la descarga: ", paste(falt, collapse = ", "))
completo <- complete.cases(base[, nucleo])
base <- base[min(which(completo)):max(which(completo)), ]
rownames(base) <- NULL

write.csv(base, ruta("data", "base_mensual.csv"), row.names = FALSE)
message(sprintf("Base mensual: %s a %s (%d meses), %d series.",
                format(min(base$fecha), "%Y-%m"), format(max(base$fecha), "%Y-%m"),
                nrow(base), ncol(base) - 1))
