# 00_paquetes.R ---------------------------------------------------------
# Instala (si falta) y carga los paquetes del proyecto. Correr una vez.
# Rblpapi solo es necesario en la PC con Terminal Bloomberg (script 01).

pkgs <- c("vars", "BVAR", "urca", "tseries", "zoo", "ggplot2", "patchwork",
          "sandwich", "lmtest", "strucchange")

faltan <- setdiff(pkgs, rownames(installed.packages()))
if (length(faltan)) install.packages(faltan)

invisible(lapply(pkgs, library, character.only = TRUE))
message("Paquetes listos: ", paste(pkgs, collapse = ", "))
