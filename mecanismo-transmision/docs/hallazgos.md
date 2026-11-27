# Hallazgos y decisiones

Datos de mercado de Bloomberg al 26-11-2026. Este documento no contiene posiciones del BCB.

## 1. Modelo (script 02)

**El VAR.** Mensual, de 1994-01 a 2026-10, con 2 rezagos (HQ), 12 variables en tres bloques:
- **Política:** EFFR.
- **Financiero:** 2Y, 10Y, prima por plazo 10Y (ACM), dólar (DXY), oro, Nasdaq 100, spread de alto rendimiento.

**Índice tecnológico: Nasdaq 100** (sugerencia de la mesa). El sector tecnología del S&P 500 sigue la clasificación GICS, que desde 2018 deja fuera a Alphabet y Meta (comunicaciones) y nunca incluyó a Amazon ni a Tesla (consumo). El Nasdaq 100 incluye a todas y es el índice con el que opera el mercado. Correlación de retornos mensuales entre ambos: 0,97. El S&P 500 tecnología queda como comprobación de robustez (sección 6).
- **Real:** producción industrial, nóminas, desempleo, IPC.

**Pandemia.** Marzo-agosto de 2020 se tratan con una variable ficticia por mes (Lenza y Primiceri 2022). Sin esto, los saltos de empleo de 2020 dominan el modelo: un alza de la Fed aparecía bajando el desempleo 70 pb en 3 meses.

**Choque de la Fed: qué instrumento.** Se compararon tres versiones de la sorpresa de futuros de fed funds (`irf_politica_instrumentos.csv`, `politica_instrumentos.png`):

| Instrumento | F | Lectura |
|---|---|---|
| **Bauer-Swanson (principal):** sorpresa limpia de noticias previas a la reunión (nóminas, empleo, S&P 500, pendiente, materias primas) | 24,9 | Efecto financiero claro; efecto real chico |
| Sorpresa total, sin limpiar | 42,0 | Parecido, con más "efecto información" (acciones y empleo suben tras un alza) |
| Solo días en que acciones y sorpresa se movieron en sentido opuesto (Jarociński-Karadi simplificado) | 15,8 | Efecto real fuerte, pero tecnología −14% al impacto: con ventana diaria selecciona días de caídas bursátiles por cualquier motivo. Solo como cota superior |

**Choque de estrés tecnológico.** Restricciones de signo al impacto (Uhlig 2005; Rubio-Ramírez, Waggoner y Zha 2010):
- Tecnología cae, spread HY sube, la EFFR no sube y la actividad no mejora en el mes.
- Es ortogonal al choque de la Fed.
- De las 500 rotaciones admisibles se usa la que más explica las acciones tecnológicas en el mes.
- 1 desviación estándar equivale a: Nasdaq 100 −4,3%, spread HY +30 pb, oro +0,4%.

## 2. Transmisión de una sorpresa de +25 pb (`irf_politica_*.png`)

**Bloque financiero (reacciona en el mes):**
- **Curva:** 2Y +8 pb al impacto y +13 pb a los 6-12 meses. El 10Y **baja** 11-14 pb los primeros 3 meses porque cae la prima por plazo (−16 a −20 pb). La curva se aplana, como en `var-tasas-fed`.
- **Tecnología (Nasdaq 100):** −2,5% al impacto; se recupera en 3-4 meses.
- **Crédito:** spread HY +30 pb al impacto, se cierra en 3-4 meses.
- **Oro:** −1,6% al impacto (banda de 90%: −2,3% a −1,0%); se recupera en unos 6 meses y a los 12 el efecto no es significativo.
- **Dólar:** casi sin efecto al impacto; luego −0,6%, no significativo.

**Bloque real (débil y con rezago):**
- **IPC:** −0,2 a −0,3% durante el primer año; es la respuesta real más clara.
- **Producción industrial:** −0,1 a −0,15% en los primeros 6 meses, en el borde de la significancia.
- **Empleo y desempleo:** sin efecto distinguible de cero con el instrumento principal.
- **Cota superior** (instrumento de acciones opuestas): producción −1%, desempleo +27 pb, nóminas −0,5%.

**Lectura.** La transmisión de la Fed a los mercados es rápida y medible. A la economía real llega débil, lenta e incierta en esta muestra. Es coherente con la literatura posterior a 1990 (Ramey 2016).

## 3. Escenarios: "la Fed sube 50 pb hasta enero" (`escenarios_condicionales.png`)

**La clave: el mercado ya lo descuenta casi todo.** Al 26-11-2026:
- EFFR 3,88%.
- Futuros: 4,06% en diciembre, 4,15% en enero, 4,28% en febrero, 4,43% en abril.
- Con reuniones el 9-dic y el 27-ene, subir 25 + 25 deja la EFFR en 4,38% desde febrero. Eso es solo **+10 pb** sobre lo descontado para febrero y **−5 pb** desde abril, porque el mercado espera algo más después.

**Escenarios, como desvío frente a la trayectoria de mercado:**
1. **Fed +50 pb a enero, luego pausa.** Sorpresa casi nula. Efectos de 1-5 pb en tasas y de menos de 1% en activos.
2. **Fed en pausa (no sube).** Sorpresa dovish de −55 pb desde abril. 2Y −19 pb a 6 meses y −29 pb a 12; spread HY −26 pb a 6 meses; oro +2,1% a 6 meses; IPC +0,5%.
3. **Fed +100 pb a enero, luego pausa.** Sorpresa de +45 pb. 2Y +25 pb a 12 meses; tecnología −2,5% y spread HY +32 pb a los 3 meses; IPC −0,4%.
4. **Fed +50 pb + corrección tecnológica de −15% en enero.** Es el escenario con efecto real visible:
   - spread HY hasta +200 pb;
   - 2Y −32 pb y 10Y −36 pb;
   - producción −1,5% y nóminas −0,8% a 12 meses;
   - desempleo +63 pb;
   - IPC −0,7%;
   - oro +2,1% a 12 meses y +5,1% a 24.
5. **Referencia: +50 pb que nadie esperaba.** Equivale a dos sorpresas de +25 pb sostenidas.

**Supuesto clave.** En el escenario 4 la Fed **no** reacciona a la corrección durante 12 meses, porque su trayectoria está fijada por construcción. Si recortara, el golpe real sería menor y la caída de tasas, mayor.

## 4. Traducción a reservas (script 03, `portafolios_escenarios.png`)

Retorno a 12 meses, en pb, como desvío frente al escenario de mercado. 1 pb = 10.000 USD por cada 100 millones.

| Escenario | Letras 1M | 3M | 6M | 1 año | 2 años | Oro |
|---|---|---|---|---|---|---|
| Fed +50 a enero, pausa | −1 | −1 | −1 | +1 | +4 | +15 |
| Fed en pausa | −38 | −34 | −24 | −2 | +41 | +133 |
| Fed +100 a enero, pausa | +36 | +32 | +23 | +3 | −33 | −103 |
| Fed +50 + corrección tecnológica | −1 | −1 | +1 | +7 | +19 | +211 |
| +50 pb que nadie esperaba | +40 | +35 | +25 | +3 | −37 | −115 |

**Lectura para la gestión:**
- **"+50 pb hasta enero" no es un riesgo para PL y PL2:** el mercado ya lo descuenta. Un portafolio de letras cortas casi no cambia frente a lo que ya rinde.
- **El riesgo relevante es la sorpresa, en ambos sentidos:**
  - Si la Fed no sube, las letras cortas renuevan a tasas menores (−35 pb en 12 meses) y ganan 2 años y oro.
  - Si sube más de lo esperado, ganan las letras cortas y pierden 2 años y oro.
- **El plazo de 1 año es casi neutro en todos los escenarios.** Comprado hoy, su retorno a 12 meses queda fijado por la tasa de compra.
- **El oro es la cobertura natural frente al estrés tecnológico** (+2,1% a 12 meses). Frente a una Fed más dura, en cambio, cae junto con los bonos.

**Limitaciones:**
- Rendimientos de 3M a 1 año por hipótesis de expectativas sobre la EFFR.
- Modelo lineal: una corrección del 15% se trata como 3,4 veces un choque típico.
- Las respuestas reales tienen bandas amplias.
- La trayectoria de mercado se supone plana después de abril de 2027.

## 5. ¿Pega más una alza cuando los mercados ya están tensos? (script 04)

**Enfoque.** Proyecciones locales con dependencia del estado (Ramey y Zubairy 2018; Tenreyro y Thwaites 2016):
- **Choque:** la serie del choque de política del VAR (sección 1), el mismo en ambos estados: sube la EFFR 25 pb al impacto en promedio.
- **Estado:** se mide el mes anterior al choque.
- **Muestra:** 1994-2026, sin las ventanas que tocan la pandemia.

**Por qué no la versión con instrumento por estado.** Se probó y se descartó: al partir la muestra, la sorpresa de la Fed pierde fuerza como instrumento (F = 1,2 en los meses de tecnología firme).

Dos definiciones de estado tenso:
- **Condiciones financieras:** índice de Bloomberg menor que 0, es decir, más restrictivas que lo normal (159 meses de 393).
- **Tecnología débil:** el Nasdaq 100 cayó en los 6 meses previos (89 meses de 387).

**Resultado: no hay evidencia de que la alza golpee más a la economía real en mercados tensos.** Si algo, es al revés: en estado tenso el empleo y la producción salen mejor después del choque. Es coherente con el "efecto información": cuando la Fed sube en plena tensión, el mercado lo lee como confianza en la economía. Lo que sí cambia es **cómo** se transmite (`lp_estado_*.png`, `lp_estado_resumen.csv`):

| +25 pb de la Fed | Mercados tensos | Mercados normales | p de la diferencia |
|---|---|---|---|
| 2Y al impacto | +2 pb | +16 pb | 0,04 |
| 10Y al impacto | −19 pb | +1 pb | 0,005 |
| EFFR a los 6 meses | +22 pb | +36 pb | 0,23 |
| Spread HY al impacto | +35 pb | +24 pb | 0,50 |
| Tecnología a 12 meses | +15% | −1% | 0,04 |
| IPC a 6 meses | −0,17% | −0,46% | 0,23 |

**Mercados tensos:**
- La alza casi no mueve el 2Y, porque el mercado anticipa que la Fed no la sostendrá; de hecho, la EFFR se mantiene menos.
- El 10Y cae por búsqueda de refugio y caída de la prima por plazo.
- La curva se aplana desde el tramo largo y el spread sube algo más al inicio.

**Mercados normales:**
- Es el canal "de libro": sube el 2Y, la Fed sostiene el alza y la inflación cae más (−0,3% a −0,5% durante 6 a 24 meses).
- Con tecnología firme, el IPC cae 0,35-0,55%; con tecnología débil la Fed retrocede (la EFFR a los 6 meses sube 9 pb, frente a 44 pb; p = 0,03) y la inflación casi no cae.

**Dónde estamos hoy:** en estado **normal** en ambas medidas. El índice de condiciones financieras está en +1,0 en octubre, holgado, y el Nasdaq 100 subió 14% en 6 meses. Si la Fed sorprende con alzas ahora, lo esperable es el canal de libro:
- se mueve el tramo de 2 años;
- la inflación cae;
- las acciones tecnológicas sufren poco y sin rebote.

Para reservas, el riesgo de duración está en el tramo de 1 a 2 años, no en el largo.

**Cautelas:**
- Varias diferencias no son significativas, y las bandas a 24 meses son amplias.
- El estado tenso concentra episodios de recuperación (2002-03, 2009-10), lo que puede inflar la respuesta real posterior.

## 6. Robustez: Nasdaq 100 frente a S&P 500 tecnología

Se repitieron los scripts 02 y 04 con el S&P 500 tecnología (`TEC=sp500_tec`; tablas con sufijo `_sp500_tec`). Las conclusiones no cambian:

| Resultado | Nasdaq 100 (principal) | S&P 500 tecnología |
|---|---|---|
| Tecnología al impacto de +25 pb | −2,5% | −3,3% |
| 2Y a 12 meses | +14 pb | +12 pb |
| 10Y al impacto | −11 pb | −11 pb |
| Oro al impacto | −1,6% | −1,6% |
| Spread HY al impacto | +30 pb | +30 pb |
| IPC a 6 meses | −0,16% | −0,17% |
| Choque tecnológico de 1 d.e. | −4,3% | −4,4% |
| Estado tenso: 2Y / 10Y al impacto | +2 / −19 pb | +2 / −19 pb |

**Lo único que se mueve es el oro a 12 meses en los escenarios.** Con Fed en pausa pasa de +0,8% a +1,3%, y con Fed +100 pb, de −0,6% a −1,0%. Son cifras imprecisas: la respuesta del oro a 12 meses no es significativa con ninguno de los dos índices. La lectura cualitativa se mantiene, pero no conviene presentar el oro a 12 meses como una cifra exacta.

## Pendiente

- Con el trader: pesos y duración de PL, PL2 y ORO, para pasar de estrategias genéricas a los portafolios reales (en el repositorio privado).
