# 09_sorpresas_eventos.R ------------------------------------------------
# Sorpresas de política medidas con futuros de fed funds y estudio de eventos diario.
#
# 1) Sorpresa "target" (Kuttner 2001): cambio en la tasa implícita del futuro del
#    mes en curso el día del anuncio, escalado por los días que faltan del mes:
#       sorpresa = (D / (D − d)) × Δ(100 − FF1)
#    d = día del mes del anuncio, D = días del mes. En los últimos 7 días del mes se
#    usa el cambio del futuro del mes siguiente (FF2) sin escalar. Si el anuncio cae
#    el primer día hábil del mes, el precio de la víspera se toma del FF2 (el genérico
#    FF1 ya rotó de contrato).
# 2) Sorpresa "path" (trayectoria; idea de Gürkaynak, Sack y Swanson 2005): cambio
#    en la tasa implícita del futuro a 3 meses (FF4) el día del anuncio, menos la
#    parte explicada por la sorpresa target (residuo de una regresión). Captura la
#    guía futura y funciona también en el límite inferior cero.
# 3) Estudio de eventos: Δ rendimiento (pb, cierre a cierre) en cada tramo contra
#    las sorpresas; asimetría alza/recorte; esperado vs inesperado (Kuttner);
#    persistencia diaria (proyecciones locales h = 0…20 días hábiles); respuesta de la EFFR.
# Ventana diaria (cierre de la víspera al cierre del día): incluye otras noticias del
# día; con datos intradía la ventana sería más limpia (30 min, GSS), pero Bloomberg
# no guarda historia intradía tan larga.

local({
  # Busca el utils.R de ESTA carpeta (var-tasas-fed), sin importar dónde esté parado RStudio
  cand <- c(if (file.exists("var-tasas-fed.Rproj")) "R/utils.R", "var-tasas-fed/R/utils.R", "../var-tasas-fed/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/var-tasas-fed/R/utils.R")
  source(cand[file.exists(cand)][1])
})
suppressPackageStartupMessages({ library(ggplot2); library(patchwork); library(sandwich) })

# Datos diarios ---------------------------------------------------------------
raw <- read.csv(ruta("data", "raw", "bloomberg_tasas.csv"), stringsAsFactors = FALSE)
fut <- read.csv(ruta("data", "raw", "bloomberg_futuros.csv"), stringsAsFactors = FALSE)
diario <- rbind(raw[raw$frecuencia == "DAILY", c("fecha", "var", "valor")], fut[, c("fecha", "var", "valor")])
diario$fecha <- as.Date(diario$fecha)
D <- reshape(diario, idvar = "fecha", timevar = "var", direction = "wide")
names(D) <- sub("^valor\\.", "", names(D))
D <- D[order(D$fecha), ]
D <- D[!is.na(D$y2y) & !is.na(D$ff1), ]                  # días hábiles con curva y futuros
rownames(D) <- NULL
for (k in grep("^ff[0-9]$", names(D), value = TRUE)) D[[paste0("r", k)]] <- 100 - D[[k]]   # tasa implícita

fomc <- read.csv(ruta("data", "fomc_fechas.csv"), stringsAsFactors = FALSE)
fomc$fecha <- as.Date(fomc$fecha)
fomc <- fomc[fomc$fecha >= as.Date("1994-01-01") & fomc$fecha <= max(D$fecha), ]

# Sorpresas -----------------------------------------------------------------
TRAMOS <- c("y3m", "y6m", "y2y", "y5y", "y10y", "y30y")
ev <- do.call(rbind, lapply(seq_len(nrow(fomc)), function(i) {
  t <- which(D$fecha >= fomc$fecha[i])[1]                 # primer día hábil desde el anuncio
  if (is.na(t) || t < 2) return(NULL)
  f0 <- D[t - 1, ]; f1 <- D[t, ]
  dia <- as.numeric(format(f1$fecha, "%d"))
  dmes <- as.numeric(format(seq(as.Date(format(f1$fecha, "%Y-%m-01")), by = "month", length.out = 2)[2] - 1, "%d"))
  nuevo_mes <- format(f0$fecha, "%m") != format(f1$fecha, "%m")
  # tasa implícita de la víspera para el mismo contrato
  prev <- function(k) if (nuevo_mes) f0[[paste0("rff", k + 1)]] else f0[[paste0("rff", k)]]
  if (dmes - dia < 7) {
    target <- f1$rff2 - prev(2)                              # últimos 7 días: contrato del mes siguiente
  } else {
    target <- (dmes / (dmes - dia)) * (f1$rff1 - prev(1))
  }
  ff4 <- if (!is.null(f1$rff4)) f1$rff4 - prev(4) else NA
  out <- data.frame(fecha_anuncio = fomc$fecha[i], fecha_evento = f1$fecha, tipo = fomc$tipo[i],
                    excluir_base = fomc$excluir_base[i], target_pb = 100 * target, ff4_pb = 100 * ff4,
                    cambio_meta_pb = 100 * (f1$ffr_meta - f0$ffr_meta))
  for (v in TRAMOS) out[[paste0("d_", v)]] <- 100 * (f1[[v]] - f0[[v]])
  # EFFR: se toma de la víspera al día siguiente (el nuevo objetivo rige desde el día hábil posterior)
  out$d_effr <- if (t + 1 <= nrow(D)) 100 * (D$ffr[t + 1] - f0$ffr) else NA
  out$idx <- t
  out
}))
ev$excluir_base <- as.logical(ev$excluir_base)
ev$periodo <- ifelse(ev$fecha_evento <= as.Date("2007-12-31"), "1994-2007",
               ifelse(ev$fecha_evento <= as.Date("2015-11-30") | (ev$fecha_evento >= as.Date("2020-03-01") & ev$fecha_evento <= as.Date("2022-02-28")),
                      "2008-2015 y 2020-2022 (crisis y ZLB)", "2016-2019 y 2022-2026"))
# Sorpresa path: FF4 ortogonalizado respecto de target (muestra base)
b <- ev[!ev$excluir_base & !is.na(ev$ff4_pb), ]
mp <- lm(ff4_pb ~ target_pb, data = b)
ev$path_pb <- ev$ff4_pb - predict(mp, newdata = ev)
write.csv(ev, ruta("data", "sorpresas_fomc.csv"), row.names = FALSE)
message(sprintf("Eventos FOMC: %d (%d programados, %d no programados; %d excluidos de la base).",
                nrow(ev), sum(ev$tipo == "programada"), sum(ev$tipo != "programada"), sum(ev$excluir_base)))

desc <- aggregate(cbind(target_pb, path_pb) ~ periodo, data = ev[!ev$excluir_base, ],
                  FUN = function(x) c(n = length(x), sd = round(sd(x), 1), min = round(min(x), 1), max = round(max(x), 1)))
desc <- do.call(data.frame, desc); guardar_tabla(desc, "sorpresas_descripcion"); print(desc)

# Estudio de eventos --------------------------------------------------------------
reg <- function(dat, y, x) {
  f <- as.formula(paste(y, "~", paste(x, collapse = " + ")))
  m <- lm(f, data = dat); V <- vcovHC(m, type = "HC1")
  data.frame(variable = sub("^d_", "", y), regresor = x, coef = coef(m)[x], se = sqrt(diag(V))[x],
             n = nobs(m), R2 = summary(m)$r.squared, row.names = NULL)
}
base_ev <- ev[!ev$excluir_base, ]
muestras <- list("1994-2007" = base_ev[base_ev$periodo == "1994-2007", ],
                 "2008-2026" = base_ev[base_ev$periodo != "1994-2007", ],
                 "Completa"  = base_ev)
ys <- paste0("d_", c(TRAMOS, "effr"))
est <- do.call(rbind, lapply(names(muestras), function(mu)
  do.call(rbind, lapply(ys, function(y) cbind(muestra = mu, reg(muestras[[mu]], y, c("target_pb", "path_pb")))))))
est$efecto_por_25pb <- 25 * est$coef; est$ic90_lo <- 25 * (est$coef - 1.645 * est$se); est$ic90_hi <- 25 * (est$coef + 1.645 * est$se)
guardar_tabla(est, "eventos_coeficientes")
print(transform(est[est$variable != "effr", c("muestra", "variable", "regresor", "efecto_por_25pb", "n", "R2")],
                efecto_por_25pb = round(efecto_por_25pb, 1), R2 = round(R2, 2)), row.names = FALSE)

# Figura: efecto por tramo
fe <- est[est$variable %in% TRAMOS, ]
fe$variable <- factor(etiq(fe$variable), levels = etiq(TRAMOS))
fe$regresor <- factor(ifelse(fe$regresor == "target_pb", "Sorpresa target (tasa de hoy)", "Sorpresa path (trayectoria)"),
                      levels = c("Sorpresa target (tasa de hoy)", "Sorpresa path (trayectoria)"))
g1 <- ggplot(fe, aes(variable, efecto_por_25pb, colour = regresor)) +
  geom_hline(yintercept = 0, colour = "grey50") +
  geom_pointrange(aes(ymin = ic90_lo, ymax = ic90_hi), position = position_dodge(width = 0.5), size = 0.4) +
  facet_wrap(~muestra) + scale_colour_manual(values = c("#d1495b", "#1b6ca8")) +
  labs(title = "Respuesta de la curva el día del anuncio del FOMC a una sorpresa de 25 pb",
       subtitle = "Estudio de eventos con futuros de fed funds; intervalos de 90% (errores robustos HC1)",
       x = NULL, y = "Puntos básicos", colour = NULL,
       caption = "Ventana diaria (cierre a cierre). Excluye 2001-09-17, 2007-08-17 y 2020-03-16. Fuente: Bloomberg (FF1-FF4, USGG*), calendario FOMC.") +
  tema_limpio()
guardar_fig(g1, "eventos_efecto_por_tramo", ancho = 10, alto = 5)

# Dispersión: sorpresa target vs Δ2Y y Δ10Y (1994-2007)
sc <- muestras[["1994-2007"]]
dd <- rbind(data.frame(x = sc$target_pb, y = sc$d_y2y, tramo = "2Y"), data.frame(x = sc$target_pb, y = sc$d_y10y, tramo = "10Y"))
dd$tramo <- factor(dd$tramo, levels = c("2Y", "10Y"))
g2 <- ggplot(dd, aes(x, y)) + geom_hline(yintercept = 0, colour = "grey80") + geom_vline(xintercept = 0, colour = "grey80") +
  geom_point(colour = "#0b3c5d", alpha = 0.6, size = 1.6) + geom_smooth(method = "lm", formula = y ~ x, colour = "#d1495b", fill = "#d1495b", alpha = 0.15) +
  facet_wrap(~tramo) + labs(title = "Sorpresa target y cambio del rendimiento el día del FOMC (1994-2007)",
                            x = "Sorpresa target (pb)", y = "Cambio del rendimiento (pb)") + tema_limpio()
guardar_fig(g2, "eventos_dispersion_target", ancho = 9, alto = 4.5)

# Kuttner: cambio esperado vs inesperado de la meta (hasta 2008-12, antes del rango)
ku <- base_ev[base_ev$fecha_evento <= as.Date("2008-12-15"), ]
ku$inesperado_pb <- ku$target_pb; ku$esperado_pb <- ku$cambio_meta_pb - ku$target_pb
kt <- do.call(rbind, lapply(ys, function(y) reg(ku, y, c("esperado_pb", "inesperado_pb"))))
kt$efecto_por_25pb <- round(25 * kt$coef, 1); kt$t <- round(kt$coef / kt$se, 1)
guardar_tabla(kt, "eventos_kuttner_esperado_inesperado")
print(kt[, c("variable", "regresor", "efecto_por_25pb", "t", "n")], row.names = FALSE)

# Asimetría: sorpresas positivas vs negativas (1994-2007, donde la sorpresa target tiene variación)
asim <- muestras[["1994-2007"]]
asim$target_pos <- pmax(asim$target_pb, 0); asim$target_neg <- pmin(asim$target_pb, 0)
at <- do.call(rbind, lapply(ys, function(y) {
  m <- lm(as.formula(paste(y, "~ target_pos + target_neg + path_pb")), data = asim)
  V <- vcovHC(m, type = "HC1"); b <- coef(m)
  dif <- b["target_pos"] - b["target_neg"]; sd_dif <- sqrt(V["target_pos", "target_pos"] + V["target_neg", "target_neg"] - 2 * V["target_pos", "target_neg"])
  data.frame(variable = sub("^d_", "", y), alza_25pb = round(25 * b["target_pos"], 1), recorte_25pb = round(-25 * b["target_neg"], 1),
             p_simetria = round(2 * pnorm(-abs(dif / sd_dif)), 3), n_pos = sum(asim$target_pb > 0), n_neg = sum(asim$target_pb < 0), row.names = NULL)
}))
guardar_tabla(at, "eventos_asimetria"); print(at, row.names = FALSE)

# Persistencia: proyecciones locales diarias en días de evento -----------------------
HD <- 20
lpd <- do.call(rbind, lapply(names(muestras)[c(1, 3)], function(mu) {
  e <- muestras[[mu]]
  do.call(rbind, lapply(TRAMOS, function(v) do.call(rbind, lapply(0:HD, function(h) {
    ok <- e$idx + h <= nrow(D)
    dy <- 100 * (D[[v]][e$idx[ok] + h] - D[[v]][e$idx[ok] - 1])
    m <- lm(dy ~ target_pb + path_pb, data = e[ok, ]); V <- vcovHC(m, type = "HC1")
    data.frame(muestra = mu, variable = v, h = h,
               regresor = c("target", "path"), b25 = 25 * coef(m)[2:3], se25 = 25 * sqrt(diag(V))[2:3])
  }))))
}))
guardar_tabla(lpd, "eventos_persistencia_diaria")
lpd$variable <- factor(etiq(lpd$variable), levels = etiq(TRAMOS))
lpd$regresor <- ifelse(lpd$regresor == "target", "Sorpresa target", "Sorpresa path")
g3 <- ggplot(lpd[lpd$muestra == "1994-2007", ], aes(h, b25, colour = regresor, fill = regresor)) +
  geom_hline(yintercept = 0, colour = "grey50") +
  geom_ribbon(aes(ymin = b25 - 1.645 * se25, ymax = b25 + 1.645 * se25), alpha = 0.15, colour = NA) +
  geom_line(linewidth = 0.8) + facet_wrap(~variable, ncol = 3) +
  scale_colour_manual(values = c("#1b6ca8", "#d1495b")) + scale_fill_manual(values = c("#1b6ca8", "#d1495b")) +
  labs(title = "¿Persiste el efecto? Respuesta acumulada en los 20 días hábiles siguientes (1994-2007)",
       subtitle = "Por sorpresa de 25 pb; intervalos de 90%", x = "Días hábiles después del anuncio", y = "Puntos básicos",
       colour = NULL, fill = NULL) + tema_limpio()
guardar_fig(g3, "eventos_persistencia_diaria", ancho = 10, alto = 6)

# Serie de sorpresas
gs <- ggplot(ev, aes(fecha_evento)) + geom_hline(yintercept = 0, colour = "grey60") +
  geom_rect(data = ZLB, aes(xmin = ini, xmax = fin, ymin = -Inf, ymax = Inf), inherit.aes = FALSE, fill = "grey88") +
  geom_segment(aes(xend = fecha_evento, y = 0, yend = target_pb), colour = "#d1495b") +
  geom_point(aes(y = path_pb), colour = "#1b6ca8", size = 0.9) +
  labs(title = "Sorpresas de política en cada anuncio del FOMC", subtitle = "Barras rojas = target; puntos azules = path. Sombra = ZLB",
       x = NULL, y = "Puntos básicos") + tema_limpio()
guardar_fig(gs, "sorpresas_serie", ancho = 10, alto = 4)

# Sorpresas mensuales para el proxy SVAR (ponderación de Gertler y Karadi 2015) ----------
# Las tasas del VAR son promedios mensuales: una sorpresa el día d de un mes de D días
# afecta solo (D − d + 1)/D del promedio de ese mes y el resto, (d − 1)/D, del mes
# siguiente. Sumar las sorpresas sin ponderar da un instrumento débil (F ≈ 2).
evb <- ev[!ev$excluir_base, ]
meses <- seq(as.Date("1994-01-01"), as.Date(format(max(ev$fecha_evento), "%Y-%m-01")), by = "month")
pondera <- function(col) {
  z <- setNames(rep(0, length(meses)), as.character(meses))
  for (i in seq_len(nrow(evb))) {
    s <- evb[[col]][i]; if (is.na(s)) next
    f <- evb$fecha_evento[i]; m <- as.Date(format(f, "%Y-%m-01")); m2 <- seq(m, by = "month", length.out = 2)[2]
    Dm <- as.numeric(format(m2 - 1, "%d")); d <- as.numeric(format(f, "%d"))
    z[as.character(m)] <- z[as.character(m)] + s * (Dm - d + 1) / Dm
    if (as.character(m2) %in% names(z)) z[as.character(m2)] <- z[as.character(m2)] + s * (d - 1) / Dm
  }
  unname(z)
}
zm <- data.frame(fecha = meses, target_pb = pondera("target_pb"), ff4_pb = pondera("ff4_pb"), path_pb = pondera("path_pb"))
write.csv(zm, ruta("data", "sorpresas_mensuales.csv"), row.names = FALSE)
