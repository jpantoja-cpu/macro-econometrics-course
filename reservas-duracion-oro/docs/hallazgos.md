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
