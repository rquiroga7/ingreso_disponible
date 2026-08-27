# Fase 1a — verificacion de microdatos EPH (t231..t261) ya descargados.
#
# La descarga original se hizo via INDEC (ruta verificada en el skill EPH-INDEC;
# zips cacheados en data/raw/eph/zips/). Este script no re-descarga: verifica
# presencia de bases y reporta. La integridad fina la cubre
# tests/test_eph_microdata.R. Si falta un trimestre, descargar a mano siguiendo
# la seccion 1 del skill EPH-INDEC.

repo_root <- getOption("repo_root", ".")

# t262 (2026T2) es opcional: se publica ~sep-26. t263+ no existen todavia.
trimestres <- c(sprintf("t%d%d", rep(23:25, each = 4), 1:4), "t261", "t262")
faltan <- character(0)
for (id in trimestres) {
  dir_q <- file.path(repo_root, "data", "raw", "eph", id)
  archivos <- if (dir.exists(dir_q)) list.files(dir_q, pattern = "usu_(individual|hogar)", recursive = TRUE) else character(0)
  tiene <- length(grep("individual", archivos)) > 0 && length(grep("hogar", archivos)) > 0
  estado <- if (tiene) "ok" else "pendiente (se publica ~sep-26)"
  cat(sprintf("%s: %s\n", id, estado))
}
