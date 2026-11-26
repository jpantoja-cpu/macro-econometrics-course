@echo off
chcp 65001 >nul
rem ---------------------------------------------------------------------
rem subir_datos.bat - sube a GitHub los datos nuevos de Bloomberg.
rem Uso: doble clic (despues de correr R\actualizar_datos.R en RStudio).
rem Sube SOLO data\raw. Los resultados (output\) y las bases derivadas
rem (data\*.csv) que esta PC regenera se descartan: se regeneran en GitHub
rem a partir de los datos, asi el repositorio no se llena de cambios falsos.
rem ---------------------------------------------------------------------
cd /d "%~dp0"

echo.
echo == 1/4  Preparando los datos nuevos (data\raw) ==
git add data/raw
if errorlevel 1 goto error

echo == 2/4  Descartando resultados regenerados en esta PC ==
git restore output data

git diff --cached --quiet
if errorlevel 1 (
  git commit -m "Datos Bloomberg %date%"
  if errorlevel 1 goto error
) else (
  echo     No hay datos nuevos en data\raw.
)

echo == 3/4  Trayendo cambios de GitHub ==
git pull --no-edit
if errorlevel 1 goto error

echo == 4/4  Subiendo a GitHub ==
git push
if errorlevel 1 goto error

echo.
echo  LISTO: tu copia esta igual a GitHub y los datos nuevos quedaron subidos.
goto fin

:error
echo.
echo  HUBO UN ERROR. Copia todo lo que aparece arriba y pegaselo a Claude.

:fin
echo.
pause
