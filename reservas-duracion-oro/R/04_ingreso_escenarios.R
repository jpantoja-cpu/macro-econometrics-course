# 04_ingreso_escenarios.R -----------------------------------------------
# ¿Cuánto ganaría en 12 meses un portafolio como PL/PL2 frente a alternativas de
# mayor plazo, según lo que haga la Fed?
#
# Trayectoria de la tasa de la Fed (EFFR) para los próximos 24 meses, por escenario:
#   Mercado : meses 1-6 = tasa implícita en los futuros de fed funds (FF1-FF6);
#             meses 7-24 = se mantiene el nivel del mes 6 (supuesto simple, documentado)
#   Pausa   : la EFFR actual se mantiene 24 meses
#   Recortes: −100 pb en línea recta durante 12 meses, luego se mantiene
#   Alzas   : +150 pb en línea recta durante 12 meses, luego se mantiene
# Rendimiento de una letra de plazo k en el mes τ:
#   y(τ, k) = promedio de la EFFR esperada entre τ y τ+k + b(k)
#   b(k) = rendimiento observado hoy − promedio de la EFFR que descuenta el mercado
#          en ese plazo (prima por plazo + diferencial letras–EFFR), constante en el tiempo.
#   Para 1 mes (no hay genérico) se usa b(1M) = b(3M)/3.
# Estrategias, retorno a 12 meses:
#   Como hoy (letras de 1 mes renovadas) · letras 3M renovadas · letras 6M renovadas
#   1 año comprado hoy y mantenido · 2 años comprado hoy y vendido a los 12 meses
# Resultado en % y en USD por cada 100 millones invertidos (no usa montos del BCB).

local({
  # Busca el utils.R de ESTA carpeta (reservas-duracion-oro), sin importar dónde esté parado RStudio
  cand <- c(if (file.exists("reservas-duracion-oro.Rproj")) "R/utils.R", "reservas-duracion-oro/R/utils.R", "../reservas-duracion-oro/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/reservas-duracion-oro/R/utils.R")
  source(cand[file.exists(cand)][1])
})
suppressPackageStartupMessages({ library(ggplot2) })

d <- read.csv(ruta_vtf("data", "raw", "bloomberg_tasas.csv"), stringsAsFactors = FALSE)
f <- read.csv(ruta_vtf("data", "raw", "bloomberg_futuros.csv"), stringsAsFactors = FALSE)
x <- rbind(d[d$frecuencia == "DAILY", c("fecha", "var", "valor")], f[, c("fecha", "var", "valor")])
x$fecha <- as.Date(x$fecha); x <- x[order(x$fecha), ]
ult <- function(v) { z <- x[x$var == v & !is.na(x$valor), ]; c(fecha = as.character(tail(z$fecha, 1)), valor = tail(z$valor, 1)) }
hoy <- sapply(c("ffr", "y3m", "y6m", "y1y", "y2y", paste0("ff", 1:6)), function(v) as.numeric(ult(v)[["valor"]]))
fecha_datos <- max(as.Date(sapply(c("y2y", "ff6"), function(v) ult(v)[["fecha"]])))

# Trayectorias mensuales de la EFFR (meses 1..36; 36 para valorar el 2 años a los 12 meses)
H <- 36
ff <- 100 - hoy[paste0("ff", 1:6)]
mercado <- c(ff, rep(ff[6], H - 6))
e0 <- hoy[["ffr"]]
rampa <- function(total) c(e0 + total * (1:12) / 12, rep(e0 + total, H - 12))
TRAY <- list("Mercado (futuros)" = mercado, "Pausa" = rep(e0, H), "Recortes (−100 pb)" = rampa(-1), "Alzas (+150 pb)" = rampa(1.5))

prom <- function(p, desde, k) mean(p[(desde + 1):(desde + k)])                 # meses desde+1 ... desde+k
b <- c(m3 = hoy[["y3m"]] - prom(mercado, 0, 3), m6 = hoy[["y6m"]] - prom(mercado, 0, 6),
       m12 = hoy[["y1y"]] - prom(mercado, 0, 12), m24 = hoy[["y2y"]] - prom(mercado, 0, 24))
b <- c(m1 = b[["m3"]] / 3, b)
y_letra <- function(p, tau, k) prom(p, tau, k) + b[[paste0("m", k)]]             # % anual

renovar <- function(p, k) { r <- 1; for (tau in seq(0, 12 - k, by = k)) r <- r * (1 + y_letra(p, tau, k) / 100 * k / 12); r - 1 }
res <- do.call(rbind, lapply(names(TRAY), function(s) {
  p <- TRAY[[s]]
  y2_12 <- y_letra(p, 12, 12)                                                    # rendimiento a 1 año dentro de 12 meses
  r <- c("Como hoy: letras 1 mes" = renovar(p, 1), "Letras 3M renovadas" = renovar(p, 3), "Letras 6M renovadas" = renovar(p, 6),
         "1 año (comprar y mantener)" = hoy[["y1y"]] / 100,
         "2 años (vender a los 12 meses)" = (1 + hoy[["y2y"]] / 100)^2 / (1 + y2_12 / 100) - 1)
  data.frame(escenario = s, estrategia = names(r), retorno_12m_pct = round(100 * r, 2), usd_por_100mm = round(1e8 * r, -3))
}))
base <- res[res$estrategia == "Como hoy: letras 1 mes", c("escenario", "retorno_12m_pct")]; names(base)[2] <- "base"
res <- merge(res, base, by = "escenario"); res$vs_hoy_pb <- round(100 * (res$retorno_12m_pct - res$base)); res$base <- NULL
ORD_E <- names(TRAY); ORD_S <- c("Como hoy: letras 1 mes", "Letras 3M renovadas", "Letras 6M renovadas", "1 año (comprar y mantener)", "2 años (vender a los 12 meses)")
res <- res[order(match(res$escenario, ORD_E), match(res$estrategia, ORD_S)), ]
guardar_tabla(res, "ingreso_12m_escenarios"); print(res, row.names = FALSE)

supuestos <- data.frame(dato = c("Fecha de los datos", "EFFR hoy (%)", paste0("EFFR implícita mes ", 1:6, " (%)"),
                                 "Letra 3M hoy (%)", "Letra 6M hoy (%)", "1 año hoy (%)", "2 años hoy (%)",
                                 "b(1M) pb", "b(3M) pb", "b(6M) pb", "b(12M) pb", "b(24M) pb"),
                        valor = c(as.character(fecha_datos), e0, round(ff, 3), hoy[["y3m"]], hoy[["y6m"]], hoy[["y1y"]], hoy[["y2y"]],
                                  round(100 * b, 0)))
guardar_tabla(supuestos, "ingreso_supuestos"); print(supuestos, row.names = FALSE)

# Trayectorias
tl <- do.call(rbind, lapply(names(TRAY), function(s) data.frame(mes = 0:24, escenario = s, effr = c(e0, TRAY[[s]][1:24]))))
tl$escenario <- factor(tl$escenario, levels = ORD_E)
g0 <- ggplot(tl, aes(mes, effr, colour = escenario)) + geom_line(linewidth = 0.8) +
  scale_colour_manual(values = c("#0b3c5d", "#8c8c8c", "#2a9d8f", "#d1495b")) +
  labs(title = "Escenarios para la tasa de la Fed (EFFR)", subtitle = sprintf("Mercado = futuros de fed funds al %s", format(fecha_datos, "%d-%m-%Y")),
       x = "Meses", y = "%", colour = NULL) + tema_limpio()
guardar_fig(g0, "escenarios_effr", ancho = 8, alto = 4.5)

# Retorno por estrategia y escenario
fr <- res; fr$escenario <- factor(fr$escenario, levels = ORD_E); fr$estrategia <- factor(fr$estrategia, levels = ORD_S)
g1 <- ggplot(fr, aes(estrategia, retorno_12m_pct, fill = escenario)) + geom_col(position = position_dodge(0.8), width = 0.75) +
  scale_fill_manual(values = c("#0b3c5d", "#b9b9b0", "#2a9d8f", "#d1495b")) + coord_flip() +
  labs(title = "Retorno a 12 meses por estrategia y escenario de la Fed", x = NULL, y = "%", fill = NULL) + tema_limpio()
guardar_fig(g1, "ingreso_12m_escenarios", ancho = 9, alto = 5)
