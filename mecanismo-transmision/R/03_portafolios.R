# 03_portafolios.R ------------------------------------------------------
# Traduce los escenarios del script 02 a retorno de estrategias tipo reservas y del oro.
# Resultados por cada 100 millones de USD, como DESVÍO respecto del escenario de mercado (lo que hoy
# descuentan los futuros). No usa posiciones del BCB.
#
# Estrategias de vencimiento constante, rebalanceadas cada mes (como en reservas-duracion-oro):
#   caja / letras 1M (≈ EFFR), letras 3M, letras 6M, 1 año, 2 años; y oro.
# Rendimiento de cada plazo: plazos de hasta 1 año = promedio de la EFFR esperada en ese horizonte
# (hipótesis de expectativas aplicada al desvío; el VAR no tiene esos plazos); 2 años = respuesta del VAR.
# Retorno mensual de un cupón cero de plazo k comprado a fin de mes: r ≈ y(t-1)/12 − (k − 1/12)·[y(t) − y(t-1)].

local({
  cand <- c(if (file.exists("mecanismo-transmision.Rproj")) "R/utils.R", "mecanismo-transmision/R/utils.R", "../mecanismo-transmision/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/mecanismo-transmision/R/utils.R")
  source(cand[file.exists(cand)][1])
})
suppressPackageStartupMessages(library(ggplot2))

m <- readRDS(ruta("output", "modelo_transmision.rds")); ESC <- m$ESC
MONTO <- 100e6; H12 <- 12
PLAZOS <- c("Letras 1M (caja)" = 1 / 12, "Letras 3M" = 0.25, "Letras 6M" = 0.5, "1 año" = 1, "2 años" = 2)

retorno_esc <- function(e) {
  e <- e[order(e$h), ]; ef <- e$ffr / 100                                     # desvío EFFR en pp, meses 1..24
  y_eh <- function(k, t) { n <- max(1, round(12 * k)); if (t == 0) return(0); mean(ef[t:min(length(ef), t + n - 1)]) }
  out <- sapply(names(PLAZOS), function(nm) {
    k <- PLAZOS[[nm]]
    y <- if (k == 2) c(0, e$y2y / 100) else c(0, sapply(1:length(ef), function(t) y_eh(k, t)))   # y[1] = desvío al inicio (0)
    r <- sapply(1:H12, function(t) y[t] / 12 - (k - 1 / 12) * (y[t + 1] - y[t]))
    100 * sum(r)                                                             # pb a 12 meses (y en pp -> r en pp; ×100 = pb)
  })
  c(out, "Oro" = e$oro[e$h == H12] * 100)                                     # % -> pb
}
tab <- do.call(rbind, lapply(split(ESC, ESC$escenario), function(e) data.frame(escenario = e$escenario[1], estrategia = c(names(PLAZOS), "Oro"),
                                                                              desvio_pb = retorno_esc(e))))
tab$usd_por_100MM <- round(tab$desvio_pb / 1e4 * MONTO)
tab$desvio_pb <- round(tab$desvio_pb, 1)
lv <- unique(ESC$escenario); tab$escenario <- factor(tab$escenario, levels = lv); tab$estrategia <- factor(tab$estrategia, levels = c(names(PLAZOS), "Oro"))
tab <- tab[order(tab$escenario, tab$estrategia), ]
guardar_tabla(tab, "portafolios_retorno_12m_desvio")
ancho <- reshape(tab[, c("escenario", "estrategia", "desvio_pb")], idvar = "escenario", timevar = "estrategia", direction = "wide")
names(ancho) <- sub("desvio_pb\\.", "", names(ancho)); print(ancho, row.names = FALSE)
guardar_tabla(ancho, "portafolios_retorno_12m_desvio_ancho")

g <- ggplot(tab, aes(estrategia, desvio_pb, fill = estrategia == "Oro")) + geom_col(width = 0.7) + geom_hline(yintercept = 0, colour = "grey40") +
  geom_text(aes(label = round(desvio_pb), vjust = ifelse(desvio_pb >= 0, -0.3, 1.2)), size = 2.8) +
  facet_wrap(~escenario, ncol = 3) + scale_fill_manual(values = c("#1b6ca8", "#c9a227"), guide = "none") +
  scale_y_continuous(expand = expansion(mult = 0.15)) +
  labs(title = "Retorno a 12 meses: desvío respecto del escenario de mercado (pb)",
       subtitle = "Estrategias de vencimiento constante y oro. 1 pb = 10.000 USD por cada 100 millones",
       x = NULL, y = "pb") + tema_limpio(9) + theme(axis.text.x = element_text(angle = 35, hjust = 1))
guardar_fig(g, "portafolios_escenarios", ancho = 11, alto = 6.5)
