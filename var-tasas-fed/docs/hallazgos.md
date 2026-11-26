# Hallazgos, decisiones y tests fallidos

Registro de cada decisión tomada en el proyecto, de los tests que fallan y de la lectura económica.
Datos: Bloomberg, descargados el 2026-11-26 (`data/raw/bloomberg_tasas.csv`, 19 series, 1988-01 a 2026-11).
Base mensual: 1988-01 a 2026-10 (466 meses).

## 1. Datos y decisiones de construcción

| Decisión | Motivo |
|---|---|
| Tasas y BCOM: promedio mensual de datos diarios | Consistente con IP e IPC, que son mensuales; reduce ruido diario. |
| IP, IPC y BCOM en 100 × log | Las respuestas se leen como variaciones porcentuales. |
| Tasas en niveles, en % | Un choque de 25 pb = 0.25; las IRF se reportan en pb. |
| Se descarta el mes en curso (nov-2026) en las series diarias | Su promedio está incompleto. |
| **Octubre 2025 interpolado en IPC y desempleo** | El BLS no publicó ese mes por el cierre del gobierno de EE.UU. Se usa el promedio de septiembre y noviembre (en log×100 para el IPC). Registro en `data/meses_interpolados.csv`. |
| **USGG12M (1 año) no se usa como indicador de política** | Tiene un hueco de 2001-08 a 2008-06: el Tesoro suspendió las letras a 1 año. La variante de muestra completa usa el **2Y** (Hanson y Stein 2015) en lugar del 1Y de Gertler y Karadi (2015). |
| 19 tickers validados con `bdp(..., "NAME")` | Todos OK; log en `data/raw/log_tickers.csv`. Los índices total return del Tesoro empiezan en 1992. |

## 2. Inspección (antes de estimar)

- Paneles por serie en `output/figuras/inspeccion_*.png` (nivel, diferencia, ACF/PACF, densidad, estacionalidad).
- **Raíz unitaria** (`output/tablas/raiz_unitaria.csv`): las tasas a 2Y, 5Y, 10Y y 30Y y los logs de IP, IPC y BCOM son I(1) según ADF y KPSS. Fed funds y 3M dan resultado ambiguo: ADF rechaza al 5% por poco, pero KPSS también rechaza. Todas son I(0) en diferencias. Zivot-Andrews ubica los quiebres de las tasas en 2021-12/2022-02, al inicio del ciclo de alzas.
- **Decisión: VAR en niveles.** Con raíces unitarias, las IRF del VAR en niveles siguen siendo consistentes (Sims, Stock y Watson 1990) y no hay que imponer relaciones de cointegración. La raíz máxima del sistema es 0.999, como se espera en niveles.
- **Estacionalidad:** IP e IPC vienen desestacionalizados (SA) de Bloomberg; los boxplots por mes no muestran patrón en las tasas.
- **Colinealidad fed funds–3M:** correlación de 0.99 en niveles, pero de 0.71 en primeras diferencias (1988-2007). El 3M aporta información propia, así que se mantiene; la variante "sin 3M" va en robustez.

## 3. Especificaciones

**A (principal): 1988-01 a 2007-12, política = fed funds efectiva.** Termina antes del límite inferior cero (ZLB), donde la fed funds deja de moverse.
Orden Cholesky: [IP, IPC, BCOM, fed funds, 3M, 2Y, 5Y, 10Y, 30Y]. La macro no reacciona dentro del mes al choque de política; las tasas de mercado sí.

**B: 1988-01 a 2026-10, política = 2Y.** Orden: [IP, IPC, BCOM, 2Y, 3M, 5Y, 10Y, 30Y].

**Rezagos.** AIC, BIC y HQ eligen 1-2 rezagos en A y 2-3 en B. **Decisión: p = 6**, con un piso de 6 meses, porque con datos mensuales 1-2 rezagos no capturan la dinámica de la política (ver la nota sobre robustez más abajo: esta decisión pesa en el mediano plazo).

## 4. Resultados

### 4.1 Especificación A: choque de +25 pb en la fed funds (1988-2007)

| Tramo | Impacto (pb) | Banda 68% | Precio al impacto (%) |
|---|---|---|---|
| 3M | 16.7 | [14.7, 18.9] | −0.04 |
| 2Y | 14.3 | [11.0, 17.7] | −0.27 |
| 5Y | 9.5 | [6.2, 12.9] | −0.42 |
| 10Y | 5.8 | [2.8, 9.0] | −0.46 |
| 30Y | 3.1 | [0.6, 6.2] | −0.48 |

- **La transmisión cae con el plazo:** 2/3 del choque llega al 3M, cerca del 60% al 2Y, un cuarto al 10Y y un octavo al 30Y. **La curva se aplana:** 10Y−3M cae 11 pb y 30Y−2Y cae 11 pb al impacto.
- **En precios el orden se invierte:** aunque el rendimiento largo se mueve menos, la duración (8.0 años en el 10Y, 15.5 en el 30Y) hace que el precio largo caiga más.
- **FEVD:** el choque de política explica poco de la varianza de las tasas: 3-16% a 12 meses y ~10% a 48 meses. La mayor parte del movimiento de la curva no viene de sorpresas de la fed funds.

### 4.2 Especificación B: choque de +25 pb en el 2Y (muestra completa)

| Tramo | Impacto (pb) | 12 meses (pb) | Precio al impacto (%) |
|---|---|---|---|
| 3M | 12.5 | 43.6 | −0.03 |
| 5Y | 24.4 | 27.3 | −1.08 |
| 10Y | 19.5 | 19.4 | −1.55 |
| 30Y | 14.0 | 13.2 | −2.13 |

- Un choque al 2Y se transmite **mucho más al tramo largo** que un choque a la fed funds: 19.5 pb al 10Y contra 5.8 pb en A. Además el 3M sube con rezago (+44 pb a 12 meses), es decir, la Fed termina convalidando el movimiento.
- **Lectura:** el choque de A se parece a un choque de "nivel actual" de la tasa (target). El de B se parece a uno de "trayectoria esperada" (path, en la terminología de Gürkaynak, Sack y Swanson 2005), y ese es el que mueve los precios de los bonos largos.
- **Advertencia:** en B el choque explica 48-87% de la varianza de las tasas a 12 meses. No es un choque monetario puro: al ordenar el 2Y primero entre las tasas, el choque absorbe todo lo que mueve el 2Y dentro del mes, incluida la información macro. Por eso A es la especificación principal para un choque de la Fed propiamente dicho.

### 4.3 Validación de precios con índices total return

Proyecciones locales de los índices total return del Tesoro de Bloomberg sobre el choque B (+25 pb, impacto):

| Índice | ΔP con índice TR | ΔP por duración (B) |
|---|---|---|
| 7-10 años | −1.40% | −1.55% (10Y) |
| 20+ años | −2.24% | −2.13% (30Y) |

Los dos métodos coinciden en magnitud, así que la traducción de rendimientos a precios por duración es razonable.

### 4.4 ¿Alza y recorte tienen efectos simétricos?

En el VAR lineal la simetría se impone por construcción. Las proyecciones locales con choques positivos y negativos separados muestran:

- **Primeros ~20 meses:** alza y recorte dan respuestas espejo en todos los tramos y en todas las muestras. No se rechaza simetría.
- **Especificación A (1988-2007):** se rechaza simetría en 2-5 de 37 horizontes, que es lo esperable por azar al 10%. **No hay evidencia de asimetría.**
- **Especificación B, a partir de ~2 años:** las respuestas divergen. Tras un alza las tasas siguen altas; tras un recorte, las tasas largas terminan *por encima* de su nivel previo (el recorte se revierte). Se rechaza simetría en 11-18 horizontes con la muestra completa, y la divergencia persiste en el 10Y y el 30Y aun excluyendo 2020-2022 (11-12 horizontes, `lp_asimetria_B_hasta2019.png`).
- **Lectura prudente:** más que una asimetría en la transmisión, esto refleja que los recortes ocurren en recesiones y les sigue una recuperación con alzas. Las proyecciones locales solo controlan por rezagos y no capturan el estado del ciclo. Además, a horizontes largos hay pocos episodios independientes y las pruebas se repiten sobre 37 horizontes superpuestos.

## 5. Robustez (especificación A)

Archivo `output/figuras/robustez_irf.png`.

- **Impacto: robusto.** En todas las variantes (BVAR, 3 o 9 rezagos, política primero, sin 3M, muestra completa) el impacto queda en 16-21 pb para el 3M, 12-17 para el 2Y, 7-12 para el 5Y, 4-7.5 para el 10Y y 1.7-4.7 para el 30Y.
- **Mediano plazo: no robusto.** Con 6 y 9 rezagos aparece una oscilación en el tramo largo: cae 10-12 pb hacia el mes 5 y sube +8-12 pb hacia el mes 15. **No aparece en el BVAR** (λ = 0.08, elegido por verosimilitud marginal) **ni en el VAR(3)**, que dan un descenso suave hacia cero. Como los criterios de información prefieren pocos rezagos y el BVAR es el estimador más disciplinado con 9 variables y 234 observaciones, la oscilación debe leerse como sobreajuste, no como un hallazgo.
- **Muestra completa con fed funds:** respuestas más persistentes y planas en el largo plazo. Es la contaminación esperada del ZLB (2009-2015, 2020-2022), donde la fed funds no se mueve y el VAR atribuye mal la dinámica; confirma por qué no es la especificación principal.

## 6. Tests que fallan (documentados, no escondidos)

| Test | Resultado | Lectura |
|---|---|---|
| Portmanteau (h=24) y LM (h=12) | Se rechaza no-autocorrelación en A y B (p < 0.001) | Queda dinámica sin capturar con p=6; es otra razón para no sobreinterpretar el mediano plazo. Subir p empeora el sobreajuste. |
| Jarque-Bera | En A se rechaza normalidad en IP, IPC, BCOM, fed funds y 5Y; en B, en todas las ecuaciones | Colas pesadas por 2008 y 2020. Las bandas son bootstrap de residuos, así que no dependen de la normalidad. |
| ARCH (12 rezagos) | Se rechaza en la ecuación del IPC (A y B) e IP/2Y (B) | Volatilidad cambiante. No afecta la consistencia de las IRF puntuales. |
| Sesgo del bootstrap | En algunos horizontes medios la IRF puntual queda fuera de la banda 68% (p. ej., 10Y a 24 meses en A: 5.4 vs [−2.6, 5.1]) | Sesgo de muestra pequeña en VAR casi integrados: las réplicas son menos persistentes que la estimación. Mejora pendiente: bootstrap con corrección de sesgo de Kilian (1998). |

## 7. Pendientes / siguientes pasos

1. Identificación con instrumento externo: sorpresas de futuros de fed funds en días FOMC (Gertler-Karadi), descargables de Bloomberg (`FF1 Comdty`, `FF2 Comdty`), o separar choques "target" y "path" (Gürkaynak-Sack-Swanson).
2. Bootstrap con corrección de sesgo (Kilian 1998).
3. Proyecciones locales dependientes del estado (recesión/expansión) para separar asimetría de ciclo.
4. Shadow rate de Wu-Xia para usar la fed funds en la muestra completa.
