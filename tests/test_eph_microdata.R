# Test: integridad de los microdatos EPH descargados (data/raw/eph/)
#
# Layout canonico (t{yy}{q} = año yy, trimestre q; p.ej. t231 = 2023T1):
#   data/raw/eph/t{yy}{q}/usu_individual_t{yy}{q}.txt
#   data/raw/eph/t{yy}{q}/usu_hogar_t{yy}{q}.txt
# Acepta ademas .csv con el mismo contenido. Si no hay nada descargado, el test
# hace SKIP. Los trimestres de 2026 son opcionales (t262 = 2026T2 se publica
# ~sep-2026; t261 ya esta publicado): su ausencia no es un fallo.

repo_root <- getOption("repo_root", ".")
if (!exists("test_env_new", envir = globalenv())) {
  source(file.path(repo_root, "tests", "helper.R"))
}
e <- test_setup("eph_microdata")

eph_dir <- file.path(repo_root, "data", "raw", "eph")
if (!dir.exists(eph_dir) || length(list.files(eph_dir, recursive = TRUE)) == 0) {
  test_skip(e, "data/raw/eph/ vacio: microdatos aun no descargados (Fase 1)")
} else {
  trimestres <- sprintf("t%d%d", rep(23:26, each = 4), 1:4)

  required_ind <- c(
    "CODUSU", "NRO_HOGAR", "COMPONENTE", "PONDERA", "ESTADO",
    "CAT_OCUP", "CH06", "P21", "P47T"
  )
  required_hog <- c("CODUSU", "NRO_HOGAR", "PONDERA", "II7", "ITF", "IX_TOT")
  pension_vars <- c("V2_M", "V2_1", "V2_1_M", "V2_01_M")

  find_base <- function(dir_q, base) {
    candidatos <- list.files(dir_q, pattern = base, recursive = TRUE, full.names = TRUE)
    candidatos <- candidatos[grepl("\\.(txt|csv)$", candidatos, ignore.case = TRUE)]
    if (length(candidatos) == 0) NULL else candidatos[1]
  }

  read_base <- function(f) {
    read.table(
      f,
      sep = ";", dec = ",", header = TRUE, fill = TRUE,
      comment.char = "",
      colClasses = "character", fileEncoding = "UTF-8"
    )
  }

  num <- function(x) suppressWarnings(as.numeric(x))

  for (id in trimestres) {
    dir_q <- file.path(eph_dir, id)
    f_ind <- if (dir.exists(dir_q)) find_base(dir_q, "individual") else NULL
    f_hog <- if (dir.exists(dir_q)) find_base(dir_q, "hogar") else NULL

    if (is.null(f_ind) || is.null(f_hog)) {
      if (grepl("^t26", id)) {
        test_skip(e, paste0(id, ": aun no publicado (esperado ~2 meses tras el trimestre)"))
      } else {
        test_fail(e, paste0(id, ": faltan bases (individual o hogar) en data/raw/eph/", id))
      }
      next
    }

    ind <- tryCatch(read_base(f_ind), error = function(err) NULL)
    hog <- tryCatch(read_base(f_hog), error = function(err) NULL)
    if (is.null(ind) || is.null(hog)) {
      test_fail(e, paste0(id, ": no se pudieron leer las bases (formato inesperado)"))
      next
    }
    names(ind) <- toupper(names(ind))
    names(hog) <- toupper(names(hog))

    faltan_ind <- setdiff(required_ind, names(ind))
    test_assert(
      e,
      length(faltan_ind) == 0,
      paste0(id, " individual: columnas clave presentes"),
      paste0(id, " individual: faltan columnas: ", paste(faltan_ind, collapse = ", "))
    )
    faltan_hog <- setdiff(required_hog, names(hog))
    test_assert(
      e,
      length(faltan_hog) == 0,
      paste0(id, " hogar: columnas clave presentes"),
      paste0(id, " hogar: faltan columnas: ", paste(faltan_hog, collapse = ", "))
    )
    tiene_pension <- length(intersect(pension_vars, names(ind))) > 0
    test_assert(
      e,
      tiene_pension,
      paste0(id, " individual: variable de jubilacion/pension presente"),
      paste0(id, " individual: sin variable de jubilacion/pension (V2_1 / V2_1_M / V2_01_M)")
    )

    n_ind <- nrow(ind)
    test_assert(
      e,
      n_ind >= 40000 && n_ind <= 90000,
      sprintf("%s individual: %d filas en rango [40k, 90k]", id, n_ind),
      sprintf("%s individual: %d filas fuera de rango [40k, 90k]", id, n_ind)
    )

    pondera <- num(ind$PONDERA)
    pop <- sum(pondera[!is.na(pondera)])
    test_assert(
      e,
      pop >= 25e6 && pop <= 40e6,
      sprintf("%s: suma PONDERA = %.1f M en rango [25, 40] M", id, pop / 1e6),
      sprintf("%s: suma PONDERA = %.1f M fuera de rango [25, 40] M (pesos mal leidos?)", id, pop / 1e6)
    )

    p21 <- num(ind$P21)
    test_assert(
      e,
      all(p21[!is.na(p21)] >= -9),
      paste0(id, " individual: P21 sin valores por debajo de -9 (codigos respetados)"),
      paste0(id, " individual: P21 tiene valores < -9 (parseo roto?)")
    )

    n_hog <- nrow(hog)
    test_assert(
      e,
      n_hog >= 15000 && n_hog <= 45000,
      sprintf("%s hogar: %d filas en rango [15k, 45k]", id, n_hog),
      sprintf("%s hogar: %d filas fuera de rango [15k, 45k]", id, n_hog)
    )

    itf <- num(hog$ITF)
    test_assert(
      e,
      all(itf[!is.na(itf)] >= -9),
      paste0(id, " hogar: ITF sin valores por debajo de -9"),
      paste0(id, " hogar: ITF tiene valores < -9 (parseo roto?)")
    )

    test_ok(e, sprintf("%s: individual=%s | hogar=%s", id, basename(f_ind), basename(f_hog)))
  }
}

test_finish(e)
