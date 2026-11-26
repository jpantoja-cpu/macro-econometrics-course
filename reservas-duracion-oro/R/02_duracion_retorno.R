# 02_duracion_retorno.R -------------------------------------------------
# ¿Qué se gana y qué se arriesga alargando la duración de un portafolio de letras?
# Estrategias de vencimiento constante, rebalanceadas cada mes, 1988-2026:
#   Caja (EFFR) · letras 3M · 6M · 1 año · 2 años · 3 años
# Retorno mensual de un bono cupón cero de vencimiento m (años) comprado a fin de mes
# y vendido al mes siguiente, ya con vencimiento m − 1/12:
#   r_t = (1 + y_{t−1}(m))^m / (1 + y_t(m))^(m − 1/12) − 1
# (se usa el rendimiento del mismo plazo para revaluar: no incluye el "roll-down"
#  a lo largo de la curva, lo que subestima levemente el retorno de los plazos largos
#  cuando la curva tiene pendiente positiva). Caja: r_t = EFFR_{t−1}/12.
# Validación: el retorno de la estrategia de 2 años se compara con el índice total
# return de Bloomberg del Tesoro 1-3 años (duración ≈ 1,9).
# Lectura central: retorno a 12 meses según lo que haga la Fed en esos 12 meses
# (alzas: meta +50 pb o más; recortes: −50 pb o más; estable: el resto).

local({
  # Busca el utils.R de ESTA carpeta (reservas-duracion-oro), sin importar dónde esté parado RStudio
  cand <- c(if (file.exists("reservas-duracion-oro.Rproj")) "R/utils.R", "reservas-duracion-oro/R/utils.R", "../reservas-duracion-oro/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/reservas-duracion-oro/R/utils.R")
  source(cand[file.exists(cand)][1])
})
suppressPackageStartupMessages({ library(ggplot2); library(patchwork) })

# Datos: fin de mes ----------------------------------------------------------------
raw <- read.csv(ruta_vtf("data", "raw", "bloomberg_tasas.csv"), stringsAsFactors = FALSE)
ex <- ruta_vtf("data", "raw", "bloomberg_curva_macro.csv")
if (file.exists(ex)) raw <- rbind(raw[, c("fecha", "var", "valor")], read.csv(ex)[, c("fecha", "var", "valor")]) else raw <- raw[, c("fecha", "var", "valor")]
raw <- raw[raw$var %in% c("ffr", "ffr_meta", "y3m", "y6m", "y1y", "y2y", "y3y", "tr_1_3"), ]
raw$fecha <- as.Date(raw$fecha); raw$mes <- as.Date(format(raw$fecha, "%Y-%m-01"))
raw <- raw[order(raw$fecha), ]
fm <- do.call(rbind, lapply(split(raw, list(raw$var, raw$mes), drop = TRUE), function(d) d[nrow(d), ]))   # último dato del mes
M <- reshape(fm[, c("mes", "var", "valor")], idvar = "mes", timevar = "var", direction = "wide")
names(M) <- sub("^valor\\.", "", names(M)); M <- M[order(M$mes), ]
M <- M[M$mes < as.Date(format(Sys.Date(), "%Y-%m-01")), ]               # sin el mes en curso
M <- M[!is.na(M$y3m) & !is.na(M$y2y) & !is.na(M$ffr), ]

# Hueco del 1 año (2001-08 a 2008-06, no se emitieron letras a 1 año): interpolación
# lineal entre 6M y 2Y en esos meses, registrada en la tabla de decisiones.
hueco <- is.na(M$y1y)
M$y1y[hueco] <- M$y6m[hueco] + (M$y2y[hueco] - M$y6m[hueco]) * (12 - 6) / (24 - 6)
n_hueco <- sum(hueco)

PLAZOS <- c(y3m = 0.25, y6m = 0.5, y1y = 1, y2y = 2, y3y = 3)
PLAZOS <- PLAZOS[names(PLAZOS) %in% names(M)]
NOMBRE <- c(caja = "Caja (EFFR)", y3m = "Letras 3M", y6m = "Letras 6M", y1y = "1 año", y2y = "2 años", y3y = "3 años")

ret <- data.frame(mes = M$mes[-1], caja = M$ffr[-nrow(M)] / 100 / 12)
for (k in names(PLAZOS)) {
  m <- PLAZOS[[k]]; y0 <- M[[k]][-nrow(M)] / 100; y1 <- M[[k]][-1] / 100
  ret[[k]] <- (1 + y0)^m / (1 + y1)^(m - 1 / 12) - 1
}
EST <- c("caja", names(PLAZOS))
ret <- ret[complete.cases(ret[, intersect(EST, c("caja", "y3m", "y6m", "y1y", "y2y"))]), ]

# Validación contra el índice Bloomberg Tesoro 1-3 años
if ("tr_1_3" %in% names(M)) {
  tr <- data.frame(mes = M$mes[-1], tr13 = M$tr_1_3[-1] / M$tr_1_3[-nrow(M)] - 1)
  vv <- merge(ret[, c("mes", "y2y")], tr, by = "mes"); vv <- vv[complete.cases(vv), ]
  val <- data.frame(medida = c("Meses comparados", "Correlación mensual 2 años vs índice 1-3 años",
                               "Retorno anual promedio, estrategia 2 años (%)", "Retorno anual promedio, índice 1-3 años (%)"),
                    valor = c(nrow(vv), round(cor(vv$y2y, vv$tr13), 3), round(100 * 12 * mean(vv$y2y), 2), round(100 * 12 * mean(vv$tr13), 2)))
  guardar_tabla(val, "validacion_indice_1_3"); print(val, row.names = FALSE)
}

# Retornos a 12 meses (ventanas móviles) y régimen de la Fed en esos 12 meses --------
acum12 <- function(r) { n <- length(r); out <- rep(NA, n); for (i in 1:(n - 11)) out[i] <- prod(1 + r[i:(i + 11)]) - 1; out }
R12 <- data.frame(inicio = ret$mes)
for (k in EST) if (k %in% names(ret)) R12[[k]] <- acum12(ret[[k]])
meta <- M$ffr_meta[match(ret$mes, M$mes)]                                          # meta al cierre del primer mes
meta_ini <- M$ffr_meta[match(ret$mes, M$mes) - 1]                                 # meta al inicio (fin del mes previo)
meta_fin <- c(meta[-(1:11)], rep(NA, 11))
R12$d_meta_pb <- 100 * (meta_fin - meta_ini)
R12$regimen <- ifelse(R12$d_meta_pb >= 50, "Alzas (+50 pb o más)", ifelse(R12$d_meta_pb <= -50, "Recortes (−50 pb o más)", "Estable"))
R12 <- R12[!is.na(R12$y2y) & !is.na(R12$d_meta_pb), ]
REG <- c("Recortes (−50 pb o más)", "Estable", "Alzas (+50 pb o más)")

# Tabla resumen por estrategia ----------------------------------------------------------
ESTd <- intersect(EST, names(ret))
dd <- function(r) { v <- cumprod(1 + r); min(v / cummax(v) - 1) }
resumen <- do.call(rbind, lapply(ESTd, function(k) {
  r <- ret[[k]][!is.na(ret[[k]])]; a <- R12[[k]][!is.na(R12[[k]])]
  data.frame(estrategia = NOMBRE[k], duracion_aprox = if (k == "caja") 0 else round(PLAZOS[[k]] / (1 + mean(M[[k]], na.rm = TRUE) / 100), 2),
             retorno_anual_pct = round(100 * ((prod(1 + r))^(12 / length(r)) - 1), 2),
             volatilidad_anual_pct = round(100 * sd(r) * sqrt(12), 2),
             peor_12m_pct = round(100 * min(a), 2), p5_12m_pct = round(100 * quantile(a, 0.05), 2),
             pct_ventanas_12m_negativas = round(100 * mean(a < 0), 1),
             max_caida_pct = round(100 * dd(r), 2), meses = length(r))
}))
guardar_tabla(resumen, "resumen_estrategias"); print(resumen, row.names = FALSE)

por_reg <- do.call(rbind, lapply(REG, function(g) do.call(rbind, lapply(ESTd, function(k) {
  a <- R12[[k]][R12$regimen == g]; a <- a[!is.na(a)]; c0 <- R12$caja[R12$regimen == g]; c0 <- c0[!is.na(a)]
  data.frame(regimen = g, estrategia = NOMBRE[k], n_ventanas = length(a),
             media_12m_pct = round(100 * mean(a), 2), p5_12m_pct = round(100 * quantile(a, 0.05), 2),
             p95_12m_pct = round(100 * quantile(a, 0.95), 2),
             exceso_vs_caja_pb = round(10000 * mean(a - R12$caja[R12$regimen == g][!is.na(R12[[k]][R12$regimen == g])]), 0))
}))))
guardar_tabla(por_reg, "retorno_12m_por_regimen_fed"); print(por_reg, row.names = FALSE)

# Figura 1: retorno a 12 meses por estrategia y régimen de la Fed ------------------------
f1 <- por_reg; f1$estrategia <- factor(f1$estrategia, levels = NOMBRE[ESTd]); f1$regimen <- factor(f1$regimen, levels = REG)
g1 <- ggplot(f1, aes(estrategia, media_12m_pct, fill = regimen)) + geom_hline(yintercept = 0, colour = "grey50") +
  geom_col(position = position_dodge(0.8), width = 0.75) +
  geom_errorbar(aes(ymin = p5_12m_pct, ymax = p95_12m_pct), position = position_dodge(0.8), width = 0, colour = "grey30", linewidth = 0.4) +
  scale_fill_manual(values = c("#1b6ca8", "#b9cfe0", "#d1495b")) +
  labs(title = "Alargar la duración paga cuando la Fed recorta y cuesta cuando sube",
       subtitle = sprintf("Retorno a 12 meses por estrategia según lo que hizo la Fed en esos 12 meses (%%). Línea: percentiles 5 a 95. %s a %s",
                          format(min(ret$mes), "%Y"), format(max(ret$mes), "%Y")),
       x = NULL, y = "Retorno a 12 meses (%)", fill = NULL,
       caption = "Estrategias de vencimiento constante rebalanceadas cada mes, con rendimientos genéricos del Tesoro (Bloomberg). Caja = EFFR.") + tema_limpio()
guardar_fig(g1, "retorno_12m_por_regimen", ancho = 10, alto = 5.5)

# Figura 2: retorno medio vs peor caso (percentil 5) ---------------------------------------
f2 <- resumen; f2$estrategia <- factor(f2$estrategia, levels = NOMBRE[ESTd])
g2 <- ggplot(f2, aes(p5_12m_pct, retorno_anual_pct, label = estrategia)) +
  geom_path(colour = "grey70") + geom_point(size = 3, colour = "#0b3c5d") +
  geom_text(nudge_y = 0.08, size = 3.3, family = FUENTE) +
  labs(title = "Cuánto retorno se gana por cada punto de riesgo de pérdida",
       subtitle = "Retorno anual promedio vs percentil 5 del retorno a 12 meses (peor año en 1 de cada 20)",
       x = "Percentil 5 del retorno a 12 meses (%)", y = "Retorno anual promedio (%)") + tema_limpio()
guardar_fig(g2, "retorno_vs_riesgo", ancho = 8, alto = 5)

# Figura 3: exceso de retorno a 12 meses de 1 y 2 años sobre caja, en el tiempo ---------------
f3 <- rbind(data.frame(inicio = R12$inicio, estrategia = "1 año", ex = 100 * (R12$y1y - R12$caja)),
            data.frame(inicio = R12$inicio, estrategia = "2 años", ex = 100 * (R12$y2y - R12$caja)))
g3 <- ggplot(f3, aes(inicio, ex, colour = estrategia)) + geom_hline(yintercept = 0, colour = "grey50") +
  geom_line(linewidth = 0.5) + scale_colour_manual(values = c("#3b9ab2", "#0b3c5d")) +
  labs(title = "Exceso de retorno a 12 meses sobre la caja", subtitle = "Puntos porcentuales; fecha = inicio de la ventana de 12 meses",
       x = NULL, y = "pp", colour = NULL) + tema_limpio()
guardar_fig(g3, "exceso_vs_caja_tiempo", ancho = 10, alto = 4.5)

write.csv(ret, ruta("output", "tablas", "retornos_mensuales_estrategias.csv"), row.names = FALSE)
message(sprintf("Meses con 1 año interpolado (hueco 2001-08 a 2008-06): %d", n_hueco))
