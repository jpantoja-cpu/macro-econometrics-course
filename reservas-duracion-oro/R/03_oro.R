# 03_oro.R --------------------------------------------------------------
# ¿Qué mueve el precio del oro y cómo reacciona a la Fed?
# 1) Día del anuncio del FOMC (y de los datos de IPC y empleo): cambio del oro (%),
#    de la tasa real a 10 años (pb) y del dólar (%), contra las sorpresas target y
#    path de los futuros de fed funds y las sorpresas de datos macro (proyecto
#    var-tasas-fed, scripts 09 y 17). Regresión diaria sobre todos los días hábiles.
# 2) Determinantes mensuales: Δlog oro contra Δ tasa real 10 años, Δlog dólar y
#    Δlog VIX; coeficientes en ventanas móviles de 5 años, para ver si la relación
#    clásica oro–tasa real cambió (p. ej., desde 2022).

local({
  # Busca el utils.R de ESTA carpeta (reservas-duracion-oro), sin importar dónde esté parado RStudio
  cand <- c(if (file.exists("reservas-duracion-oro.Rproj")) "R/utils.R", "reservas-duracion-oro/R/utils.R", "../reservas-duracion-oro/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/reservas-duracion-oro/R/utils.R")
  source(cand[file.exists(cand)][1])
})
suppressPackageStartupMessages({ library(ggplot2); library(sandwich) })

mk <- read.csv(ruta("data", "raw", "bloomberg_mercado.csv"), stringsAsFactors = FALSE)
vx <- read.csv(ruta_vtf("data", "raw", "bloomberg_vix.csv"), stringsAsFactors = FALSE)
dd <- rbind(mk[mk$var %in% c("oro", "real10", "real5", "dxy"), c("fecha", "var", "valor")], vx[vx$var == "vix", c("fecha", "var", "valor")])
dd$fecha <- as.Date(dd$fecha)
D <- reshape(dd, idvar = "fecha", timevar = "var", direction = "wide"); names(D) <- sub("^valor\\.", "", names(D))
D <- D[order(D$fecha), ]; D <- D[!is.na(D$oro), ]
D$d_oro <- c(NA, 100 * diff(log(D$oro)))
D$d_real10 <- c(NA, 100 * diff(D$real10))
D$d_dxy <- c(NA, 100 * diff(log(D$dxy)))
D$dia_sem <- format(D$fecha, "%u"); D <- D[D$dia_sem %in% as.character(1:5), ]
ETQ_R <- c(d_oro = "Oro (%)", d_real10 = "Tasa real 10 años (pb)", d_dxy = "Dólar DXY (%)")

# 1) Días de FOMC y de datos macro --------------------------------------------------
ev <- read.csv(ruta_vtf("data", "sorpresas_fomc.csv")); ev$fecha_evento <- as.Date(ev$fecha_evento)
ev <- ev[!as.logical(ev$excluir_base), ]
# Cada evento se asigna al primer día hábil con dato de oro desde su fecha
dia_habil <- function(f) D$fecha[pmin(findInterval(f - 1, D$fecha) + 1, nrow(D))]
asigna <- function(col, fechas, valores) {
  s <- aggregate(v ~ f, data = data.frame(f = dia_habil(fechas), v = valores), FUN = sum)
  x <- rep(0, nrow(D)); x[match(s$f, D$fecha)] <- s$v; x
}
D$s_target <- asigna("s_target", ev$fecha_evento, ev$target_pb / 25)          # por sorpresa de 25 pb
D$s_path <- asigna("s_path", ev$fecha_evento, ifelse(is.na(ev$path_pb), 0, ev$path_pb / 25))
nt <- ruta_vtf("data", "raw", "bloomberg_noticias.csv")
if (file.exists(nt)) {
  n <- read.csv(nt, stringsAsFactors = FALSE)
  pub <- do.call(rbind, lapply(c("ipc", "ipc_sub", "nominas"), function(k) {
    x <- n[n$var == k, c("fecha_obs", "campo", "valor")]
    w <- reshape(x, idvar = "fecha_obs", timevar = "campo", direction = "wide"); names(w) <- sub("^valor\\.", "", names(w))
    data.frame(var = k, fecha = as.Date(w$ECO_RELEASE_DT), s = suppressWarnings(as.numeric(w$ACTUAL_RELEASE) - as.numeric(w$BN_SURVEY_MEDIAN)))
  }))
  pub <- pub[complete.cases(pub) & !(pub$fecha >= as.Date("2020-03-01") & pub$fecha <= as.Date("2020-12-31")), ]
  pub$z <- ave(pub$s, pub$var, FUN = function(v) v / sd(v))
  for (k in c("ipc", "ipc_sub", "nominas")) {
    D[[paste0("s_", k)]] <- asigna(k, pub$fecha[pub$var == k], pub$z[pub$var == k])
  }
}
REG <- intersect(c("s_target", "s_path", "s_ipc", "s_ipc_sub", "s_nominas"), names(D))
ETQ_S <- c(s_target = "FOMC: sorpresa target (25 pb)", s_path = "FOMC: sorpresa path (25 pb)",
           s_ipc = "IPC general (1 d.e.)", s_ipc_sub = "IPC subyacente (1 d.e.)", s_nominas = "Nóminas (1 d.e.)")
E <- D[D$fecha >= as.Date("1994-01-01") & !(D$fecha >= as.Date("2020-03-01") & D$fecha <= as.Date("2020-12-31")), ]
E$periodo <- ifelse(E$fecha < as.Date("2008-01-01"), "1994-2007", ifelse(E$fecha < as.Date("2020-01-01"), "2008-2019", "2021-2026"))
est <- do.call(rbind, lapply(c("Completa", "1994-2007", "2008-2019", "2021-2026"), function(mu) {
  dat <- if (mu == "Completa") E else E[E$periodo == mu, ]
  do.call(rbind, lapply(names(ETQ_R), function(y) {
    if (!y %in% names(dat) || sum(!is.na(dat[[y]])) < 300) return(NULL)
    regs <- REG[sapply(REG, function(r) any(dat[[r]] != 0))]
    m <- lm(as.formula(paste(y, "~", paste(regs, collapse = " + "))), data = dat); V <- vcovHC(m, type = "HC1")
    data.frame(muestra = mu, respuesta = y, regresor = regs, coef = coef(m)[regs], se = sqrt(diag(V))[regs], n = nobs(m), row.names = NULL)
  }))
}))
est$t <- est$coef / est$se
guardar_tabla(est, "oro_eventos_coeficientes")
tab <- est[est$muestra == "Completa", ]
print(data.frame(respuesta = ETQ_R[tab$respuesta], noticia = ETQ_S[tab$regresor],
                 efecto = sprintf("%.2f%s", tab$coef, ifelse(abs(tab$t) > 2.58, "***", ifelse(abs(tab$t) > 1.96, "**", ifelse(abs(tab$t) > 1.645, "*", ""))))), row.names = FALSE)

f1 <- est[est$respuesta == "d_oro" & est$muestra != "Completa", ]
f1$regresor <- factor(ETQ_S[f1$regresor], levels = ETQ_S[REG])
g1 <- ggplot(f1, aes(regresor, coef, fill = muestra)) + geom_hline(yintercept = 0, colour = "grey50") +
  geom_col(position = position_dodge(0.8), width = 0.75) +
  geom_errorbar(aes(ymin = coef - 1.645 * se, ymax = coef + 1.645 * se), position = position_dodge(0.8), width = 0, colour = "grey30") +
  scale_fill_manual(values = c("#b9cfe0", "#76a8e0", "#1f6fc5")) + coord_flip() +
  labs(title = "¿Cómo reacciona el oro el día de cada noticia?",
       subtitle = "Cambio del precio del oro (%) por sorpresa; intervalos de 90%. Positivo = restrictivo o economía más fuerte",
       x = NULL, y = "%", fill = NULL, caption = "Regresión diaria sobre todos los días hábiles; excluye mar-dic 2020. Fuente: Bloomberg.") + tema_limpio()
guardar_fig(g1, "oro_eventos", ancho = 9, alto = 5)

# 2) Determinantes mensuales y ventanas móviles ----------------------------------------
D$mes <- as.Date(format(D$fecha, "%Y-%m-01"))
fm <- do.call(rbind, lapply(split(D, D$mes), function(d) d[nrow(d), c("mes", "oro", "real10", "dxy", "vix")]))
fm <- fm[fm$mes < as.Date(format(Sys.Date(), "%Y-%m-01")), ]
mm <- data.frame(mes = fm$mes[-1], d_oro = 100 * diff(log(fm$oro)), d_real10 = diff(fm$real10),
                 d_dxy = 100 * diff(log(fm$dxy)), d_vix = 100 * diff(log(fm$vix)))
mm <- mm[complete.cases(mm), ]
m_all <- lm(d_oro ~ d_real10 + d_dxy + d_vix, data = mm); V <- vcovHC(m_all, type = "HC1")
det <- data.frame(regresor = c("Tasa real 10 años (+1 pp)", "Dólar DXY (+1%)", "VIX (+1%)"),
                  coef_pct = round(coef(m_all)[-1], 2), t = round(coef(m_all)[-1] / sqrt(diag(V))[-1], 1),
                  R2 = round(summary(m_all)$r.squared, 2), meses = nobs(m_all),
                  desde = format(min(mm$mes), "%Y-%m"))
guardar_tabla(det, "oro_determinantes_mensuales"); print(det, row.names = FALSE)

W <- 60
rol <- do.call(rbind, lapply(W:nrow(mm), function(i) {
  x <- mm[(i - W + 1):i, ]; m <- lm(d_oro ~ d_real10 + d_dxy + d_vix, data = x); s <- sqrt(diag(vcovHC(m, type = "HC1")))
  data.frame(mes = mm$mes[i], regresor = c("Tasa real 10 años (+1 pp)", "Dólar DXY (+1%)"),
             coef = coef(m)[c("d_real10", "d_dxy")], se = s[c("d_real10", "d_dxy")])
}))
guardar_tabla(rol, "oro_coeficientes_moviles_5a")
g2 <- ggplot(rol, aes(mes, coef)) + geom_hline(yintercept = 0, colour = "grey50") +
  geom_ribbon(aes(ymin = coef - 1.645 * se, ymax = coef + 1.645 * se), fill = "#1b6ca8", alpha = 0.2) +
  geom_line(colour = "#0b3c5d", linewidth = 0.7) + facet_wrap(~regresor, scales = "free_y", ncol = 1) +
  labs(title = "¿Se rompió la relación del oro con la tasa real y el dólar?",
       subtitle = "Efecto sobre el oro (% mensual) en ventanas móviles de 5 años; banda de 90%", x = "Fin de la ventana", y = "% por unidad") + tema_limpio()
guardar_fig(g2, "oro_coeficientes_moviles", ancho = 9, alto = 6)
