# Reservas: duración vs retorno y oro

Análisis de mercado para apoyar decisiones sobre los tramos de reservas invertidos en letras del Tesoro de EE.UU. y en oro.

> **Regla de este repositorio (público): aquí NO van posiciones ni datos internos del BCB.** Solo datos de mercado públicos (Bloomberg) y resultados agregados. El análisis con posiciones reales irá en un repositorio privado.

## Preguntas

1. **Duración vs retorno.** Con 38 años de historia, ¿qué retorno, qué peor año y qué probabilidad de pérdida tienen estrategias de letras del Tesoro de duración 0,1, 0,25, 0,5, 1 y 2 años? ¿Cómo se comportan en ciclos de alzas y de recortes de la Fed?
2. **Oro.** ¿Qué mueve el precio del oro (tasas reales, dólar, volatilidad) y cómo reacciona el día de las sorpresas del FOMC?

## Datos

- Ya descargados en el proyecto hermano `../var-tasas-fed/data/raw/` (se reutilizan): rendimientos del Tesoro, índices total return por tramo, sorpresas del FOMC, VIX, MOVE, breakevens.
- Nuevos (`R/01_descarga_mercado.R`): oro (XAU, LBMA), tasas reales (TIPS 5Y y 10Y), dólar (DXY), volatilidad del oro (GVZ) e índices de letras del Tesoro.

## Resultados principales

1. **Duración:** sin una visión sobre la Fed, alargar de letras a 2 años paga unos 30 pb al año, con un peor año de −5,6%. Con visión, el efecto es grande y asimétrico: +214 pb sobre la caja si la Fed recorta 50 pb o más, −168 pb si sube. Las letras rinden 20-30 pb menos que la EFFR, que es el costo de su liquidez.
2. **Oro:** una sorpresa restrictiva de la Fed sobre la trayectoria de tasas baja el oro (−1,8% por 25 pb; −5% en 2021-2026), sube la tasa real y fortalece el dólar. La relación de largo plazo con la tasa real se debilitó mucho desde 2022 (de −17% a −3% por punto porcentual); la relación con el dólar sigue estable.

## Cómo correr

1. En la PC con Bloomberg: `R/01_descarga_mercado.R` (Source) y luego doble clic en `subir_datos.bat`.
2. Análisis: scripts `R/02_*` en adelante.

Detalle de decisiones y resultados: [docs/hallazgos.md](docs/hallazgos.md).
