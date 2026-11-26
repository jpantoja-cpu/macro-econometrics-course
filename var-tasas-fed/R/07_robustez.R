# 07_robustez.R ---------------------------------------------------------
# Robustez de la especificación A (1988-2007, fed funds):
#   1) BVAR Minnesota (observaciones ficticias, Banbura-Giannone-Reichlin 2010),
#      tensión lambda elegida maximizando la verosimilitud marginal (como en
#      Giannone-Lenza-Primiceri 2015, pero por grilla).
#   2) Rezagos alternativos (p−3 y p+3).
#   3) Ordenamiento alternativo: política primero (la macro puede reaccionar
#      dentro del mes al choque).
#   4) Muestra completa con fed funds (contaminada por el límite inferior cero; se muestra
#      para ver por qué no es la especificación principal).
#   5) Sin la tasa a 3M (casi colineal con la fed funds).

local({
  cand <- c("R/utils.R", "var-tasas-fed/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/var-tasas-fed/R/utils.R")
  source(cand[file.exists(cand)][1])
})
source(ruta("R", "var_funciones.R"))
suppressPackageStartupMessages({ library(ggplot2) })

NBOOT <- as.numeric(Sys.getenv("NBOOT", 500)); H <- 48
res  <- readRDS(ruta("output", "var_base.rds")); A <- res$A
base <- read.csv(ruta("data", "base_mensual.csv")); base$fecha <- as.Date(base$fecha)
VER  <- c("y3m", "y2y", "y5y", "y10y", "y30y")

datos <- function(vars, desde = "1988-01-01", hasta = "2007-12-01") {
  hasta <- if (is.na(hasta)) max(base$fecha) else as.Date(hasta)
  as.matrix(base[base$fecha >= as.Date(desde) & base$fecha <= hasta, vars])
}
corre_ols <- function(nombre, vars, p, desde = "1988-01-01", hasta = "2007-12-01", pol = "ffr") {
  Y <- datos(vars, desde, hasta); v <- var_ols(Y, p)
  ib <- irf_bootstrap(v, H, which(vars == pol), 0.25, NBOOT)
  message(sprintf("  %-40s p=%d T=%d raíz máx.=%.3f", nombre, p, v$TT, max(raices(v))))
  cbind(espec = nombre, irf_tabla(ib))
}

out <- list()
out[[1]] <- cbind(espec = sprintf("Base A: VAR(%d) MCO", A$p), A$tab[A$tab$variable %in% VER, -1])

# 1) BVAR
Y <- datos(A$e$vars)
grid <- bvar_lambda(Y, A$p, seq(0.02, 1, by = 0.02))
lam <- grid$lambda[which.max(grid$logML)]
guardar_tabla(grid, "bvar_lambda_logml")
message(sprintf("  BVAR: lambda óptimo = %.2f", lam))
fit <- bvar_fit(Y, A$p, lam)
bi <- bvar_irf(fit, H, which(A$e$vars == "ffr"), 0.25, ndraws = 1000)
out[[2]] <- cbind(espec = sprintf("BVAR Minnesota (lambda=%.2f)", lam), irf_tabla(bi))

# 2) Rezagos
out[[3]] <- corre_ols(sprintf("VAR(%d)", max(2, A$p - 3)), A$e$vars, max(2, A$p - 3))
out[[4]] <- corre_ols(sprintf("VAR(%d)", A$p + 3), A$e$vars, A$p + 3)
# 3) Orden: política primero
out[[5]] <- corre_ols("Política primero en el orden", c("ffr", "ip", "cpi", "bcom", VER), A$p)
# 4) Muestra completa con fed funds
out[[6]] <- corre_ols("Muestra completa con fed funds (ZLB)", A$e$vars, A$p, hasta = NA)
# 5) Sin 3M
out[[7]] <- corre_ols("Sin tasa 3M", setdiff(A$e$vars, "y3m"), A$p)

rob <- do.call(rbind, out); rownames(rob) <- NULL
rob <- rob[rob$variable %in% VER, ]
guardar_tabla(rob, "robustez_irf")

rob$variable <- factor(etiq(rob$variable), levels = etiq(VER))
base_lbl <- unique(rob$espec)[1]
g <- ggplot(rob, aes(h, 100 * irf, colour = espec, linewidth = espec == base_lbl)) +
  geom_hline(yintercept = 0, colour = "grey50") +
  geom_ribbon(data = rob[rob$espec == base_lbl, ], aes(ymin = 100 * q16, ymax = 100 * q84),
              fill = "grey70", alpha = 0.4, colour = NA, inherit.aes = TRUE, show.legend = FALSE) +
  geom_line() + scale_linewidth_manual(values = c(0.5, 1.1), guide = "none") +
  scale_colour_manual(values = c("#000000", "#d1495b", "#e1a33b", "#3b9ab2", "#6a3d9a", "#8c8c8c", "#66a61e")) +
  facet_wrap(~variable, scales = "free_y", ncol = 3) +
  labs(title = "Robustez: respuesta de la curva a un alza de 25 pb de la fed funds",
       subtitle = "Negro grueso = especificación A (banda gris 68%). Resto = variantes",
       x = "Meses después del choque", y = "Puntos básicos", colour = NULL) +
  tema_limpio() + guides(colour = guide_legend(ncol = 2))
guardar_fig(g, "robustez_irf", ancho = 10, alto = 7)

# Tabla compacta: impacto y 12 meses
comp <- rob[rob$h %in% c(0, 12, 24), c("espec", "variable", "h", "irf")]
comp$irf_pb <- round(100 * comp$irf, 1); comp$irf <- NULL
comp <- reshape(comp, idvar = c("espec", "variable"), timevar = "h", direction = "wide")
guardar_tabla(comp, "robustez_resumen_pb"); print(comp)
