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
#   Rubio-Ramírez, Waggoner y Zha 2010): tecnología cae, spread HY sube, EFFR no sube y la actividad
#   (producción, nóminas, desempleo) no mejora en el mes.
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
# Índice tecnológico: Nasdaq 100 por defecto (incluye Alphabet, Meta y Amazon, que la clasificación GICS deja
# fuera del sector tecnología del S&P 500). Para la comprobación de robustez: Sys.setenv(TEC = "sp500_tec").
TEC <- Sys.getenv("TEC", "nasdaq100")
ETQ_TEC <- c(nasdaq100 = "Tecnología: Nasdaq 100 (%)", sp500_tec = "Tecnología: S&P 500 tec. (%)")[[TEC]]
SUF <- if (TEC == "nasdaq100") "" else paste0("_", TEC)   # la robustez se guarda con sufijo, sin pisar los resultados principales
.gt <- guardar_tabla; .gf <- guardar_fig
guardar_tabla <- function(x, nombre, ...) .gt(x, paste0(nombre, SUF), ...)
guardar_fig <- function(g, nombre, ...) .gf(g, paste0(nombre, SUF), ...)

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
               list(ruta("data", "raw", "bloomberg_transmision.csv"), c("nasdaq100", "sp500_tec", "spread_hy", "cond_fin", "bancos")))) {
  base <- merge(base, mensual(p[[1]], p[[2]]), by = "fecha", all.x = TRUE)
}
base <- base[order(base$fecha), ]
for (v in c("dxy", "oro", "nasdaq100", "sp500_tec", "nfp")) base[[v]] <- 100 * log(base[[v]])
base$tec <- base[[TEC]]                                  # índice tecnológico elegido (100 × log)
if (max(base$spread_hy, na.rm = TRUE) > 50) base$spread_hy <- base$spread_hy / 100   # pb -> pp si viene en pb
VARS <- c("ffr", "y2y", "y10y", "tp10", "dxy", "oro", "tec", "spread_hy", "ip", "nfp", "unemp", "cpi")
ETQ <- c(ffr = "EFFR", y2y = "2Y", y10y = "10Y", tp10 = "Prima por plazo 10Y", dxy = "Dólar DXY (%)", oro = "Oro (%)",
         tec = ETQ_TEC, spread_hy = "Spread alto rendimiento", ip = "Producción industrial (%)",
         nfp = "Empleo: nóminas (%)", unemp = "Desempleo", cpi = "IPC (%)")
BLOQUE <- c(ffr = "Política", y2y = "Financiero", y10y = "Financiero", tp10 = "Financiero", dxy = "Financiero", oro = "Financiero",
            tec = "Financiero", spread_hy = "Financiero", ip = "Real", nfp = "Real", unemp = "Real", cpi = "Real")
EN_PB <- c("ffr", "y2y", "y10y", "tp10", "spread_hy", "unemp")       # tasas/spreads/desempleo en pp -> se grafican en pb

d <- base[base$fecha >= as.Date("1994-01-01"), c("fecha", VARS)]; d <- d[complete.cases(d), ]
Y <- as.matrix(d[, VARS])
ic <- seleccion_rezagos(Y, 6); sel <- sapply(ic[, c("AIC", "BIC", "HQ")], which.min)
P <- max(2, min(sel[["HQ"]], 4))
# Pandemia: marzo-agosto de 2020 tienen movimientos de empleo y producción 10-20 veces lo normal y
# dominarían las covarianzas (Lenza y Primiceri 2022). Se tratan con una variable ficticia por mes,
# lo que equivale a excluir esas ecuaciones de la estimación (sus residuos quedan en cero).
COVID <- seq(as.Date("2020-03-01"), as.Date("2020-08-01"), by = "month")
var_ols_ex <- function(Y, p, fechas_u) {
  m <- var_matrices(Y, p); keep <- !(fechas_u %in% COVID)
  Xk <- m$X[keep, , drop = FALSE]
  B <- solve(crossprod(Xk), crossprod(Xk, m$Y[keep, , drop = FALSE]))
  U <- m$Y - m$X %*% B; U[!keep, ] <- 0
  TT <- sum(keep); K <- ncol(m$X); Sigma <- crossprod(U) / (TT - K)
  structure(list(B = B, U = U, Sigma = Sigma, Sigma_ml = crossprod(U) / TT, X = m$X, Yd = m$Y, Y = as.matrix(Y),
                 N = m$N, p = p, TT = nrow(m$Y), K = K, nombres = colnames(Y), keep = keep), class = "mivar")
}
proxy_bootstrap_ex <- function(v, z, j, H, escala, nboot, fechas_u, semilla = 99) {
  set.seed(semilla); z[!v$keep] <- NA
  s0 <- proxy_impacto(v$U, z, j, escala)
  base <- irf_desde_impacto(v$B, v$N, v$p, H, s0); colnames(base) <- v$nombres
  Y0 <- v$Y[1:v$p, , drop = FALSE]; A <- v$B[-1, , drop = FALSE]; c0 <- v$B[1, ]
  draws <- array(NA_real_, c(H + 1, v$N, nboot))
  for (b in 1:nboot) {
    w <- sample(c(-1, 1), v$TT, replace = TRUE); Ub <- v$U * w; zb <- z * w
    Ys <- matrix(0, v$TT + v$p, v$N); Ys[1:v$p, ] <- Y0
    for (t in 1:v$TT) Ys[t + v$p, ] <- c0 + as.vector(t(Ys[(t + v$p - 1):t, , drop = FALSE])) %*% A + Ub[t, ]
    colnames(Ys) <- v$nombres
    vb <- var_ols_ex(Ys, v$p, fechas_u)
    if (max(raices(vb)) >= 1.05) next
    sb <- proxy_impacto(vb$U, zb, j, escala)
    if (!all(is.finite(sb)) || max(abs(sb)) > 50 * escala) next
    draws[, , b] <- irf_desde_impacto(vb$B, v$N, v$p, H, sb)
  }
  ok <- !is.na(draws[1, 1, ]); dr <- draws[, , ok, drop = FALSE]; dimnames(dr) <- list(NULL, v$nombres, NULL)
  list(base = base, draws = dr, H = H, nboot_ok = sum(ok), impacto = setNames(s0, v$nombres))
}
fu <- d$fecha[(P + 1):nrow(d)]
v <- var_ols_ex(Y, P, fu)
message(sprintf("[%s] VAR transmisión %s a %s: T=%d, N=%d, p=%d (AIC=%d, BIC=%d, HQ=%d), raíz máx.=%.3f",
                TEC, format(d$fecha[1], "%Y-%m"), format(max(d$fecha), "%Y-%m"), v$TT, v$N, P, sel[["AIC"]], sel[["BIC"]], sel[["HQ"]], max(raices(v))))

# Choque 1: política (instrumento externo) -----------------------------------------------
# La sorpresa de futuros de fed funds (target) mezcla dos cosas: el endurecimiento "puro" y la
# respuesta de la Fed a noticias económicas que el mercado aún no había incorporado. Si se usa tal cual,
# un alza aparece asociada a una economía que mejora (acciones arriba, desempleo abajo).
# Instrumento principal — Bauer y Swanson (2023): la sorpresa se ortogonaliza respecto de información
# macro-financiera disponible ANTES de la reunión: sorpresa de nóminas del último dato, crecimiento
# del empleo a 12 meses, variación a 3 meses del S&P 500, de la pendiente 10Y-3M y de materias primas.
# Robustez — "poor man's" de Jarociński y Karadi (2020): solo los días en que la sorpresa y el S&P 500
# se movieron en sentido opuesto. Con ventana DIARIA (no de 30 minutos) este criterio selecciona días
# en que las acciones cayeron por cualquier motivo, por eso se reporta solo como comparación.
ev <- read.csv(ruta_vtf("data", "sorpresas_fomc.csv")); ev$fecha_evento <- as.Date(ev$fecha_evento)
ev <- ev[!as.logical(ev$excluir_base) & !is.na(ev$target_pb), ]
diaria <- function(archivo, v) {
  x <- read.csv(archivo, stringsAsFactors = FALSE); x <- x[x$var == v, c("fecha", "valor")]
  x$fecha <- as.Date(x$fecha); x[order(x$fecha), ]
}
sp <- diaria(ruta("data", "raw", "bloomberg_transmision.csv"), "sp500")
y10 <- diaria(ruta_vtf("data", "raw", "bloomberg_tasas.csv"), "y10y"); y3m <- diaria(ruta_vtf("data", "raw", "bloomberg_tasas.csv"), "y3m")
bcom <- diaria(ruta_vtf("data", "raw", "bloomberg_tasas.csv"), "bcom")
pend <- merge(y10, y3m, by = "fecha"); pend <- data.frame(fecha = pend$fecha, valor = pend$valor.x - pend$valor.y)
ultimo <- function(s, f) { i <- findInterval(as.numeric(f), as.numeric(s$fecha)); ifelse(i > 0, s$valor[pmax(i, 1)], NA) }
var3m <- function(s, f, log = TRUE) {           # cambio entre ~3 meses antes y el día previo a la reunión
  a <- ultimo(s, f - 1); b <- ultimo(s, f - 92); if (log) 100 * log(a / b) else a - b
}
ev$sp_3m <- var3m(sp, ev$fecha_evento); ev$bcom_3m <- var3m(bcom, ev$fecha_evento); ev$pend_3m <- var3m(pend, ev$fecha_evento, FALSE)
no <- read.csv(ruta_vtf("data", "raw", "bloomberg_noticias.csv"), stringsAsFactors = FALSE); no <- no[no$var == "nominas", ]
nw <- reshape(no[, c("fecha_obs", "campo", "valor")], idvar = "fecha_obs", timevar = "campo", direction = "wide")
nw <- data.frame(pub = as.Date(nw$valor.ECO_RELEASE_DT), sorp = as.numeric(nw$valor.ACTUAL_RELEASE) - as.numeric(nw$valor.BN_SURVEY_MEDIAN),
                 nivel = as.numeric(nw$valor.PX_LAST), obs = as.Date(nw$fecha_obs))
nw <- nw[!is.na(nw$pub), ]; nw <- nw[order(nw$pub), ]
iu <- findInterval(as.numeric(ev$fecha_evento - 1), as.numeric(nw$pub))
ev$nfp_sorp <- ifelse(iu > 0, nw$sorp[pmax(iu, 1)], NA)
ev$nfp_sorp <- ev$nfp_sorp / sd(ev$nfp_sorp, na.rm = TRUE); ev$nfp_sorp[is.na(ev$nfp_sorp)] <- 0   # sin encuesta antes de 1997: 0
emp <- read.csv(ruta_vtf("data", "raw", "bloomberg_curva_macro.csv")); emp <- emp[emp$var == "nfp", ]; emp$fecha <- as.Date(emp$fecha)
emp <- aggregate(valor ~ fecha, emp, mean); emp <- emp[order(emp$fecha), ]
# crecimiento a 12 meses del último nivel de empleo publicado antes de la reunión (rezago de publicación: 1 mes)
ev$emp_12m <- sapply(ev$fecha_evento, function(f) {
  m <- as.Date(format(f, "%Y-%m-01")); m1 <- seq(m, by = "-1 month", length.out = 3)[3]; m13 <- seq(m1, by = "-12 months", length.out = 2)[2]
  a <- emp$valor[findInterval(as.numeric(m1 + 27), as.numeric(emp$fecha))]; b <- emp$valor[findInterval(as.numeric(m13 + 27), as.numeric(emp$fecha))]
  if (length(a) && length(b)) 100 * log(a / b) else NA })
bs <- lm(target_pb ~ nfp_sorp + emp_12m + sp_3m + pend_3m + bcom_3m, data = ev, na.action = na.exclude)
ev$target_bs <- residuals(bs)
cf <- summary(bs)$coefficients; tb <- data.frame(regresor = rownames(cf), round(cf, 3), R2 = round(summary(bs)$r.squared, 3), n = nobs(bs))
guardar_tabla(tb, "bauer_swanson_regresion"); print(tb, row.names = FALSE)
ev$d_sp <- sapply(ev$fecha_evento, function(f) { i <- match(f, sp$fecha); if (is.na(i) || i < 2) NA else 100 * log(sp$valor[i] / sp$valor[i - 1]) })
ev$tipo <- ifelse(is.na(ev$d_sp), NA, ifelse(sign(ev$target_pb) * sign(ev$d_sp) < 0, "monetaria", "informacion"))
pondera_gk <- function(fechas, valores, meses) {
  z <- setNames(rep(0, length(meses)), as.character(meses)); ok <- !is.na(valores); fechas <- fechas[ok]; valores <- valores[ok]
  for (i in seq_along(fechas)) {
    m <- as.Date(format(fechas[i], "%Y-%m-01")); m2 <- seq(m, by = "month", length.out = 2)[2]
    Dm <- as.numeric(format(m2 - 1, "%d")); dd <- as.numeric(format(fechas[i], "%d"))
    if (as.character(m) %in% names(z)) z[as.character(m)] <- z[as.character(m)] + valores[i] * (Dm - dd + 1) / Dm
    if (as.character(m2) %in% names(z)) z[as.character(m2)] <- z[as.character(m2)] + valores[i] * (dd - 1) / Dm
  }
  unname(z)
}
meses_z <- seq(as.Date("1994-01-01"), max(d$fecha), by = "month")
mon <- !is.na(ev$tipo) & ev$tipo == "monetaria"
Z <- data.frame(fecha = meses_z,
                total = pondera_gk(ev$fecha_evento, ev$target_pb, meses_z),
                bauer_swanson = pondera_gk(ev$fecha_evento, ev$target_bs, meses_z),
                monetaria = pondera_gk(ev$fecha_evento[mon], ev$target_pb[mon], meses_z))
guardar_tabla(data.frame(tipo = c("monetaria", "informacion"), n_eventos = c(sum(ev$tipo == "monetaria", na.rm = TRUE), sum(ev$tipo == "informacion", na.rm = TRUE))),
              "eventos_monetaria_vs_informacion")
z <- Z$bauer_swanson[match(fu, Z$fecha)]; z[!v$keep] <- NA  # instrumento principal (sin meses de pandemia)
jF <- which(VARS == "ffr")
alt <- lapply(c(total = "total", monetaria = "monetaria"), function(k) {
  zk <- Z[[k]][match(fu, Z$fecha)]; zk[!v$keep] <- NA
  list(pb = proxy_bootstrap_ex(v, zk, jF, H, 0.25, NBOOT, fu), fe = primera_etapa(v$U, zk, jF))
})
fe <- primera_etapa(v$U, z, jF)
pb <- proxy_bootstrap_ex(v, z, jF, H, 0.25, NBOOT, fu)
message(sprintf("Choque de política: F primera etapa = %.1f; réplicas válidas = %d", fe$F_robusto, pb$nboot_ok))
irf_pol <- cbind(choque = "Política: +25 pb en la EFFR", irf_tabla(pb))
message(sprintf("Comparación: F total = %.1f; F 'poor man's' = %.1f", alt$total$fe$F_robusto, alt$monetaria$fe$F_robusto))
cmp <- rbind(cbind(instrumento = "Bauer-Swanson (principal)", irf_tabla(pb)),
             cbind(instrumento = "Sorpresa total (sin limpiar)", irf_tabla(alt$total$pb)),
             cbind(instrumento = "Solo días con acciones en sentido opuesto", irf_tabla(alt$monetaria$pb)))
guardar_tabla(cmp, "irf_politica_instrumentos")
guardar_tabla(data.frame(instrumento = c("Bauer-Swanson", "Total", "Acciones opuestas"),
                         rbind(fe, alt$total$fe, alt$monetaria$fe), replicas = c(pb$nboot_ok, alt$total$pb$nboot_ok, alt$monetaria$pb$nboot_ok)),
              "primera_etapa_instrumentos")
cr <- cmp[cmp$variable %in% c("tec", "ip", "nfp", "unemp", "cpi", "y10y"), ]
kk <- ifelse(cr$variable %in% EN_PB, 100, 1); for (cc in c("irf", "q16", "q84")) cr[[cc]] <- cr[[cc]] * kk
cr$variable <- factor(paste0(ETQ[cr$variable], ifelse(cr$variable %in% EN_PB, " (pb)", "")))
gcmp <- ggplot(cr, aes(h, irf, colour = instrumento, fill = instrumento)) + geom_hline(yintercept = 0, colour = "grey50") +
  geom_ribbon(aes(ymin = q16, ymax = q84), alpha = 0.12, colour = NA) + geom_line(linewidth = 0.8) +
  facet_wrap(~variable, scales = "free_y", ncol = 3) + scale_colour_manual(values = c("#0b3c5d", "#8d99ae", "#d1495b")) +
  scale_fill_manual(values = c("#0b3c5d", "#8d99ae", "#d1495b")) +
  labs(title = "Limpiar la sorpresa de la Fed cambia la lectura del choque",
       subtitle = "Respuesta a +25 pb en la EFFR con tres instrumentos; bandas 68%", x = "Meses", y = NULL, colour = NULL, fill = NULL) +
  tema_limpio(9) + guides(colour = guide_legend(ncol = 1))
guardar_fig(gcmp, "politica_instrumentos", ancho = 10, alto = 6)

# Choque 2: estrés tecnológico (restricciones de signo, ortogonal al de política) ----------
# Impactos admisibles a = A q, con A = chol(Sigma)' y q unitario. Ortogonalidad con el choque
# de política: q' A^{-1} s_pol = 0 (los choques estructurales no se correlacionan).
A <- t(chol(v$Sigma)); s_pol <- pb$impacto / pb$impacto[jF] * sqrt(v$Sigma[jF, jF])
w <- solve(A, s_pol); w <- w / sqrt(sum(w^2))
signos <- function(a) a[VARS == "tec"] < 0 && a[VARS == "spread_hy"] > 0 && a[VARS == "ffr"] <= 0 &&
  a[VARS == "ip"] <= 0 && a[VARS == "nfp"] <= 0 && a[VARS == "unemp"] >= 0     # el estrés no mejora la actividad en el mes
acept <- list(); intentos <- 0
while (length(acept) < 500 && intentos < 500000) {
  intentos <- intentos + 1
  q <- rnorm(v$N); q <- q - sum(q * w) * w; q <- q / sqrt(sum(q^2))    # ortogonal al de política
  a <- as.vector(A %*% q)
  if (signos(a)) acept[[length(acept) + 1]] <- a else if (signos(-a)) acept[[length(acept) + 1]] <- -a
}
message(sprintf("Estrés tecnológico: %d rotaciones aceptadas de %d intentos", length(acept), intentos))
Phi <- ma_coef(v$B, v$N, v$p, H)
irf_imp <- function(a) t(sapply(1:(H + 1), function(h) Phi[, , h] %*% a))
dr <- simplify2array(lapply(acept, irf_imp)); dimnames(dr) <- list(NULL, VARS, NULL)
# Entre las rotaciones admisibles se elige la que más explica las acciones tecnológicas en el mes del
# choque (criterio de penalización de Uhlig 2005 / "máxima participación"): así el choque es sobre todo
# tecnológico y no una mezcla con otros choques reales. Las bandas usan todas las rotaciones aceptadas.
a_tec <- acept[[which.max(sapply(acept, function(a) -a[VARS == "tec"]))]]
ib_tec <- list(base = irf_imp(a_tec), draws = dr, H = H); colnames(ib_tec$base) <- VARS
irf_tec <- cbind(choque = "Estrés tecnológico: 1 d.e.", irf_tabla(ib_tec))
guardar_tabla(data.frame(variable = VARS, impacto = a_tec), "impacto_choque_tecnologico")

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
                        paste("Instrumento: sorpresa de futuros de fed funds limpia de noticias previas (Bauer-Swanson; F =", round(fe$F_robusto, 1), ").", cap)), "irf_politica_financiero", 11, 6)
guardar_fig(graf_bloque(irf_pol$choque[1], "Real", "Choque de política (+25 pb): la economía real responde con rezago", cap), "irf_politica_real", 11, 3.6)
guardar_fig(graf_bloque(irf_tec$choque[1], c("Política", "Financiero"), "Choque de estrés tecnológico (1 d.e.): mercados",
                        paste("Signos al impacto: tecnología < 0, spread HY > 0, EFFR ≤ 0, actividad no mejora; ortogonal al choque de política.", cap)), "irf_tecnologico_financiero", 11, 6)
guardar_fig(graf_bloque(irf_tec$choque[1], "Real", "Choque de estrés tecnológico (1 d.e.): economía real", cap), "irf_tecnologico_real", 11, 3.6)

# Escenarios condicionales -------------------------------------------------------------------
# Lo que mueve a la economía no es el alza en sí sino la parte que el mercado NO esperaba. Por eso los
# escenarios se definen como desvío de la EFFR respecto de la trayectoria que hoy descuentan los futuros
# de fed funds (FF1-FF6; después del mes 6 se supone plana). El VAR es lineal: el desvío de cada variable
# respecto de su trayectoria "de mercado" depende solo del desvío de la EFFR (y del choque tecnológico).
# Reuniones de decisión (calendario de la Fed): 9-dic-2026, 27-ene-2027, 17-mar-2027, 28-abr-2027;
# la EFFR cambia al día siguiente.
HS <- 24
pronostico <- function(choques) {           # choques: HS x 2 (política en unidades del impacto s_pol; tecnológico en unidades de a_tec)
  Yh <- rbind(Y, matrix(NA, HS, v$N)); TT <- nrow(Y)
  for (t in 1:HS) {
    x <- c(1, as.vector(t(Yh[(TT + t - 1):(TT + t - P), , drop = FALSE])))
    Yh[TT + t, ] <- x %*% v$B + choques[t, 1] * s_pol + choques[t, 2] * a_tec
  }
  Yh[(TT + 1):(TT + HS), , drop = FALSE]
}
base_f <- pronostico(matrix(0, HS, 2)); colnames(base_f) <- VARS
meses <- seq(max(d$fecha), by = "month", length.out = HS + 1)[-1]

# Trayectoria de mercado: promedio mensual implícito en futuros (precio = 100 - tasa)
fu_f <- read.csv(ruta_vtf("data", "raw", "bloomberg_futuros.csv"), stringsAsFactors = FALSE); fu_f$fecha <- as.Date(fu_f$fecha)
f_dat <- max(fu_f$fecha); fx <- fu_f[fu_f$fecha == f_dat, ]
effr_d <- read.csv(ruta_vtf("data", "raw", "bloomberg_tasas.csv"), stringsAsFactors = FALSE); effr_d <- effr_d[effr_d$var == "ffr", ]
effr0 <- effr_d$valor[which.max(as.Date(effr_d$fecha))]
mes_fut <- seq(as.Date(format(f_dat, "%Y-%m-01")), by = "month", length.out = 6)              # FF1 = mes en curso
mercado_fut <- setNames(sapply(1:6, function(k) { p <- fx$valor[fx$var == paste0("ff", k)]; if (length(p)) 100 - p else NA }), as.character(mes_fut))
if (is.na(mercado_fut[1])) mercado_fut[1] <- effr0
mercado <- approx(as.numeric(mes_fut), mercado_fut, as.numeric(meses), rule = 2)$y            # plana después del último contrato
# EFFR promedio mensual si la Fed mueve "pasos" (pp) en cada reunión
REUNION <- as.Date(c("2026-12-10", "2027-01-28", "2027-03-18", "2027-04-29"))                  # día en que cambia la EFFR
tray <- function(pasos) sapply(meses, function(m) {
  dias <- seq(m, seq(m, by = "month", length.out = 2)[2] - 1, by = "day")
  mean(sapply(dias, function(dd) effr0 + sum(pasos[REUNION <= dd])))
})
DEF <- list(
  "Fed +50 pb a enero, luego pausa"       = list(pasos = c(0.25, 0.25, 0, 0), tec = 0),
  "Fed en pausa (no sube)"                = list(pasos = c(0, 0, 0, 0), tec = 0),
  "Fed +100 pb a enero, luego pausa"      = list(pasos = c(0.50, 0.50, 0, 0), tec = 0),
  "Fed +50 pb a enero + corrección tecnológica" = list(pasos = c(0.25, 0.25, 0, 0), tec = -15),
  "Referencia: +50 pb que nadie esperaba" = list(desv = c(0, 0.25, rep(0.5, 10)), tec = 0))
MES_TEC <- 3                                  # la corrección tecnológica ocurre en el tercer mes (enero de 2027)
escala_tec <- function(caida) caida / a_tec[VARS == "tec"]   # cuántas "unidades" del choque dan esa caída al impacto
escenario <- function(desv, tec) {
  ch <- matrix(0, HS, 2); if (tec != 0) ch[MES_TEC, 2] <- escala_tec(tec)
  b0 <- pronostico(ch)                        # con el choque tecnológico pero sin choques de política
  for (t in seq_along(desv)) {                # choque de política que deja la EFFR en base + desvío pedido
    f0 <- pronostico(ch)[t, jF]
    ch[t, 1] <- (base_f[t, jF] + desv[t] - f0) / s_pol[jF]
  }
  e <- pronostico(ch); colnames(e) <- VARS; list(e = e, ch = ch)
}
ESC <- NULL; TRAY_EFFR <- data.frame(mes = meses, mercado = mercado)
for (nm in names(DEF)) {
  dd <- DEF[[nm]]
  if (is.null(dd$desv)) { tr_e <- tray(dd$pasos); desv <- (tr_e - mercado)[1:12] } else { desv <- dd$desv; tr_e <- mercado + c(desv, rep(NA, HS - 12)) }
  r <- escenario(desv, dd$tec)
  TRAY_EFFR[[nm]] <- tr_e
  ESC <- rbind(ESC, data.frame(escenario = nm, mes = meses, h = 1:HS, desvio_effr_objetivo_pb = c(desv, rep(NA, HS - 12)) * 100,
                               do.call(cbind, lapply(VARS, function(k) setNames(data.frame((r$e[, k] - base_f[, k]) * ifelse(k %in% EN_PB, 100, 1)), k)))))
}
guardar_tabla(ESC, "escenarios_desvio_vs_mercado")
guardar_tabla(TRAY_EFFR, "escenarios_trayectoria_effr")
message(sprintf("Futuros al %s: EFFR %.2f%%; mercado descuenta %.2f%% en %s y %.2f%% en %s", format(f_dat, "%d-%m-%Y"), effr0,
                mercado[3], format(meses[3], "%b-%Y"), mercado[4], format(meses[4], "%b-%Y")))
print(data.frame(mes = format(meses[1:8], "%Y-%m"), round(TRAY_EFFR[1:8, -1], 3)), row.names = FALSE)
res <- ESC[ESC$h %in% c(3, 6, 12, 24), c("escenario", "h", VARS)]
res[, VARS] <- round(res[, VARS], 2); print(res, row.names = FALSE)

# Gráfico: variables seleccionadas, desvío respecto de la trayectoria de mercado
SEL <- c("ffr", "y2y", "y10y", "dxy", "oro", "tec", "spread_hy", "ip", "unemp", "cpi")
el <- do.call(rbind, lapply(SEL, function(k) data.frame(escenario = ESC$escenario, h = ESC$h, variable = k, valor = ESC[[k]])))
el$variable <- factor(paste0(ETQ[el$variable], ifelse(el$variable %in% EN_PB, " (pb)", "")),
                      levels = paste0(ETQ[SEL], ifelse(SEL %in% EN_PB, " (pb)", "")))
el$escenario <- factor(el$escenario, levels = names(DEF))
g <- ggplot(el, aes(h, valor, colour = escenario, linetype = escenario)) + geom_hline(yintercept = 0, colour = "grey50") + geom_line(linewidth = 0.8) +
  facet_wrap(~variable, scales = "free_y", ncol = 5) +
  scale_colour_manual(values = c("#0b3c5d", "#2a9d8f", "#d1495b", "#e9a03b", "#8d99ae")) +
  scale_linetype_manual(values = c("solid", "solid", "solid", "solid", "dashed")) +
  labs(title = "Escenarios de la Fed: desvío respecto de lo que hoy descuenta el mercado",
       subtitle = sprintf("Trayectoria de mercado = futuros de fed funds al %s. Corrección tecnológica: -15%% en el mes %d.", format(f_dat, "%d-%m-%Y"), MES_TEC),
       x = sprintf("Meses desde %s", format(meses[1] - 1, "%b-%Y")), y = NULL, colour = NULL, linetype = NULL) +
  tema_limpio(9) + guides(colour = guide_legend(ncol = 2))
guardar_fig(g, "escenarios_condicionales", ancho = 12, alto = 6.5)
saveRDS(list(v = v, s_pol = s_pol, a_tec = a_tec, VARS = VARS, ESC = ESC, TRAY = TRAY_EFFR, base_f = base_f, d = d, f_dat = f_dat, Z = Z, base = base),
        ruta("output", paste0("modelo_transmision", SUF, ".rds")))
