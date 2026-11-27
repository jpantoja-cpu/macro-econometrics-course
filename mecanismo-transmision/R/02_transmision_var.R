# 02_transmision_var.R --------------------------------------------------
# Mecanismo de transmisión: Fed -> mercados financieros -> economía real, y estrés tecnológico.
#
# VAR mensual (promedios mensuales, 1994-2026) con tres bloques:
#   política   : EFFR
#   financiero : 2Y, 10Y, prima por plazo 10Y (ACM), dólar (DXY), oro, S&P 500 tecnología, spread de alto rendimiento
#   real       : producción industrial, nóminas (empleo), desempleo, IPC
# Choque 1 — política monetaria: instrumento externo = sorpresa target de futuros de fed funds
#   (ponderación Gertler-Karadi, proyecto var-tasas-fed). Normalizado a +25 pb en la EFFR.
# Choque 2 — estrés tecnológico: restricciones de signo al impacto (Uhlig 2005; algoritmo de
#   Rubio-Ramírez, Waggoner y Zha 2010): tecnología cae, spread HY sube, EFFR no sube.
#   Se exige además que sea ortogonal al choque de política identificado con el instrumento.
# Escenario condicional (Waggoner y Zha 1999, versión con choques de política): la secuencia de
#   choques de política que deja la EFFR 25 pb por encima de su trayectoria base en el mes 1 y 50 pb
#   desde el mes 2, durante 12 meses; después la política vuelve a responder sola (sin choques).
#   Escenario combinado: lo mismo más un choque de estrés tecnológico de 2 d.e. en el mes 3.
# Salida: respuestas por bloque y escenarios como desvíos respecto del pronóstico base.

local({
  # Busca el utils.R de ESTA carpeta (mecanismo-transmision), sin importar dónde esté parado RStudio
  cand <- c(if (file.exists("mecanismo-transmision.Rproj")) "R/utils.R", "mecanismo-transmision/R/utils.R", "../mecanismo-transmision/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/mecanismo-transmision/R/utils.R")
  source(cand[file.exists(cand)][1])
})
source(ruta_vtf("R", "var_funciones.R"))
suppressPackageStartupMessages({ library(ggplot2); library(patchwork) })
set.seed(2026)

NBOOT <- as.numeric(Sys.getenv("NBOOT", 500)); H <- 36

# Base mensual ------------------------------------------------------------------------
mensual <- function(archivo, vars) {
  x <- read.csv(archivo, stringsAsFactors = FALSE); x <- x[x$var %in% vars, ]
  x$fecha <- as.Date(x$fecha); x$mes <- as.Date(format(x$fecha, "%Y-%m-01"))
  md <- as.Date(format(as.Date(max(x$fecha_descarga)), "%Y-%m-01")); x <- x[x$mes < md, ]
  m <- aggregate(valor ~ var + mes, data = x, FUN = mean)
  m <- reshape(m, idvar = "mes", timevar = "var", direction = "wide"); names(m) <- sub("^valor\\.", "", names(m))
  names(m)[names(m) == "mes"] <- "fecha"; m
}
base <- read.csv(ruta_vtf("data", "base_mensual.csv")); base$fecha <- as.Date(base$fecha)
base <- base[, c("fecha", "ffr", "y2y", "y10y", "ip", "cpi", "unemp")]
for (p in list(list(ruta_vtf("data", "raw", "bloomberg_acm.csv"), "tp10"),
               list(ruta_vtf("data", "raw", "bloomberg_curva_macro.csv"), "nfp"),
               list(ruta_rdo("data", "raw", "bloomberg_mercado.csv"), c("dxy", "oro")),
               list(ruta("data", "raw", "bloomberg_transmision.csv"), c("sp500_tec", "spread_hy", "cond_fin", "bancos")))) {
  base <- merge(base, mensual(p[[1]], p[[2]]), by = "fecha", all.x = TRUE)
}
base <- base[order(base$fecha), ]
for (v in c("dxy", "oro", "sp500_tec", "nfp")) base[[v]] <- 100 * log(base[[v]])
if (max(base$spread_hy, na.rm = TRUE) > 50) base$spread_hy <- base$spread_hy / 100   # pb -> pp si viene en pb
VARS <- c("ffr", "y2y", "y10y", "tp10", "dxy", "oro", "sp500_tec", "spread_hy", "ip", "nfp", "unemp", "cpi")
ETQ <- c(ffr = "EFFR", y2y = "2Y", y10y = "10Y", tp10 = "Prima por plazo 10Y", dxy = "Dólar DXY (%)", oro = "Oro (%)",
         sp500_tec = "Tecnología S&P 500 (%)", spread_hy = "Spread alto rendimiento", ip = "Producción industrial (%)",
         nfp = "Empleo: nóminas (%)", unemp = "Desempleo", cpi = "IPC (%)")
BLOQUE <- c(ffr = "Política", y2y = "Financiero", y10y = "Financiero", tp10 = "Financiero", dxy = "Financiero", oro = "Financiero",
            sp500_tec = "Financiero", spread_hy = "Financiero", ip = "Real", nfp = "Real", unemp = "Real", cpi = "Real")
EN_PB <- c("ffr", "y2y", "y10y", "tp10", "spread_hy", "unemp")       # tasas/spreads/desempleo en pp -> se grafican en pb

d <- base[base$fecha >= as.Date("1994-01-01"), c("fecha", VARS)]; d <- d[complete.cases(d), ]
Y <- as.matrix(d[, VARS])
ic <- seleccion_rezagos(Y, 6); sel <- sapply(ic[, c("AIC", "BIC", "HQ")], which.min)
P <- max(2, min(sel[["HQ"]], 4))
v <- var_ols(Y, P)
message(sprintf("VAR transmisión %s a %s: T=%d, N=%d, p=%d (AIC=%d, BIC=%d, HQ=%d), raíz máx.=%.3f",
                format(d$fecha[1], "%Y-%m"), format(max(d$fecha), "%Y-%m"), v$TT, v$N, P, sel[["AIC"]], sel[["BIC"]], sel[["HQ"]], max(raices(v))))

# Choque 1: política (instrumento externo) -----------------------------------------------
# Efecto información de la Fed (Jarociński y Karadi 2020): una sorpresa de tasas acompañada de una
# SUBIDA de las acciones el mismo día refleja sobre todo noticias de la Fed sobre una economía fuerte,
# no un endurecimiento puro. Versión "poor man's": la sorpresa monetaria pura usa solo los días FOMC en
# que la sorpresa target y el S&P 500 se movieron en sentido opuesto; el resto es "información".
# Ambas series se agregan por mes con la ponderación de Gertler-Karadi.
ev <- read.csv(ruta_vtf("data", "sorpresas_fomc.csv")); ev$fecha_evento <- as.Date(ev$fecha_evento)
ev <- ev[!as.logical(ev$excluir_base) & !is.na(ev$target_pb), ]
tr <- read.csv(ruta("data", "raw", "bloomberg_transmision.csv"), stringsAsFactors = FALSE)
sp <- tr[tr$var == "sp500", c("fecha", "valor")]; sp$fecha <- as.Date(sp$fecha); sp <- sp[order(sp$fecha), ]
ev$d_sp <- sapply(ev$fecha_evento, function(f) { i <- match(f, sp$fecha); if (is.na(i) || i < 2) NA else 100 * log(sp$valor[i] / sp$valor[i - 1]) })
ev$tipo <- ifelse(is.na(ev$d_sp), NA, ifelse(sign(ev$target_pb) * sign(ev$d_sp) < 0, "monetaria", "informacion"))
pondera_gk <- function(fechas, valores, meses) {
  z <- setNames(rep(0, length(meses)), as.character(meses))
  for (i in seq_along(fechas)) {
    m <- as.Date(format(fechas[i], "%Y-%m-01")); m2 <- seq(m, by = "month", length.out = 2)[2]
    Dm <- as.numeric(format(m2 - 1, "%d")); dd <- as.numeric(format(fechas[i], "%d"))
    if (as.character(m) %in% names(z)) z[as.character(m)] <- z[as.character(m)] + valores[i] * (Dm - dd + 1) / Dm
    if (as.character(m2) %in% names(z)) z[as.character(m2)] <- z[as.character(m2)] + valores[i] * (dd - 1) / Dm
  }
  unname(z)
}
meses_z <- seq(as.Date("1994-01-01"), max(d$fecha), by = "month")
ok <- !is.na(ev$tipo)
Z <- data.frame(fecha = meses_z,
                total = pondera_gk(ev$fecha_evento[ok], ev$target_pb[ok], meses_z),
                monetaria = pondera_gk(ev$fecha_evento[ok & ev$tipo == "monetaria"], ev$target_pb[ok & ev$tipo == "monetaria"], meses_z),
                informacion = pondera_gk(ev$fecha_evento[ok & ev$tipo == "informacion"], ev$target_pb[ok & ev$tipo == "informacion"], meses_z))
guardar_tabla(data.frame(tipo = c("monetaria", "informacion"), n_eventos = c(sum(ev$tipo == "monetaria", na.rm = TRUE), sum(ev$tipo == "informacion", na.rm = TRUE))),
              "eventos_monetaria_vs_informacion")
fu <- d$fecha[(P + 1):nrow(d)]
z <- Z$monetaria[match(fu, Z$fecha)]                     # instrumento principal: sorpresa monetaria pura
z_total <- Z$total[match(fu, Z$fecha)]
pb_total <- proxy_bootstrap(v, z_total, which(VARS == "ffr"), H, 0.25, NBOOT)
fe_total <- primera_etapa(v$U, z_total, which(VARS == "ffr"))
jF <- which(VARS == "ffr")
fe <- primera_etapa(v$U, z, jF)
pb <- proxy_bootstrap(v, z, jF, H, 0.25, NBOOT)
message(sprintf("Choque de política: F primera etapa = %.1f; réplicas válidas = %d", fe$F_robusto, pb$nboot_ok))
irf_pol <- cbind(choque = "Política: +25 pb en la EFFR", irf_tabla(pb))
message(sprintf("Comparación: instrumento total (con efecto información) F = %.1f", fe_total$F_robusto))
cmp <- rbind(cbind(instrumento = "Sorpresa monetaria pura (acciones en sentido opuesto)", irf_tabla(pb)),
             cbind(instrumento = "Sorpresa total (incluye efecto información)", irf_tabla(pb_total)))
guardar_tabla(cmp, "irf_politica_pura_vs_total")
cr <- cmp[cmp$variable %in% c("sp500_tec", "ip", "nfp", "unemp", "cpi", "y10y"), ]
kk <- ifelse(cr$variable %in% EN_PB, 100, 1); for (cc in c("irf", "q16", "q84")) cr[[cc]] <- cr[[cc]] * kk
cr$variable <- factor(paste0(ETQ[cr$variable], ifelse(cr$variable %in% EN_PB, " (pb)", "")))
gcmp <- ggplot(cr, aes(h, irf, colour = instrumento, fill = instrumento)) + geom_hline(yintercept = 0, colour = "grey50") +
  geom_ribbon(aes(ymin = q16, ymax = q84), alpha = 0.12, colour = NA) + geom_line(linewidth = 0.8) +
  facet_wrap(~variable, scales = "free_y", ncol = 3) + scale_colour_manual(values = c("#d1495b", "#0b3c5d")) +
  scale_fill_manual(values = c("#d1495b", "#0b3c5d")) +
  labs(title = "Separar el efecto información cambia la lectura del choque de la Fed",
       subtitle = "Respuesta a +25 pb en la EFFR con dos instrumentos; bandas 68%", x = "Meses", y = NULL, colour = NULL, fill = NULL) +
  tema_limpio(9) + guides(colour = guide_legend(ncol = 1))
guardar_fig(gcmp, "politica_pura_vs_total", ancho = 10, alto = 6)

# Choque 2: estrés tecnológico (restricciones de signo, ortogonal al de política) ----------
# Impactos admisibles a = A q, con A = chol(Sigma)' y q unitario. Ortogonalidad con el choque
# de política: q' A^{-1} s_pol = 0 (los choques estructurales no se correlacionan).
A <- t(chol(v$Sigma)); s_pol <- pb$impacto / pb$impacto[jF] * sqrt(v$Sigma[jF, jF])
w <- solve(A, s_pol); w <- w / sqrt(sum(w^2))
signos <- function(a) a[VARS == "sp500_tec"] < 0 && a[VARS == "spread_hy"] > 0 && a[VARS == "ffr"] <= 0
acept <- list(); intentos <- 0
while (length(acept) < 300 && intentos < 200000) {
  intentos <- intentos + 1
  q <- rnorm(v$N); q <- q - sum(q * w) * w; q <- q / sqrt(sum(q^2))    # ortogonal al de política
  a <- as.vector(A %*% q)
  if (signos(a)) acept[[length(acept) + 1]] <- a else if (signos(-a)) acept[[length(acept) + 1]] <- -a
}
message(sprintf("Estrés tecnológico: %d rotaciones aceptadas de %d intentos", length(acept), intentos))
Phi <- ma_coef(v$B, v$N, v$p, H)
irf_imp <- function(a) t(sapply(1:(H + 1), function(h) Phi[, , h] %*% a))
dr <- simplify2array(lapply(acept, irf_imp)); dimnames(dr) <- list(NULL, VARS, NULL)
# Mediana punto a punto + la rotación más cercana a la mediana (Fry y Pagan 2011) como respuesta "central"
med <- apply(dr, c(1, 2), median)
dist <- sapply(seq_along(acept), function(k) sum(((dr[, , k] - med) / apply(dr, c(1, 2), sd))^2))
a_tec <- acept[[which.min(dist)]]
ib_tec <- list(base = irf_imp(a_tec), draws = dr, H = H); colnames(ib_tec$base) <- VARS
irf_tec <- cbind(choque = "Estrés tecnológico: 1 d.e.", irf_tabla(ib_tec))
write.csv(data.frame(variable = VARS, impacto = a_tec), ruta("output", "tablas", "impacto_choque_tecnologico.csv"), row.names = FALSE)

IRF <- rbind(irf_pol, irf_tec); guardar_tabla(IRF, "irf_transmision")
guardar_tabla(cbind(fe, rezagos = P, T = v$TT, aceptadas_signos = length(acept), intentos_signos = intentos), "resumen_identificacion")

graf_bloque <- function(ch, bloque, titulo, sub) {
  t <- IRF[IRF$choque == ch & IRF$variable %in% names(BLOQUE)[BLOQUE %in% bloque], ]
  k <- ifelse(t$variable %in% EN_PB, 100, 1)
  t$irf <- t$irf * k; t$q05 <- t$q05 * k; t$q95 <- t$q95 * k; t$q16 <- t$q16 * k; t$q84 <- t$q84 * k
  t$variable <- factor(paste0(ETQ[t$variable], ifelse(t$variable %in% EN_PB, " (pb)", "")),
                       levels = paste0(ETQ[VARS], ifelse(VARS %in% EN_PB, " (pb)", "")))
  ggplot(t, aes(h)) + geom_hline(yintercept = 0, colour = "grey50", linewidth = 0.3) +
    geom_ribbon(aes(ymin = q05, ymax = q95), fill = "#1b6ca8", alpha = 0.15) +
    geom_ribbon(aes(ymin = q16, ymax = q84), fill = "#1b6ca8", alpha = 0.3) +
    geom_line(aes(y = irf), colour = "#0b3c5d", linewidth = 0.8) + facet_wrap(~variable, scales = "free_y", ncol = 4) +
    labs(title = titulo, subtitle = sub, x = "Meses después del choque", y = NULL) + tema_limpio(9)
}
cap <- sprintf("VAR(%d) mensual %s a %s. Bandas 68%% y 90%%.", P, format(d$fecha[1], "%Y"), format(max(d$fecha), "%Y"))
guardar_fig(graf_bloque(irf_pol$choque[1], c("Política", "Financiero"), "Choque de política (+25 pb): el bloque financiero reacciona primero",
                        paste("Instrumento externo: sorpresas de futuros de fed funds (F =", round(fe$F_robusto, 1), ").", cap)), "irf_politica_financiero", 11, 6)
guardar_fig(graf_bloque(irf_pol$choque[1], "Real", "Choque de política (+25 pb): la economía real responde con rezago", cap), "irf_politica_real", 11, 3.6)
guardar_fig(graf_bloque(irf_tec$choque[1], c("Política", "Financiero"), "Choque de estrés tecnológico (1 d.e.): mercados",
                        paste("Signos al impacto: tecnología < 0, spread HY > 0, EFFR ≤ 0; ortogonal al choque de política.", cap)), "irf_tecnologico_financiero", 11, 6)
guardar_fig(graf_bloque(irf_tec$choque[1], "Real", "Choque de estrés tecnológico (1 d.e.): economía real", cap), "irf_tecnologico_real", 11, 3.6)

# Escenarios condicionales -------------------------------------------------------------------
# Pronóstico base desde el último mes; luego se agregan choques: de política (para que la EFFR siga
# la trayectoria pedida) y, en el escenario combinado, un choque tecnológico de 2 d.e. en el mes 3.
HS <- 24
pronostico <- function(choques) {           # choques: HS x 2 (política en unidades del impacto s_pol; tecnológico en d.e.)
  Yh <- rbind(Y, matrix(NA, HS, v$N)); TT <- nrow(Y)
  for (t in 1:HS) {
    x <- c(1, as.vector(t(Yh[(TT + t - 1):(TT + t - P), , drop = FALSE])))
    Yh[TT + t, ] <- x %*% v$B + choques[t, 1] * s_pol + choques[t, 2] * a_tec
  }
  Yh[(TT + 1):(TT + HS), , drop = FALSE]
}
base_f <- pronostico(matrix(0, HS, 2)); colnames(base_f) <- VARS
desv_obj <- c(0.25, rep(0.50, 11))                                        # +25 pb en el mes 1, +50 pb en los meses 2-12
choques_pol <- function(extra_tec = NULL) {
  ch <- matrix(0, HS, 2); if (!is.null(extra_tec)) ch[extra_tec[1], 2] <- extra_tec[2]
  for (t in seq_along(desv_obj)) {           # resuelve mes a mes el choque que deja la EFFR en base + desvío
    f0 <- pronostico(ch)[t, jF]
    ch[t, 1] <- (base_f[t, jF] + desv_obj[t] - f0) / s_pol[jF]
  }
  ch
}
ch1 <- choques_pol(); esc1 <- pronostico(ch1)
ch2 <- choques_pol(c(3, 2)); esc2 <- pronostico(ch2)
colnames(esc1) <- colnames(esc2) <- VARS
meses <- seq(max(d$fecha), by = "month", length.out = HS + 1)[-1]
desvio <- function(e, nombre) data.frame(escenario = nombre, mes = meses, h = 1:HS,
                                         do.call(cbind, lapply(VARS, function(k) setNames(data.frame((e[, k] - base_f[, k]) * ifelse(k %in% EN_PB, 100, 1)), k))))
ESC <- rbind(desvio(esc1, "Fed +50 pb sobre la base"), desvio(esc2, "Fed +50 pb + estrés tecnológico"))
guardar_tabla(ESC, "escenarios_desvio_vs_base")
guardar_tabla(data.frame(mes = meses, base_effr = base_f[, "ffr"], esc1_effr = esc1[, "ffr"], esc2_effr = esc2[, "ffr"],
                         choque_pol_esc1 = ch1[, 1], choque_pol_esc2 = ch2[, 1]), "escenarios_trayectoria_effr")
res <- ESC[ESC$h %in% c(3, 6, 12, 24), c("escenario", "h", VARS)]
res[, VARS] <- round(res[, VARS], 2); print(res, row.names = FALSE)

el <- do.call(rbind, lapply(VARS, function(k) data.frame(escenario = ESC$escenario, h = ESC$h, variable = k, valor = ESC[[k]])))
el$variable <- factor(paste0(ETQ[el$variable], ifelse(el$variable %in% EN_PB, " (pb)", "")),
                      levels = paste0(ETQ[VARS], ifelse(VARS %in% EN_PB, " (pb)", "")))
g <- ggplot(el, aes(h, valor, colour = escenario)) + geom_hline(yintercept = 0, colour = "grey50") + geom_line(linewidth = 0.8) +
  facet_wrap(~variable, scales = "free_y", ncol = 4) + scale_colour_manual(values = c("#0b3c5d", "#d1495b")) +
  labs(title = "Escenarios: desvío respecto del pronóstico base", subtitle = "La EFFR queda 50 pb por encima de su trayectoria base durante 12 meses; el escenario combinado agrega estrés tecnológico (2 d.e.) en el mes 3",
       x = "Meses", y = NULL, colour = NULL) + tema_limpio(9)
guardar_fig(g, "escenarios_condicionales", ancho = 11, alto = 7.5)
saveRDS(list(v = v, s_pol = s_pol, a_tec = a_tec, VARS = VARS, ESC = ESC, base_f = base_f, d = d), ruta("output", "modelo_transmision.rds"))
