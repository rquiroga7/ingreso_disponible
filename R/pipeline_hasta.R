# Ultimo mes del pipeline: el ultimo mes con IPC publicado y con IST disponible
# (el IST es lo que extiende las series de ingreso cuando la API de SIPA llega
# con rezago). Lo usan los scripts de procesamiento para no quedar atados a una
# fecha fija.

pipeline_hasta <- function(repo_root = ".") {
  ipc <- read.csv(file.path(repo_root, "data", "work", "ipc_series.csv"))
  ultimo <- max(as.Date(ipc$fecha))

  ist_csv <- file.path(repo_root, "data", "raw", "salarios", "variacion_indice_salarios.csv")
  if (file.exists(ist_csv)) {
    ist <- read.csv(ist_csv, sep = ";", dec = ",", na.strings = "NA")
    meses <- format(as.Date(ist$periodo, "%d/%m/%Y"), "%Y-%m")
    ultimo <- min(ultimo, as.Date(paste0(max(meses), "-01")))
  }
  format(ultimo, "%Y-%m")
}
