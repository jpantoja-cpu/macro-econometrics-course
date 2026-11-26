# utils.R ---------------------------------------------------------------
# Funciones comunes: ubicar la raíz del proyecto, tema gráfico (fondo blanco,
# Arial) y utilidades pequeñas. Todos los scripts hacen source() de este archivo.

# Raíz del proyecto = carpeta var-tasas-fed/.
# Funciona si: (a) se abrió var-tasas-fed.Rproj, (b) el directorio de trabajo es
# la raíz del repo, o (c) el clon está en la ruta de la oficina.
raiz_proyecto <- function() {
  candidatos <- c(
    getwd(),
    file.path(getwd(), "var-tasas-fed"),
    dirname(getwd()),
    "C:/Users/jpantoja/Documents/macro-econometrics-course/var-tasas-fed"
  )
  for (d in candidatos) {
    if (file.exists(file.path(d, "var-tasas-fed.Rproj"))) return(normalizePath(d, winslash = "/"))
  }
  stop("No encuentro la carpeta var-tasas-fed/. Abre var-tasas-fed.Rproj en RStudio ",
       "o fija el directorio con setwd('.../macro-econometrics-course/var-tasas-fed').")
}

RAIZ <- raiz_proyecto()
ruta <- function(...) file.path(RAIZ, ...)
dir.create(ruta("output", "figuras"), recursive = TRUE, showWarnings = FALSE)
dir.create(ruta("output", "tablas"), recursive = TRUE, showWarnings = FALSE)

# Fuente: Arial en Windows/Mac; en Linux se usa Liberation Sans (métricamente idéntica).
FUENTE <- if (.Platform$OS.type == "windows" || Sys.info()[["sysname"]] == "Darwin") "Arial" else "Liberation Sans"

tema_limpio <- function(base = 10) {
  ggplot2::theme_minimal(base_size = base, base_family = FUENTE) +
    ggplot2::theme(
      plot.background  = ggplot2::element_rect(fill = "white", colour = NA),
      panel.background = ggplot2::element_rect(fill = "white", colour = NA),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(colour = "grey90", linewidth = 0.3),
      plot.title    = ggplot2::element_text(face = "bold", size = base + 1),
      plot.subtitle = ggplot2::element_text(colour = "grey35"),
      plot.caption  = ggplot2::element_text(colour = "grey45", hjust = 0, size = base - 2),
      strip.text    = ggplot2::element_text(face = "bold"),
      legend.position = "bottom"
    )
}

guardar_fig <- function(p, nombre, ancho = 9, alto = 5.5) {
  f <- ruta("output", "figuras", paste0(nombre, ".png"))
  ggplot2::ggsave(f, p, width = ancho, height = alto, dpi = 150, bg = "white")
  message("  figura: ", f)
  invisible(f)
}

guardar_tabla <- function(df, nombre) {
  f <- ruta("output", "tablas", paste0(nombre, ".csv"))
  utils::write.csv(df, f, row.names = FALSE)
  message("  tabla:  ", f)
  invisible(f)
}

# Colores (paleta sobria; un color por tramo de la curva)
COL_TRAMO <- c("3M" = "#1b6ca8", "2Y" = "#3b9ab2", "5Y" = "#e1a33b",
               "10Y" = "#d1495b", "30Y" = "#6a3d9a")
