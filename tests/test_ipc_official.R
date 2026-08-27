# Test: IPC oficial (INDEC, base dic-2016 = ENGHo 2004/05) via API datos.gob.ar
#
# Valida que la fuente de deflactacion este viva, actualizada y consistente con
# valores oficiales conocidos. Los valores de referencia fueron verificados
# contra la API el 2026-08-24 (ver skill EPH-INDEC, seccion 2).

repo_root <- getOption("repo_root", ".")
if (!exists("test_env_new", envir = globalenv())) {
  source(file.path(repo_root, "tests", "helper.R"))
}
e <- test_setup("ipc_oficial")

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  test_skip(e, "paquete 'jsonlite' no instalado (correr install.packages('jsonlite'))")
} else {
  fetch_series <- function(id) {
    url <- sprintf(
      "https://apis.datos.gob.ar/series/api/series/?ids=%s&format=json&limit=1000",
      id
    )
    txt <- tryCatch(readLines(url(url), warn = FALSE), error = function(e) NULL)
    if (is.null(txt)) {
      return(NULL)
    }
    js <- jsonlite::fromJSON(paste(txt, collapse = "\n"))
    if (is.null(js$data) || length(js$data) == 0) {
      return(NULL)
    }
    setNames(as.numeric(js$data[, 2]), substr(js$data[, 1], 1, 7))
  }

  ipc <- fetch_series("148.3_INIVELNAL_DICI_M_26")

  if (is.null(ipc) || length(ipc) == 0) {
    test_fail(e, "no se pudo descargar IPC nivel general (148.3_INIVELNAL_DICI_M_26) desde datos.gob.ar")
  } else {
    meses <- names(ipc)
    test_ok(e, sprintf(
      "API respondio: %d obs mensuales (%s a %s)",
      length(ipc), meses[1], meses[length(meses)]
    ))

    test_assert(
      e,
      meses[length(meses)] >= "2026-06",
      sprintf("serie actualizada hasta %s (>= jun-26)", meses[length(meses)]),
      sprintf("serie desactualizada: ultima obs %s < 2026-06", meses[length(meses)])
    )

    v <- ipc
    var_mm <- function(m0, m1) (v[[m1]] / v[[m0]] - 1) * 100

    dic23 <- var_mm("2023-11", "2023-12")
    test_assert(
      e,
      !is.na(dic23) && dic23 > 20 && dic23 < 30,
      sprintf("variacion m/m dic-23 = %.1f%% en [20, 30] (oficial 25.5)", dic23),
      sprintf("variacion m/m dic-23 = %.1f%% fuera de [20, 30]", dic23)
    )

    feb24 <- var_mm("2024-01", "2024-02")
    test_assert(
      e,
      !is.na(feb24) && feb24 > 10 && feb24 < 16,
      sprintf("variacion m/m feb-24 = %.1f%% en [10, 16] (oficial 13.2)", feb24),
      sprintf("variacion m/m feb-24 = %.1f%% fuera de [10, 16]", feb24)
    )

    ventana_base <- sprintf("2023-0%d", 1:9)
    if (all(ventana_base %in% meses)) {
      base <- mean(v[ventana_base])
      reb <- function(m) v[[m]] / base * 100

      refs <- data.frame(
        mes = c("2023-12", "2024-02", "2025-06", "2026-06"),
        ref = c(214.1, 292.4, 536.5, 716.5),
        tol = c(1.0, 1.5, 2.0, 2.5)
      )
      for (i in seq_len(nrow(refs))) {
        m <- refs$mes[i]
        ref <- refs$ref[i]
        tol <- refs$tol[i]
        r <- reb(m)
        test_assert(
          e,
          !is.na(r) && abs(r - ref) <= tol,
          sprintf("IPC rebase ene23:sep23=100, %s = %.1f (ref %.1f +- %.1f)", m, r, ref, tol),
          sprintf("IPC rebase %s = %.1f difiere de referencia %.1f (INDEC reviso la serie?)", m, r, ref)
        )
      }
    } else {
      test_fail(e, "faltan meses de la ventana base ene-23:sep-23 en la serie IPC")
    }
  }
}

test_finish(e)
