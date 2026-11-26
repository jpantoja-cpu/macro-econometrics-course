# 10_proxy_svar.R -------------------------------------------------------
# VAR mensual identificado con las sorpresas de mercado como instrumento externo
# (Stock y Watson 2012; Mertens y Ravn 2013; Gertler y Karadi 2015). En lugar de
# suponer un orden (Cholesky), el choque de política es la parte de los residuos
# del VAR correlacionada con la sorpresa de futuros en los días FOMC.
#
#   P1: política = EFFR, VAR 1988-01 a 2008-11 (antes del ZLB),
#       instrumento = sorpresa target (FF1), 1994-2008.
#   P2: política = EFFR, VAR 1988-01 a 2026-10 (muestra completa),
#       instrumento = sorpresa target. En el ZLB la EFFR casi no se mueve:
#       se reporta para mostrar qué pasa con más datos usando la EFFR.
#   P3: política = 2Y, muestra completa, instrumento = sorpresa FF4 (target + path),
#       que sí tiene variación en el ZLB.
# Se reporta el F de primera etapa (robusto): F < 10 = instrumento débil.
# Bandas: wild bootstrap recursivo (Rademacher), 68% y 90%.

local({
  cand <- c("R/utils.R", "var-tasas-fed/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/var-tasas-fed/R/utils.R")
  source(cand[file.exists(cand)][1])
})
source(ruta("R", "var_funciones.R"))
suppressPackageStartupMessages({ library(ggplot2) })

NBOOT <- as.numeric(Sys.getenv("NBOOT", 500)); H <- 48; P <- 6
base <- read.csv(ruta("data", "base_mensual.csv")); base$fecha <- as.Date(base$fecha)
zm <- read.csv(ruta("data", "sorpresas_mensuales.csv")); zm$fecha <- as.Date(zm$fecha)
CURVA <- c("y3m", "y2y", "y5y", "y10y", "y30y")

ESP <- list(
  P1 = list(nombre = "P1: EFFR, 1988-2008, instrumento target", hasta = "2008-11-01",
            vars = c("ip", "cpi", "bcom", "ffr", CURVA), pol = "ffr", z = "target_pb"),
  P2 = list(nombre = "P2: EFFR, muestra completa, instrumento target", hasta = NA,
            vars = c("ip", "cpi", "bcom", "ffr", CURVA), pol = "ffr", z = "target_pb"),
  P3 = list(nombre = "P3: 2Y, muestra completa, instrumento FF4", hasta = NA,
            vars = c("ip", "cpi", "bcom", "y2y", "y3m", "y5y", "y10y", "y30y"), pol = "y2y", z = "ff4_pb")
)

corre <- function(k) {
  e <- ESP[[k]]
  hasta <- if (is.na(e$hasta)) max(base$fecha) else as.Date(e$hasta)
  d <- base[base$fecha >= as.Date("1988-01-01") & base$fecha <= hasta, c("fecha", e$vars)]
  v <- var_ols(as.matrix(d[, e$vars]), P)
  fechas_u <- d$fecha[(P + 1):nrow(d)]
  z <- zm[[e$z]][match(fechas_u, zm$fecha)]           # NA antes de 1994 (fuera de la muestra del instrumento)
  j <- which(e$vars == e$pol)
  fe <- primera_etapa(v$U, z, j)
  pb <- proxy_bootstrap(v, z, j, H, 0.25, NBOOT)
  message(sprintf("[%s] T=%d, meses con instrumento=%d, F primera etapa=%.1f, réplicas válidas=%d",
                  k, v$TT, fe$n, fe$F_robusto, pb$nboot_ok))
  list(e = e, fe = cbind(espec = k, nombre = e$nombre, fe), tab = cbind(espec = k, irf_tabla(pb)), pb = pb)
}
px <- lapply(names(ESP), corre); names(px) <- names(ESP)

guardar_tabla(do.call(rbind, lapply(px, `[[`, "fe")), "proxy_primera_etapa")
tab <- do.call(rbind, lapply(px, `[[`, "tab")); guardar_tabla(tab, "proxy_irf")
print(do.call(rbind, lapply(px, `[[`, "fe")), row.names = FALSE)

res_h <- tab[tab$h %in% c(0, 12, 24) & tab$variable %in% c("ffr", CURVA), ]
res_h <- data.frame(espec = res_h$espec, variable = etiq(res_h$variable), h = res_h$h, irf_pb = round(100 * res_h$irf, 1),
                    banda68 = sprintf("[%.1f, %.1f]", 100 * res_h$q16, 100 * res_h$q84))
guardar_tabla(res_h, "proxy_resumen_pb"); print(res_h, row.names = FALSE)

for (k in names(px)) {
  r <- px[[k]]
  g <- graf_irf(r$tab, unique(c(r$e$pol, CURVA)), ncol = 3,
                titulo = sprintf("Respuesta de la curva a un alza de 25 pb (%s)", r$e$nombre),
                subtitulo = sprintf("VAR con instrumento externo (sorpresas de futuros en días FOMC). F de primera etapa = %.1f",
                                    r$fe$F_robusto),
                caption = sprintf("VAR(%d) en niveles. Bandas wild bootstrap 68%% y 90%% (%d réplicas). Fuente: Bloomberg.", P, r$pb$nboot_ok))
  guardar_fig(g, paste0("proxy_irf_", k), ancho = 10, alto = 6.5)
}

# Comparación con Cholesky (especificación A del script 04)
res <- readRDS(ruta("output", "var_base.rds"))
cmp <- rbind(data.frame(metodo = "Cholesky (A, 1988-2007)", res$A$tab[res$A$tab$variable %in% CURVA, c("h", "variable", "irf", "q16", "q84")]),
             data.frame(metodo = "Instrumento externo (P1, 1988-2008)", px$P1$tab[px$P1$tab$variable %in% CURVA, c("h", "variable", "irf", "q16", "q84")]))
cmp$variable <- factor(etiq(cmp$variable), levels = etiq(CURVA))
g <- ggplot(cmp, aes(h, 100 * irf, colour = metodo, fill = metodo)) + geom_hline(yintercept = 0, colour = "grey50") +
  geom_ribbon(aes(ymin = 100 * q16, ymax = 100 * q84), alpha = 0.15, colour = NA) + geom_line(linewidth = 0.8) +
  facet_wrap(~variable, scales = "free_y", ncol = 3) +
  scale_colour_manual(values = c("#0b3c5d", "#d1495b")) + scale_fill_manual(values = c("#0b3c5d", "#d1495b")) +
  labs(title = "Choque de 25 pb en la EFFR: identificación Cholesky vs instrumento de mercado",
       subtitle = "Bandas 68%", x = "Meses después del choque", y = "Puntos básicos", colour = NULL, fill = NULL) + tema_limpio()
guardar_fig(g, "proxy_vs_cholesky", ancho = 10, alto = 6.5)
