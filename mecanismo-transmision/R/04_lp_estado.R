# 04_lp_estado.R --------------------------------------------------------
# ¿Una sorpresa de la Fed pega más cuando los mercados ya están tensos?
#
# Proyecciones locales con dependencia del estado (Jordà 2005; Ramey y Zubairy 2018; Tenreyro y Thwaites 2016):
#   y(t+h) − y(t−1) = a_h + b_h^A·e(t)·I(t−1) + b_h^B·e(t)·[1 − I(t−1)] + c_h·I(t−1) + controles + u
# e(t) es la serie del choque de política del script 02 (proxy SVAR con la sorpresa Bauer-Swanson):
# e = a' Σ⁻¹ u, con a el vector de impacto escalado a varianza unitaria. Se usa la serie del choque y no
# la sorpresa como instrumento por estado porque, al partir la muestra, el instrumento se vuelve débil
# (F = 1,2 en meses de tecnología firme). El estado se mide el mes anterior, para que no lo cause el
# choque. Ambas respuestas se normalizan al MISMO choque: el que sube la EFFR 25 pb en el promedio de la
# muestra. Así la diferencia entre estados incluye también cuánto se mueve la propia EFFR.
#
# Dos definiciones de estado "tenso":
#   1. Condiciones financieras: índice de Bloomberg (BFCIUS) < 0, más restrictivas que lo normal.
#   2. Tecnología débil: el índice tecnológico (Nasdaq 100 por defecto) cayó en los 6 meses previos.
# Controles: 2 rezagos de las 12 variables del VAR. Errores Newey-West (h + 1 rezagos).
# Pandemia: se excluyen las ventanas [t−2, t+h] que tocan marzo-agosto de 2020.
# Salida: respuestas por estado, diferencia y su valor p.

local({
  cand <- c(if (file.exists("mecanismo-transmision.Rproj")) "R/utils.R", "mecanismo-transmision/R/utils.R", "../mecanismo-transmision/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/mecanismo-transmision/R/utils.R")
  source(cand[file.exists(cand)][1])
})
source(ruta_vtf("R", "var_funciones.R"))
suppressPackageStartupMessages({ library(ggplot2); library(sandwich) })

TEC <- Sys.getenv("TEC", "nasdaq100"); SUF <- if (TEC == "nasdaq100") "" else paste0("_", TEC)
.gt <- guardar_tabla; .gf <- guardar_fig
guardar_tabla <- function(x, nombre, ...) .gt(x, paste0(nombre, SUF), ...)
guardar_fig <- function(g, nombre, ...) .gf(g, paste0(nombre, SUF), ...)
m <- readRDS(ruta("output", paste0("modelo_transmision", SUF, ".rds")))
VARS <- m$VARS; H <- 24
EN_PB <- c("ffr", "y2y", "y10y", "tp10", "spread_hy", "unemp")
ETQ <- c(ffr = "EFFR", y2y = "2Y", y10y = "10Y", oro = "Oro (%)", tec = c(nasdaq100 = "Tecnología: Nasdaq 100 (%)", sp500_tec = "Tecnología: S&P 500 tec. (%)")[[TEC]], spread_hy = "Spread alto rendimiento",
         ip = "Producción industrial (%)", nfp = "Empleo: nóminas (%)", unemp = "Desempleo", cpi = "IPC (%)")
RESP <- names(ETQ)

b <- m$base[m$base$fecha >= as.Date("1994-01-01"), ]
b <- b[complete.cases(b[, c(VARS, "cond_fin")]), ]; b <- b[order(b$fecha), ]
# Serie del choque de política (meses de la pandemia en cero; igual se excluyen abajo)
v <- m$v; a1 <- m$s_pol / sqrt(as.numeric(t(m$s_pol) %*% solve(v$Sigma, m$s_pol)))    # a' Σ⁻¹ a = 1
e_ser <- as.vector(v$U %*% solve(v$Sigma, a1))
fu <- m$d$fecha[(v$p + 1):nrow(m$d)]
b$e <- e_ser[match(b$fecha, fu)] * a1[VARS == "ffr"] / 0.25                              # 1 = choque que sube la EFFR 25 pb al impacto
guardar_tabla(data.frame(fecha = b$fecha, choque_politica = b$e), "serie_choque_politica")
TT <- nrow(b)
ESTADOS <- list(
  "Condiciones financieras" = list(I = c(NA, as.numeric(b$cond_fin[-TT] < 0)),
                                   etq = c("Tensas (BFCI < 0)", "Normales (BFCI ≥ 0)")),
  "Sector tecnológico" = list(I = c(NA, as.numeric((b$tec - c(rep(NA, 6), head(b$tec, -6)))[-TT] < 0)),
                              etq = c("Débil (cayó en 6 meses)", "Firme (subió en 6 meses)")))
COVID <- seq(as.Date("2020-03-01"), as.Date("2020-08-01"), by = "month")
L <- rezagos_df(b[, VARS], 2)

lp_estado <- function(y, I) {
  do.call(rbind, lapply(0:H, function(h) {
    idx <- 3:(TT - h)
    toca <- sapply(idx, function(t) any(b$fecha[(t - 2):(t + h)] %in% COVID))
    idx <- idx[!toca]
    df <- data.frame(dy = y[idx + h] - y[idx - 1], eA = b$e[idx] * I[idx], eB = b$e[idx] * (1 - I[idx]), I = I[idx], L[idx, ])
    df <- df[complete.cases(df), ]
    mod <- lm(dy ~ ., data = df)
    V <- NeweyWest(mod, lag = h + 1, prewhite = FALSE)
    bb <- coef(mod)[c("eA", "eB")]; VV <- V[c("eA", "eB"), c("eA", "eB")]
    dif <- bb[1] - bb[2]; sdd <- sqrt(VV[1, 1] + VV[2, 2] - 2 * VV[1, 2])
    data.frame(h = h, b_A = bb[1], se_A = sqrt(VV[1, 1]), b_B = bb[2], se_B = sqrt(VV[2, 2]),
               dif = dif, p_dif = 2 * pnorm(-abs(dif / sdd)), n = nrow(df), n_A = sum(df$I == 1))
  }))
}

RES <- NULL; FE <- NULL
for (en in names(ESTADOS)) {
  I <- ESTADOS[[en]]$I
  FE <- rbind(FE, data.frame(estado = en, condicion = ESTADOS[[en]]$etq,
                             meses = c(sum(I == 1, na.rm = TRUE), sum(I == 0, na.rm = TRUE)),
                             choque_de_desv_est = round(c(sd(b$e[I == 1], na.rm = TRUE), sd(b$e[I == 0], na.rm = TRUE)), 3)))
  for (v in RESP) {
    k <- ifelse(v %in% EN_PB, 100, 1)
    r <- lp_estado(b[[v]], I); r[, c("b_A", "se_A", "b_B", "se_B", "dif")] <- r[, c("b_A", "se_A", "b_B", "se_B", "dif")] * k
    RES <- rbind(RES, data.frame(estado = en, variable = v, r))
  }
}
print(FE, row.names = FALSE)
guardar_tabla(FE, "lp_estado_meses"); guardar_tabla(RES, "lp_estado_respuestas")

res <- RES[RES$h %in% c(0, 6, 12, 24), ]
res$tensa <- sprintf("%.2f (%.2f)", res$b_A, res$se_A); res$normal <- sprintf("%.2f (%.2f)", res$b_B, res$se_B)
res <- res[, c("estado", "variable", "h", "tensa", "normal", "p_dif")]; res$p_dif <- round(res$p_dif, 3)
print(res, row.names = FALSE); guardar_tabla(res, "lp_estado_resumen")

for (en in names(ESTADOS)) {
  et <- ESTADOS[[en]]$etq
  t <- RES[RES$estado == en, ]
  g <- rbind(data.frame(t[, c("variable", "h")], condicion = et[1], b = t$b_A, se = t$se_A),
             data.frame(t[, c("variable", "h")], condicion = et[2], b = t$b_B, se = t$se_B))
  g$variable <- factor(paste0(ETQ[g$variable], ifelse(g$variable %in% EN_PB, " (pb)", "")),
                       levels = paste0(ETQ[RESP], ifelse(RESP %in% EN_PB, " (pb)", "")))
  g$condicion <- factor(g$condicion, levels = et)
  p <- ggplot(g, aes(h, b, colour = condicion, fill = condicion)) + geom_hline(yintercept = 0, colour = "grey50") +
    geom_ribbon(aes(ymin = b - se, ymax = b + se), alpha = 0.15, colour = NA) + geom_line(linewidth = 0.8) +
    facet_wrap(~variable, scales = "free_y", ncol = 5) +
    scale_colour_manual(values = c("#d1495b", "#0b3c5d")) + scale_fill_manual(values = c("#d1495b", "#0b3c5d")) +
    labs(title = sprintf("Sorpresa de +25 pb de la Fed según el estado previo: %s", tolower(en)),
         subtitle = "Mismo choque en ambos estados (sube la EFFR 25 pb al impacto en promedio). Proyecciones locales 1994-2026 sin la pandemia; bandas ±1 e.e.",
         x = "Meses después del choque", y = NULL, colour = NULL, fill = NULL) + tema_limpio(9)
  guardar_fig(p, paste0("lp_estado_", ifelse(grepl("financ", en), "condiciones_financieras", "tecnologia")), ancho = 12, alto = 5.5)
}
