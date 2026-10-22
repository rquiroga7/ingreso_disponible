# Fase 0 — actualizacion de todos los insumos del pipeline.
#
# Uso (desde la raiz del repo):
#   Rscript scripts/00_actualizar_datos.R
#
# Refresca:
#  - series IPC y administrativas de datos.gob.ar (script 02 con refresh)
#  - aperturas del IPC CABA (descubre el xlsx vigente en IDECBA)
#  - IST (variaciones mensuales INDEC)
#  - microdatos EPH faltantes (descubre trimestres publicados en INDEC)
#  - mora de familias del BCRA (anexo estadistico del Informe sobre Bancos)
# No toca: bono ANSES (dato de politica, se mantiene a mano en
# data/work/bono_anses.csv; aca solo se avisa si falta un mes).

repo_root <- getOption("repo_root", ".")
options(repo_root = repo_root, refresh_data = TRUE)
source(file.path(repo_root, "R", "pipeline_hasta.R"))

cat("== Series IPC / administrativas / CABA / IST ==\n")
source(file.path(repo_root, "scripts", "02_descargar_ipc.R"))

## Microdatos EPH: descubre los zips publicados y baja los trimestres faltantes.
actualizar_eph <- function(repo_root) {
  listado <- "https://www.indec.gob.ar/Institucional/Indec/BasesDeDatos/1"
  html <- tryCatch(paste(readLines(listado, warn = FALSE), collapse = "\n"),
                   error = function(e) "")
  if (!nzchar(html)) {
    warning("No se pudo leer el listado de EPH; se usan los trimestres locales")
    return(invisible(FALSE))
  }
  zips <- unique(regmatches(html, gregexpr(
    "/ftp/cuadros/menusuperior/eph/EPH_usu_[^\"']+_txt\\.zip", html
  ))[[1]])
  rx <- "EPH_usu_([0-9])(?:er|do|to)?_?Trim_([0-9]{4})_txt\\.zip$"
  q <- suppressWarnings(as.integer(sub(rx, "\\1", basename(zips))))
  y <- suppressWarnings(as.integer(sub(rx, "\\2", basename(zips))))
  ok <- !is.na(q) & !is.na(y) & y >= 2023
  zips <- zips[ok]; q <- q[ok]; y <- y[ok]
  descargados <- character(0)

  for (i in seq_along(zips)) {
    id <- sprintf("t%02d%d", y[i] %% 100, q[i])
    dir_q <- file.path(repo_root, "data", "raw", "eph", id)
    esperados <- file.path(dir_q, sprintf("usu_%s_%s.txt", c("individual", "hogar"), id))
    if (all(file.exists(esperados))) next

    zip_local <- file.path(repo_root, "data", "raw", "eph", "zips", basename(zips[i]))
    dir.create(dirname(zip_local), recursive = TRUE, showWarnings = FALSE)
    if (!file.exists(zip_local)) {
      ok_dl <- tryCatch({
        download.file(paste0("https://www.indec.gob.ar", zips[i]), zip_local,
                      quiet = TRUE, mode = "wb")
        TRUE
      }, error = function(e) FALSE)
      if (!ok_dl) {
        warning(sprintf("No se pudo descargar %s", zips[i]))
        next
      }
    }

    inner <- sprintf("usu_(individual|hogar)_T%d%d\\.txt$", q[i], y[i] %% 100)
    entries <- tryCatch(unzip(zip_local, list = TRUE)$Name, error = function(e) character(0))
    if (!all(grepl(inner, entries))) {
      warning(sprintf("Zip invalido o inesperado: %s", basename(zips[i])))
      next
    }

    tmp <- tempfile()
    dir.create(tmp)
    unzip(zip_local, exdir = tmp)
    files <- list.files(tmp, recursive = TRUE, full.names = TRUE)
    dir.create(dir_q, recursive = TRUE, showWarnings = FALSE)
    file.copy(files[grepl(sprintf("usu_individual_T%d%d\\.txt$", q[i], y[i] %% 100), files)],
              esperados[1], overwrite = TRUE)
    file.copy(files[grepl(sprintf("usu_hogar_T%d%d\\.txt$", q[i], y[i] %% 100), files)],
              esperados[2], overwrite = TRUE)
    unlink(tmp, recursive = TRUE)
    descargados <- c(descargados, id)
  }
  if (length(descargados)) cat("EPH nuevos:", paste(descargados, collapse = ", "), "\n")
  else cat("EPH: sin trimestres nuevos\n")
  invisible(TRUE)
}

## Mora de familias: anexo estadistico del Informe sobre Bancos (BCRA).
actualizar_mora_bcra <- function(repo_root) {
  if (!requireNamespace("readxl", quietly = TRUE)) {
    warning("readxl no instalado: se conserva data/work/bcra_mora_familias.csv")
    return(invisible(FALSE))
  }
  url <- "https://www.bcra.gob.ar/archivos/Pdfs/PublicacionesEstadisticas/informes/informe-bancos-anexo.xlsx"
  xlsx <- file.path(repo_root, "data", "raw", "bcra", "informe-bancos-anexo.xlsx")
  dir.create(dirname(xlsx), recursive = TRUE, showWarnings = FALSE)
  ok <- tryCatch({ download.file(url, xlsx, quiet = TRUE, mode = "wb"); TRUE },
                 error = function(e) FALSE)
  if (!ok) {
    warning("No se pudo descargar el anexo del BCRA; se conserva la mora local")
    return(invisible(FALSE))
  }
  d <- suppressMessages(suppressWarnings(readxl::read_excel(
    xlsx, sheet = "Calidad de Cartera (por líneas)", col_names = FALSE,
    .name_repair = "minimal"
  )))
  i <- which(trimws(as.character(d[[1]])) == "2. Familias - Total")
  if (!length(i)) {
    warning("No se encontro '2. Familias - Total' en el anexo BCRA")
    return(invisible(FALSE))
  }
  fechas <- as.numeric(unlist(d[i + 2, -1]))
  valores <- as.numeric(unlist(d[i + 3, -1]))
  keep <- !is.na(fechas) & !is.na(valores)
  out <- data.frame(
    fecha = as.Date(fechas[keep], origin = "1899-12-30"),
    mora_familias = valores[keep]
  )
  write.csv(out, file.path(repo_root, "data", "work", "bcra_mora_familias.csv"),
            row.names = FALSE)
  cat(sprintf("Mora BCRA actualizada: %s a %s\n",
              format(min(out$fecha)), format(max(out$fecha))))
  invisible(TRUE)
}

cat("\n== Microdatos EPH ==\n")
actualizar_eph(repo_root)

cat("\n== Mora de familias (BCRA) ==\n")
actualizar_mora_bcra(repo_root)

## Bono ANSES: insumo de politica, no hay serie automatica confiable.
hasta <- pipeline_hasta(repo_root)
bono <- read.csv(file.path(repo_root, "data", "work", "bono_anses.csv"))
faltan <- setdiff(hasta, bono$mes)
if (length(faltan)) {
  warning(sprintf("Falta el bono ANSES para: %s (completar data/work/bono_anses.csv)",
                  paste(faltan, collapse = ", ")))
}
cat(sprintf("\nUltimo mes del pipeline: %s\n", hasta))
