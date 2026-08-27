---
name: EPH-INDEC
description: >
  Knowledge base for reconstructing Argentina income/price statistics from INDEC
  public data: EPH household-survey microdata (download routes, format, variables),
  IPC national CPI (official ENGHo 2004/05 base and re-weighted ENGHo 2017/18),
  ENGHo household spending survey weights, the datos.gob.ar series API, and the
  Equilibra "ingreso real y disponible" reproduction project. Use when working on
  this repo's pipeline (scripts/, R/, tests/), downloading INDEC data, or touching
  anything related to EPH, IPC, ENGHo, or the Equilibra target series.
---

# EPH-INDEC data knowledge (proyecto ingreso_disponible)

## 0. Quick facts (verified 2026-08-24)

- **INDEC downloads WORK — but the URLs changed and the site is an MVC SPA.** The old
  `EPH_usu_{q}Trim_{year}_txt.zip` paths (used by `eph::get_microdata()` and old docs) return a
  soft-404 HTML page (exactly 37,465 bytes, `text/html`). The files live under the same `/ftp/...`
  tree with NEW names (§1). Wayback Machine does NOT have these zips (checked 2026-08-24) — go
  straight to INDEC.
- **SPA partial-view trick**: browser URLs like `/indec/web/Institucional-Indec-BasesDeDatos-1`
  return only the JS shell. The real content is at the slash-form route:
  `https://www.indec.gob.ar/Institucional/Indec/BasesDeDatos/1` (Controller/Action/id, no
  `X-Requested-With` header needed). This page lists every EPH usuaria zip 2016→present.
- **curl gotcha**: `-O` fails on this server (`curl: (23) Failed writing...`); always use explicit
  `-o <filename>`. Zips are ~3–5 MB; 1 s between downloads is fine. `file -b` the result to confirm
  "Zip archive data" (HTML soft-404s also return HTTP 200 — never trust status alone).
- **datos.gob.ar series API works** from this network (no auth, JSON).
- EPH usuaria bases: semicolon-separated TXT, decimal comma, header row 1, fields quoted with `"`.
  `read.table(f, sep=";", dec=",", header=TRUE, fill=TRUE)` (default quote handling; force decile
  columns to character). ΣPONDERA per quarter ≈ 29–30 M.
- R 4.6.1 installed (62 pkgs incl. jsonlite/httr2/rlang/tibble as of 2026-08-24); Python 3.9 +
  pandas available. `pdftotext` available.

## 1. EPH microdata (Encuesta Permanente de Hogares, continua)

### What we need
Quarters **2023T1 → 2026T1** (t231…t261 in our canonical naming), files `individual` + `hogar`
(~44–60k / ~15–17k rows each). Bases "usuaria" = public user bases (aglomerados urbanos, PONDERA
expansion factor). 2026T2 (INDEC inner name T262) not yet published as of 2026-08-24 (due ~sep-26).

### Download route (WORKING, verified 2026-08-24)
1. List page (SPA partial view):
   `https://www.indec.gob.ar/Institucional/Indec/BasesDeDatos/1` — grep `href` for
   `/ftp/cuadros/menusuperior/eph/EPH_usu_.*_txt\.zip`.
2. Zip URL patterns (note underscores; irregular names for 2016–2017):
   - 2018+: `EPH_usu_{q}_Trim_{year}_txt.zip` (e.g. `EPH_usu_1_Trim_2023_txt.zip`)
   - 2017: `EPH_usu_1_Trim_2017_txt.zip`, `EPH_usu_2_Trim_2017_txt.zip`, …
   - 2016: `EPH_usu_2doTrim_2016_txt.zip`, `EPH_usu_3erTrim_2016_txt.zip`, `EPH_usu_4toTrim_2016_txt.zip`
3. Download with `curl -sS -o <name> <url>` (NOT `-O`). Verify with `file` (must be Zip archive).
4. Registro dictionaries (variable layouts per quarter):
   `https://www.indec.gob.ar/ftp/cuadros/menusuperior/eph/EPH_registro_{q}T{yy}.pdf`
   (e.g. `EPH_registro_1T2026.pdf`). Latest copy: `data/dicts/EPH_registro_1T2026.pdf`.
5. Inner zip layout: `EPH_usu_{q}{er|do|er|to}Trim_{year}_txt/usu_{individual|hogar}_T{q}{yy}.txt`
   — **INDEC inner naming is T{quarter}{year}**: `T123`=2023T1, `T126`=2026T1, `T225`=2025T2.
   Our canonical layout renames to `data/raw/eph/t{yy}{q}/usu_{individual|hogar}_t{yy}{q}.txt`.

### Status (2026-08-24)
Downloaded + extracted + test-validated: **t231–t261** (all 11 quarters) in `data/raw/eph/`,
zips cached in `data/raw/eph/zips/`. Pending: t262 (not yet published).

### Fallbacks (only if INDEC breaks again)
Wayback (`archive.org/wayback/available?url=...` — zips NOT archived as of 2026-08-24, but PDFs
may be) · datademia.ar · UNR Observatorio (RDATA) · holatam/data GitHub mirror (≤2023T1, RDS) ·
last resort: published tabulados (needs user sign-off).

### Key variables (base individual, usuaria)
| Variable | Meaning / use |
|---|---|
| `CODUSU`, `NRO_HOGAR`, `COMPONENTE` | merge keys individual↔hogar |
| `PONDERA` | expansion weight (use this; PONDIIO/PONDII legacy) |
| `ESTADO` | 1 ocupado, 2 desocupado, 3 inactivo, 4 menor de 10 |
| `CAT_OCUP` | 1 patrón, 2 cuentapropista, 3 obrero/empleado, 4 fam. sin remuneración |
| `PP04D_COD` | tipo de institución del empleador (map estatal/privado via diseño de registro — fetch `EPH_registro_{q}T{yy}.pdf` from Wayback if needed) |
| `PP07H` | ¿le descuentan jubilación? 1=Sí → asalariado registrado/formal |
| `P21` | ingreso neto ocupación principal (mes ref.) |
| `P22` | ingreso neto otras ocupaciones |
| `P47T` | ingreso total individual (laboral + no laboral) |
| `V2_M` (2023T1–T3) / `V2_01_M`,`V2_02_M`,`V2_03_M` (2023T4+) | monto jubilaciones/pensiones (por aportes / ama de casa / otras). Aguinaldos: `V21_M` / `V21_0x_M` |
| `CH06` edad, `CH04` sexo, `CH08` cobertura médica (1 obra social, 2 mutual/prepaga, 12 ambas) | demographics / prepagas |
| `DECIFR`, `IPCF`, `ITF` | decil, ingreso per cápita familiar, ingreso total familiar |

Key variables (base hogar): `II7` tenencia (3=inquilino), `II8` monto alquiler, `II9` monto expensas,
`IV12_1/2` gas red/garrafa, `IV13*` electricidad, `IX_TOT` miembros, `ITF`, `IPCF`.

Missing-income codes: `-9` Ns/Nr, `-8` no tuvo ingreso, `-7` no correspondía (post-2009 bases are
hot-deck imputed; treat negatives as 0 for means, document).

### Plausibility checks (used by tests)
- individual rows ~45k–70k per quarter; hogar ~20k–30k.
- Σ PONDERA (individual) ≈ 45–50 M (urban population in aglomerados).
- `ITF >= 0` for ~99% of hogares (−9 = Ns/Nr minority).

## 2. IPC (Índice de Precios al Consumidor Nacional, base dic-2016)

- Official IPC = weights from **ENGHo 2004/05** (this is why "IPC INDEC" ≡ "IPC ENGHo 2004/05" in the
  Equilibra chart). INDEC has NOT published an official IPC with ENGHo 2017/18 weights → we re-weight.
- datos.gob.ar dataset families (series id prefix): `146.x_*` division indices, `147.x_*`
  bienes/servicios, `148.x_*` categorías (núcleo/estacionales/regulados). Suffix pattern:
  `{dataset}_{CODIGO}_DICI_{M|T}_{nn}` where NAL=Nacional, GBA, UYO=Cuyo, NIA=Patagonia;
  `_M_` monthly, `_T_` quarterly. Example: `146.3_IEDUCACNAL_DICI_M_22` = Educación Nacional
  mensual (índice), data through 2026-07.
- Search API: `https://apis.datos.gob.ar/series/api/search/?q=IPC&limit=200` (simple terms work
  best; results are paginated/incomplete — enumerate divisions at execution).
- Fetch: `https://apis.datos.gob.ar/series/api/series/?ids=<id1>,<id2>&format=json&limit=1000`
  → JSON `data: [[iso_date, value], ...]`. **Default limit is 100 rows and caps silently** — always
  pass `limit=1000`. One invalid id in the list errors the whole request; verify ids individually.
- Confirmed series IDs (Nacional, monthly, índice, data through 2026-07):
  - Nivel general: `148.3_INIVELNAL_DICI_M_26` (also `145.3_INGNACNAL_DICI_M_15`, duplicate dataset)
  - Núcleo: `148.3_INUCLEONAL_DICI_M_19` · Regulados: `148.3_IREGULANAL_DICI_M_22`
  - Educación: `146.3_IEDUCACNAL_DICI_M_22` · Salud: `146.3_ISALUD*` · Transporte: `146.1_IPC_TRANSP*`
    (division codes 145.x/146.x/147.x/148.x overlap datasets; enumerate at execution)
- Reference values (IPC nivel general rebased to avg ene-23:sep-23 = 100, as of 2026-08-24):
  dic-23 = 214.1 · feb-24 = 292.4 · jun-25 = 536.5 · jun-26 = 716.5.
  Official m/m: dic-23 25.5%, feb-24 13.2% (used by `tests/test_ipc_official.R`).
- TODO (Fase 1): full enumeration of 12 division series (Nacional, monthly, index); probe for
  group-level series (alquileres, electricidad/gas, agua, seguros médicos) — critical for the fixed
  basket; fallback: INDEC IPC informe xlsx via Wayback.
- Known official m/m inflation anchors (for tests): dic-23 ≈ 25.5%, feb-24 ≈ 13.2%, abr-24 ≈ 8.8%.
  Index rebased to avg(ene-23:sep-23)=100: dic-23 ≈ 153, feb-24 ≈ 209.

## 3. ENGHo weights

### ENGHo 2017/18 (Cuadro 1, "Resultados definitivos", Total del país, % of consumption)
Divisiones: Alimentos y bebidas no alc. 22.7 · Bebidas alc. y tabaco 1.9 · Prendas de vestir y
calzado 6.8 · Vivienda, agua, elec., gas 14.5 · Equipamiento hogar 5.4 · Salud 6.4 · Transporte 14.3 ·
Comunicaciones 5.2 · Recreación y cultura 8.6 · Educación 3.1 · Restaurantes y hoteles 6.6 ·
Bienes y servicios varios 4.3.

Grupos clave: alquileres efectivos 5.0 · conservación y reparación vivienda 1.1 · agua 2.5 ·
electricidad/gas/combustibles 5.9 · productos médicos 2.7 (medicamentos ⊂ esto) · seguros médicos
(prepagas) 2.3 · transporte: adquisición 3.0 / funcionamiento 8.1 / servicios 3.2 · servicios
telefónicos 4.6 (+equipos 0.6) · educación 3.1. Regional breakdown (GBA, Pampeana, NOA, NEA, Cuyo,
Patagonia) in the same Cuadro 1 of `data/sources/engho_2017_2018_informe_gastos.pdf`.

### ENGHo 2004/05
Official IPC weights source (metodología IPC INDEC). PDF metodológico local:
`data/sources/engho200405_metodologico.pdf` (survey design; division weights are in the IPC
"estructura de ponderaciones" publication — fetch at execution if needed for sanity checks).

### Re-weighting method (IPC 2017/18)
Laspeyres over division index levels sharing base dic-16=100:
`IPC_2017(t) = Σ w_i · I_i(t) / Σ w_i · I_i(t0)`, then rebase to avg(ene-23:sep-23)=100.
Known bias: within division 04, alquileres (≈IPC-linked) vs tarifas (huge 2024 hikes) diverge —
division-level may understate the 2017/18 vs 2004/05 gap (~2.4 pts at jun-26 is the target).

## 4. Equilibra target (the thing we reproduce)

- Chart: `data/sources/Ingreso_real_y_registrado_equilibra.png`. Monthly ene-23→jun-26, base
  avg(ene-23:sep-23)=100, universe ≈14.5M (formal private salaried + public + retirees).
- Anchors (canonical copy: `tests/anchors_equilibra.csv`):
  feb-24: 80 / 80 / 75 · jun-25: ~94 / 92 / 88 · jun-26: 91.5 / 89.1 / 83.1
  (order: Real 2004/05, Real 2017/18, Disponible 2017/18).
- Fixed-spending categories (footnote): alquiler, expensas, tarifas energéticas, comunicación,
  transporte, medicamentos, educación, prepagas → ≈38–43% of consumption per ENGHo 2017/18.
- Qualitative dynamics to reproduce: cliff nov-23→feb-24; recovery to jun-25 peak; 2017/18 line
  ~2.4 pts below 2004/05 line from mid-2024; disponible gap opens with tarifazos (feb-24, 2026),
  narrows with 2025 tariff freeze.
- **Implied nominal income cross-check** (IPC rebased × Equilibra real anchors, base-window pesos):
  feb-24 ≈ 80×2.924 ≈ 234 · jun-25 ≈ 94×5.365 ≈ 504 · jun-26 ≈ 91.5×7.165 ≈ 656.
  The EPH nominal income series (Phase 2) should land near these BEFORE deflation — fastest way to
  catch universe/measure errors.
- Article: https://www.notiar.com.ar/index.php/actualidad1/142154/ (Leandro Gabin, Equilibra).

## 5. Local inventory

| Path | Content | Status |
|---|---|---|
| `data/sources/*.pdf`, `*.png` | eph manual, ENGHo 2004/05 metodológico, ENGHo 2017/18 informe, Equilibra chart | ✅ present |
| `data/raw/eph/t{yy}{q}/` | 11 quarters t231→t261, `usu_individual_t{yy}{q}.txt` + `usu_hogar_t{yy}{q}.txt` | ✅ downloaded+validated 2026-08-24 |
| `data/raw/eph/zips/` | original INDEC zips (EPH_usu_*_Trim_*_txt.zip) | ✅ cached |
| `data/raw/ipc/` | IPC series JSON/CSV cache (nivel general, 12 divisiones NAL, regulados) | ✅ (Fase 1b done 2026-08-24) |
| `data/dicts/` | `EPH_registro_1T2026.pdf` + `weights_engho_2017_18.csv` (divisiones + grupos, Total país) | ✅ complete |
| `data/work/` | pipeline intermediates: `ipc_series.csv`, `admin_series.csv`, `ynom_mensual.csv`, `ipc2017.csv`, `canasta_fija.csv` | ✅ |
| `output/` | `serie_ingreso_real_ipc2004.csv`, `serie_ingreso_real_ipc2017.csv`, `serie_ingreso_disponible.csv` (fecha,valor; base ventana=100) + `grafico_equilibra.png` | ✅ (Fases 2-4 done 2026-08-24) |
| `scripts/01…06` | pipeline re-ejecutable: verificar EPH, IPC, ingreso nominal híbrido, serie A, serie B, serie C+gráfico | ✅ |
| `METHODOLOGY.md` | decisiones, sensibilidad, sesgos | ✅ |
| `tests/` | `run_all.R` + 3 tests + `anchors_equilibra.csv` | ✅ (IPC+EPH verdes; anclas 6/9 ok, 3 fuera ≤1,7 pt — ver PLAN §14) |

### Wage/pension admin series on datos.gob.ar (discovered 2026-08-24)

- `158.1_REPTE_0_0_5` — RIPTE pesos corrientes, mensual, hasta jun-26 (fresh).
- `149.1_SOR_PRIADO_OCTU_0_25` / `149.1_SOR_PUBICO_OCTU_0_14` / `149.1_TL_REGIADO_OCTU_0_16` —
  IST nominal registrado privado/público/total, mensual, hasta abr-26 (lag ~2 meses).
- `58.1_MP_0_M_24` (y `_13`) — haber mínimo jubilatorio pesos corrientes, hasta ago-26.
- `189.1_JUBILACIONINO_*`, `189.1_PENSIONES_INO_*`, `189.1_TOTAL_JUBIINO_*` — **ROJAS**
  (ceros hasta 2026-01, luego NA). Haber medio NO está en la API.
- ICL (contratos de locación) NO está en la API. EPH hogar II8/II9 son tramos categóricos
  desde el diseño 2023 — sin montos de alquiler.
- IPC por GRUPOS (alquileres, elec/gas, agua, prepagas) NO está en la API de INDEC — solo
  divisiones. GBA division series existen (`146.3_I{ABBR}GBA_DICI_M_{nn}`, sufijo numérico
  distinto por serie: IALIMENGBA_40, IBEBIDAGBA_34, IPRENDAGBA_30, IVIVIENGBA_47,
  IEQUIPAGBA_41, ISALUDGBA_13, ITRANSPGBA_18, ICOMUNIGBA_22, IRECREAGBA_26, IEDUCACGBA_17,
  IRESTAUGBA_28).
- **FUENTE NO-INDEC con grupos (clave para canasta fija)**: IPC CABA (IDECBA,
  estadisticaciudad.gob.ar) publica xlsx "IPCBA base 2021=100 según principales aperturas"
  con índices mensuales por GRUPO: alquiler, gastos comunes (expensas), electricidad+gas,
  agua, salud (prepagas dentro), funcionamiento/servicios de transporte, educación,
  comunicaciones. URL (feb-22→jul-26): /eyc/wp-content/uploads/2026/06/IPCBA_base_2021100-Principales_aperturas_indices.xlsx
  (fechas en columnas mm/dd/yyyy; convertir con libreoffice --headless --convert-to csv).
  Informes mensuales PDF: /eyc/publicaciones/ipcba-{mes}-de-{anio}/ (slugs viejos) o
  ipcba-ciudad-de-buenos-aires-{mes}-de-{anio} (nuevos); tabla de aperturas = "Cuadro 8"
  (2023-24) o "C.4.A" (2025+). ICL de alquileres: BCRA lo publica (diar_icl.xls) pero crece
  por debajo del IPC — inútil como proxy de alquileres de mercado post-liberación.

### Equilibra reproduction status (2026-08-24)

Pipeline híbrido (admin growth × EPH weights) reproduce tendencia y 6/9 anclas; ver
METHODOLOGY.md §7 y PLAN.md §14. EPH-pura sobrestima jun-25 +13,5 pts (deriva de
composición/imputación) — no insistir con medias de encuesta. La nota fuente (notiar
142154) cita variaciones m/m e i.a. por segmento útiles como cross-check y para colas.

## 6. Pitfalls

- INDEC HTML soft-404s return HTTP 200 with `text/html` — always check `Content-Type`/first bytes,
  never status alone. Old `EPH_usu_{q}Trim_{year}` (no underscore before Trim) paths are dead.
- curl to INDEC: use `-o <file>`, not `-O` (error 23).
- SPA pages: dash-form browser URLs return the JS shell; fetch the slash-form partial view instead.
- INDEC inner file naming `T{q}{yy}` (T126=2026T1) vs our canonical `t{yy}{q}` (t261) — never mix.
- EPH txt: `dec=","`; fields quoted; decile columns contain values like `01`…`10` → read as character.
- EPH income negatives are codes (−7/−8/−9), not amounts. Pension amount var: `V2_M` (2023T1–T3)
  vs `V2_01_M`+ (2023T4+).
- ΣPONDERA ≈ 29–30 M per quarter (EPH aglomerados universe), NOT total urban population.
- datos.gob.ar search API is flaky with multi-word queries; prefer single words + filter client-side.
  Series API: pass `limit=1000` (default 100 caps silently); one bad id errors the whole request.
- Equilibra's 2023 segment is flat at exactly 100 in the image; our reconstruction will wiggle ±1 pt
  there. Tests compare the base-window average, not each month.
