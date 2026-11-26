# 15_prima_plazo.R ------------------------------------------------------
# ¿El 10Y se mueve por expectativas de tasas o por la prima por plazo?
# Descomposición de Adrian, Crump y Moench (2013, "ACM"), publicada por la Fed de NY:
#   rendimiento (n) = expectativa de tasas (neutral al riesgo, n) + prima por plazo (n)
# Bloomberg trae solo la prima ACM; la expectativa se obtiene como rendimiento − prima.
# El neutral al riesgo es el promedio esperado de la tasa corta en los próximos n años;
# la prima por plazo es lo que se cobra por el riesgo de mantener el bono largo.
#
# 1) Historia: descomposición del 10Y y reparto en episodios (conundrum 2004-06,
#    taper tantrum 2013, alzas 2022-23, etc.).
# 2) Días FOMC: ¿las sorpresas target y path mueven las expectativas o la prima?
# 3) VAR mensual [desempleo, inflación, EFFR, VIX, MOVE, expectativa 10Y, prima 10Y]:
#    qué mueve cada componente, descomposición de varianza e histórica; choque de
#    política alternativo con instrumento de mercado.

local({
  cand <- c("R/utils.R", "var-tasas-fed/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/var-tasas-fed/R/utils.R")
  source(cand[file.exists(cand)][1])
})
source(ruta("R", "var_funciones.R"))
suppressPackageStartupMessages({ library(ggplot2); library(patchwork); library(sandwich) })

NBOOT <- as.numeric(Sys.getenv("NBOOT", 1000)); H <- 48
ETIQ[c("rny2", "rny5", "rny10", "tp2", "tp5", "tp10", "acmy10", "move", "vix", "inflacion", "unemp")] <-
  c("Expectativa 2Y", "Expectativa 5Y", "Expectativa 10Y", "Prima 2Y", "Prima 5Y", "Prima 10Y", "Rendimiento ACM 10Y",
    "MOVE", "VIX", "Inflación (IPC, % a/a)", "Desempleo (%)")

# Datos ---------------------------------------------------------------------------
acm <- read.csv(ruta("data", "raw", "bloomberg_acm.csv"), stringsAsFactors = FALSE)
acm$fecha <- as.Date(acm$fecha)
disp <- unique(acm$var)
if (!"tp10" %in% disp) stop("Falta ACMTP10 en la descarga: revisa data/raw/log_tickers_acm.csv")
message("Series ACM disponibles: ", paste(sort(disp), collapse = ", "))
# Bloomberg solo publica la prima por plazo ACM (ACMTP02/05/10); los rendimientos
# neutrales al riesgo (ACMRNY) no están. Se construye la expectativa como
#   expectativa(n) = rendimiento de mercado(n) − prima ACM(n)
# usando los genéricos USGG2YR/5YR/10YR. Difiere de ACMRNY solo por el error de ajuste
# del modelo ACM y por usar rendimientos par en vez de cupón cero (unos pocos pb).
if (!"rny10" %in% disp) {
  ry <- read.csv(ruta("data", "raw", "bloomberg_tasas.csv"), stringsAsFactors = FALSE)
  ry <- ry[ry$var %in% c("y2y", "y5y", "y10y"), ]; ry$fecha <- as.Date(ry$fecha)
  mapa <- c(tp2 = "y2y", tp5 = "y5y", tp10 = "y10y")
  nuevas <- do.call(rbind, lapply(intersect(names(mapa), disp), function(tpv) {
    a <- acm[acm$var == tpv, ]; y <- ry[ry$var == mapa[[tpv]], ]
    m <- merge(a, y[, c("fecha", "valor")], by = "fecha", suffixes = c("", "_y"))
    data.frame(fecha = m$fecha, ticker = paste(mapa[[tpv]], "− prima ACM"), var = sub("^tp", "rny", tpv),
               nombre = "Expectativa = rendimiento − prima ACM", frecuencia = "DAILY", valor = m$valor_y - m$valor,
               fecha_descarga = m$fecha_descarga)
  }))
  acm <- rbind(acm[, names(nuevas)], nuevas)
  disp <- unique(acm$var)
  message("Expectativas construidas como rendimiento − prima: ", paste(sort(unique(nuevas$var)), collapse = ", "))
}

# Diario (ancho) para el estudio de eventos
AD <- reshape(acm[, c("fecha", "var", "valor")], idvar = "fecha", timevar = "var", direction = "wide")
names(AD) <- sub("^valor\\.", "", names(AD)); AD <- AD[order(AD$fecha), ]

# Mensual: promedio del mes (sin el mes en curso)
acm$mes <- as.Date(format(acm$fecha, "%Y-%m-01"))
mes_desc <- as.Date(format(as.Date(max(acm$fecha_descarga)), "%Y-%m-01"))
am <- aggregate(valor ~ var + mes, data = acm[acm$mes < mes_desc, ], FUN = mean)
am <- reshape(am, idvar = "mes", timevar = "var", direction = "wide"); names(am) <- sub("^valor\\.", "", names(am))
names(am)[names(am) == "mes"] <- "fecha"

base <- read.csv(ruta("data", "base_mensual.csv")); base$fecha <- as.Date(base$fecha)
for (extra in ruta("data", "raw", c("bloomberg_vix.csv"))) if (file.exists(extra)) {
  x <- read.csv(extra, stringsAsFactors = FALSE); x$fecha <- as.Date(x$fecha); x$mes <- as.Date(format(x$fecha, "%Y-%m-01"))
  md <- as.Date(format(as.Date(max(x$fecha_descarga)), "%Y-%m-01"))
  xm <- aggregate(valor ~ var + mes, data = x[x$mes < md, ], FUN = mean)
  xm <- reshape(xm, idvar = "mes", timevar = "var", direction = "wide"); names(xm) <- sub("^valor\\.", "", names(xm))
  names(xm)[names(xm) == "mes"] <- "fecha"; base <- merge(base, xm, by = "fecha", all.x = TRUE)
}
base <- merge(base, am, by = "fecha", all.x = TRUE); base <- base[order(base$fecha), ]
base$inflacion <- base$cpi - c(rep(NA, 12), head(base$cpi, -12))

# 1) Historia -------------------------------------------------------------------------
d10 <- base[!is.na(base$tp10), ]
chk <- data.frame(medida = c("Prima 10Y: promedio 1990-2007 (pb)", "Prima 10Y: promedio 2008-2019 (pb)",
                             "Prima 10Y: promedio 2020-2026 (pb)", "Prima 10Y: último mes (pb)",
                             "Correlación de cambios mensuales: Δ10Y vs Δprima", "Correlación de cambios mensuales: Δ10Y vs Δexpectativa"),
                  valor = round(c(100 * mean(d10$tp10[d10$fecha >= as.Date("1990-01-01") & d10$fecha <= as.Date("2007-12-01")]),
                                  100 * mean(d10$tp10[d10$fecha >= as.Date("2008-01-01") & d10$fecha <= as.Date("2019-12-01")]),
                                  100 * mean(d10$tp10[d10$fecha >= as.Date("2020-01-01")]), 100 * tail(d10$tp10, 1),
                                  cor(diff(d10$y10y), diff(d10$tp10)), cor(diff(d10$y10y), diff(d10$rny10))), 2))
guardar_tabla(chk, "acm_descriptivo"); print(chk, row.names = FALSE)

hl <- rbind(data.frame(fecha = d10$fecha, serie = "Rendimiento 10Y (Bloomberg)", valor = d10$y10y),
            data.frame(fecha = d10$fecha, serie = "Expectativa de tasas 10Y (neutral al riesgo)", valor = d10$rny10),
            data.frame(fecha = d10$fecha, serie = "Prima por plazo 10Y", valor = d10$tp10))
EPIS <- data.frame(nombre = c("Conundrum", "Taper tantrum", "Alzas 2022-23", "Recortes 2024-26"),
                   ini = as.Date(c("2004-06-01", "2013-04-01", "2021-12-01", "2023-10-01")),
                   fin = c(as.Date(c("2006-06-01", "2013-09-01", "2023-10-01")), max(d10$fecha)),
                   vj = c(1.5, 1.5, 1.5, 3.3))
g <- ggplot(hl, aes(fecha, valor, colour = serie)) +
  geom_rect(data = EPIS, aes(xmin = ini, xmax = fin, ymin = -Inf, ymax = Inf), inherit.aes = FALSE, fill = "#e1a33b", alpha = 0.12) +
  geom_text(data = EPIS, aes(x = ini, y = Inf, label = nombre, vjust = vj), inherit.aes = FALSE, hjust = 0, size = 2.8, colour = "grey30", family = FUENTE) +
  geom_hline(yintercept = 0, colour = "grey60") + geom_line(linewidth = 0.6) +
  scale_colour_manual(values = c("#0b3c5d", "#1b6ca8", "#d1495b")) +
  labs(title = "El rendimiento a 10 años: expectativas de tasas vs prima por plazo",
       subtitle = "Prima ACM (Fed de Nueva York); expectativa = rendimiento − prima. Promedios mensuales; sombras = episodios",
       x = NULL, y = "%", colour = NULL, caption = "Fuente: Bloomberg (ACMTP10, USGG10YR).") +
  tema_limpio() + guides(colour = guide_legend(nrow = 2))
guardar_fig(g, "acm_descomposicion_10y", ancho = 10, alto = 5.5)

episodio <- function(i) {
  e <- EPIS[i, ]; a <- base[base$fecha == e$ini, ]; b <- base[base$fecha == e$fin, ]
  data.frame(episodio = e$nombre, periodo = paste(format(e$ini, "%Y-%m"), "a", format(e$fin, "%Y-%m")),
             d_effr_pb = round(100 * (b$ffr - a$ffr)), d_10y_pb = round(100 * (b$y10y - a$y10y)),
             d_expectativa_pb = round(100 * (b$rny10 - a$rny10)), d_prima_pb = round(100 * (b$tp10 - a$tp10)))
}
ep <- do.call(rbind, lapply(seq_len(nrow(EPIS)), episodio))
guardar_tabla(ep, "acm_episodios"); print(ep, row.names = FALSE)

# 2) Días FOMC ------------------------------------------------------------------------
ev <- read.csv(ruta("data", "sorpresas_fomc.csv")); ev$fecha_evento <- as.Date(ev$fecha_evento)
ev <- ev[!as.logical(ev$excluir_base), ]
comp <- intersect(c("rny2", "tp2", "rny5", "tp5", "rny10", "tp10"), names(AD))
for (v in comp) {
  ev[[paste0("d_", v)]] <- sapply(ev$fecha_evento, function(f) {
    i <- match(f, AD$fecha); if (is.na(i) || i < 2) return(NA); 100 * (AD[[v]][i] - AD[[v]][i - 1])
  })
}
mues <- list("1994-2007" = ev[ev$fecha_evento <= as.Date("2007-12-31"), ], "2008-2026" = ev[ev$fecha_evento > as.Date("2007-12-31"), ],
             "Completa" = ev)
ee <- do.call(rbind, lapply(names(mues), function(mu) do.call(rbind, lapply(comp, function(v) {
  dd <- mues[[mu]]; dd <- dd[!is.na(dd[[paste0("d_", v)]]), ]
  if (nrow(dd) < 20) return(NULL)
  m <- lm(as.formula(paste0("d_", v, " ~ target_pb + path_pb")), data = dd); V <- vcovHC(m, type = "HC1")
  data.frame(muestra = mu, componente = v, regresor = c("target", "path"), efecto_25pb = 25 * coef(m)[2:3],
             se_25pb = 25 * sqrt(diag(V))[2:3], n = nobs(m), row.names = NULL)
}))))
guardar_tabla(ee, "acm_eventos_fomc")
print(transform(ee, efecto_25pb = round(efecto_25pb, 1), se_25pb = round(se_25pb, 1)), row.names = FALSE)
if (nrow(ee)) {
  ee$plazo <- factor(sub("^(rny|tp)", "", ee$componente), levels = c("2", "5", "10"), labels = c("2Y", "5Y", "10Y"))
  ee$tipo <- ifelse(grepl("^rny", ee$componente), "Expectativas", "Prima por plazo")
  ee$regresor <- factor(ifelse(ee$regresor == "target", "Sorpresa target", "Sorpresa path"), levels = c("Sorpresa target", "Sorpresa path"))
  g <- ggplot(ee[ee$muestra != "Completa", ], aes(plazo, efecto_25pb, fill = tipo)) +
    geom_hline(yintercept = 0, colour = "grey50") +
    geom_col(position = position_dodge(width = 0.75), width = 0.7) +
    geom_errorbar(aes(ymin = efecto_25pb - 1.645 * se_25pb, ymax = efecto_25pb + 1.645 * se_25pb),
                  position = position_dodge(width = 0.75), width = 0.2, colour = "grey30") +
    facet_grid(muestra ~ regresor) + scale_fill_manual(values = c("#1b6ca8", "#d1495b")) +
    labs(title = "Día del anuncio del FOMC: ¿se mueven las expectativas o la prima por plazo?",
         subtitle = "Efecto de una sorpresa de 25 pb; intervalos de 90% (HC1)", x = "Plazo", y = "Puntos básicos", fill = NULL) +
    tema_limpio()
  guardar_fig(g, "acm_eventos_fomc", ancho = 9, alto = 6.5)
}

# 3) VAR mensual ----------------------------------------------------------------------------
VARS <- c("unemp", "inflacion", "ffr", intersect(c("vix", "move"), names(base)), "rny10", "tp10")
CHOQUES <- setdiff(VARS, c("rny10", "tp10"))
NOMBRE <- c(unemp = "Desempleo", inflacion = "Inflación", ffr = "Política (EFFR)", vix = "Riesgo: VIX",
            move = "Volatilidad de bonos: MOVE", rny10 = "Expectativas (propio)", tp10 = "Prima (propio)")[VARS]
d <- base[base$fecha >= as.Date("1990-02-01"), c("fecha", VARS)]; d <- d[complete.cases(d), ]
Ym <- as.matrix(d[, VARS])
ic <- seleccion_rezagos(Ym, 8); sel <- sapply(ic[, c("AIC", "BIC", "HQ")], which.min)
p <- min(max(sel[["HQ"]], 2), 6); v <- var_ols(Ym, p)
message(sprintf("VAR expectativas-prima %s a %s: T=%d, p=%d (AIC=%d, BIC=%d, HQ=%d), raíz máx.=%.3f",
                format(d$fecha[1], "%Y-%m"), format(max(d$fecha), "%Y-%m"), v$TT, p, sel[["AIC"]], sel[["BIC"]], sel[["HQ"]], max(raices(v))))

irf <- do.call(rbind, lapply(CHOQUES, function(s) {
  j <- which(VARS == s); esc <- if (s == "ffr") 0.25 else sqrt(v$Sigma[j, j])
  cbind(choque = s, tamano = esc, irf_tabla(irf_bootstrap(v, H, j, esc, NBOOT)))
}))
guardar_tabla(irf, "acm_var_irf")
di <- irf[irf$variable %in% c("rny10", "tp10"), ]
tam <- unique(di[, c("choque", "tamano")])
lab <- setNames(sprintf("%s\n(%s)", NOMBRE[tam$choque], ifelse(tam$choque == "ffr", "+25 pb",
               ifelse(tam$choque %in% c("vix", "move"), sprintf("+%.1f puntos", tam$tamano), sprintf("+%.2f pp", tam$tamano)))), tam$choque)
di$choque <- factor(lab[di$choque], levels = lab[CHOQUES])
di$variable <- factor(etiq(di$variable), levels = etiq(c("rny10", "tp10")))
g <- ggplot(di, aes(h)) + geom_hline(yintercept = 0, colour = "grey50", linewidth = 0.3) +
  geom_ribbon(aes(ymin = 100 * q05, ymax = 100 * q95), fill = "#1b6ca8", alpha = 0.15) +
  geom_ribbon(aes(ymin = 100 * q16, ymax = 100 * q84), fill = "#1b6ca8", alpha = 0.3) +
  geom_line(aes(y = 100 * irf), colour = "#0b3c5d", linewidth = 0.8) +
  facet_grid(variable ~ choque, scales = "free_y") +
  labs(title = "¿Qué mueve las expectativas y la prima por plazo del 10Y?",
       subtitle = "Choques de 1 d.e. (política: +25 pb). Puntos básicos; bandas bootstrap 68% y 90%",
       x = "Meses después del choque", y = "Puntos básicos",
       caption = sprintf("VAR(%d) [%s], Cholesky en ese orden, %s a %s. Fuente: Bloomberg, ACM (Fed de NY).", p,
                         paste(etiq(VARS), collapse = ", "), format(d$fecha[1], "%Y-%m"), format(max(d$fecha), "%Y-%m"))) +
  tema_limpio(9)
guardar_fig(g, "acm_var_irf", ancho = 11, alto = 6)

res_irf <- di[di$h %in% c(0, 12, 24), ]
res_irf <- data.frame(choque = gsub("\n", " ", as.character(res_irf$choque)), componente = res_irf$variable, h = res_irf$h,
                      irf_pb = round(100 * res_irf$irf, 1), banda68 = sprintf("[%.1f, %.1f]", 100 * res_irf$q16, 100 * res_irf$q84))
guardar_tabla(res_irf, "acm_var_irf_resumen"); print(res_irf, row.names = FALSE)

fv <- fevd_chol(v, c(12, 48)); fv <- fv[fv$variable %in% c("rny10", "tp10"), ]
fvt <- data.frame(horizonte = fv$horizonte, componente = etiq(fv$variable),
                  round(100 * fv[, paste0("choque_", VARS)], 1), check.names = FALSE)
names(fvt)[-(1:2)] <- NOMBRE
guardar_tabla(fvt, "acm_var_fevd"); print(fvt, row.names = FALSE)

# Política con instrumento de mercado
zm <- read.csv(ruta("data", "sorpresas_mensuales.csv")); zm$fecha <- as.Date(zm$fecha)
fu <- d$fecha[(p + 1):nrow(d)]
px <- lapply(c(target = "target_pb", ff4 = "ff4_pb"), function(zn) {
  z <- zm[[zn]][match(fu, zm$fecha)]; j <- which(VARS == "ffr")
  list(fe = primera_etapa(v$U, z, j), tab = irf_tabla(proxy_bootstrap(v, z, j, H, 0.25, NBOOT)))
})
fe <- do.call(rbind, lapply(names(px), function(k) cbind(instrumento = k, px[[k]]$fe)))
guardar_tabla(fe, "acm_proxy_primera_etapa"); print(fe, row.names = FALSE)
cmp <- rbind(cbind(metodo = "Cholesky", irf[irf$choque == "ffr", names(px$target$tab)]),
             cbind(metodo = sprintf("Instrumento target (F=%.0f)", px$target$fe$F_robusto), px$target$tab),
             cbind(metodo = sprintf("Instrumento FF4 (F=%.0f)", px$ff4$fe$F_robusto), px$ff4$tab))
cmp <- cmp[cmp$variable %in% c("ffr", "rny10", "tp10"), ]
guardar_tabla(cmp, "acm_politica_irf")
cmp$variable <- factor(etiq(cmp$variable), levels = etiq(c("ffr", "rny10", "tp10")))
g <- ggplot(cmp, aes(h, 100 * irf, colour = metodo, fill = metodo)) + geom_hline(yintercept = 0, colour = "grey50") +
  geom_ribbon(aes(ymin = 100 * q16, ymax = 100 * q84), alpha = 0.12, colour = NA) + geom_line(linewidth = 0.8) +
  facet_wrap(~variable, scales = "free_y") +
  scale_colour_manual(values = c("#0b3c5d", "#d1495b", "#e1a33b")) + scale_fill_manual(values = c("#0b3c5d", "#d1495b", "#e1a33b")) +
  labs(title = "Un alza de 25 pb en la EFFR: ¿sube la expectativa o la prima del 10Y?",
       subtitle = "Bandas 68%", x = "Meses después del choque", y = "Puntos básicos", colour = NULL, fill = NULL) + tema_limpio()
guardar_fig(g, "acm_politica_proxy", ancho = 10, alto = 4.5)

# Descomposición histórica de expectativa y prima
dh <- descomp_historica(v)
grupos <- c(list("Macro: inflación" = "inflacion", "Macro: desempleo" = "unemp", "Política (EFFR)" = "ffr"),
            if ("vix" %in% VARS) list("Riesgo: VIX" = "vix"), if ("move" %in% VARS) list("Volatilidad de bonos: MOVE" = "move"),
            list("Choques propios (expectativas y prima)" = c("rny10", "tp10")))
hd <- do.call(rbind, lapply(c("rny10", "tp10"), function(k) do.call(rbind, lapply(names(grupos), function(gq)
  data.frame(fecha = fu, variable = k, grupo = gq, valor = rowSums(dh$contrib[, k, grupos[[gq]], drop = FALSE]))))))
obs <- do.call(rbind, lapply(c("rny10", "tp10"), function(k) data.frame(fecha = fu, variable = k, valor = v$Yd[, k] - dh$base[, k])))
guardar_tabla(hd, "acm_descomposicion_historica")
hd$grupo <- factor(hd$grupo, levels = names(grupos)); hd$variable <- factor(etiq(hd$variable), levels = etiq(c("rny10", "tp10")))
obs$variable <- factor(etiq(obs$variable), levels = etiq(c("rny10", "tp10")))
g <- ggplot(hd[hd$fecha >= as.Date("2015-01-01"), ], aes(fecha, valor, fill = grupo)) + geom_col(width = 26) +
  geom_line(data = obs[obs$fecha >= as.Date("2015-01-01"), ], aes(fecha, valor), inherit.aes = FALSE, colour = "black", linewidth = 0.6) +
  facet_wrap(~variable, ncol = 1, scales = "free_y") +
  scale_fill_manual(values = c("Macro: inflación" = "#d1495b", "Macro: desempleo" = "#6a3d9a", "Política (EFFR)" = "#0b3c5d",
                               "Riesgo: VIX" = "#e1a33b", "Volatilidad de bonos: MOVE" = "#66a61e",
                               "Choques propios (expectativas y prima)" = "#b9cfe0")) +
  labs(title = "¿Qué movió las expectativas y la prima del 10Y desde 2015?",
       subtitle = "Desvío respecto de la trayectoria base (línea negra), repartido por tipo de choque",
       x = NULL, y = "pp", fill = NULL) + tema_limpio() + guides(fill = guide_legend(nrow = 2))
guardar_fig(g, "acm_descomposicion_historica", ancho = 10, alto = 7)

rep_per <- function(k, ini, fin) {
  i <- which(fu == as.Date(ini)); f <- which(fu == as.Date(fin)); if (!length(i) || !length(f)) return(NULL)
  data.frame(componente = etiq(k), periodo = paste(format(as.Date(ini), "%Y-%m"), "a", format(as.Date(fin), "%Y-%m")),
             cambio_pb = round(100 * (v$Yd[f, k] - v$Yd[i, k])),
             t(sapply(names(grupos), function(gq) round(100 * (sum(dh$contrib[f, k, grupos[[gq]]]) - sum(dh$contrib[i, k, grupos[[gq]]]))))),
             check.names = FALSE)
}
rp <- rbind(rep_per("rny10", "2021-12-01", "2023-10-01"), rep_per("tp10", "2021-12-01", "2023-10-01"),
            rep_per("rny10", "2023-10-01", as.character(max(fu))), rep_per("tp10", "2023-10-01", as.character(max(fu))))
guardar_tabla(rp, "acm_reparto_episodios"); print(rp, row.names = FALSE)
