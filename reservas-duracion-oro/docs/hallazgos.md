# Hallazgos y decisiones

Datos de mercado de Bloomberg. Este documento no contiene posiciones del BCB.

## 1. Duración vs retorno (script 02)

**Enfoque.**
- **Estrategias:** vencimiento constante (caja, letras de 3 y 6 meses, 1, 2 y 3 años), rebalanceadas cada mes, de 1988-02 a 2026-10 (465 meses).
- **Retorno mensual:** el de un bono cupón cero de ese plazo, comprado a fin de mes y vendido al mes siguiente. La caja rinde la EFFR.
- **Lectura central:** el retorno a 12 meses según lo que hizo la Fed en esos 12 meses (recortes de 50 pb o más, alzas de 50 pb o más, o estable).

**Decisiones y validación.**
- **Hueco del 1 año (81 meses, de 2001-08 a 2008-06):** el Tesoro no emitió letras a 1 año. Se interpola linealmente entre 6 meses y 2 años.
- **Validación:** la estrategia de 2 años tiene una correlación mensual de 0,991 con el índice total return de Bloomberg del Tesoro 1-3 años. Rinde unos 0,3 pp menos al año porque no incluye el *roll-down* (la ganancia de "deslizarse" por la curva con pendiente positiva). Por eso los retornos de los plazos largos están levemente **subestimados**.

**Resultados** (`resumen_estrategias.csv`, `retorno_12m_por_regimen_fed.csv`):

| Estrategia | Duración | Retorno anual | Peor 12 meses | % de años con pérdida |
|---|---|---|---|---|
| Caja (EFFR) | 0 | 3,30% | +0,07% | 0% |
| Letras 3M | 0,24 | 3,01% | −0,03% | 1,8% |
| Letras 6M | 0,48 | 3,15% | −0,53% | 3,1% |
| 1 año | 0,97 | 3,28% | −2,24% | 5,1% |
| 2 años | 1,93 | 3,59% | −5,56% | 12,3% |
| 3 años | 2,89 | 3,73% | −8,45% | 20,9% |

Exceso de retorno a 12 meses sobre la caja, en pb, según lo que hizo la Fed:

| | Letras 3M | Letras 6M | 1 año | 2 años | 3 años |
|---|---|---|---|---|---|
| Recortes | −21 | +22 | +91 | +214 | +285 |
| Estable | −21 | −12 | 0 | +30 | +61 |
| Alzas | −44 | −57 | −104 | −168 | −224 |

- **La duración paga en recortes y cuesta en alzas, y el efecto es asimétrico:** en recortes, 2 años gana 214 pb sobre la caja; en alzas pierde 168 pb.
- **Sin una visión sobre la Fed, el premio por duración es pequeño:** unos 30 pb al año en 2 años, algo más con roll-down. El costo en peor caso es grande: −5,6% en 12 meses en 2022.
- **Las letras rinden menos que la EFFR (≈ 20-30 pb al año).** Es la "prima de conveniencia" de las letras: el mercado paga por su liquidez y seguridad. Un portafolio de letras muy cortas cuesta algo frente a la tasa de la Fed, y ese es el precio de la liquidez.
- **Hasta 1 año el riesgo de pérdida anual es bajo:** 5% de los años, con un peor caso de −2,2%. Desde 2 años el riesgo sube rápido.

## 2. Oro (script 03)

**Datos.** Oro spot (`XAU Curncy`), tasa real a 10 años (`USGGT10Y`, TIPS, desde 1997), dólar (`DXY`) y VIX. Sorpresas del FOMC y de datos macro del proyecto `var-tasas-fed`. La serie LBMA (`GOLDLNPM`) validó pero no trajo historia; se usa el spot.

### 2.1 Día de la noticia (`oro_eventos.png`, `oro_eventos_coeficientes.csv`)

Regresión diaria sobre todos los días hábiles de 1994-2026, sin marzo-diciembre de 2020. Efecto sobre el oro en %:

| Noticia | 1994-2026 | 1994-2007 | 2008-2019 | 2021-2026 |
|---|---|---|---|---|
| FOMC: sorpresa target de 25 pb | −0,77*** | −0,14 | −1,34*** | −0,17 |
| FOMC: sorpresa path de 25 pb | −1,79*** | −0,11 | −4,36*** | −5,20*** |
| Nóminas (1 d.e.) | −0,24*** | −0,11 | −0,77*** | −0,16** |
| IPC general / subyacente (1 d.e.) | ≈ 0 | ≈ 0 | ≈ 0 | ≈ 0 |

- **Una Fed más dura baja el oro, sobre todo cuando sorprende con la trayectoria esperada de tasas.** En la muestra completa, una sorpresa path de 25 pb sube la tasa real a 10 años 24 pb, sube el dólar 1,4% y baja el oro 1,8%. En 2021-2026 el efecto sobre el oro llega a −5,2%.
- **Antes de 2008 el oro no reaccionaba a la Fed.** La sensibilidad apareció con la crisis y la guía futura.
- **Un informe de empleo fuerte baja el oro;** las sorpresas del IPC no lo mueven el mismo día.
- En la práctica las sorpresas path son chicas (unos 3-4 pb de desviación estándar), así que una sorpresa típica mueve el oro alrededor de 0,5-0,8%.

### 2.2 Determinantes mensuales (`oro_determinantes_mensuales.csv`, `oro_coeficientes_moviles.png`)

Para 1997-2026 (338 meses, R² = 0,29):
- +1 pp en la tasa real a 10 años → oro **−6,4%** (t = −4,6).
- +1% en el dólar → oro **−0,8%** (t = −6,4).
- El VIX no es significativo.

**La relación con la tasa real se debilitó mucho desde 2022.** En ventanas de 5 años:
- **Hasta 2019:** +1 pp de tasa real bajaba el oro **17%**.
- **Desde 2023:** solo **3-4%**. El oro subió a máximos (≈ 3.570 USD/oz a fines de noviembre de 2026) con tasas reales cerca de 2,7%, algo que el modelo clásico no habría anticipado. Es coherente con un motor que este modelo no observa, como la demanda de oro de bancos centrales y la búsqueda de cobertura geopolítica.
- **La relación con el dólar se mantuvo estable**, en torno a −0,8% a −1,2% por cada 1%.

**Lectura para la gestión de reservas:**
- El oro protege poco frente a una Fed restrictiva en el corto plazo: el día de la sorpresa cae junto con los bonos.
- Su relación de largo plazo con las tasas reales hoy es mucho más débil que en el pasado. Los modelos que proyectan el oro solo con tasas reales y dólar hoy lo explican peor.
