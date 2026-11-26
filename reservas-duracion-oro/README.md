# Reservas: duración vs retorno y oro

Análisis de mercado para apoyar decisiones sobre los tramos de reservas invertidos en letras del Tesoro de EE.UU. y en oro.

> **Regla de este repositorio (público): aquí NO van posiciones ni datos internos del BCB.** Solo datos de mercado públicos (Bloomberg) y resultados agregados. El análisis con posiciones reales irá en un repositorio privado.

## Preguntas

1. **Duración vs retorno.** Con 38 años de historia, ¿qué retorno, qué peor año y qué probabilidad de pérdida tienen estrategias de letras del Tesoro de duración 0,1, 0,25, 0,5, 1 y 2 años? ¿Cómo se comportan en ciclos de alzas y de recortes de la Fed?
2. **Oro.** ¿Qué mueve el precio del oro (tasas reales, dólar, volatilidad) y cómo reacciona el día de las sorpresas del FOMC?

## Datos

- Ya descargados en el proyecto hermano `../var-tasas-fed/data/raw/` (se reutilizan): rendimientos del Tesoro, índices total return por tramo, sorpresas del FOMC, VIX, MOVE, breakevens.
- Nuevos (`R/01_descarga_mercado.R`): oro (XAU, LBMA), tasas reales (TIPS 5Y y 10Y), dólar (DXY), volatilidad del oro (GVZ) e índices de letras del Tesoro.

## Cómo correr

1. En la PC con Bloomberg: `R/01_descarga_mercado.R` (Source) y luego doble clic en `subir_datos.bat`.
2. Análisis: scripts `R/02_*` en adelante.

Detalle de decisiones y resultados: [docs/hallazgos.md](docs/hallazgos.md).
