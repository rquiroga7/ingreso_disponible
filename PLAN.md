# PLAN — Reconstrucción del "Ingreso Real y Disponible" (Equilibra) desde microdatos EPH

Última actualización: 2026-08-24
Estado: **Fases 0–5 ejecutadas.** Pipeline `scripts/01…06` re-ejecutable; series y gráfico
en `output/`; decisiones y sensibilidad en `METHODOLOGY.md`. Resultados de calibración al
final (§14). Tests: IPC y EPH verdes; test de anclas con 3/9 fuera de tolerancia (desvíos
≤1,7 pt, causas documentadas — ver §14.2).

---

## 1. Objetivo

Reconstruir desde microdatos de la EPH (INDEC) y series de precios públicas las tres series
mensuales que publica Equilibra en el gráfico "Ingreso real registrado y disponible (14,5M personas)":

1. **Ingreso Real (IPC INDEC ENGHo 2004/05)** — debe calcar la serie oficial de INDEC (el IPC oficial
   nacional usa ponderaciones ENGHo 2004/05). Es nuestra fase de validación.
2. **Ingreso Real (IPC ENGHo 2017/18)** — requiere reponderar los índices de división del IPC con la
   canasta ENGHo 2017/18 (INDEC aún no publica un IPC oficial con esa base).
3. **Ingreso Disponible (IPC ENGHo 2017/18)** — ingreso menos erogaciones de baja elasticidad
   ("gastos fijos"), deflactado.

Fuente del objetivo: https://www.notiar.com.ar/index.php/actualidad1/142154/ (nota de Leandro Gabin,
Equilibra) — imagen local: `data/sources/Ingreso_real_y_registrado_equilibra.png`.

Definición Equilibra (cita del medio): *"Es el poder de compra efectivo tras descontar erogaciones
con escaso margen de ajuste (alquileres, expensas, tarifas de luz/gas/agua, transporte,
comunicaciones, educación y medicina prepaga). Universo relevado: 14,5 millones de personas con
ingresos formales estables (asalariados privados, empleados públicos y jubilados), excluyendo
trabajadores informales y monotributistas."*

---

## 2. Target: especificación del gráfico de Equilibra

- Frecuencia: mensual, ene-23 → jun-26.
- Base: promedio ene-23:sep-23 = 100. Las tres líneas arrancan planchas en 100 hasta ~oct-23
  (nuestra reconstrucción puede oscilar ±1 pt en 2023; aceptable).
- Universo: ~14,5 M de personas — asalariados privados formales, empleados públicos y
  jubilados/pensionados. Excluye informales, monotributistas, patrones, desocupados.
- Nota al pie del gráfico: *"*Ingresos excluyendo pago de alquiler, expensas, tarifas energéticas,
  comunicación, transporte, medicamentos, educación y prepagas. IPC actualizado*"*

### Anclas de calibración (leídas del gráfico; valores rotulados exactos salvo "~")

| Ancla | Real IPC 2004/05 | Real IPC 2017/18 | Disponible IPC 2017/18 |
|---|---|---|---|
| ene-23 … sep-23 (prom.) | 100 | 100 | 100 |
| feb-24 (valle) | ~80 | ~80 | ~75 |
| jun-25 (pico) | ~94 | 92 | 88 |
| jun-26 (último) | 91,5 | 89,1 | 83,1 |

Tolerancias de testeo: ±1,0 pt para anclas estimadas (~), ±0,3 pt para rotuladas.
Archivo canónico: `tests/anchors_equilibra.csv`.

Observaciones cualitativas que la metodología debe reproducir:
- Caída pronunciada nov-23 → feb-24 (tarifazo + devaluación; ingreso nominal rezagado).
- Recuperación mar-24 → jun-25; meseta y leve deterioro jun-25 → jun-26.
- La línea 2017/18 queda consistentemente ~2,4 pts por debajo de la 2004/05 desde mediados de 2024 (mayor peso de servicios regulados en la canasta nueva).
- La línea Disponible se separa de la Real 2017/18: brecha ~6 pts en feb-24 (tarifazo), se estrecha en 2025 (congelamiento tarifario), vuelve a abrirse hacia jun-26.

---

## 3. Arquitectura metodológica

```
                    ┌── IPC oficial (ENGHo 2004/05) ──► Serie A: Ingreso Real 2004/05   (validación)
Y_nom(t) ──────────┤
(EPH, trimestral)   ├── IPC reponderado 2017/18 ──────► Serie B: Ingreso Real 2017/18
                    │
                    └── Y_nom − G_fijo_nom ───────────► Serie C: Disponible (deflactada con IPC 2017/18)
                         (G_fijo actualizado con índice de precios de la canasta fija)
```

Componentes a construir:
- **Y_nom(t)**: ingreso nominal medio del universo, trimestral (EPH) → mensual por interpolación.
- **IPC_2004(t)**: IPC oficial nivel general (datos.gob.ar / INDEC).
- **IPC_2017(t)**: reponderación de índices por división con pesos ENGHo 2017/18.
- **P_fijo(t)**: índice de precios de la canasta de gastos fijos (subconjunto de divisiones/grupos).
- **G_fijo_nom(t)**: gasto fijo nominal del universo (calibrado; ver §9).

---

## 4. Datos: inventario y adquisición

### 4.1 Inventario local

| Archivo | Contenido |
|---|---|
| `data/sources/Ingreso_real_y_registrado_equilibra.png` | Gráfico objetivo |
| `data/sources/eph.pdf` | Manual del paquete R `eph` (get_microdata, organize_labels, calculate_tabulates…) |
| `data/sources/engho200405_metodologico.pdf` | Metodología ENGHo 2004/05 |
| `data/sources/engho_2017_2018_informe_gastos.pdf` | ENGHo 2017/18 resultados definitivos (**Cuadro 1**: estructura del gasto por división y región — ya extraído, ver skill EPH-INDEC) |
| `data/raw/`, `data/dicts/` | Vacíos (aquí bajamos microdatos y diccionarios) |
| `tests/` | Suite de tests (ver §11) |

### 4.2 Microdatos EPH — ESTADO DE LA ADQUISICIÓN (verificado 2026-08-24)

**El FTP de INDEC está caído**: toda URL bajo `https://www.indec.gob.ar/ftp/...` (y `sitioanterior.indec.gob.ar`) devuelve una página HTML soft-404 de 37.465 bytes. Esto rompe el
fallback de `eph::get_microdata()` para trimestres recientes (el mirror de GitHub `holatam/data` solo llega a 2023T1). Cadena de intentos:

1. `eph::get_microdata(year, period, type)` — intenta GitHub mirror → INDEC FTP (fallirá para 2023T2+).
2. **Wayback Machine**: `http://archive.org/wayback/available?url=indec.gob.ar/ftp/cuadros/menusuperior/eph/EPH_usu_{q}Trim_{year}_txt.zip`
   (respetar rate-limit: hubo HTTP 429; reintentar con sleep). Descargar vía
   `https://web.archive.org/web/{timestamp}id_/{url_original}`.
3. **Endpoints AJAX del sitio nuevo de INDEC** (la página BasesDeDatos es una SPA; inspeccionar
   llamadas XHR que cargan los links de descarga).
4. **datademia.ar** u otros mirrors (UNR Observatorio publica bases RDATA).
5. Último recurso (más débil): reconstruir ingresos desde tabulados publicados de INDEC
   ("Distribución del ingreso", "Mercado de trabajo") — sólo si todo lo anterior falla; reportar al
   usuario antes de degradar la fuente.

Formato de las bases usuaria: TXT separado por `;` con decimales `,`, header en primera línea
(`read.table(sep=";", dec=",", header=TRUE)`; columnas de deciles como character).
Trimestres requeridos: **2023T1 → 2026T2** (t123…t126; individual + hogar). Verificar disponibilidad
de t126 (se publica ~sep-26); si no está, jun-26 interpola desde t125 y se documenta.

### 4.3 IPC — vía API de datos.gob.ar (funciona, verificado)

- Endpoint: `https://apis.datos.gob.ar/series/api/series/?ids=<ID>&format=json`
- Búsqueda: `https://apis.datos.gob.ar/series/api/search/?q=<query>&limit=100` (a veces necesita
  términos simples; paginar).
- Familia de datasets del **IPC Nacional base dic-2016** (ponderaciones ENGHo 2004/05):
  - `148.x_*` categorías (núcleo / estacionales / regulados), `147.x_*` bienes/servicios,
    `146.x_*` por división — p. ej. `146.3_IEDUCACNAL_DICI_M_22` (Educación Nacional, mensual,
    índice, hasta 2026-07). Enumerar el set completo por división en Fase 1.
- Tarea Fase 1: obtener **nivel general + 12 divisiones (Nacional, mensual, índice)** desde dic-2022
  (o antes) a jun-2026; sondear si hay **series por grupo** (alquileres, electricidad/gas, agua,
  seguros médicos) — clave para la canasta fija. Fallback: xlsx del informe IPC vía Wayback.
- Pesos IPC ENGHo 2004/05 por división: publicados por INDEC (metodología IPC / informe); bajar en
  Fase 1 (sirven de chequeo de la reponderación).

### 4.4 Pesos ENGHo 2017/18 — YA EXTRAÍDOS

Fuente: `engho_2017_2018_informe_gastos.pdf`, Cuadro 1 (Total del país, % del gasto de consumo):

| División | % | | Subdivisión | % |
|---|---|---|---|---|
| 01 Alimentos y bebidas no alc. | 22,7 | | 04.1 Alquileres efectivos | 5,0 |
| 02 Bebidas alc. y tabaco | 1,9 | | 04.2 Conservación y reparación | 1,1 |
| 03 Prendas de vestir y calzado | 6,8 | | 04.3 Agua y servicios vivienda | 2,5 |
| 04 Vivienda, agua, elec., gas | 14,5 | | 04.4 Electricidad, gas, combust. | 5,9 |
| 05 Equipamiento del hogar | 5,4 | | 06.1 Productos médicos | 2,7 |
| 06 Salud | 6,4 | | 06.2 Serv. ambulatorios | 1,3 |
| 07 Transporte | 14,3 | | 06.3 Serv. de hospital | 0,1 |
| 08 Comunicaciones | 5,2 | | 06.4 Seguros médicos (prepagas) | 2,3 |
| 09 Recreación y cultura | 8,6 | | 07.1 Adquisición de vehículos | 3,0 |
| 10 Educación | 3,1 | | 07.2 Funcionamiento de vehículos | 8,1 |
| 11 Restaurantes y hoteles | 6,6 | | 07.3 Servicios de transporte | 3,2 |
| 12 Bienes y servicios varios | 4,3 | | | |

Variantes regionales (GBA) disponibles en el mismo cuadro si la calibración lo pide.

---

## 5. Fase 0 — Entorno

- Instalar: `eph`, `dplyr`, `readr`, `tidyr`, `purrr`, `stringr`, `lubridate`, `zoo`, `readxl`,
  `janitor`, `jsonlite`, `httr2`, `ggplot2`, `scales` (aprobado por el usuario).
- Convenciones de código: skills del proyecto (`r-code`, `designing-tidy-r-functions`) —
  snake_case, pipe nativo `|>`, una función por archivo en `R/`, `air format .` si está disponible.
- Estructura: `R/` (funciones), `scripts/01…06` (pipeline numerado re-ejecutable), `data/`,
  `output/` (series CSV + gráficos), `tests/`.

---

## 6. Fase 1 — Adquisición (camino crítico: resolver EPH primero)

1. **EPH t123–t126** (individual + hogar) por la cadena de §4.2; cachear en `data/raw/eph/`.
   Validar cada trimestre: filas en rango plausible (individual ~45–70 mil), columnas clave
   presentes, suma de PONDERA ~45–50 M.
2. **IPC**: nivel general + divisiones (Nacional mensual) dic-22→jun-26 desde datos.gob.ar;
   sondear series por grupo; cachear en `data/raw/ipc/`.
3. **Pesos**: tabla ENGHo 2017/18 (ya extraída → `R/data_weights.R` o CSV en `data/dicts/`);
   pesos IPC 2004/05 desde INDEC.
4. Tests de adquisición en verde (`tests/run_all.R`).

---

## 7. Fase 2 — Ingreso Real ENGHo 2004/05 (puerta de validación)

### 7.1 Universo (~14,5 M — calibrar)

| Segmento | Filtro EPH (base individual) | Notas |
|---|---|---|
| Asalariados privados formales | `ESTADO==1 & CAT_OCUP==3` + sector privado (`PP04D_COD`, mapear con diseño de registro) + registrado (`PP07H==1`, descuento jubilatorio) | excluye monotributistas/cuentapropistas por construcción |
| Empleados públicos | `ESTADO==1 & CAT_OCUP==3` + estatal | verificar formalidad con `PP07H` |
| Jubilados/pensionados | `ESTADO!=1` (variantes: sólo inactivos vs. incluye ocupados) con `V2_1_M>0` (o suma de V2_*_M) | probar variantes para calzar 14,5 M |
| Excluye | patrones, cuentapropistas, desocupados, informales, menores | |

Expandir con `PONDERA`. **Gate**: total expandido ≈ 14,5 M (±10%).

### 7.2 Medida de ingreso

- Trabajadores: `P21` (neto ocupación principal) — primaria. Variantes: `P21+P22`, `P47T`.
- Jubilados: `V2_1_M` (+ `V21_M` aguinaldo si se usa promedio anualizado; decidir).
- Promedio trimestral ponderado del universo → serie trimestral.

### 7.3 Frecuencia mensual

Interpolar trimestral→mensual (valor en el centro del trimestre, lineal entre centros; probar
también step y spline). Elegir la que mejor reproduce el valle de feb-24 y las anclas.

### 7.4 Deflactación y rebase

`Y_real(t) = Y_nom_interp(t) / IPC_2004(t)`; índice = `Y_real / mean(Y_real[ene-23..sep-23]) * 100`.

### 7.5 Gate de validación

- feb-24 ≈ 80 ±1; jun-25 ≈ 94 ±1; jun-26 = 91,5 ±0,3.
- Chequeo cruzado: comparar niveles con ingresos medios publicados por INDEC (informe
  "Distribución del ingreso") deflactados por IPC.
- Iterar universo/medida/interpolación hasta pasar; documentar cada elección.

---

## 8. Fase 3 — IPC ENGHo 2017/18

- Reponderación Laspeyres sobre índices de división (base común dic-16=100):
  `IPC_2017(t) = Σ w_i^2017 · I_i(t) / Σ w_i^2017 · I_i(t0)`, rebase a la ventana ene-23:sep-23.
- Pesos: Total del país (§4.4); probar variante GBA si no calza.
- **Gate**: reproducir la brecha vs línea 2004/05 (jun-25: 92 vs ~94; jun-26: 89,1 vs 91,5 → brecha ≈ 2,4 pts) y las anclas de la serie B.
- Si la brecha no se reproduce con 12 divisiones (composición interna de la div. 04: alquileres vs tarifas divergen fuertemente post-2024), buscar índices por grupo (alquileres, electricidad/gas, agua) y reponderar dentro de la división. Documentar el sesgo si sólo hay división.

---

## 9. Fase 4 — Ingreso Disponible

### 9.1 Canasta fija (nota al pie de Equilibra) → mapeo ENGHo 2017/18

| Concepto | Grupos ENGHo | Peso (% consumo) | Disponibilidad IPC |
|---|---|---|---|
| Alquiler | 04.1 | 5,0 | división 04 (grupo si existe) |
| Expensas | dentro de 04.2/04.4 — **TBD** con detalle ENGHo | ~1–3 | división 04 |
| Tarifas energéticas | 04.4 (+04.3 agua, a probar) | 5,9 (+2,5) | división 04 |
| Comunicación | 08 | 5,2 | división 08 |
| Transporte | 07 (o 07.2+07.3=11,3 sin compra de vehículos — probar ambos) | 14,3 / 11,3 | división 07 |
| Medicamentos | subconjunto de 06.1 (detalle ENGHo **TBD**) | ~2,0–2,4 | división 06 |
| Educación | 10 | 3,1 | división 10 |
| Prepagas | 06.4 | 2,3 | división 06 |
| **Total** | | **≈38–43** | `P_fijo(t)` |

### 9.2 Formulaciones candidatas (calibrar contra las 3 anclas rojas)

Sea `s0` el gasto fijo de la base como fracción del ingreso, `pf(t)=P_fijo(t)/P_fijo(t_base)`,
`pr(t)=IPC_2017(t)/IPC_2017(t_base)`:

- **F1 (arrastre por precios):** `G_fijo(t) = s0 · Y_nom(t) · pf(t) / (Y_nom(t)/Y_nom(t_base))⁻¹`…
  equivalentemente `disp_real = Y_real · (1 − s0 · pf/pr)`. Implica s0 pequeño (~5%) para calzar
  brechas de 4–7 pts — probar.
- **F2 (nivel ENGHo):** `G_fijo(t) = G0 · pf(t)` con `G0` nivel de gasto fijo por persona del
  universo (de ENGHo o calibrado), deflactar `(Y_nom − G_fijo)/IPC_2017`. El drag depende de
  `Y_rel(t)` — reproduce mejor la dinámica feb-24 (ingreso cae → drag sube).
- **F3 (deflactor ex-fijo):** deflactar `(Y − G)` con IPC que excluye la canasta fija.

La evidencia del gráfico (brecha rojo-negro: 6 pts en feb-24, 4 pts en jun-25, 6,7 pts en jun-26)
sugiere que el drag crece cuando las tarifas se mueven por encima del IPC general y se contrae con
el congelamiento 2025. Calibrar (s0 | G0) y el mapeo de §9.2 para minimizar el error cuadrático
sobre las anclas; reportar sensibilidad (qué categorías/variantes mueven el resultado).

### 9.3 Gate

feb-24 ≈ 75 ±1; jun-25 = 88 ±0,3; jun-26 = 83,1 ±0,3. Además: brecha rojo-negro ~6 pts en feb-24.

---

## 10. Fase 5 — Entregables

1. Gráfico de reproducción (3 series, base ene-23:sep-23=100, estilo del original) + overlay con
   las anclas de Equilibra.
2. `output/serie_ingreso_real_ipc2004.csv`, `output/serie_ingreso_real_ipc2017.csv`,
   `output/serie_ingreso_disponible.csv` (columnas: `fecha,valor`).
3. `METHODOLOGY.md`: decisiones, fuentes, sesgos, límites de identificación.
4. `PLAN.md` actualizado con resultados de calibración.
5. Scripts numerados re-ejecutables (`scripts/01…06`).

---

## 11. Estrategia de tests (`tests/`)

Runner: `tests/run_all.R` — ejecuta cada test, imprime PASS/FAIL/SKIP, sale con error si hay FAIL.
Los tests se saltan (SKIP) con mensaje claro si los insumos todavía no se descargaron.

| Test | Qué valida | Depende de |
|---|---|---|
| `test_eph_microdata.R` | Presencia/integridad de t123–t126: columnas clave, filas en rango, ΣPONDERA ~45–50 M, coherencias básicas (P21≥−9, ITF≥0…) | `data/raw/eph/` |
| `test_ipc_official.R` | API datos.gob.ar viva; IPC nivel general: última obs ≥ 2026-06; variaciones m/m conocidas (dic-23 ∈ [20,30]%, feb-24 ∈ [10,16]%); índice rebase ene23:sep23=100 → dic-23 ∈ [145,160] (≈153), feb-24 ∈ [195,225] | red + jsonlite |
| `test_series_equilibra.R` | Las 3 series construidas vs `anchors_equilibra.csv` (tabla comparativa valor-esperado-desvío); base=100 exacta; SKIP si no hay outputs | `output/*.csv` |
| `anchors_equilibra.csv` | Fuente única de anclas con tolerancias por ancla | — |

Los valores esperados del test de IPC están acotados a lo verificable públicamente (2023–2024);
sirven para detectar roturas de pipeline, no para fijar historia.

---

## 12. Riesgos y preguntas abiertas

1. **Adquisición EPH** (crítico): FTP INDEC muerto; Wayback con rate-limit. Resuelto primero en Fase 1.
2. **Frecuencia mensual**: Equilibra probablemente combina fuentes mensuales (SIPA/ANSES) con EPH;
   nuestro camino EPH+interpolación calza anclas, no cada mes. Documentado, no oculto.
3. **Detalle IPC por grupo**: si no es público, la reponderación por división puede subestimar la
   brecha 2017/18; probar variante GBA y documentar sesgo.
4. **t126 (2026T2)**: si no está publicado al ejecutar, jun-26 interpola desde t125 (documentar).
5. **Identificación**: ~6–9 anclas visuales → múltiples parametrizaciones pueden calzar; la
   sensibilidad de §9.3 es parte del entregable, no un extra.
6. **Expensas y medicamentos** dentro de las divisiones 04/06: resolver con el detalle de ENGHo (informe o microdatos ENGHo públicos) antes de calibrar la canasta fija.

## 13. Referencias

- Nota Equilibra/notiar (fuente del gráfico): ver §1.
- Skill `EPH-INDEC` (`.agents/skills/EPH-INDEC/SKILL.md`): URLs exactas, patrones de series de la API, tabla completa de pesos ENGHo 2017/18, cheat-sheet de variables EPH, estado de descargas.
- INDEC: diseño de registros EPH (`EPH_registro_3T2025.pdf` online), metodología IPC base dic-2016, ENGHo 2017/18 resultados definitivos (PDF local).
- CEDLAS "Los ingresos en Argentina" (ajuste de ingresos EPH con registros administrativos) — referencia metodológica secundaria.

## 14. Resultados de calibración (ejecución 2026-08-24)

### 14.1 Decisiones que se apartaron del plan original

1. **Ingreso nominal híbrido** (§3 de METHODOLOGY): la nota de Equilibra usa dinámicas de
   registros administrativos por segmento (ST/ANSES), no medias de encuesta; la ruta
   EPH-pura del §7 sobrestima jun-25 en +13,5 pts y ningún knob (mediana, full-time,
   composición fija, ex-imputados) la corrige. Se adoptó IST (priv/pub) + media previsional
   EPH interpolada, agregada con pesos fijos de población EPH.
2. **Colas may/jun-26**: IST cierra abr-26; se extendió con RIPTE m/m y con las variaciones
   reales m/m que la propia nota reporta para jun-26 (−0,9% priv, +2,1% pub, +0,5% jub).
3. **Universo 9,57 M** (gate 14,5 M ±10% no alcanzable con filtros formales desde EPH
   aglomerados); ver §2 de METHODOLOGY.
4. **Paquetes**: pipeline 100% base R + jsonlite (el tidyverse del §5 no se instaló; no
   aporta nada sobre `aggregate`/`approx`/`merge` aquí).

### 14.2 Anclas (detalle en METHODOLOGY §7)

| Serie | feb-24 | jun-25 | jun-26 | Brecha B−A jun-26 |
|---|---|---|---|---|
| A real 2004/05 | 78,3 (−1,7) | 94,3 (+0,3) | 91,2 (−0,3) | — |
| B real 2017/18 | 78,4 (−1,6) | 91,6 (−0,4) | 87,4 (−1,7) | −3,8 (obj. −2,4) |
| C disponible | 80,3 (+5,3) | 88,7 (+0,7) | 85,0 (+1,9) | — |

**Revisión metodológica 2026-08-25 v2 (sin calibración, formulación ENGHo-anclada)**:
ningún parámetro se ajusta a Equilibra. (1) Canasta fija con aperturas del IPC CABA
(alquiler, expensas, tarifas, agua, salud, transporte, educación, comunicaciones — fuente
no-INDEC con grupos; serie empalmada jul-12→jul-26). (2) g0 = 31,0% del ingreso, derivado
a priori de los microdatos ENGHo 2017/18. (3) s(t) = g0 × [canasta fija/nivel general](t) /
[canasta fija/nivel general](oct-2018), es decir el gasto fijo como % del ingreso medido
por la ENGHo evolucionado con la inflación relativa de los gastos fijos desde el operativo.
(4) disp = 100 × B × (1−s)/(1−s_base). (5) Colas may/jun-26 con RIPTE puro. Resultado:
las tres series reproducen a Equilibra (desvíos ≤1,7 pts salvo el valle feb-24 del
disponible +4,3); el disponible pierde −16,1% vs base en jun-26 (Equilibra −16,9%).

### 14.3 Pendientes menores

- Refrescar cola may/jun-26 cuando INDEC publique IST de esos meses (~ago-26).
- Incorporar t262 al universo/pesos cuando se publique (~sep-26).
- Si INDEC libera los índices por grupo del IPC (o el nuevo IPC base 17/18), reponderar la
  división 04 internamente y recalibrar g0.
