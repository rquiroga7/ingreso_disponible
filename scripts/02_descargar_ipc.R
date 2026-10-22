# Fase 1b — actualiza IPC y series administrativas con cache en data/raw/.
#
# Series Nacional mensuales (indice, base dic-16=100):
#  - nivel general (IPC oficial, ponderaciones ENGHo 2004/05)
#  - 12 divisiones COICOP (para reponderar con ENGHo 2017/18 en Fase 3)
#  - regulados (diagnostico de la dinamica tarifaria, Fase 4)
#
# Con options(refresh_data = TRUE) se re-descargan todas las series y el xlsx
# del IPC CABA (lo usa scripts/00_actualizar_datos.R).

repo_root <- getOption("repo_root", ".")
refresh <- isTRUE(getOption("refresh_data"))
source(file.path(repo_root, "R", "fetch_series_datosgobar.R"))

# IPC: serie oficial de INDEC por divisiones (CSV semicolon, decimal coma, region
# Nacional). Se usa esta fuente en vez de la API de datos.gob.ar porque dos
# divisiones (recreacion y restaurantes) quedaron vacias en la API en ago-2026.
ipc_csv <- file.path(repo_root, "data", "raw", "ipc", "serie_ipc_divisiones.csv")
dir.create(dirname(ipc_csv), recursive = TRUE, showWarnings = FALSE)
if (refresh || !file.exists(ipc_csv)) {
  tmp <- tempfile(fileext = ".csv")
  ok <- tryCatch({
    download.file("https://www.indec.gob.ar/ftp/cuadros/economia/serie_ipc_divisiones.csv",
                  tmp, quiet = TRUE)
    TRUE
  }, error = function(e) FALSE)
  if (ok) file.copy(tmp, ipc_csv, overwrite = TRUE)
  else if (!file.exists(ipc_csv)) stop("No se pudo descargar el IPC por divisiones")
  unlink(tmp)
}

leer_ipc_indec <- function(archivo) {
  raw <- read.csv2(archivo, fileEncoding = "latin1", check.names = FALSE,
                   stringsAsFactors = FALSE)
  raw$fecha <- as.Date(paste0(substr(raw$Periodo, 1, 4), "-",
                              substr(raw$Periodo, 5, 6), "-01"))
  div <- raw[raw$Region == "Nacional" &
               raw$Clasificador == "Nivel general y divisiones COICOP", ]
  reg <- raw[raw$Region == "Nacional" & raw$Codigo == "Regulados", ]
  codigos <- c(
    ipc_nivel_general = "0", div01_alimentos = "01", div02_bebidas = "02",
    div03_prendas = "03", div04_vivienda = "04", div05_equipamiento = "05",
    div06_salud = "06", div07_transporte = "07", div08_comunicacion = "08",
    div09_recreacion = "09", div10_educacion = "10", div11_restaurantes = "11",
    div12_bienes_varios = "12"
  )
  out <- data.frame(fecha = sort(unique(div$fecha)))
  for (nm in names(codigos)) {
    d <- div[div$Codigo == codigos[[nm]], c("fecha", "Indice_IPC")]
    d <- d[!duplicated(d$fecha), ]
    out[[nm]] <- as.numeric(d$Indice_IPC[match(out$fecha, d$fecha)])
  }
  d <- reg[!duplicated(reg$fecha), c("fecha", "Indice_IPC")]
  out$ipc_regulados <- as.numeric(d$Indice_IPC[match(out$fecha, d$fecha)])
  out
}

dir.create(file.path(repo_root, "data", "work"), recursive = TRUE, showWarnings = FALSE)
ipc <- leer_ipc_indec(ipc_csv)
write.csv(ipc, file.path(repo_root, "data", "work", "ipc_series.csv"), row.names = FALSE)
# Cache con el nombre que leen los scripts 04/10 (nivel general).
write.csv(data.frame(fecha = ipc$fecha, valor = ipc$ipc_nivel_general),
          file.path(repo_root, "data", "raw", "ipc", "148.3_INIVELNAL_DICI_M_26.csv"),
          row.names = FALSE)

# Series administrativas de ingresos (Fase 2): IST privado/publico, haber minimo, SIPA
admin_ids <- c(
  ist_nom_priv = "149.1_SOR_PRIADO_OCTU_0_25",
  ist_nom_pub = "149.1_SOR_PUBICO_OCTU_0_14",
  haber_minimo = "58.1_MP_0_M_24",
  sipa_prom_priv = "153.1_RNERACIDIO_2009_M_21",  # SIPA remuneracion promedio priv (SST)
  sipa_med_priv = "153.1_RNERACIANA_2009_M_20"   # SIPA remuneracion mediana priv (SST)
)
admin <- fetch_series_datosgobar(unname(admin_ids), file.path(repo_root, "data", "raw", "ipc"), refresh = refresh)
admin$fecha <- as.Date(admin$fecha)
names(admin) <- c("fecha", names(admin_ids))
write.csv(admin, file.path(repo_root, "data", "work", "admin_series.csv"), row.names = FALSE)

# Canasta fija: aperturas del IPC CABA (IDECBA, fuente no-INDEC con grupos:
# alquiler, gastos comunes/expensas, electricidad+gas, agua, salud, transporte,
# educacion, comunicaciones). La pagina de IDECBA linkea el xlsx vigente; se
# scrapea para no quedar atado al mes de upload. Conversion xlsx->csv con libreoffice.
pagina_caba <- paste0(
  "https://www.estadisticaciudad.gob.ar/eyc/banco-datos/",
  "ipcba-base-2021-100-segun-principales-aperturas-indice-mensual-",
  "ciudad-de-buenos-aires-febrero-de-2022-agosto-de-2025/"
)
xlsx_caba <- file.path(repo_root, "data", "raw", "ipc", "IPCBA_aperturas.xlsx")
csv_caba <- file.path(repo_root, "data", "work", "ipcba_aperturas.csv")

url_caba <- tryCatch({
  html <- paste(readLines(pagina_caba, warn = FALSE), collapse = "\n")
  m <- regmatches(html, regexpr(
    "https://[^\"' ]+IPCBA_base_2021100-Principales_aperturas_indices\\.xlsx", html
  ))
  if (length(m) == 1) m else NA_character_
}, error = function(e) NA_character_)

if (!is.na(url_caba)) {
  tmp <- tempfile(fileext = ".xlsx")
  ok <- tryCatch({ download.file(url_caba, tmp, quiet = TRUE, mode = "wb"); TRUE },
                 error = function(e) FALSE)
  nuevo <- ok && (!file.exists(xlsx_caba) ||
    !identical(unname(tools::md5sum(tmp)), unname(tools::md5sum(xlsx_caba))))
  if (nuevo) {
    file.copy(tmp, xlsx_caba, overwrite = TRUE)
    cat("IPC CABA actualizado:", url_caba, "\n")
  } else if (!ok) {
    warning("No se pudo descargar el IPC CABA; se usa el cache local")
  }
  unlink(tmp)
} else if (!file.exists(xlsx_caba)) {
  stop("No se pudo descubrir el xlsx vigente del IPC CABA")
} else {
  warning("No se pudo descubrir el link al IPC CABA; se usa el cache local")
}

if (!file.exists(csv_caba) || file.mtime(xlsx_caba) > file.mtime(csv_caba)) {
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
if (refresh || !file.exists(csv_emp)) {
  system2("libreoffice", c("--headless", "--convert-to", "csv", "--outdir",
                           dirname(csv_emp), xlsx_emp))
  file.rename(file.path(dirname(csv_emp), "IPCBA_aperturas_empalme.csv"), csv_emp)
}

# SIPA remuneracion promedio asalariados privados registrados (SST) — fuente del
# salario privado (revision 2026-08-25: Equilibra usa SIPA, que capta bonos y
# no-remunerativos y cae en 2026, a diferencia del IST/RIPTE).
# IST variaciones mensuales oficiales (INDEC): para extender las series de nivel
# (API con rezago) con el propio IST.
ist_csv <- file.path(repo_root, "data", "raw", "salarios", "variacion_indice_salarios.csv")
dir.create(dirname(ist_csv), recursive = TRUE, showWarnings = FALSE)
if (refresh || !file.exists(ist_csv)) {
  tmp <- tempfile(fileext = ".csv")
  ok <- tryCatch({
    download.file("https://www.indec.gob.ar/ftp/cuadros/sociedad/variacion_indice_salarios.csv",
                  tmp, quiet = TRUE)
    TRUE
  }, error = function(e) FALSE)
  if (ok) file.copy(tmp, ist_csv, overwrite = TRUE)
  else if (!file.exists(ist_csv)) stop("No se pudo descargar el IST")
  unlink(tmp)
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
cat(sprintf("IPC cacheado: %d series x %d meses (%s a %s)\n", ncol(ipc) - 1, nrow(ipc), format(min(ipc$fecha), "%Y-%m"), ultima))

# Chequeo rapido: variaciones m/m conocidas del nivel general
ng <- setNames(ipc$ipc_nivel_general, format(ipc$fecha, "%Y-%m"))
var_mm <- function(m0, m1) (ng[[m1]] / ng[[m0]] - 1) * 100
cat(sprintf("m/m dic-23: %.1f%% (oficial 25.5) | m/m feb-24: %.1f%% (oficial 13.2)\n",
            var_mm("2023-11", "2023-12"), var_mm("2024-01", "2024-02")))
