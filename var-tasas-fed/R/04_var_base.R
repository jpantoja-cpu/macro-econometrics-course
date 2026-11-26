# 04_var_base.R ---------------------------------------------------------
# VAR en niveles con identificación recursiva (Cholesky).
#   Orden: [log IP, log IPC, log BCOM, política, 3M, 2Y, 5Y, 10Y, 30Y]
#   - Bloque lento (macro): no reacciona dentro del mes al choque de política.
#   - Bloque rápido (tasas de mercado): reacciona dentro del mes.
# Dos especificaciones:
#   A) Principal: 1988-2007, política = fed funds efectiva (antes del límite inferior cero).
#   B) Muestra completa: política = tasa a 1 año (Gertler-Karadi 2015), que sí se
#      mueve en el ZLB por la guía futura y las compras de activos.
# Choque normalizado a +25 pb sobre la variable de política. En un VAR lineal la
# respuesta a −25 pb es exactamente el espejo (se reporta igual, para dejarlo claro).

local({
  cand <- c("R/utils.R", "var-tasas-fed/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/var-tasas-fed/R/utils.R")
  source(cand[file.exists(cand)][1])
})
source(ruta("R", "var_funciones.R"))
suppressPackageStartupMessages({ library(ggplot2); library(patchwork) })

NBOOT <- as.numeric(Sys.getenv("NBOOT", 1000))   # réplicas bootstrap
H     <- 48       # horizonte de las IRF (meses)
PMIN  <- 6; PMAX <- 12

base <- read.csv(ruta("data", "base_mensual.csv")); base$fecha <- as.Date(base$fecha)

ESPEC <- list(
  A = list(nombre = "A: 1988-2007, fed funds", desde = "1988-01-01", hasta = "2007-12-01",
           vars = c("ip", "cpi", "bcom", "ffr", "y3m", "y2y", "y5y", "y10y", "y30y"), politica = "ffr"),
  B = list(nombre = "B: muestra completa, tasa 1 año como política", desde = "1988-01-01", hasta = NA,
           vars = c("ip", "cpi", "bcom", "y1y", "y3m", "y2y", "y5y", "y10y", "y30y"), politica = "y1y")
)
CURVA <- c("y3m", "y2y", "y5y", "y10y", "y30y")
SPREADS <- list(s10y3m = c(y10y = 1, y3m = -1), s30y2y = c(y30y = 1, y2y = -1))

estimar <- function(e, clave) {
  hasta <- if (is.na(e$hasta)) max(base$fecha) else as.Date(e$hasta)
  d <- base[base$fecha >= as.Date(e$desde) & base$fecha <= hasta, c("fecha", e$vars)]
  Y <- as.matrix(d[, e$vars]); rownames(Y) <- format(d$fecha, "%Y-%m")
  ic <- seleccion_rezagos(Y, PMAX)
  sel <- sapply(ic[, c("AIC", "BIC", "HQ")], which.min)
  # Regla: HQ (punto medio entre AIC y BIC), acotado a [PMIN, PMAX] porque con
  # datos mensuales menos de 6 rezagos no captura la dinámica de la política.
  p <- min(max(sel[["HQ"]], PMIN), PMAX)
  v <- var_ols(Y, p)
  j <- which(e$vars == e$politica)
  message(sprintf("[%s] %s a %s, T=%d, p=%d (AIC=%d, BIC=%d, HQ=%d), raíz máx.=%.3f",
                  clave, rownames(Y)[1], rownames(Y)[nrow(Y)], v$TT, p, sel[["AIC"]], sel[["BIC"]], sel[["HQ"]], max(raices(v))))
  ib <- irf_bootstrap(v, H = H, choque = j, escala = 0.25, nboot = NBOOT)
  tab <- irf_tabla(ib, SPREADS)
  diag <- rbind(portmanteau(v, 24), lm_serial(v, 12))
  list(e = e, d = d, v = v, p = p, ic = cbind(espec = clave, ic), sel = sel, ib = ib, tab = cbind(espec = clave, tab),
       fevd = cbind(espec = clave, fevd_chol(v)), diag = cbind(espec = clave, diag),
       diag_eq = cbind(espec = clave, diag_ecuaciones(v)), j = j,
       choque = data.frame(fecha = d$fecha[(p + 1):nrow(d)], e = choques_estructurales(v)[, j],
                           sd_pp = t(chol(v$Sigma))[j, j]))
}

res <- lapply(names(ESPEC), function(k) estimar(ESPEC[[k]], k)); names(res) <- names(ESPEC)
saveRDS(res, ruta("output", "var_base.rds"))

# Tablas -------------------------------------------------------------------
guardar_tabla(do.call(rbind, lapply(res, `[[`, "ic")), "seleccion_rezagos")
guardar_tabla(do.call(rbind, lapply(res, `[[`, "tab")), "irf_var_base")
guardar_tabla(do.call(rbind, lapply(res, `[[`, "diag")), "diagnosticos_sistema")
guardar_tabla(do.call(rbind, lapply(res, `[[`, "diag_eq")), "diagnosticos_ecuaciones")
guardar_tabla(data.frame(espec = names(res), raiz_max = sapply(res, function(r) max(raices(r$v))),
                         p = sapply(res, `[[`, "p"), T = sapply(res, function(r) r$v$TT),
                         sd_choque_pb = sapply(res, function(r) 100 * r$choque$sd_pp[1]),
                         nboot_ok = sapply(res, function(r) r$ib$nboot_ok)), "resumen_especificaciones")
for (k in names(res)) write.csv(res[[k]]$choque, ruta("output", "tablas", paste0("choque_politica_", k, ".csv")), row.names = FALSE)

# FEVD: participación del choque de política en la varianza de cada tasa
fv <- do.call(rbind, lapply(res, function(r) {
  f <- r$fevd; col <- paste0("choque_", r$e$politica)
  data.frame(espec = f$espec, horizonte = f$horizonte, variable = f$variable,
             participacion_politica_pct = round(100 * f[[col]], 1))
}))
fv <- fv[fv$variable %in% c(CURVA, "ip", "cpi"), ]
guardar_tabla(fv, "fevd_choque_politica")

# Tabla resumen de respuestas (pb) en horizontes clave
resumen_h <- function(tab, hs = c(0, 3, 6, 12, 24, 48)) {
  t2 <- tab[tab$h %in% hs & tab$variable %in% c(CURVA, names(SPREADS)), ]
  data.frame(espec = t2$espec, variable = etiq(t2$variable), h = t2$h,
             irf_pb = round(100 * t2$irf, 1), banda68 = sprintf("[%.1f, %.1f]", 100 * t2$q16, 100 * t2$q84),
             banda90 = sprintf("[%.1f, %.1f]", 100 * t2$q05, 100 * t2$q95))
}
guardar_tabla(do.call(rbind, lapply(res, function(r) resumen_h(r$tab))), "irf_resumen_pb")

# Figuras ------------------------------------------------------------------
for (k in names(res)) {
  r <- res[[k]]
  cap <- sprintf("VAR(%d) en niveles, T=%d, identificación Cholesky. Bandas bootstrap 68%% y 90%% (%d réplicas). Fuente: Bloomberg.",
                 r$p, r$v$TT, r$ib$nboot_ok)
  g <- graf_irf(r$tab, c(r$e$politica, CURVA), ncol = 3,
                titulo = sprintf("Respuesta de la curva del Tesoro a un alza de 25 pb (%s)", r$e$nombre),
                subtitulo = "Un recorte de 25 pb da la misma respuesta con signo opuesto (VAR lineal)", caption = cap)
  guardar_fig(g, paste0("irf_curva_", k), ancho = 10, alto = 6.5)
  g2 <- graf_irf(r$tab, names(SPREADS), ncol = 2, titulo = sprintf("Pendiente de la curva ante un alza de 25 pb (%s)", r$e$nombre),
                 subtitulo = "Negativo = la curva se aplana", caption = cap)
  guardar_fig(g2, paste0("irf_pendiente_", k), ancho = 9, alto = 4)
  g3 <- graf_irf(r$tab, c("ip", "cpi", "bcom"), pb = FALSE, ncol = 3,
                 titulo = sprintf("Bloque macro ante un alza de 25 pb (%s)", r$e$nombre),
                 subtitulo = "Respuesta en % (log×100)", caption = cap)
  guardar_fig(g3, paste0("irf_macro_", k), ancho = 10, alto = 3.8)
}

# Alza vs recorte (espejo) para 2Y y 10Y, especificación A
r <- res$A; t2 <- r$tab[r$tab$variable %in% c("y2y", "y10y"), ]
dd <- rbind(transform(t2, choque = "Alza de 25 pb"),
            transform(t2, choque = "Recorte de 25 pb", irf = -irf, q05 = -q95, q95 = -q05, q16 = -q84, q84 = -q16))
dd$variable <- factor(etiq(dd$variable), levels = etiq(c("y2y", "y10y")))
g4 <- ggplot(dd, aes(h, colour = choque, fill = choque)) + geom_hline(yintercept = 0, colour = "grey50") +
  geom_ribbon(aes(ymin = 100 * q16, ymax = 100 * q84), alpha = 0.2, colour = NA) +
  geom_line(aes(y = 100 * irf), linewidth = 0.8) + facet_wrap(~variable) +
  scale_colour_manual(values = c("#d1495b", "#1b6ca8")) + scale_fill_manual(values = c("#d1495b", "#1b6ca8")) +
  labs(title = "En el VAR lineal, un recorte es el espejo de un alza",
       subtitle = "Especificación A. Para medir asimetría real ver proyecciones locales (script 05)",
       x = "Meses después del choque", y = "Puntos básicos", colour = NULL, fill = NULL) + tema_limpio()
guardar_fig(g4, "irf_alza_vs_recorte_A", ancho = 9, alto = 4)

print(do.call(rbind, lapply(res, function(r) resumen_h(r$tab, c(0, 12, 24)))))
