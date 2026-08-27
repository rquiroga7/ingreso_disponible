# Fase 1b — descarga IPC (API datos.gob.ar) con cache en data/raw/ipc/.
#
# Series Nacional mensuales (indice, base dic-16=100):
#  - nivel general (IPC oficial, ponderaciones ENGHo 2004/05)
#  - 12 divisiones COICOP (para reponderar con ENGHo 2017/18 en Fase 3)
#  - regulados (diagnostico de la dinamica tarifaria, Fase 4)
# Los IDs se enumeraron via /search/ del catalogo el 2026-08-24.

repo_root <- getOption("repo_root", ".")
source(file.path(repo_root, "R", "fetch_series_datosgobar.R"))

ids <- c(
  ipc_nivel_general = "148.3_INIVELNAL_DICI_M_26",
  div01_alimentos   = "146.3_IALIMENNAL_DICI_M_45",
  div02_bebidas     = "146.3_IBEBIDANAL_DICI_M_39",
  div03_prendas     = "146.3_IPRENDANAL_DICI_M_35",
  div04_vivienda    = "146.3_IVIVIENNAL_DICI_M_52",
  div05_equipamiento = "146.3_IEQUIPANAL_DICI_M_46",
  div06_salud       = "146.3_ISALUDNAL_DICI_M_18",
  div07_transporte  = "146.3_ITRANSPNAL_DICI_M_23",
  div08_comunicacion = "146.3_ICOMUNINAL_DICI_M_27",
  div09_recreacion  = "146.3_IRECREANAL_DICI_M_31",
  div10_educacion   = "146.3_IEDUCACNAL_DICI_M_22",
  div11_restaurantes = "146.3_IRESTAUNAL_DICI_M_33",
  div12_bienes_varios = "146.3_IBIENESNAL_DICI_M_36",
  ipc_regulados     = "148.3_IREGULANAL_DICI_M_22"
)

dir.create(file.path(repo_root, "data", "work"), recursive = TRUE, showWarnings = FALSE)
ipc <- fetch_series_datosgobar(unname(ids), file.path(repo_root, "data", "raw", "ipc"))
ipc$fecha <- as.Date(ipc$fecha)
names(ipc) <- c("fecha", names(ids))
write.csv(ipc, file.path(repo_root, "data", "work", "ipc_series.csv"), row.names = FALSE)

# Series administrativas de ingresos (Fase 2): RIPTE, IST privado/publico, haber minimo
admin_ids <- c(
  ripte_priv = "158.1_REPTE_0_0_5",
  ist_nom_priv = "149.1_SOR_PRIADO_OCTU_0_25",
  ist_nom_pub = "149.1_SOR_PUBICO_OCTU_0_14",
  haber_minimo = "58.1_MP_0_M_24",
  sipa_prom_priv = "153.1_RNERACIDIO_2009_M_21",  # SIPA remuneracion promedio priv (SST)
  sipa_med_priv = "153.1_RNERACIANA_2009_M_20"   # SIPA remuneracion mediana priv (SST)
)
admin <- fetch_series_datosgobar(unname(admin_ids), file.path(repo_root, "data", "raw", "ipc"))
admin$fecha <- as.Date(admin$fecha)
names(admin) <- c("fecha", names(admin_ids))
write.csv(admin, file.path(repo_root, "data", "work", "admin_series.csv"), row.names = FALSE)

# Canasta fija: aperturas del IPC CABA (IDECBA, fuente no-INDEC con grupos:
# alquiler, gastos comunes/expensas, electricidad+gas, agua, salud, transporte,
# educacion, comunicaciones). Conversion xlsx->csv con libreoffice.
xlsx_caba <- file.path(repo_root, "data", "raw", "ipc", "IPCBA_aperturas.xlsx")
csv_caba <- file.path(repo_root, "data", "work", "ipcba_aperturas.csv")
if (!file.exists(xlsx_caba)) {
  download.file(
    "https://www.estadisticaciudad.gob.ar/eyc/wp-content/uploads/2026/06/IPCBA_base_2021100-Principales_aperturas_indices.xlsx",
    xlsx_caba, quiet = TRUE, mode = "wb"
  )
}
if (!file.exists(csv_caba)) {
  system2("libreoffice", c("--headless", "--convert-to", "csv", "--outdir",
                           dirname(csv_caba), xlsx_caba))
  file.rename(file.path(dirname(csv_caba), "IPCBA_aperturas.csv"), csv_caba)
}
# Serie empalmada de aperturas (jul-12..feb-22) para anclar la canasta fija en 2018
xlsx_emp <- file.path(repo_root, "data", "raw", "ipc", "IPCBA_aperturas_empalme.xlsx")
if (!file.exists(xlsx_emp)) {
  download.file("https://www.estadisticaciudad.gob.ar/eyc/wp-content/uploads/2023/05/IPCBA_base_2021100-Principales_aperturas_empalme.xlsx",
                xlsx_emp, quiet = TRUE, mode = "wb")
}
csv_emp <- file.path(repo_root, "data", "work", "ipcba_aperturas_empalme.csv")
if (!file.exists(csv_emp)) {
  system2("libreoffice", c("--headless", "--convert-to", "csv", "--outdir",
                           dirname(csv_emp), xlsx_emp))
  file.rename(file.path(dirname(csv_emp), "IPCBA_aperturas_empalme.csv"), csv_emp)
}

# SIPA remuneracion promedio asalariados privados registrados (SST) — fuente del
# salario privado (revision 2026-08-25: Equilibra usa SIPA, que capta bonos y
# no-remunerativos y cae en 2026, a diferencia del IST/RIPTE).
# IST variaciones mensuales oficiales (INDEC): para extender las series de nivel
# (API hasta abr-26) con el propio IST hasta jun-26.
ist_csv <- file.path(repo_root, "data", "raw", "salarios", "variacion_indice_salarios.csv")
dir.create(dirname(ist_csv), recursive = TRUE, showWarnings = FALSE)
if (!file.exists(ist_csv)) {
  download.file("https://www.indec.gob.ar/ftp/cuadros/sociedad/variacion_indice_salarios.csv",
                ist_csv, quiet = TRUE)
}

# ENGHo 2017/18 base de hogares (microdatos oficiales): para derivar g0 a priori
# (participacion de la canasta fija en el INGRESO de los hogares, sin calibrar).
zip_engho <- file.path(repo_root, "data", "raw", "engho", "engho2018_hogares.zip")
txt_engho <- file.path(repo_root, "data", "raw", "engho", "engho2018_hogares.txt")
dir.create(dirname(zip_engho), recursive = TRUE, showWarnings = FALSE)
if (!file.exists(txt_engho)) {
  download.file("https://www.indec.gob.ar/ftp/cuadros/menusuperior/engho/engho2018_hogares.zip",
                zip_engho, quiet = TRUE, mode = "wb")
  unzip(zip_engho, exdir = dirname(zip_engho))
}

ultima <- format(max(ipc$fecha), "%Y-%m")
cat(sprintf("IPC descargado y cacheado: %d series x %d meses (%s a %s)\n", length(ids), nrow(ipc), format(min(ipc$fecha), "%Y-%m"), ultima))

# Chequeo rapido: variaciones m/m conocidas del nivel general
ng <- setNames(ipc$ipc_nivel_general, format(ipc$fecha, "%Y-%m"))
var_mm <- function(m0, m1) (ng[[m1]] / ng[[m0]] - 1) * 100
cat(sprintf("m/m dic-23: %.1f%% (oficial 25.5) | m/m feb-24: %.1f%% (oficial 13.2)\n",
            var_mm("2023-11", "2023-12"), var_mm("2024-01", "2024-02")))
