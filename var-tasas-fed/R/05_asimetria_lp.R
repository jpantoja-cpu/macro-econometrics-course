# 05_asimetria_lp.R -----------------------------------------------------
# ¿Un alza y un recorte de la Fed mueven la curva de forma simétrica?
# El VAR lineal impone simetría. Aquí se relaja con proyecciones locales (Jordà 2005):
#   y_{t+h} − y_{t−1} = a_h + b+_h x+_t + b−_h x−_t + controles_t + u_{t+h}
# donde x_t es el choque de política identificado en el VAR (en pp de la tasa de
# política), x+ = max(x,0) y x− = min(x,0). Controles: 6 rezagos de las variables del VAR.
# Errores Newey-West con h+1 rezagos. H0 de simetría: b+_h = b−_h.
# Principal: choque de la especificación B (muestra completa, más episodios de
# alzas y recortes). Robustez: choque de la especificación A (1988-2007).

local({
  cand <- c("R/utils.R", "var-tasas-fed/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/var-tasas-fed/R/utils.R")
  source(cand[file.exists(cand)][1])
})
source(ruta("R", "var_funciones.R"))
suppressPackageStartupMessages({ library(ggplot2) })

HLP <- 36; PLP <- 6
res <- readRDS(ruta("output", "var_base.rds"))
CURVA <- c("y3m", "y2y", "y5y", "y10y", "y30y")

lp_espec <- function(k, hasta = NULL) {
  r <- res[[k]]; d <- r$d
  ch <- merge(d, r$choque, by = "fecha")                 # alinea fechas
  if (!is.null(hasta)) ch <- ch[ch$fecha <= as.Date(hasta), ]
  x <- ch$e * ch$sd_pp                                    # choque en pp de la tasa de política
  ctrl <- rezagos_df(ch[, r$e$vars], PLP)
  out <- lapply(unique(c(r$e$politica, CURVA)), function(v) {
    l <- lp_asimetrica(ch[[v]], x, ctrl, H = HLP)
    cbind(espec = k, variable = v, l)
  })
  list(tab = do.call(rbind, out), x = x, fechas = ch$fecha)
}
lp <- list(B = lp_espec("B"), A = lp_espec("A"),
           # Control: choque B hasta 2019-12, sin el episodio recorte 2020 -> alzas 2022
           B_hasta2019 = lp_espec("B", "2019-12-01"))
lp$B_hasta2019$tab$espec <- "B_hasta2019"
tab <- do.call(rbind, lapply(lp, `[[`, "tab")); rownames(tab) <- NULL
guardar_tabla(tab, "lp_asimetria_coeficientes")

# Descripción de los choques
desc <- do.call(rbind, lapply(names(lp), function(k) {
  x <- lp[[k]]$x
  data.frame(espec = k, n_pos = sum(x > 0), n_neg = sum(x < 0),
             media_pos_pb = round(100 * mean(x[x > 0]), 1), media_neg_pb = round(100 * mean(x[x < 0]), 1),
             p95_pos_pb = round(100 * quantile(x[x > 0], .95), 1), p05_neg_pb = round(100 * quantile(x[x < 0], .05), 1))
}))
guardar_tabla(desc, "lp_descripcion_choques"); print(desc)

# Figura: respuesta a +25 pb vs espejo de la respuesta a −25 pb
fig_asim <- function(k) {
  t2 <- tab[tab$espec == k, ]
  dd <- rbind(data.frame(t2[, c("variable", "h")], tipo = "Alza de 25 pb",
                         m = 25 * t2$b_pos, lo = 25 * (t2$b_pos - t2$se_pos), hi = 25 * (t2$b_pos + t2$se_pos)),
              data.frame(t2[, c("variable", "h")], tipo = "Recorte de 25 pb (con signo invertido)",
                         m = 25 * t2$b_neg, lo = 25 * (t2$b_neg - t2$se_neg), hi = 25 * (t2$b_neg + t2$se_neg)))
  vv <- unique(c(res[[k]]$e$politica, CURVA))
  dd$variable <- factor(etiq(dd$variable), levels = etiq(vv))
  sig <- t2[t2$p_igualdad < 0.10, c("variable", "h")]
  sig$variable <- factor(etiq(sig$variable), levels = etiq(vv))
  ggplot(dd, aes(h, colour = tipo, fill = tipo)) +
    geom_hline(yintercept = 0, colour = "grey50") +
    geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.15, colour = NA) +
    geom_line(aes(y = m), linewidth = 0.8) +
    geom_rug(data = sig, aes(x = h), inherit.aes = FALSE, sides = "b", colour = "black", linewidth = 0.6) +
    facet_wrap(~variable, scales = "free_y", ncol = 3) +
    scale_colour_manual(values = c("#d1495b", "#1b6ca8")) + scale_fill_manual(values = c("#d1495b", "#1b6ca8")) +
    labs(title = sprintf("¿Simetría? Alza vs recorte de la Fed (proyecciones locales, choque de la especificación %s)", k),
         subtitle = "Si las líneas coinciden, el efecto es simétrico. Marcas en el eje: diferencia significativa al 10%",
         x = "Meses después del choque", y = "Puntos básicos", colour = NULL, fill = NULL,
         caption = sprintf("Bandas ±1 e.e. Newey-West. Controles: %d rezagos de las variables del VAR. Fuente: Bloomberg.", PLP)) +
    tema_limpio()
}
guardar_fig(fig_asim("B"), "lp_asimetria_B", ancho = 10, alto = 6.5)
guardar_fig(fig_asim("A"), "lp_asimetria_A", ancho = 10, alto = 6.5)
res$B_hasta2019 <- res$B
guardar_fig(fig_asim("B_hasta2019") + labs(title = "¿Simetría? Choque de la especificación B, muestra hasta 2019 (sin 2020-2022)"),
            "lp_asimetria_B_hasta2019", ancho = 10, alto = 6.5)

# Resumen: horizontes donde se rechaza simetría al 10%
rs <- aggregate(p_igualdad ~ espec + variable, data = tab, FUN = function(p) sum(p < 0.10))
names(rs)[3] <- "horizontes_rechaza_simetria_10pct_de_37"
rs$variable <- etiq(rs$variable)
guardar_tabla(rs, "lp_resumen_simetria"); print(rs)
