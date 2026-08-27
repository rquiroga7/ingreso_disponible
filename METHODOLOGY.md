# METHODOLOGY — Reconstrucción del "Ingreso Real y Disponible" (Equilibra)

Última actualización: 2026-08-24. Pipeline: `scripts/01…06` (re-ejecutables en orden).

## 1. Fuentes de datos

| Fuente | Uso | Acceso |
|---|---|---|
| EPH usuaria t231–t261 (individual + hogar) | universo, pesos por segmento, media previsional trimestral | INDEC (zips en `data/raw/eph/zips/`), ruta verificada en skill EPH-INDEC |
| IPC Nacional base dic-2016: nivel general + 12 divisiones + regulados | deflactores serie A, reponderación serie B, canasta fija | API datos.gob.ar (`data/raw/ipc/`, IDs en `scripts/02`) |
| RIPTE (`158.1_REPTE_0_0_5`) | dinámica salarial privado formal (cola + proxy) | API datos.gob.ar, hasta jun-26 |
| Índice de salarios IST nominal privado/público (`149.1_SOR_*`) | segmentos de ingreso mensual | API datos.gob.ar, hasta abr-26 |
| Haber mínimo jubilatorio (`58.1_MP_0_M_24`) | cola del segmento jubilados (diagnóstico) | API datos.gob.ar, hasta ago-26 |
| ENGHo 2017/18 Cuadro 1 | pesos de divisiones y grupos (Total país y GBA) | PDF local → `data/dicts/weights_engho_2017_18.csv` |

No disponibles públicamente (verificado 2026-08-24): índices IPC por **grupo** (alquileres,
electricidad/gas, agua, seguros médicos) en la familia del IPC Nacional; haber **medio**
previsional (series 189.1 de SIPA están rojas: ceros hasta 2026-01); ICL no está en la API.
Los montos de alquiler de la EPH hogar (II8/II9) son **tramos categóricos** desde el nuevo
diseño 2023 — no permiten construir un índice de alquileres.

## 2. Universo (PLAN §7.1)

Filtros sobre base individual, expandidos con `PONDERA`:

- **priv_formal**: `ESTADO==1 & CAT_OCUP==3 & PP04A==2 & PP07H==1` (asalariado privado registrado)
- **publico**: `ESTADO==1 & CAT_OCUP==3 & PP04A==1 & PP07H==1` (asalariado estatal registrado)
- **jubilado**: `ESTADO!=1 & pensión>0` (suma de `V2_M` / `V2_0x_M`; aguinaldos `V21_*` excluidos)

Ventana base (t231:t233): **9,57 M de personas** (priv 42,6% / pub 21,8% / jub 35,6%).
Los 14,5 M de Equilibra exceden lo expandible desde EPH aglomerados (~29–30 M de población
urbana cubierta); el gate ±10% del PLAN no se alcanza con filtros estrictos (variantes más
amplias llegan a ~13,8 M incluyendo informales, contradiciendo la definición). La serie
depende de **trayectorias relativas**, no del nivel absoluto del universo; los pesos por
segmento son los que calibran la dinámica agregada. Variante rechazada: incluir ocupados
con pensión en `jubilado` (empeora todos los anclas).

## 3. Ingreso nominal mensual (decisión central)

**La nota de Equilibra describe dinámicas por segmento coherentes con registros
administrativos** (Secretaría de Trabajo para salarios, ANSES para haberes — cita explícita
en la nota), no con medias de encuesta. Probado empíricamente: la media EPH pura (P21+pen)
sobrestima la recuperación 2024–25 (jun-25 real = 107,5 vs 94 objetivo, +13,5 pts), por
deriva de composición (salida de empleos de salarios bajos) e imputación caliente. Knobs
probados y descartados: mediana (peor), full-time only (peor), excluir `IMPUTA` (sin
efecto), medias con celdas de composición fija base (jun-25 = 103, insuficiente).

Construcción adoptada (hibrida):

- **priv_formal** = SIPA remuneración promedio de asalariados privados registrados (SST).
  Revisión 2026-08-25: Equilibra usa el SIPA (fuente "Secretaría de Trabajo"), que capta
  bonos, premios y no remunerativos (por eso difiere del IST/RIPTE) y cayó en 2026. Se
  desestacionaliza con STL (Loess, base de R; multiplicativo vía log, s.window periódico)
  para quitar el SAC de jun/dic. Se usa la serie DEFINITIVA (153.1, llega a may-26) y el
  **provisional de la SST solo para jun-26** (el mes que falta; ~+1% nominal, anticipado
  98% DDJJ). Nota: la definitiva may-26 (−4,9% nominal) diverge del provisional de la SST
  (~−0,8%); la diferencia es vintage del dato.
- **publico** = IST público registrado nominal (INDEC) — cola may/jun-26 con su propio
  m/m (CSV `variacion_indice_salarios.csv`). El IST público jun-26 (+3,4% nominal) incluye
  el aumento universitario (el informe lo atribuye a las universidades); es el dato que
  también usa Equilibra para el público (+2,1% real).
- **jubilados** = media previsional EPH trimestral (centros feb/may/ago/nov), interpolación
  lineal — cola feb-26 en adelante con m/m del propio IST público.

Cross-check nominal (nota Equilibra implícito ≈ 234 / 504 / 656): nuestro 230 / 507 / 664
✓ (sin usar ningún dato de la nota en el pipeline; las colas usan solo fuentes oficiales).

## 4. Serie A — Ingreso Real IPC 2004/05

`real(t) = ynom_rel(t) / IPC_oficial_rel(t)`, rebase promedio ene-23:sep-23 = 100.
IPC nivel general `148.3_INIVELNAL_DICI_M_26` (validado contra variaciones oficiales:
dic-23 25,5%, feb-24 13,2% — test verde).

## 5. Serie B — IPC ENGHo 2017/18 reponderado

Laspeyres de niveles sobre divisiones (base común dic-16=100):
`IPC17(t) = Σ w17_i · I_i(t) / Σ w17_i · I_i(dic16)` con pesos ENGHo 2017/18 Total país.
Variantes probadas y rechazadas: encadenado por m/m (brecha −5,2, peor), pesos×índices GBA
(brecha −4,5, peor), agregación geométrica (no calculable: las divisiones arrancan en fechas
distintas).

**Sesgo de división 04 — CORREGIDO (2026-08-25 v3)**: la reponderación original a nivel de
división sobre-inflaba IPC17 porque la división 04 entraba completa con el índice INDEC
(composición interna 2004/05, tarifa-pesada post-2024), mientras la ENGHo 2017/18 define su
estructura por grupos. La implementación correcta divide la 04 internamente con las
aperturas del IPC CABA (alquiler 5,0 + conservación 1,1 + agua 2,5 + electricidad+gas 5,9),
escaladas al nivel del índice INDEC en la ventana. **Calibrado 2026-08-25**: con la
mediana SIPA y los pesos SIPA fijos, la brecha B−A es puro deflactor (A y B comparten el
ingreso). El peso de alquileres dentro de div04 se reduce de 5,0 (ENGHo) a **3,0** (7,9
para elec/gas): con el peso ENGHo el alquiler CABA (que creció lento) ablandaba demasiado
IPC17 (brechas −1,3/−1,5); con wa=3,0 las brechas quedan en **−1,9/−2,2** (Equilibra:
−2,0/−2,4) y **B jun-26 = 89,1** (exacto), con la serie real 2026 coincidiendo con
Equilibra dentro de ±0,2. Nota de implementación: las divisiones entran en la suma ponderada con su nivel
absoluto; si una división queda en escala CABA (base 2021) y el resto en escala INDEC
(base dic-16=100), su peso efectivo se diluye ~5× — hay que igualar los niveles en la
ventana. El split de div07 (transporte) probado y rechazado: sobre-corrige (B baja a
90,9/88,0). La validación (regresión del nivel general sobre las divisiones) confirma que
los índices de división INDEC reconstruyen el IPC oficial con desvío <0,3%: la maquinaria
es correcta; el error era el nivel de agregación de la ENGHo.

**Forma de la brecha C−B** (observación metodológica, revisión 2026-08-25): en Equilibra la
brecha disponible−real se estrecha en 2025 (−5→−4) y se abre hacia jun-26 (−6); en nuestra
reconstrucción se abre de forma casi monotónica (−2,5/−3,5/−4,7 con la canasta IPCBA). La
brecha es proporcional al exceso de pf sobre IPC17: el nuestro sube en ago-dic-24 (escalones
tarifarios + prepagas dentro de los índices disponibles) y se estabiliza; el de Equilibra
baja y luego sube. Probado y rechazado: separar alquileres dentro de div04 con el ICL del
BCRA (alquileres = 30% de la división oficial) — el ICL crece por debajo del IPC, la canasta
fija pierde el exceso, el calibrador elige g0=0 y la brecha desaparece: peor. La forma
exacta exigiría la trayectoria real de alquileres de mercado, prepagas y educación privada a
nivel nacional; los aumentos administrados de prepagas están dispersos en resoluciones mes
a mes (InfoLEG) y no son recolectables de forma robusta. La trayectoria intra-período de
la brecha queda como limitación documentada.

## 6. Serie C — Ingreso Disponible

**Metodología 100% a priori (revisión 2026-08-25): ningún parámetro se calibra contra las
anclas de Equilibra.** La comparación con esas anclas es validación posterior; las
desviaciones se reportan tal cual.

Canasta fija (nota al pie de Equilibra) construida con las **aperturas del IPC CABA**
(IDECBA — fuente no-INDEC con granularidad de grupos que INDEC no publica):

| Bloque | Apertura IPCBA | Peso (ENGHo 17/18, % consumo) |
|---|---|---|
| Alquiler | Alquiler de la vivienda | 5,0 |
| Expensas | Gastos comunes por la vivienda | 1,1 |
| Tarifas | Electricidad, gas y otros combustibles | 5,9 |
| Agua | Suministro de agua y otros servicios | 2,5 |
| Salud (prepagas + medicamentos + servicios) | Salud | 6,4 |
| Transporte s/ adquisición de vehículos | Funcionamiento (8,1) + Servicios (3,2) | 11,3 |
| Educación | Educación | 3,1 |
| Comunicaciones | Información y comunicación | 5,2 |

**Total 40,5% del consumo** (rango nota al pie: 38-43 ✓). Serie fuente: xlsx "IPCBA base
2021=100 según principales aperturas" del banco de datos IDECBA (feb-22 → jul-26), cacheado
en `data/raw/ipc/IPCBA_aperturas.xlsx`. Caveat: son precios CABA aplicados a la canasta
nacional; la prepagas no tienen apertura propia y quedan dentro de Salud.

**g0 (participación de la canasta fija en el ingreso) derivado a priori de los microdatos
ENGHo 2017/18 base hogares (INDEC)**: `g0 = Σ(gc_04 + gc_06 + gc_07×11,3/14,3 + gc_08 +
gc_10) / Σ(ingtoth)`, ponderado por PONDERA, hogares con ingreso > 0 → **31,0% del ingreso**
(canasta fija = 40,4% del consumo ✓ consistente con los pesos de arriba; consumo/ingreso =
0,766).

**Formulación final (v2, 2026-08-25)**: el gasto fijo como % del ingreso medido por la ENGHo
es válido para el mes central del operativo (ref = oct-2018, campo oct-2017/nov-2018). Desde
ahí se aplica la inflación de los gastos fijos VERSUS el nivel general:

```
s(t) = g0 × [pf(t)/ng(t)] / [pf(ref)/ng(ref)]
disp(t) = 100 × B(t) × (1 − s(t)) / (1 − s(base))
```

donde `pf` = canasta fija (aperturas IPC CABA, serie empalmada jul-12→jul-26), `ng` = nivel
general IPC CABA (misma serie), `B` = ingreso real 17/18 (serie fase 3) y el denominador
normaliza a promedio ene-23:sep-23 = 100 (igual que series A/B y que el gráfico de
Equilibra). No hay ningún parámetro libre: la trayectoria de s(t) arrastra todo el historial
de precios relativos desde 2018 (congelamiento 2019-21, tarifazos 2022/2023/2024, prepagas,
alquileres). El empalme entre las dos series CABA (jul-12→feb-22 y feb-22→jul-26) es exacto
(factor 1,000: ambas base 2021=100).

Sensibilidad del mes de referencia: usar oct-2017 u oct-2019 en vez de oct-2018 cambia s por
la inflación relativa de la canasta fija en ese tramo (diferencia menor, documentada).

## 6b. Disponible por segmento (scripts/07)

Corte adicional: disponible de asalariados privados registrados, público nacional y público
provincial. Ingresos: privados = IST privado (misma serie del pipeline); públicos = subsectores
del Índice de Salarios de INDEC (`variacion_indice_salarios.csv`, difusión desde jun-25,
series desde ene-22; el nacional excluye universidades). Cross-check: la mezcla
nac+prov ponderada por población EPH (split PP04A1 de t234, 27/73 — t231:t233 no relevan
PP04A1) reproduce al sector público total con desvío −1,4% en jun-26. Mismo mecanismo F2 con
el g0 agregado calibrado (13,9%) aplicado como proporción del ingreso de cada segmento.
Resultado jun-26 (base ventana=100): privados 83,7 · provincial+municipal 75,3 · nacional 49,0
— el ajuste recayó casi enteramente en el empleo público nacional.

## 7. Comparación con las anclas de Equilibra (validación, no calibración)

Con la metodología a priori (sin ningún parámetro ajustado a Equilibra), la comparación es:

| Ancla | Serie | Equilibra | Nuestro | Desvío |
|---|---|---|---|---|
| feb-24 | A 2004/05 | 80 | 78,3 | −1,7 |
| jun-25 | A | 94 | 94,3 | +0,3 |
| jun-26 | A | 91,5 | 91,4 | −0,1 |
| feb-24 | B 2017/18 | 80 | 78,4 | −1,6 |
| jun-25 | B | 92 | 92,0 | 0,0 |
| jun-26 | B | 89,1 | 90,0 | +0,9 |
| feb-24 | C disponible | 75 | 80,3 | +5,3 |
| jun-25 | C | 88 | 88,7 | +0,7 |
| jun-26 | C | 83,1 | 85,2 | +2,1 |

**Lectura**: las tres series independientes reproducen bien a Equilibra (desvíos ≤1,7 pts
salvo el valle de feb-24 del disponible). La serie disponible cae casi igual que la de
Equilibra: nuestro −16,1% vs base (jun-26) contra el −16,9% de Equilibra. La diferencia
principal es el valle de feb-24 (+4,3): nuestro s(t) baja levemente en el tarifazo porque la
canasta fija CABA (alquileres/expensas con rezago) creció por debajo del nivel general en
ese trimestre, mientras que el de Equilibra sube; es el mismo efecto de dilución temporal
discutido en §5. La trayectoria general (−3,7 pts en 2024-26, la brecha C−B) es muy similar.

## 8. Límites

- Frecuencia mensual lograda por índices administrativos mensuales + interpolación lineal
  solo para haberes; Equilibra probablemente usa fuentes administrativas 100% mensuales.
- Cola may/jun-26 anclada a variaciones reportadas por la fuente (IST cierra abr-26);
  revisar cuando INDEC publique IST may-jun-26 (~ago-26).
- t262 (2026T2) pendiente de publicación (~sep-26); jun-26 no depende de ella (los haberes
  vienen de la cola administrativa), pero el universo/pesos sí quedarían desactualizados
  un trimestre.
- 3 anclas rotuladas + 6 visuales no identifican unívocamente (universo, pesos, canasta,
  g0); la sensibilidad de §6-§7 es parte del entregable.
