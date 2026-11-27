# Hallazgos y decisiones

Datos de mercado de Bloomberg al 26-11-2026. Este documento no contiene posiciones del BCB.

## 1. Modelo (script 02)

**El VAR.** Mensual, de 1994-01 a 2026-10, con 2 rezagos (HQ), 12 variables en tres bloques:
- **Política:** EFFR.
- **Financiero:** 2Y, 10Y, prima por plazo 10Y (ACM), dólar (DXY), oro, S&P 500 tecnología, spread de alto rendimiento.
- **Real:** producción industrial, nóminas, desempleo, IPC.

**Pandemia.** Marzo-agosto de 2020 se tratan con una variable ficticia por mes (Lenza y Primiceri 2022). Sin esto, los saltos de empleo de 2020 dominan el modelo: un alza de la Fed aparecía bajando el desempleo 70 pb en 3 meses.

**Choque de la Fed: qué instrumento.** Se compararon tres versiones de la sorpresa de futuros de fed funds (`irf_politica_instrumentos.csv`, `politica_instrumentos.png`):

| Instrumento | F | Lectura |
|---|---|---|
| **Bauer-Swanson (principal):** sorpresa limpia de noticias previas a la reunión (nóminas, empleo, S&P 500, pendiente, materias primas) | 24,9 | Efecto financiero claro; efecto real chico |
| Sorpresa total, sin limpiar | 41,9 | Parecido, con más "efecto información" (acciones y empleo suben tras un alza) |
| Solo días en que acciones y sorpresa se movieron en sentido opuesto (Jarociński-Karadi simplificado) | 15,4 | Efecto real fuerte, pero tecnología −16% al impacto: con ventana diaria selecciona días de caídas bursátiles por cualquier motivo. Solo como cota superior |

**Choque de estrés tecnológico.** Restricciones de signo al impacto (Uhlig 2005; Rubio-Ramírez, Waggoner y Zha 2010):
- Tecnología cae, spread HY sube, la EFFR no sube y la actividad no mejora en el mes.
- Es ortogonal al choque de la Fed.
- De las 500 rotaciones admisibles se usa la que más explica las acciones tecnológicas en el mes.
- 1 desviación estándar equivale a: tecnología −4,4%, spread HY +30 pb, oro +0,4%.

## 2. Transmisión de una sorpresa de +25 pb (`irf_politica_*.png`)

**Bloque financiero (reacciona en el mes):**
- **Curva:** 2Y +8 pb al impacto y +12 pb a los 6-12 meses. El 10Y **baja** 11-14 pb los primeros 3 meses porque cae la prima por plazo (−16 a −20 pb). La curva se aplana, como en `var-tasas-fed`.
- **Tecnología:** −3,3% al impacto; se recupera en unos 6 meses.
- **Crédito:** spread HY +30 pb al impacto, se cierra en 3-4 meses.
- **Oro:** −1,6% al impacto, sin efecto a 12 meses.
- **Dólar:** casi sin efecto al impacto; luego −0,6%, no significativo.

**Bloque real (débil y con rezago):**
- **IPC:** −0,2 a −0,3% durante el primer año; es la respuesta real más clara.
- **Producción industrial:** −0,1 a −0,15% en los primeros 6 meses, en el borde de la significancia.
- **Empleo y desempleo:** sin efecto distinguible de cero con el instrumento principal.
- **Cota superior** (instrumento de acciones opuestas): producción −1%, desempleo +29 pb, nóminas −0,6%.

**Lectura.** La transmisión de la Fed a los mercados es rápida y medible. A la economía real llega débil, lenta e incierta en esta muestra. Es coherente con la literatura posterior a 1990 (Ramey 2016).

## 3. Escenarios: "la Fed sube 50 pb hasta enero" (`escenarios_condicionales.png`)

**La clave: el mercado ya lo descuenta casi todo.** Al 26-11-2026:
- EFFR 3,88%.
- Futuros: 4,06% en diciembre, 4,15% en enero, 4,28% en febrero, 4,43% en abril.
- Con reuniones el 9-dic y el 27-ene, subir 25 + 25 deja la EFFR en 4,38% desde febrero. Eso es solo **+10 pb** sobre lo descontado para febrero y **−5 pb** desde abril, porque el mercado espera algo más después.

**Escenarios, como desvío frente a la trayectoria de mercado:**
1. **Fed +50 pb a enero, luego pausa.** Sorpresa casi nula. Efectos de 1-5 pb en tasas y de menos de 1% en activos.
2. **Fed en pausa (no sube).** Sorpresa dovish de −55 pb desde abril. 2Y −27 pb y spread HY −28 pb a los 6 meses; tecnología +4%; oro +2%; IPC +0,3 a +0,5%.
3. **Fed +100 pb a enero, luego pausa.** Sorpresa de +45 pb. 2Y +23 pb a 12 meses; tecnología −3,6% y spread HY +33 pb a los 3 meses; IPC −0,4%.
4. **Fed +50 pb + corrección tecnológica de −15% en enero.** Es el escenario con efecto real visible:
   - spread HY +190 pb;
   - 2Y y 10Y −30 pb;
   - producción −1,5% y nóminas −0,8% a 12 meses;
   - desempleo +60 pb;
   - IPC −0,7%;
   - oro +2,4% a 12 meses y +5,8% a 24.
5. **Referencia: +50 pb que nadie esperaba.** Equivale a dos sorpresas de +25 pb sostenidas.

**Supuesto clave.** En el escenario 4 la Fed **no** reacciona a la corrección durante 12 meses, porque su trayectoria está fijada por construcción. Si recortara, el golpe real sería menor y la caída de tasas, mayor.

## 4. Traducción a reservas (script 03, `portafolios_escenarios.png`)

Retorno a 12 meses, en pb, como desvío frente al escenario de mercado. 1 pb = 10.000 USD por cada 100 millones.

| Escenario | Letras 1M | 3M | 6M | 1 año | 2 años | Oro |
|---|---|---|---|---|---|---|
| Fed +50 a enero, pausa | −1 | −1 | −1 | 0 | +4 | +14 |
| Fed en pausa | −38 | −34 | −24 | −3 | +38 | +83 |
| Fed +100 a enero, pausa | +36 | +32 | +23 | +4 | −31 | −55 |
| Fed +50 + corrección tecnológica | −1 | −1 | +1 | +8 | +22 | +238 |
| +50 pb que nadie esperaba | +40 | +35 | +25 | +4 | −34 | −63 |

**Lectura para la gestión:**
- **"+50 pb hasta enero" no es un riesgo para PL y PL2:** el mercado ya lo descuenta. Un portafolio de letras cortas casi no cambia frente a lo que ya rinde.
- **El riesgo relevante es la sorpresa, en ambos sentidos:**
  - Si la Fed no sube, las letras cortas renuevan a tasas menores (−35 pb en 12 meses) y ganan 2 años y oro.
  - Si sube más de lo esperado, ganan las letras cortas y pierden 2 años y oro.
- **El plazo de 1 año es casi neutro en todos los escenarios.** Comprado hoy, su retorno a 12 meses queda fijado por la tasa de compra.
- **El oro es la cobertura natural frente al estrés tecnológico** (+2,4% a 12 meses). Frente a una Fed más dura, en cambio, cae junto con los bonos.

**Limitaciones:**
- Rendimientos de 3M a 1 año por hipótesis de expectativas sobre la EFFR.
- Modelo lineal: una corrección del 15% se trata como 3,4 veces un choque típico.
- Las respuestas reales tienen bandas amplias.
- La trayectoria de mercado se supone plana después de abril de 2027.

## Pendiente

- Proyecciones locales dependientes del estado: ¿el alza pega más cuando las condiciones financieras ya están débiles?
- Con el trader: pesos y duración de PL, PL2 y ORO, para pasar de estrategias genéricas a los portafolios reales (en el repositorio privado).
