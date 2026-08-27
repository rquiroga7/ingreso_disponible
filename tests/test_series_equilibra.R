# Test: series construidas vs anclas de Equilibra (tests/anchors_equilibra.csv)
#
# Compara output/serie_*.csv contra las anclas del grafico de Equilibra y contra
# la normalizacion base promedio ene-23:sep-23 = 100. Imprime una tabla
# comparativa (esperado vs obtenido vs desvio). Si una serie todavia no fue
# construida, hace SKIP para esa serie.

repo_root <- getOption("repo_root", ".")
if (!exists("test_env_new", envir = globalenv())) {
  source(file.path(repo_root, "tests", "helper.R"))
}
e <- test_setup("series_equilibra")

anchors <- read.csv(file.path(repo_root, "tests", "anchors_equilibra.csv"), stringsAsFactors = FALSE)

series_files <- c(
  ingreso_real_ipc2004 = "serie_ingreso_real_ipc2004.csv",
  ingreso_real_ipc2017 = "serie_ingreso_real_ipc2017.csv",
  ingreso_disponible_ipc2017 = "serie_ingreso_disponible.csv"
)

normalizar_mes <- function(x) {
  x <- as.character(x)
  substr(x, 1, 7)
}

leer_serie <- function(path) {
  df <- tryCatch(read.csv(path, stringsAsFactors = FALSE), error = function(err) NULL)
  if (is.null(df)) {
    return(NULL)
  }
  if (!all(c("fecha", "valor") %in% names(df))) {
    return(NULL)
  }
  setNames(as.numeric(df$valor), normalizar_mes(df$fecha))
}

ventana_base <- sprintf("2023-0%d", 1:9)
hay_series <- FALSE

for (s in names(series_files)) {
  path <- file.path(repo_root, "output", series_files[[s]])
  if (!file.exists(path)) {
    test_skip(e, paste0("output/", series_files[[s]], " no existe aun (serie no construida)"))
    next
  }
  serie <- leer_serie(path)
  if (is.null(serie) || length(serie) == 0) {
    test_fail(e, paste0("output/", series_files[[s]], " existe pero no se pudo leer (se esperan columnas fecha,valor)"))
    next
  }
  hay_series <- TRUE

  test_assert(
    e,
    all(ventana_base %in% names(serie)),
    paste0(s, ": ventana base ene-23:sep-23 completa"),
    paste0(s, ": faltan meses de la ventana base ene-23:sep-23")
  )
  if (!all(ventana_base %in% names(serie))) {
    next
  }

  base <- mean(serie[ventana_base])
  test_assert(
    e,
    abs(base - 100) <= 0.01,
    paste0(s, ": base promedio ene-23:sep-23 = 100 (", sprintf("%.4f", base), ")"),
    paste0(s, ": base promedio ene-23:sep-23 = ", sprintf("%.4f", base), " != 100 (rebase mal aplicado)")
  )

  an_s <- anchors[anchors$series == s, , drop = FALSE]
  if (nrow(an_s) == 0) {
    test_skip(e, paste0(s, ": sin anclas en anchors_equilibra.csv"))
    next
  }

  cat(sprintf("\n   [%s] mes     |  ours | esperado | desvio | tol | estado\n", s))
  for (i in seq_len(nrow(an_s))) {
    mes <- an_s$month[i]
    esperado <- an_s$value[i]
    tol <- an_s$tolerance[i]
    if (!mes %in% names(serie)) {
      test_fail(e, sprintf("%s %s: mes ausente en la serie construida", s, mes))
      cat(sprintf("   %-9s |   --  |   %5.1f  |   --   | %.1f | AUSENTE\n", mes, esperado, tol))
      next
    }
    ours <- serie[[mes]]
    desvio <- ours - esperado
    ok <- abs(desvio) <= tol
    cat(sprintf("   %-9s | %5.1f |   %5.1f  | %+5.1f  | %.1f | %s\n",
                mes, ours, esperado, desvio, tol, ifelse(ok, "ok", "FUERA")))
    test_assert(
      e,
      ok,
      sprintf("%s %s = %.1f vs ancla %.1f (tol %.1f)", s, mes, ours, esperado, tol),
      sprintf("%s %s = %.1f vs ancla %.1f (desvio %+.1f > tol %.1f)", s, mes, ours, esperado, desvio, tol)
    )
  }
}

if (!hay_series) {
  test_skip(e, "ninguna serie construida todavia en output/ (Fases 2-4)")
}

test_finish(e)
