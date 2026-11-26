# 12_factores_curva.R ---------------------------------------------------
# La curva del Tesoro resumida en tres factores y su relación con la macro y la Fed.
# Base: Diebold y Li (2006) y Diebold, Rudebusch y Aruoba (2006, "DRA").
#
# Paso 1. Factores de Nelson-Siegel, mes a mes, por MCO de corte transversal:
#   y(τ) = L + S·[(1−e^{−λτ})/(λτ)] + C·[(1−e^{−λτ})/(λτ) − e^{−λτ}],  τ en meses
#   λ = 0.0609 (Diebold-Li: la carga de la curvatura es máxima en 30 meses).
#   L = nivel, S = "pendiente" (≈ corto − largo), C = curvatura (tramo medio).
#   Aquí se reporta PENDIENTE = −S (≈ largo − corto), positiva cuando la curva sube con el plazo.
# Paso 2. VAR mensual con [desempleo, inflación, EFFR, nivel, pendiente, curvatura].
#   Orden Cholesky: la macro (lenta) no reacciona dentro del mes a la Fed ni a la curva;
#   la EFFR reacciona a la macro; la curva (rápida) reacciona a todo dentro del mes.
#   Choque de política alternativo: instrumento externo con sorpresas de futuros (script 09).
# Si existe data/raw/bloomberg_vix.csv (script 13), el VIX entra después de la EFFR y antes
# de la curva: reacciona dentro del mes a la macro y a la Fed, y la curva reacciona a él
# (fuga hacia la calidad). La muestra empieza en 1990 (inicio del VIX).
# Preguntas: ¿qué mueve el nivel, la pendiente y la curvatura? ¿cuánto pesa cada fuente?
# ¿qué explicó los grandes movimientos de la curva (p. ej., 2022-2023)?

local({
  cand <- c("R/utils.R", "var-tasas-fed/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/var-tasas-fed/R/utils.R")
  source(cand[file.exists(cand)][1])
})
source(ruta("R", "var_funciones.R"))
suppressPackageStartupMessages({ library(ggplot2); library(patchwork) })

NBOOT <- as.numeric(Sys.getenv("NBOOT", 1000)); H <- 48; LAMBDA <- 0.0609

base <- read.csv(ruta("data", "base_mensual.csv")); base$fecha <- as.Date(base$fecha)

# Plazos adicionales y macro del script 11 (si existen) --------------------------
for (extra in ruta("data", "raw", c("bloomberg_curva_macro.csv", "bloomberg_vix.csv"))) if (file.exists(extra)) {
  x <- read.csv(extra, stringsAsFactors = FALSE); x$fecha <- as.Date(x$fecha)
  x$mes <- as.Date(format(x$fecha, "%Y-%m-01"))
  mes_desc <- as.Date(format(as.Date(max(x$fecha_descarga)), "%Y-%m-01"))
  x <- x[!(x$frecuencia == "DAILY" & x$mes >= mes_desc), ]
  xm <- aggregate(valor ~ var + mes, data = x, FUN = mean)
  xm <- reshape(xm, idvar = "mes", timevar = "var", direction = "wide"); names(xm) <- sub("^valor\\.", "", names(xm))
  names(xm)[names(xm) == "mes"] <- "fecha"
  base <- merge(base, xm, by = "fecha", all.x = TRUE)
  message("Usando plazos/macro adicionales: ", paste(setdiff(names(xm), "fecha"), collapse = ", "))
}
base <- base[order(base$fecha), ]

# Paso 1: factores de Nelson-Siegel -------------------------------------------------
PLAZOS <- c(y3m = 3, y6m = 6, y1y = 12, y2y = 24, y3y = 36, y5y = 60, y7y = 84, y10y = 120, y20y = 240, y30y = 360)
PLAZOS <- PLAZOS[names(PLAZOS) %in% names(base)]
carga <- function(tau, l = LAMBDA) cbind(1, (1 - exp(-l * tau)) / (l * tau), (1 - exp(-l * tau)) / (l * tau) - exp(-l * tau))

Y <- as.matrix(base[, names(PLAZOS)])
fac <- t(sapply(seq_len(nrow(Y)), function(t) {
  ok <- !is.na(Y[t, ]); if (sum(ok) < 4) return(c(NA, NA, NA))
  X <- carga(PLAZOS[ok]); qr.solve(X, Y[t, ok])
}))
colnames(fac) <- c("nivel", "S", "curvatura")
base$nivel <- fac[, "nivel"]; base$pendiente <- -fac[, "S"]; base$curvatura <- fac[, "curvatura"]

ajuste <- sapply(seq_len(nrow(Y)), function(t) carga(PLAZOS) %*% fac[t, ])
err <- (Y - t(ajuste)) * 100
rmse <- data.frame(plazo = etiq(names(PLAZOS)), meses = PLAZOS, n = colSums(!is.na(err)),
                   rmse_pb = round(sqrt(colMeans(err^2, na.rm = TRUE)), 1),
                   error_medio_pb = round(colMeans(err, na.rm = TRUE), 1))
guardar_tabla(rmse, "ns_ajuste_por_plazo"); print(rmse, row.names = FALSE)

# Validación: factores vs medidas empíricas (DRA)
base$emp_nivel <- base$y10y; base$emp_pend <- base$y10y - base$y3m; base$emp_curv <- 2 * base$y2y - base$y3m - base$y10y
val <- data.frame(factor = c("Nivel vs 10Y", "Pendiente vs 10Y−3M", "Curvatura vs 2·2Y−3M−10Y"),
                  correlacion = round(c(cor(base$nivel, base$emp_nivel, use = "c"), cor(base$pendiente, base$emp_pend, use = "c"),
                                        cor(base$curvatura, base$emp_curv, use = "c")), 3))
guardar_tabla(val, "ns_validacion_factores"); print(val, row.names = FALSE)
write.csv(base[, c("fecha", "nivel", "pendiente", "curvatura")], ruta("data", "factores_ns.csv"), row.names = FALSE)

# Figura de factores
fl <- rbind(data.frame(fecha = base$fecha, f = "Nivel", ns = base$nivel, emp = base$emp_nivel, lbl = "10Y"),
            data.frame(fecha = base$fecha, f = "Pendiente", ns = base$pendiente, emp = base$emp_pend, lbl = "10Y−3M"),
            data.frame(fecha = base$fecha, f = "Curvatura", ns = base$curvatura, emp = base$emp_curv, lbl = "2·2Y−3M−10Y"))
fl$f <- factor(fl$f, levels = c("Nivel", "Pendiente", "Curvatura"))
g <- ggplot(fl, aes(fecha)) +
  geom_rect(data = ZLB, aes(xmin = ini, xmax = fin, ymin = -Inf, ymax = Inf), inherit.aes = FALSE, fill = "grey88") +
  geom_hline(yintercept = 0, colour = "grey60") +
  geom_line(aes(y = emp, colour = "Medida empírica"), linewidth = 0.4) +
  geom_line(aes(y = ns, colour = "Factor Nelson-Siegel"), linewidth = 0.7) +
  facet_wrap(~f, ncol = 1, scales = "free_y") + scale_colour_manual(values = c("#0b3c5d", "#e1a33b")) +
  labs(title = "Los tres factores de la curva del Tesoro", subtitle = sprintf("Nelson-Siegel con λ = %.4f; medidas empíricas: 10Y, 10Y−3M y 2·2Y−3M−10Y. Sombra = ZLB", LAMBDA),
       x = NULL, y = "%", colour = NULL, caption = sprintf("Plazos usados: %s. Fuente: Bloomberg.", paste(etiq(names(PLAZOS)), collapse = ", "))) +
  tema_limpio()
guardar_fig(g, "ns_factores", ancho = 9, alto = 8)

# Paso 2: VAR macro-curva -------------------------------------------------------------
base$inflacion <- base$cpi - c(rep(NA, 12), head(base$cpi, -12))     # IPC, variación interanual (%)
ETIQ[c("nivel", "pendiente", "curvatura", "inflacion", "unemp")] <- c("Nivel", "Pendiente", "Curvatura", "Inflación (IPC, % a/a)", "Desempleo (%)")
CON_VIX <- "vix" %in% names(base)
ETIQ["vix"] <- "VIX"
VARS <- c("unemp", "inflacion", "ffr", if (CON_VIX) "vix", "nivel", "pendiente", "curvatura")
CHOQUES <- c("inflacion", "unemp", "ffr", if (CON_VIX) "vix")
NOMBRE_CHOQUE <- c(unemp = "Desempleo", inflacion = "Inflación", ffr = "Política (EFFR)", vix = "Riesgo (VIX)",
                   nivel = "Nivel (propio)", pendiente = "Pendiente (propio)", curvatura = "Curvatura (propio)")[VARS]
INICIO <- if (CON_VIX) "1990-02-01" else "1989-01-01"

estimar_mc <- function(desde, hasta) {
  hasta <- if (is.na(hasta)) max(base$fecha) else as.Date(hasta)
  d <- base[base$fecha >= as.Date(desde) & base$fecha <= hasta, c("fecha", VARS)]
  d <- d[complete.cases(d), ]
  Ym <- as.matrix(d[, VARS])
  ic <- seleccion_rezagos(Ym, 8); sel <- sapply(ic[, c("AIC", "BIC", "HQ")], which.min)
  p <- min(max(sel[["HQ"]], 2), 6)
  v <- var_ols(Ym, p)
  message(sprintf("VAR macro-curva %s a %s: T=%d, p=%d (AIC=%d, BIC=%d, HQ=%d), raíz máx.=%.3f",
                  format(d$fecha[1], "%Y-%m"), format(max(d$fecha), "%Y-%m"), v$TT, p, sel[["AIC"]], sel[["BIC"]], sel[["HQ"]], max(raices(v))))
  list(d = d, v = v, p = p)
}
MC <- list(A = estimar_mc(INICIO, "2007-12-01"), B = estimar_mc(INICIO, NA))
PER <- c(A = paste0(substr(INICIO, 1, 4), "-2007"), B = paste0(substr(INICIO, 1, 4), "-", format(max(base$fecha), "%Y")))

# IRF de los factores a cada choque macro (1 d.e.; política normalizada a +25 pb)
irf_mc <- function(m, k) {
  out <- lapply(CHOQUES, function(s) {
    j <- which(VARS == s)
    esc <- if (s == "ffr") 0.25 else sqrt(m$v$Sigma[j, j])          # macro: 1 desviación estándar
    ib <- irf_bootstrap(m$v, H, choque = j, escala = esc, nboot = NBOOT)
    cbind(espec = k, choque = s, tamano = esc, irf_tabla(ib))
  })
  do.call(rbind, out)
}
IRF <- rbind(irf_mc(MC$A, "A"), irf_mc(MC$B, "B"))
guardar_tabla(IRF, "mc_irf_factores")

fig_irf <- function(k) {
  d <- IRF[IRF$espec == k & IRF$variable %in% c("nivel", "pendiente", "curvatura"), ]
  tam <- unique(d[, c("choque", "tamano")])
  lab <- setNames(sprintf("%s\n(%s)", c(unemp = "Desempleo", inflacion = "Inflación", ffr = "Política", vix = "Riesgo (VIX)")[tam$choque],
                          ifelse(tam$choque == "ffr", "+25 pb", ifelse(tam$choque == "vix", sprintf("+%.1f puntos, 1 d.e.", tam$tamano),
                                                                    sprintf("+%.2f pp, 1 d.e.", tam$tamano)))), tam$choque)
  d$choque <- factor(lab[d$choque], levels = lab[CHOQUES])
  d$variable <- factor(etiq(d$variable), levels = etiq(c("nivel", "pendiente", "curvatura")))
  ggplot(d, aes(h)) + geom_hline(yintercept = 0, colour = "grey50", linewidth = 0.3) +
    geom_ribbon(aes(ymin = 100 * q05, ymax = 100 * q95), fill = "#1b6ca8", alpha = 0.15) +
    geom_ribbon(aes(ymin = 100 * q16, ymax = 100 * q84), fill = "#1b6ca8", alpha = 0.3) +
    geom_line(aes(y = 100 * irf), colour = "#0b3c5d", linewidth = 0.8) +
    facet_grid(variable ~ choque, scales = "free_y") +
    labs(title = sprintf("¿Qué mueve la curva? Respuesta de los factores a cada choque (%s)", PER[[k]]),
         subtitle = "Puntos básicos. Bandas bootstrap 68% y 90%", x = "Meses después del choque", y = "Puntos básicos",
         caption = sprintf("VAR(%d) [%s], Cholesky en ese orden. Fuente: Bloomberg.", MC[[k]]$p, paste(etiq(VARS), collapse = ", "))) +
    tema_limpio(9)
}
guardar_fig(fig_irf("A"), "mc_irf_factores_A", ancho = 10, alto = 7.5)
guardar_fig(fig_irf("B"), "mc_irf_factores_B", ancho = 10, alto = 7.5)

# Desplazamiento de toda la curva: Δy(τ) = ΔL + ΔS·carga2 − ... (con pendiente = −S)
taus <- c(3, 6, 12, 24, 36, 60, 84, 120, 180, 240, 300, 360)
curva_resp <- function(k, hs = c(0, 6, 12, 24)) {
  d <- IRF[IRF$espec == k, ]
  do.call(rbind, lapply(CHOQUES, function(s) do.call(rbind, lapply(hs, function(h) {
    f <- sapply(c("nivel", "pendiente", "curvatura"), function(v) d$irf[d$choque == s & d$variable == v & d$h == h])
    L <- carga(taus)
    data.frame(espec = k, choque = s, h = h, tau = taus, dy_pb = 100 * (L[, 1] * f[1] - L[, 2] * f[2] + L[, 3] * f[3]))
  }))))
}
CR <- rbind(curva_resp("A"), curva_resp("B")); guardar_tabla(CR, "mc_desplazamiento_curva")
fig_curva <- function(k) {
  d <- CR[CR$espec == k, ]
  nm <- c(inflacion = "Inflación (1 d.e.)", unemp = "Desempleo (1 d.e.)", ffr = "Política (+25 pb)", vix = "Riesgo: VIX (1 d.e.)")[CHOQUES]
  d$choque <- factor(nm[d$choque], levels = nm)
  d$h <- factor(paste0("h = ", d$h, " meses"), levels = paste0("h = ", c(0, 6, 12, 24), " meses"))
  ggplot(d, aes(tau / 12, dy_pb, colour = h)) + geom_hline(yintercept = 0, colour = "grey50") +
    geom_line(linewidth = 0.8) + geom_point(size = 1) + facet_wrap(~choque, scales = "free_y") +
    scale_colour_manual(values = c("#0b3c5d", "#1b6ca8", "#e1a33b", "#d1495b")) +
    scale_x_continuous(breaks = c(0.25, 2, 5, 10, 20, 30), labels = c("3M", "2Y", "5Y", "10Y", "20Y", "30Y")) +
    labs(title = sprintf("Cómo se desplaza la curva ante cada choque (%s)", PER[[k]]),
         subtitle = "Cambio del rendimiento por plazo, reconstruido con los factores de Nelson-Siegel",
         x = "Plazo", y = "Puntos básicos", colour = NULL) + tema_limpio()
}
guardar_fig(fig_curva("A"), "mc_desplazamiento_curva_A", ancho = 10, alto = 4.5)
guardar_fig(fig_curva("B"), "mc_desplazamiento_curva_B", ancho = 10, alto = 4.5)

# FEVD: ¿cuánto de cada factor explica cada fuente? (y al revés: ¿la curva anticipa la macro?)
FV <- do.call(rbind, lapply(names(MC), function(k) {
  f <- fevd_chol(MC[[k]]$v, c(12, 48)); cbind(espec = k, f)
}))
guardar_tabla(FV, "mc_fevd")
fv <- FV[FV$variable %in% c("nivel", "pendiente", "curvatura", "inflacion", "unemp"), ]
fl <- do.call(rbind, lapply(VARS, function(s) data.frame(espec = fv$espec, horizonte = fv$horizonte, variable = fv$variable,
                                                       fuente = unname(NOMBRE_CHOQUE[s]), pct = 100 * fv[[paste0("choque_", s)]], row.names = NULL)))
fl$fuente <- factor(fl$fuente, levels = unname(NOMBRE_CHOQUE))
fl$variable <- factor(etiq(fl$variable), levels = etiq(c("nivel", "pendiente", "curvatura", "inflacion", "unemp")))
fl$panel <- paste0(PER[fl$espec], " · ", fl$horizonte, " meses")
g <- ggplot(fl, aes(variable, pct, fill = fuente)) + geom_col(width = 0.7) + facet_wrap(~panel, ncol = 2) +
  scale_fill_manual(values = c(unemp = "#6a3d9a", inflacion = "#d1495b", ffr = "#0b3c5d", vix = "#e1a33b",
                               nivel = "#b9cfe0", pendiente = "#8ab0cc", curvatura = "#dce8f1")[VARS], labels = unname(NOMBRE_CHOQUE)) +
  coord_flip() + labs(title = "¿De dónde vienen los movimientos de la curva? Descomposición de varianza",
                      subtitle = "Porcentaje de la varianza del error de pronóstico explicado por cada choque",
                      x = NULL, y = "%", fill = NULL) + tema_limpio() + guides(fill = guide_legend(nrow = 2))
guardar_fig(g, "mc_fevd", ancho = 10, alto = 6.5)
tab_fv <- reshape(fl[fl$variable %in% etiq(c("nivel", "pendiente", "curvatura")), c("panel", "variable", "fuente", "pct")],
                  idvar = c("panel", "variable"), timevar = "fuente", direction = "wide")
names(tab_fv) <- sub("^pct\\.", "", names(tab_fv)); tab_fv[, -(1:2)] <- round(tab_fv[, -(1:2)], 1)
guardar_tabla(tab_fv, "mc_fevd_resumen"); print(tab_fv, row.names = FALSE)

# Choque de política con instrumento de mercado (muestra completa) -------------------
zm <- read.csv(ruta("data", "sorpresas_mensuales.csv")); zm$fecha <- as.Date(zm$fecha)
vB <- MC$B$v; fu <- MC$B$d$fecha[(MC$B$p + 1):nrow(MC$B$d)]
z <- zm$target_pb[match(fu, zm$fecha)]
fe <- primera_etapa(vB$U, z, which(VARS == "ffr"))
pxb <- proxy_bootstrap(vB, z, which(VARS == "ffr"), H, 0.25, NBOOT)
tp <- cbind(irf_tabla(pxb), metodo = "Instrumento externo (sorpresas de futuros)")
tc <- cbind(IRF[IRF$espec == "B" & IRF$choque == "ffr", names(irf_tabla(pxb))], metodo = "Cholesky")
cmp <- rbind(tp, tc); cmp <- cmp[cmp$variable %in% c("nivel", "pendiente", "curvatura"), ]
guardar_tabla(cbind(fe, nota = "Primera etapa: residuo EFFR del VAR macro-curva sobre sorpresa target ponderada"), "mc_proxy_primera_etapa")
guardar_tabla(cmp, "mc_proxy_irf")
message(sprintf("Proxy en el VAR macro-curva: F primera etapa = %.1f", fe$F_robusto))
cmp$variable <- factor(etiq(cmp$variable), levels = etiq(c("nivel", "pendiente", "curvatura")))
g <- ggplot(cmp, aes(h, 100 * irf, colour = metodo, fill = metodo)) + geom_hline(yintercept = 0, colour = "grey50") +
  geom_ribbon(aes(ymin = 100 * q16, ymax = 100 * q84), alpha = 0.15, colour = NA) + geom_line(linewidth = 0.8) +
  facet_wrap(~variable, scales = "free_y") + scale_colour_manual(values = c("#0b3c5d", "#d1495b")) +
  scale_fill_manual(values = c("#0b3c5d", "#d1495b")) +
  labs(title = sprintf("Choque de política (+25 pb en la EFFR) sobre los factores de la curva, %s", PER[["B"]]),
       subtitle = sprintf("Cholesky vs instrumento de mercado (F de primera etapa = %.1f). Bandas 68%%", fe$F_robusto),
       x = "Meses después del choque", y = "Puntos básicos", colour = NULL, fill = NULL) + tema_limpio()
guardar_fig(g, "mc_politica_proxy_vs_cholesky", ancho = 10, alto = 4.5)

# Descomposición histórica (muestra completa): ¿qué movió nivel y pendiente? ----------
dh <- descomp_historica(vB); fechas <- fu
grupos <- c(list("Macro: inflación" = "inflacion", "Macro: desempleo" = "unemp", "Política (EFFR)" = "ffr"),
            if (CON_VIX) list("Riesgo (VIX)" = "vix"),
            list("Factores de la curva (choques propios)" = c("nivel", "pendiente", "curvatura")))
hd <- do.call(rbind, lapply(c("nivel", "pendiente"), function(k) {
  do.call(rbind, lapply(names(grupos), function(g) data.frame(fecha = fechas, variable = k, grupo = g,
    valor = rowSums(dh$contrib[, k, grupos[[g]], drop = FALSE]))))
}))
obs <- do.call(rbind, lapply(c("nivel", "pendiente"), function(k)
  data.frame(fecha = fechas, variable = k, valor = vB$Yd[, k] - dh$base[, k])))
guardar_tabla(hd, "mc_descomposicion_historica")
hd$grupo <- factor(hd$grupo, levels = names(grupos)); hd$variable <- factor(etiq(hd$variable), levels = etiq(c("nivel", "pendiente")))
obs$variable <- factor(etiq(obs$variable), levels = etiq(c("nivel", "pendiente")))
g <- ggplot(hd[hd$fecha >= as.Date("2015-01-01"), ], aes(fecha, valor, fill = grupo)) + geom_col(width = 26, position = "stack") +
  geom_line(data = obs[obs$fecha >= as.Date("2015-01-01"), ], aes(fecha, valor), inherit.aes = FALSE, colour = "black", linewidth = 0.6) +
  facet_wrap(~variable, ncol = 1, scales = "free_y") +
  scale_fill_manual(values = c("Macro: inflación" = "#d1495b", "Macro: desempleo" = "#6a3d9a", "Política (EFFR)" = "#0b3c5d",
                               "Riesgo (VIX)" = "#e1a33b", "Factores de la curva (choques propios)" = "#b9cfe0")) +
  labs(title = "¿Qué movió la curva desde 2015? Descomposición histórica",
       subtitle = "Desvío de cada factor respecto de su trayectoria base (línea negra), repartido por tipo de choque",
       x = NULL, y = "pp", fill = NULL, caption = sprintf("VAR macro-curva %s, Cholesky. Fuente: Bloomberg.", PER[["B"]])) +
  tema_limpio() + guides(fill = guide_legend(nrow = 2))
guardar_fig(g, "mc_descomposicion_historica", ancho = 10, alto = 7)

# Resumen numérico: cambio 2021-12 -> 2023-10 del nivel y su reparto
rep_per <- function(k, ini, fin) {
  i <- which(fechas == as.Date(ini)); f <- which(fechas == as.Date(fin)); if (!length(i) || !length(f)) return(NULL)
  data.frame(variable = k, periodo = paste(format(as.Date(ini), "%Y-%m"), "a", format(as.Date(fin), "%Y-%m")),
             cambio_observado_pb = round(100 * (vB$Yd[f, k] - vB$Yd[i, k]), 0),
             t(sapply(names(grupos), function(g) round(100 * (sum(dh$contrib[f, k, grupos[[g]]]) - sum(dh$contrib[i, k, grupos[[g]]])), 0))),
             base_pb = round(100 * (dh$base[f, k] - dh$base[i, k]), 0), check.names = FALSE)
}
rp <- rbind(rep_per("nivel", "2021-12-01", "2023-10-01"), rep_per("pendiente", "2021-12-01", "2023-10-01"),
            rep_per("nivel", "2023-10-01", max(fechas)), rep_per("pendiente", "2023-10-01", max(fechas)))
guardar_tabla(rp, "mc_reparto_episodios"); print(rp, row.names = FALSE)
