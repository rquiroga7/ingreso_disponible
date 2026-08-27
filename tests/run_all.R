# Runner de tests del proyecto ingreso_disponible.
#
# Uso (desde cualquier directorio):
#   Rscript tests/run_all.R
#
# Cada test reporta PASS / FAIL / SKIP (SKIP = insumo aun no disponible; no es
# un fallo). El proceso sale con codigo 1 si hay al menos un FAIL.

args <- commandArgs(FALSE)
file_arg <- sub("^--file=", "", grep("^--file=", args, value = TRUE))
script_dir <- if (length(file_arg) > 0) dirname(normalizePath(file_arg)) else "tests"
repo_root <- normalizePath(file.path(script_dir, ".."))
options(repo_root = repo_root)

source(file.path(script_dir, "helper.R"))

tests <- c(
  "test_ipc_official.R",
  "test_eph_microdata.R",
  "test_series_equilibra.R"
)

resultados <- list()
for (t in tests) {
  e <- test_env_new(t)
  options(test_env = e)
  e <- tryCatch(
    {
      sys.source(file.path(script_dir, t), envir = e)
      e
    },
    error = function(err) {
      e$TEST_STATUS <- "FAIL"
      e$TEST_MSGS <- c(e$TEST_MSGS, paste0("   ERROR inesperado: ", conditionMessage(err)))
      e
    }
  )
  options(test_env = NULL)
  resultados[[t]] <- e
  cat("\n=====", t, "->", e$TEST_STATUS, "\n")
  if (length(e$TEST_MSGS) > 0) {
    cat(paste(e$TEST_MSGS, collapse = "\n"), "\n")
  }
}

n_fail <- sum(vapply(resultados, function(r) r$TEST_STATUS == "FAIL", logical(1)))
n_skip <- sum(vapply(resultados, function(r) r$TEST_STATUS == "SKIP", logical(1)))
n_pass <- sum(vapply(resultados, function(r) r$TEST_STATUS == "PASS", logical(1)))

cat(sprintf(
  "\n===== RESUMEN: %d PASS | %d FAIL | %d SKIP =====\n",
  n_pass, n_fail, n_skip
))

if (n_fail > 0) {
  quit(status = 1)
}
quit(status = 0)
