# 06_precios_bonos.R ----------------------------------------------------
# De rendimientos a precios. Para cada tramo se toma un bono a la par de plazo
# constante (cupón semestral = rendimiento inicial) y se revalúa con el
# rendimiento inicial + la respuesta del VAR en cada horizonte:
#   ΔP/P(h) = P(y0 + Δy_h ; cupón = y0) / 100 − 1     (revaluación exacta)
# También se reporta la aproximación por duración modificada y convexidad.
# Supuesto: se mide el cambio de precio de un bono "nuevo" del mismo plazo en cada
# horizonte (no el retorno de mantener un bono que se acorta con el tiempo).
# 3M se trata como bono cero cupón. Rendimiento inicial y0 = promedio de los últimos 12 meses.
# Si la descarga incluyó índices total return del Tesoro, se estima además su
# respuesta directa por proyecciones locales como validación.

local({
  cand <- c("R/utils.R", "var-tasas-fed/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/var-tasas-fed/R/utils.R")
  source(cand[file.exists(cand)][1])
})
source(ruta("R", "var_funciones.R"))
suppressPackageStartupMessages({ library(ggplot2) })

res  <- readRDS(ruta("output", "var_base.rds"))
base <- read.csv(ruta("data", "base_mensual.csv")); base$fecha <- as.Date(base$fecha)
PLAZO <- c(y3m = 0.25, y2y = 2, y5y = 5, y10y = 10, y30y = 30)

precio <- function(y, cupon, n) {                    # y y cupón en %, n en años
  if (n < 1) return(100 / (1 + y / 100)^n)
  k <- 2 * n; r <- y / 200; c <- cupon / 2
  c * (1 - (1 + r)^(-k)) / r + 100 * (1 + r)^(-k)
}
dur_conv <- function(y0, n, dy = 0.01) {             # numéricas; dy en pp (0.01 = 1 pb)
  p0 <- precio(y0, y0, n); pu <- precio(y0 + dy, y0, n); pd <- precio(y0 - dy, y0, n)
  c(dmod = -(pu - pd) / (2 * (dy / 100) * p0),          # años
    conv = (pu + pd - 2 * p0) / ((dy / 100)^2 * p0))     # en términos decimales
}

y0 <- sapply(names(PLAZO), function(v) mean(tail(base[[v]], 12)))
dc <- t(sapply(names(PLAZO), function(v) dur_conv(y0[[v]], PLAZO[[v]])))
info <- data.frame(tramo = etiq(names(PLAZO)), plazo_anios = PLAZO, y0_pct = round(y0, 2),
                   duracion_mod = round(dc[, "dmod"], 2), convexidad = round(dc[, "conv"], 2))
guardar_tabla(info, "bonos_duracion")

tabla_precios <- function(k, hs = c(0, 12, 24)) {
  t <- res[[k]]$tab
  do.call(rbind, lapply(names(PLAZO), function(v) {
    tv <- t[t$variable == v & t$h %in% hs, ]
    rp <- function(dy) 100 * (sapply(dy, function(z) precio(y0[[v]] + z, y0[[v]], PLAZO[[v]])) / precio(y0[[v]], y0[[v]], PLAZO[[v]]) - 1)
    data.frame(espec = k, tramo = etiq(v), h = tv$h, dy_pb = round(100 * tv$irf, 1),
               dP_pct = round(rp(tv$irf), 2),
               dP_pct_banda68 = sprintf("[%.2f, %.2f]", rp(tv$q84), rp(tv$q16)),   # precio cae cuando la tasa sube
               dP_pct_duracion = round(-dc[v, "dmod"] * tv$irf + 0.5 * dc[v, "conv"] * tv$irf^2 / 100, 2))
  }))
}
tp <- rbind(tabla_precios("A"), tabla_precios("B"))
guardar_tabla(tp, "precios_bonos_respuesta"); print(tp)

# Figura: respuesta del precio (%) por tramo en el tiempo, especificación A
fig_precio <- function(k) {
  t <- res[[k]]$tab
  dd <- do.call(rbind, lapply(names(PLAZO), function(v) {
    tv <- t[t$variable == v, ]; p0 <- precio(y0[[v]], y0[[v]], PLAZO[[v]])
    f <- function(z) 100 * (sapply(z, function(q) precio(y0[[v]] + q, y0[[v]], PLAZO[[v]])) / p0 - 1)
    data.frame(h = tv$h, tramo = etiq(v), m = f(tv$irf), lo = f(tv$q84), hi = f(tv$q16))
  }))
  dd$tramo <- factor(dd$tramo, levels = etiq(names(PLAZO)))
  ggplot(dd, aes(h, m, colour = tramo, fill = tramo)) + geom_hline(yintercept = 0, colour = "grey50") +
    geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.12, colour = NA) + geom_line(linewidth = 0.8) +
    scale_colour_manual(values = unname(COL_TRAMO)) + scale_fill_manual(values = unname(COL_TRAMO)) +
    labs(title = sprintf("Precio de los bonos del Tesoro ante un alza de 25 pb (especificación %s)", k),
         subtitle = "Bono a la par de plazo constante revaluado con la respuesta del VAR; bandas 68%",
         x = "Meses después del choque", y = "Cambio de precio (%)", colour = "Tramo", fill = "Tramo",
         caption = sprintf("Rendimiento inicial: promedio de los últimos 12 meses. Duraciones: %s.",
                           paste(sprintf("%s %.1f", info$tramo, info$duracion_mod), collapse = ", "))) +
    tema_limpio()
}
guardar_fig(fig_precio("A"), "precios_bonos_A", ancho = 9, alto = 5)
guardar_fig(fig_precio("B"), "precios_bonos_B", ancho = 9, alto = 5)

# Validación con índices total return (si existen) --------------------------
tr <- grep("^tr_", names(base), value = TRUE)
if (length(tr)) {
  r <- res$B; ch <- merge(base, r$choque, by = "fecha"); x <- ch$e * ch$sd_pp
  ctrl <- rezagos_df(ch[, r$e$vars], 6)
  val <- do.call(rbind, lapply(tr, function(v) {
    if (sum(!is.na(ch[[v]])) < 120) return(NULL)
    ok <- !is.na(ch[[v]])
    l <- lp_asimetrica(ch[[v]][ok], x[ok], ctrl[ok, , drop = FALSE], H = 24)
    # efecto simétrico = promedio ponderado; aquí se reporta b+ y b− por separado (×0.25 = por 25 pb)
    data.frame(indice = v, h = l$h, dP_alza25_pct = 0.25 * l$b_pos, dP_recorte25_pct = -0.25 * l$b_neg)
  }))
  if (!is.null(val)) {
    guardar_tabla(val, "precios_indices_tr_lp")
    print(val[val$h %in% c(0, 12, 24), ])
  }
} else message("Sin índices total return en la descarga: se omite la validación directa de precios.")
