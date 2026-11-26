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

# Fin de muestra: último mes con todas las series núcleo
nucleo <- c("ffr", "y3m", "y1y", "y2y", "y5y", "y10y", "y30y", "ip", "cpi", "bcom")
falt <- setdiff(nucleo, names(base))
if (length(falt)) stop("Faltan series núcleo en la descarga: ", paste(falt, collapse = ", "))
completo <- complete.cases(base[, nucleo])
base <- base[min(which(completo)):max(which(completo)), ]
rownames(base) <- NULL

write.csv(base, ruta("data", "base_mensual.csv"), row.names = FALSE)
message(sprintf("Base mensual: %s a %s (%d meses), %d series.",
                format(min(base$fecha), "%Y-%m"), format(max(base$fecha), "%Y-%m"),
                nrow(base), ncol(base) - 1))
