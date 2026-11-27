# Mecanismo de transmisión: Fed → mercados → economía real y tecnología → reservas

**Pregunta.** Si la Fed sube más de lo que el mercado espera (por ejemplo, 50 pb hasta enero frente a unos 40 pb descontados), ¿cómo se transmite a los mercados financieros (curva, dólar, oro, acciones de tecnología, crédito), luego a la economía real (empleo, producción, inflación), y cómo vuelve sobre los portafolios de reservas (letras del Tesoro y oro)?

> **Regla (repositorio público):** aquí no van posiciones ni datos internos del BCB; solo datos de mercado públicos y resultados agregados.

## Enfoque

1. **VAR por bloques** con choque de política identificado con las sorpresas de futuros de fed funds (instrumento externo, del proyecto `var-tasas-fed`): bloque financiero (2Y, 10Y, prima por plazo, dólar, oro, tecnología, spreads de crédito, VIX/MOVE) y bloque real (empleo, producción, IPC).
2. **Choque de estrés tecnológico** identificado con restricciones de signo.
3. **Proyecciones locales dependientes del estado:** ¿el alza golpea más cuando las condiciones financieras o el sector tecnológico ya están débiles?
4. **Pronósticos condicionales** (Waggoner y Zha 1999): "EFFR +50 pb a enero" y su combinación con estrés tecnológico.
5. **Traducción a los portafolios** con las herramientas de `reservas-duracion-oro`.

## Datos

- Reutilizados de `../var-tasas-fed/data/raw/` y `../reservas-duracion-oro/data/raw/`.
- Nuevos (`R/01_descarga_transmision.R`): S&P 500, Nasdaq 100, S&P 500 tecnología, semiconductores, bancos (KBW), spreads de crédito IG y HY, índice de condiciones financieras de Bloomberg.

## Scripts

| Script | Qué hace |
|---|---|
| `R/01_descarga_transmision.R` | Descarga acciones, tecnología, crédito y condiciones financieras (oficina, Bloomberg) |
| `R/02_transmision_var.R` | VAR por bloques, choque de la Fed (Bauer-Swanson), choque tecnológico (signos), escenarios frente a los futuros |
| `R/03_portafolios.R` | Retorno a 12 meses de letras, bonos y oro en cada escenario (por 100 millones) |
| `R/04_lp_estado.R` | ¿La alza pega distinto con condiciones financieras tensas o tecnología débil? (proyecciones locales por estado) |

Detalle en [docs/hallazgos.md](docs/hallazgos.md).
