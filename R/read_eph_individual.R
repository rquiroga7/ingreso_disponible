# Lee la base individual usuaria de un trimestre EPH.
#
# read_eph_individual(repo_root, id) -> data.frame con columnas clave numericas.
#   id: trimestre canonico t{yy}{q} (p.ej. t231 = 2023T1).
# Los ingresos negativos son codigos (-7/-8/-9): se pasan a NA aqui y cada uso
# decide si tratarlos como 0.

read_eph_individual <- function(repo_root, id) {
  f <- file.path(repo_root, "data", "raw", "eph", id, sprintf("usu_individual_%s.txt", id))
  ind <- read.table(
    f, sep = ";", dec = ",", header = TRUE, fill = TRUE,
    comment.char = "", colClasses = "character", fileEncoding = "UTF-8"
  )
  names(ind) <- toupper(names(ind))

  num <- function(x) suppressWarnings(as.numeric(x))
  out <- data.frame(
    pondera = num(ind$PONDERA),
    estado = num(ind$ESTADO),
    cat_ocup = num(ind$CAT_OCUP),
    pp04a = num(ind$PP04A),
    pp07h = num(ind$PP07H),
    ch06 = num(ind$CH06),
    nivel_ed = num(ind$NIVEL_ED),
    ch04 = num(ind$CH04),
    p21 = num(ind$P21),
    p47t = num(ind$P47T),
    imputa = num(ind$IMPUTA),
    intensi = num(ind$INTENSI),
    stringsAsFactors = FALSE
  )

  vcols <- grep("^V2(_M|_[0-9]+_M)$", names(ind), value = TRUE)
  pen <- rowSums(sapply(ind[vcols], num), na.rm = TRUE)
  out$pension <- ifelse(pen < 0, NA, pen)
  out
}
