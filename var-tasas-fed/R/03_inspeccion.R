# 03_inspeccion.R -------------------------------------------------------
# Inspección serie por serie ANTES de estimar (estilo OxMetrics/PcGive):
# nivel, primera diferencia, ACF/PACF, histograma y estacionalidad; pruebas de
# raíz unitaria (ADF, KPSS, Zivot-Andrews) y gráfico de la curva con el ZLB.

local({
  # Busca el utils.R de ESTA carpeta (var-tasas-fed), sin importar dónde esté parado RStudio
  cand <- c(if (file.exists("var-tasas-fed.Rproj")) "R/utils.R", "var-tasas-fed/R/utils.R", "../var-tasas-fed/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/var-tasas-fed/R/utils.R")
  source(cand[file.exists(cand)][1])
})
suppressPackageStartupMessages({ library(ggplot2); library(patchwork); library(urca) })

base <- read.csv(ruta("data", "base_mensual.csv")); base$fecha <- as.Date(base$fecha)
series <- intersect(c("ffr", "y3m", "y1y", "y2y", "y5y", "y10y", "y30y", "ip", "cpi", "bcom", "unemp"), names(base))

acf_df <- function(x, lag.max = 36, tipo = "acf") {
  a <- if (tipo == "acf") acf(x, lag.max = lag.max, plot = FALSE, na.action = na.pass)
       else pacf(x, lag.max = lag.max, plot = FALSE, na.action = na.pass)
  data.frame(lag = as.numeric(a$lag), r = as.numeric(a$acf))[if (tipo == "acf") -1 else TRUE, ]
}
g_acf <- function(x, titulo, tipo = "acf") {
  d <- acf_df(x, tipo = tipo); ci <- 1.96 / sqrt(sum(!is.na(x)))
  ggplot(d, aes(lag, r)) + geom_hline(yintercept = 0, colour = "grey50") +
    geom_hline(yintercept = c(-ci, ci), linetype = 2, colour = "#d1495b", linewidth = 0.3) +
    geom_segment(aes(xend = lag, yend = 0), colour = "#0b3c5d") +
    labs(title = titulo, x = "Rezago (meses)", y = NULL) + tema_limpio(8)
}

panel_serie <- function(v) {
  d <- data.frame(fecha = base$fecha, x = base[[v]])
  d$dx <- c(NA, diff(d$x)); d$mes <- factor(format(d$fecha, "%m"))
  u_dx <- if (v %in% c("ip", "cpi", "bcom")) "Δ log×100 (≈ % mensual)" else "Δ mensual (pp)"
  g1 <- ggplot(d, aes(fecha, x)) +
    geom_rect(data = ZLB, aes(xmin = ini, xmax = fin, ymin = -Inf, ymax = Inf), inherit.aes = FALSE,
              fill = "grey85", alpha = 0.6) +
    geom_line(colour = "#0b3c5d", linewidth = 0.4) + labs(title = "Nivel", x = NULL, y = NULL) + tema_limpio(8)
  g2 <- ggplot(d, aes(fecha, dx)) + geom_hline(yintercept = 0, colour = "grey60") +
    geom_line(colour = "#1b6ca8", linewidth = 0.3) + labs(title = "Primera diferencia", x = NULL, y = u_dx) + tema_limpio(8)
  g3 <- g_acf(d$x, "ACF del nivel"); g4 <- g_acf(d$dx, "ACF de la diferencia")
  g5 <- g_acf(d$dx, "PACF de la diferencia", "pacf")
  g6 <- ggplot(d[!is.na(d$dx), ], aes(dx)) + geom_histogram(aes(y = after_stat(density)), bins = 40,
        fill = "#1b6ca8", alpha = 0.6) + geom_density(colour = "#0b3c5d") +
        labs(title = "Densidad de la diferencia", x = u_dx, y = NULL) + tema_limpio(8)
  g7 <- ggplot(d[!is.na(d$dx), ], aes(mes, dx)) + geom_boxplot(fill = "#e1a33b", alpha = 0.5, outlier.size = 0.4) +
        labs(title = "Estacionalidad: Δ por mes calendario", x = "Mes", y = NULL) + tema_limpio(8)
  (g1 | g2) / (g3 | g4) / (g5 | g6) / g7 +
    plot_annotation(title = paste("Inspección:", etiq(v)),
                    subtitle = sprintf("%s a %s · sombra gris = límite inferior cero",
                                       format(min(d$fecha), "%Y-%m"), format(max(d$fecha), "%Y-%m")),
                    theme = tema_limpio())
}
for (v in series) guardar_fig(panel_serie(v), paste0("inspeccion_", v), ancho = 9, alto = 11)

# Pruebas de raíz unitaria --------------------------------------------------
# Tasas: ADF con constante; logs (IP, IPC, BCOM): ADF con tendencia. Rezagos por BIC (máx. 12).
raiz <- function(v) {
  x <- na.omit(base[[v]]); tipo <- if (v %in% c("ip", "cpi", "bcom")) "trend" else "drift"
  adf <- ur.df(x, type = tipo, lags = 12, selectlags = "BIC")
  adf_d <- ur.df(diff(x), type = "drift", lags = 12, selectlags = "BIC")
  kpss <- ur.kpss(x, type = if (tipo == "trend") "tau" else "mu", lags = "short")
  za <- tryCatch(ur.za(x, model = if (tipo == "trend") "both" else "intercept", lag = 4), error = function(e) NULL)
  data.frame(
    serie = v, especificacion = tipo,
    ADF_nivel = adf@teststat[1], ADF_cv5 = adf@cval[1, "5pct"],
    ADF_diff = adf_d@teststat[1], ADF_diff_cv5 = adf_d@cval[1, "5pct"],
    KPSS_nivel = kpss@teststat, KPSS_cv5 = kpss@cval[1, "5pct"],
    ZA = if (is.null(za)) NA else za@teststat, ZA_cv5 = if (is.null(za)) NA else za@cval[2],
    ZA_quiebre = if (is.null(za)) NA else format(base$fecha[!is.na(base[[v]])][za@bpoint], "%Y-%m"),
    conclusion = ifelse(adf@teststat[1] > adf@cval[1, "5pct"] & kpss@teststat > kpss@cval[1, "5pct"],
                        "I(1): ADF no rechaza y KPSS rechaza",
                 ifelse(adf@teststat[1] < adf@cval[1, "5pct"] & kpss@teststat < kpss@cval[1, "5pct"],
                        "I(0)", "Ambigua (ADF y KPSS no coinciden)")),
    row.names = NULL)
}
tab_raiz <- do.call(rbind, lapply(series, raiz))
tab_raiz[, sapply(tab_raiz, is.numeric)] <- round(tab_raiz[, sapply(tab_raiz, is.numeric)], 3)
guardar_tabla(tab_raiz, "raiz_unitaria")
print(tab_raiz[, c("serie", "ADF_nivel", "ADF_cv5", "ADF_diff", "KPSS_nivel", "KPSS_cv5", "ZA", "ZA_quiebre", "conclusion")])

# Curva: Fed funds vs tramos ---------------------------------------------------
cur <- c("ffr", "y3m", "y2y", "y10y", "y30y")
dl <- do.call(rbind, lapply(cur, function(v) data.frame(fecha = base$fecha, serie = etiq(v), valor = base[[v]])))
dl$serie <- factor(dl$serie, levels = etiq(cur))
g <- ggplot(dl, aes(fecha, valor, colour = serie)) +
  geom_rect(data = ZLB, aes(xmin = ini, xmax = fin, ymin = -Inf, ymax = Inf), inherit.aes = FALSE,
            fill = "grey85", alpha = 0.6) +
  geom_line(linewidth = 0.5) +
  scale_colour_manual(values = c("#000000", unname(COL_TRAMO[c("3M", "2Y", "10Y", "30Y")]))) +
  labs(title = "Tasa de la Fed y curva del Tesoro de EE.UU.", subtitle = "Promedios mensuales, %. Sombra = límite inferior cero",
       x = NULL, y = "%", colour = NULL, caption = "Fuente: Bloomberg (FEDL01, USGG3M, USGG2YR, USGG10YR, USGG30YR).") +
  tema_limpio()
guardar_fig(g, "curva_fed_tesoro")

# Colinealidad de la tasa Fed con 3M (decide si 3M entra al VAR)
colin <- data.frame(
  medida = c("Correlación en niveles", "Correlación de primeras diferencias"),
  ffr_vs_y3m = c(cor(base$ffr, base$y3m), cor(diff(base$ffr), diff(base$y3m))),
  ffr_vs_y3m_1988_2007 = with(base[base$fecha <= as.Date("2007-12-01"), ],
                              c(cor(ffr, y3m), cor(diff(ffr), diff(y3m)))))
guardar_tabla(colin, "colinealidad_ffr_3m"); print(colin)

# Tabla de cómo entra cada variable
tab_vars <- data.frame(
  variable = series, etiqueta = etiq(series),
  transformacion = ifelse(series %in% c("ip", "cpi", "bcom"), "100 × log(promedio o dato mensual)", ifelse(series == "y2y", "Nivel en %, promedio mensual (política en la variante B)", "Nivel en %, promedio mensual")),
  en_VAR = ifelse(series %in% c("ip", "cpi", "bcom", "ffr", "y3m", "y2y", "y5y", "y10y", "y30y"), "Sí (niveles)",
           ifelse(series == "y1y", "No (hueco 2001-08 a 2008-06)", "No")))
guardar_tabla(tab_vars, "variables_transformacion")
