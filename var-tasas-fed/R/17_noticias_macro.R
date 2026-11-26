# 17_noticias_macro.R ---------------------------------------------------
# ¿Qué mueve más la curva: los datos de inflación y empleo o la Fed?
# Base: Gürkaynak, Sack y Swanson (2005, AER) "The sensitivity of long-term interest
# rates to economic news"; Balduzzi, Elton y Green (2001).
#
# Sorpresa de un dato = publicado (primera publicación) − mediana de la encuesta de
# Bloomberg, estandarizada por su desviación estándar. Signo: positivo = economía más
# fuerte / más inflación (se invierte en desempleo y solicitudes de subsidio).
# Regresión diaria, todos los días hábiles (sorpresa = 0 si no hay dato):
#   Δy_t = a + Σ_k b_k · sorpresa_k,t + c1 · target_t + c2 · path_t + e_t
# con Δy en pb (cierre a cierre; los datos salen a las 8:30 o 10:00 de NY, antes del cierre).
# Las sorpresas del FOMC también se estandarizan, para comparar "por 1 desviación estándar".
# Se excluye marzo-diciembre de 2020 (sorpresas de pandemia de órdenes de magnitud anómalas).
# Variables de respuesta: 3M, 2Y, 5Y, 10Y, 30Y; forward nominal 5y5y (de 5Y y 10Y);
# breakeven 10Y y swap de inflación 5y5y; expectativa y prima por plazo 10Y (ACM).

local({
  # Busca el utils.R de ESTA carpeta (var-tasas-fed), sin importar dónde esté parado RStudio
  cand <- c(if (file.exists("var-tasas-fed.Rproj")) "R/utils.R", "var-tasas-fed/R/utils.R", "../var-tasas-fed/R/utils.R",
            "C:/Users/jpantoja/Documents/macro-econometrics-course/var-tasas-fed/R/utils.R")
  source(cand[file.exists(cand)][1])
})
suppressPackageStartupMessages({ library(ggplot2); library(sandwich) })

IND <- c(ipc = "IPC general", ipc_sub = "IPC subyacente", nominas = "Nóminas", desempleo = "Desempleo",
         salarios = "Salarios", ventas = "Ventas minoristas", ism = "ISM manufacturero", pib = "PIB (avance)",
         reclamos = "Solicitudes de subsidio")
INVIERTE <- c("desempleo", "reclamos")
EXCL <- c(as.Date("2020-03-01"), as.Date("2020-12-31"))

# Publicaciones y sorpresas -------------------------------------------------------
nt <- read.csv(ruta("data", "raw", "bloomberg_noticias.csv"), stringsAsFactors = FALSE)
pub <- do.call(rbind, lapply(names(IND), function(k) {
  x <- nt[nt$var == k, c("fecha_obs", "campo", "valor")]
  if (!nrow(x)) return(NULL)
  w <- reshape(x, idvar = "fecha_obs", timevar = "campo", direction = "wide"); names(w) <- sub("^valor\\.", "", names(w))
  if (!all(c("ECO_RELEASE_DT", "ACTUAL_RELEASE", "BN_SURVEY_MEDIAN") %in% names(w))) return(NULL)
  data.frame(var = k, fecha_obs = as.Date(w$fecha_obs), fecha_pub = as.Date(w$ECO_RELEASE_DT),
             publicado = suppressWarnings(as.numeric(w$ACTUAL_RELEASE)), encuesta = suppressWarnings(as.numeric(w$BN_SURVEY_MEDIAN)))
}))
pub <- pub[complete.cases(pub), ]
pub$sorpresa <- (pub$publicado - pub$encuesta) * ifelse(pub$var %in% INVIERTE, -1, 1)
fuera <- pub$fecha_pub >= EXCL[1] & pub$fecha_pub <= EXCL[2]
sdv <- tapply(pub$sorpresa[!fuera], pub$var[!fuera], sd)
pub$z <- pub$sorpresa / sdv[pub$var]
desc <- do.call(rbind, lapply(split(pub[!fuera, ], pub$var[!fuera]), function(d)
  data.frame(indicador = IND[d$var[1]], n = nrow(d), desde = min(d$fecha_pub), hasta = max(d$fecha_pub),
             sd_sorpresa = round(sd(d$sorpresa), 3), unidad = c(ipc = "pp", ipc_sub = "pp", nominas = "miles", desempleo = "pp",
             salarios = "pp", ventas = "pp", ism = "puntos", pib = "pp", reclamos = "miles")[d$var[1]],
             pct_sin_sorpresa = round(100 * mean(d$sorpresa == 0), 0))))
guardar_tabla(desc, "noticias_descripcion"); print(desc, row.names = FALSE)

# Panel diario de respuestas ------------------------------------------------------------
raw <- read.csv(ruta("data", "raw", "bloomberg_tasas.csv"), stringsAsFactors = FALSE)
dd <- raw[raw$frecuencia == "DAILY" & raw$var %in% c("y3m", "y2y", "y5y", "y10y", "y30y"), c("fecha", "var", "valor")]
for (f in c("bloomberg_breakeven.csv", "bloomberg_acm.csv")) {
  p <- ruta("data", "raw", f); if (file.exists(p)) { x <- read.csv(p, stringsAsFactors = FALSE); dd <- rbind(dd, x[x$var %in% c("be10", "fwd5y5y", "tp10"), c("fecha", "var", "valor")]) }
}
dd$fecha <- as.Date(dd$fecha)
D <- reshape(dd, idvar = "fecha", timevar = "var", direction = "wide"); names(D) <- sub("^valor\\.", "", names(D))
D <- D[order(D$fecha), ]; D <- D[!is.na(D$y10y), ]
D$fwd5y5y_nom <- (10 * D$y10y - 5 * D$y5y) / 5                      # forward nominal 5 años dentro de 5 años
if ("tp10" %in% names(D)) D$rny10 <- D$y10y - D$tp10
RESP <- intersect(c("y3m", "y2y", "y5y", "y10y", "y30y", "fwd5y5y_nom", "be10", "fwd5y5y", "rny10", "tp10"), names(D))
ETQ <- c(y3m = "3M", y2y = "2Y", y5y = "5Y", y10y = "10Y", y30y = "30Y", fwd5y5y_nom = "Forward nominal 5y5y",
         be10 = "Breakeven 10Y", fwd5y5y = "Inflación 5y5y (swap)", rny10 = "Expectativa 10Y (ACM)", tp10 = "Prima 10Y (ACM)")
for (v in RESP) D[[paste0("d_", v)]] <- c(NA, 100 * diff(D[[v]]))
# (cambios entre días hábiles consecutivos con dato; si falta un día, el cambio es NA)

# Asignar sorpresas al día hábil de publicación (o el siguiente)
dia_habil <- function(f) D$fecha[findInterval(f - 1, D$fecha) + 1]
pub$fecha_evento <- dia_habil(pub$fecha_pub)
for (k in names(IND)) {
  s <- aggregate(z ~ fecha_evento, data = pub[pub$var == k, ], FUN = sum)
  D[[paste0("s_", k)]] <- 0; D[[paste0("s_", k)]][match(s$fecha_evento, D$fecha)] <- s$z
}
ev <- read.csv(ruta("data", "sorpresas_fomc.csv")); ev$fecha_evento <- as.Date(ev$fecha_evento); ev <- ev[!as.logical(ev$excluir_base), ]
sd_t <- sd(ev$target_pb); sd_p <- sd(ev$path_pb, na.rm = TRUE)
D$s_fomc_target <- 0; D$s_fomc_path <- 0
D$s_fomc_target[match(ev$fecha_evento, D$fecha)] <- ev$target_pb / sd_t
D$s_fomc_path[match(ev$fecha_evento, D$fecha)] <- ifelse(is.na(ev$path_pb), 0, ev$path_pb / sd_p)
inicio <- max(as.Date("1998-06-01"), min(pub$fecha_evento))
D <- D[D$fecha >= inicio & !(D$fecha >= EXCL[1] & D$fecha <= EXCL[2]), ]
D$periodo <- cut(D$fecha, as.Date(c("1990-01-01", "2008-01-01", "2020-01-01", "2030-01-01")), right = FALSE,
                 labels = c("1998-2007", "2008-2019", "2021-2026"))
REG <- c(paste0("s_", names(IND)), "s_fomc_target", "s_fomc_path")
ETQ_REG <- c(setNames(IND, paste0("s_", names(IND))), s_fomc_target = "FOMC: sorpresa target", s_fomc_path = "FOMC: sorpresa path")

estimar <- function(dat, y, regs = REG) {
  regs <- regs[sapply(regs, function(r) any(dat[[r]] != 0))]          # indicador sin publicaciones en el período
  dat <- dat[!is.na(dat[[y]]), ]
  m <- lm(as.formula(paste(y, "~", paste(regs, collapse = " + "))), data = dat); V <- vcovHC(m, type = "HC1")
  data.frame(respuesta = sub("^d_", "", y), regresor = regs, coef_pb = coef(m)[regs], se = sqrt(diag(V))[regs],
             n_dias = nobs(m), n_eventos = sapply(regs, function(r) sum(dat[[r]] != 0)), row.names = NULL)
}
muestras <- c(list("Completa" = D), split(D, D$periodo))
est <- do.call(rbind, lapply(names(muestras), function(mu) do.call(rbind, lapply(paste0("d_", RESP), function(y) {
  if (sum(!is.na(muestras[[mu]][[y]])) < 500) return(NULL); cbind(muestra = mu, estimar(muestras[[mu]], y))
}))))
est$t <- est$coef_pb / est$se
guardar_tabla(est, "noticias_coeficientes")

tab <- est[est$muestra == "Completa" & est$respuesta %in% c("y2y", "y10y", "fwd5y5y_nom", "tp10"), ]
tab <- data.frame(indicador = ETQ_REG[tab$regresor], respuesta = ETQ[tab$respuesta],
                  efecto = sprintf("%.1f%s", tab$coef_pb, ifelse(abs(tab$t) > 2.58, "***", ifelse(abs(tab$t) > 1.96, "**", ifelse(abs(tab$t) > 1.645, "*", "")))))
tab <- reshape(tab, idvar = "indicador", timevar = "respuesta", direction = "wide"); names(tab) <- sub("^efecto\\.", "", names(tab))
guardar_tabla(tab, "noticias_resumen_completa"); print(tab, row.names = FALSE)

# Figura 1: efecto por indicador en 2Y y 10Y (muestra completa) ------------------------------
f1 <- est[est$muestra == "Completa" & est$respuesta %in% c("y2y", "y10y"), ]
orden <- f1[f1$respuesta == "y10y", ]; orden <- orden$regresor[order(orden$coef_pb)]
f1$regresor <- factor(ETQ_REG[f1$regresor], levels = ETQ_REG[orden])
f1$respuesta <- factor(ETQ[f1$respuesta], levels = c("2Y", "10Y"))
f1$tipo <- ifelse(grepl("fomc", f1$regresor, ignore.case = TRUE) | grepl("FOMC", f1$regresor), "Fed", "Dato macro")
g <- ggplot(f1, aes(coef_pb, regresor, colour = tipo)) + geom_vline(xintercept = 0, colour = "grey50") +
  geom_pointrange(aes(xmin = coef_pb - 1.645 * se, xmax = coef_pb + 1.645 * se), size = 0.35) +
  facet_wrap(~respuesta) + scale_colour_manual(values = c("Dato macro" = "#1b6ca8", "Fed" = "#d1495b")) +
  labs(title = "¿Qué noticia mueve más la curva? Efecto de una sorpresa de 1 desviación estándar",
       subtitle = sprintf("Cambio diario del rendimiento (pb), %s a %s, sin mar-dic 2020. Intervalos de 90%%", format(min(D$fecha), "%Y"), format(max(D$fecha), "%Y")),
       x = "Puntos básicos", y = NULL, colour = NULL,
       caption = "Sorpresa = dato publicado − mediana de la encuesta de Bloomberg; signo positivo = economía más fuerte o más inflación.") +
  tema_limpio()
guardar_fig(g, "noticias_efecto_por_indicador", ancho = 10, alto = 5.5)

# Figura 2: respuesta por plazo para las noticias principales ---------------------------------
PRINC <- c("s_ipc_sub", "s_nominas", "s_ism", "s_fomc_target", "s_fomc_path")
f2 <- est[est$muestra == "Completa" & est$regresor %in% PRINC & est$respuesta %in% c("y3m", "y2y", "y5y", "y10y", "y30y"), ]
f2$respuesta <- factor(ETQ[f2$respuesta], levels = c("3M", "2Y", "5Y", "10Y", "30Y"))
f2$regresor <- factor(ETQ_REG[f2$regresor], levels = ETQ_REG[PRINC])
g <- ggplot(f2, aes(respuesta, coef_pb, colour = regresor, group = regresor)) + geom_hline(yintercept = 0, colour = "grey50") +
  geom_line(linewidth = 0.8) + geom_point(size = 2) +
  scale_colour_manual(values = c("#1b6ca8", "#3b9ab2", "#e1a33b", "#d1495b", "#6a3d9a")) +
  labs(title = "Cómo se mueve la curva el día de cada noticia", subtitle = "Efecto de una sorpresa de 1 d.e. por plazo (pb)",
       x = "Plazo", y = "Puntos básicos", colour = NULL) + tema_limpio()
guardar_fig(g, "noticias_curva_por_noticia", ancho = 9, alto = 5)

# Figura 3: ¿cambió la sensibilidad? IPC subyacente y nóminas por período -----------------------
f3 <- est[est$muestra != "Completa" & est$regresor %in% c("s_ipc_sub", "s_ipc", "s_nominas", "s_fomc_path") &
          est$respuesta %in% c("y2y", "y10y", "fwd5y5y_nom", "fwd5y5y"), ]
f3$regresor <- factor(ETQ_REG[f3$regresor], levels = ETQ_REG[c("s_ipc", "s_ipc_sub", "s_nominas", "s_fomc_path")])
f3$respuesta <- factor(ETQ[f3$respuesta], levels = ETQ[c("y2y", "y10y", "fwd5y5y_nom", "fwd5y5y")])
g <- ggplot(f3, aes(muestra, coef_pb, fill = muestra)) + geom_hline(yintercept = 0, colour = "grey50") +
  geom_col(width = 0.7) + geom_errorbar(aes(ymin = coef_pb - 1.645 * se, ymax = coef_pb + 1.645 * se), width = 0.2, colour = "grey30") +
  facet_grid(respuesta ~ regresor, scales = "free_y") + scale_fill_manual(values = c("#b9cfe0", "#1b6ca8", "#d1495b")) +
  labs(title = "¿Cambió la sensibilidad de la curva a las noticias?", subtitle = "Efecto de 1 d.e. de sorpresa por período (pb); intervalos de 90%",
       x = NULL, y = "Puntos básicos", fill = NULL) + tema_limpio(9) + theme(legend.position = "none", axis.text.x = element_text(angle = 30, hjust = 1))
guardar_fig(g, "noticias_por_periodo", ancho = 10, alto = 8)

# Figura 4: ¿qué días mueven el 10Y? Volatilidad por tipo de día ----------------------------------
tipo_dia <- with(D, ifelse(s_fomc_target != 0 | s_fomc_path != 0, "FOMC",
                 ifelse(s_ipc != 0 | s_ipc_sub != 0, "IPC", ifelse(s_nominas != 0, "Empleo (nóminas)",
                 ifelse(s_ventas != 0 | s_ism != 0 | s_pib != 0, "Otros datos (ventas, ISM, PIB)", "Sin dato relevante")))))
vol <- do.call(rbind, lapply(split(D, list(tipo_dia, D$periodo), drop = TRUE), function(d) {
  td <- tipo_dia[match(d$fecha, D$fecha)][1]
  data.frame(tipo = td, periodo = d$periodo[1], n = nrow(d), sd_d10y_pb = sd(d$d_y10y, na.rm = TRUE), sd_d2y_pb = sd(d$d_y2y, na.rm = TRUE))
}))
base_sd <- vol[vol$tipo == "Sin dato relevante", c("periodo", "sd_d10y_pb")]; names(base_sd)[2] <- "base"
vol <- merge(vol, base_sd, by = "periodo"); vol$ratio_10y <- vol$sd_d10y_pb / vol$base
vol[, c("sd_d10y_pb", "sd_d2y_pb", "ratio_10y")] <- round(vol[, c("sd_d10y_pb", "sd_d2y_pb", "ratio_10y")], 2); vol$base <- NULL
guardar_tabla(vol[order(vol$periodo, -vol$ratio_10y), ], "noticias_volatilidad_por_tipo_de_dia")
print(vol[order(vol$periodo, -vol$ratio_10y), ], row.names = FALSE)
vol$tipo <- factor(vol$tipo, levels = c("Sin dato relevante", "Otros datos (ventas, ISM, PIB)", "Empleo (nóminas)", "IPC", "FOMC"))
g <- ggplot(vol, aes(tipo, sd_d10y_pb, fill = periodo)) + geom_col(position = position_dodge(width = 0.8), width = 0.75) +
  scale_fill_manual(values = c("#b9cfe0", "#1b6ca8", "#d1495b")) + coord_flip() +
  labs(title = "¿Qué días se mueve más el 10Y?", subtitle = "Desviación estándar del cambio diario del 10Y (pb), por tipo de día",
       x = NULL, y = "pb", fill = NULL) + tema_limpio()
guardar_fig(g, "noticias_volatilidad_por_dia", ancho = 9, alto = 4.5)
