# Estadisticas por segmento del universo Equilibra para un trimestre EPH.
#
# eph_segmento_stats(ind) -> data.frame de 3 filas (segmento, poblacion, ingreso_medio)
#
# Universo "formal" (variante estricta del PLAN 7.1):
#   priv_formal : ESTADO==1 & CAT_OCUP==3 & PP04A==2 (privado) & PP07H==1 (aportes)
#   publico     : ESTADO==1 & CAT_OCUP==3 & PP04A==1 (estatal) & PP07H==1
#   jubilado    : ESTADO!=1 & pension>0
# Ingreso: P21>=0 para ocupados; monto previsional (suma V2_*) para jubilados.
# Codigos negativos de ingreso se tratan como 0 (skill EPH-INDEC).

eph_segmento_stats <- function(ind) {
  es_ocup <- ind$estado == 1 & ind$cat_ocup == 3
  ing_lab <- ifelse(es_ocup, ifelse(is.na(ind$p21) | ind$p21 < 0, 0, ind$p21), 0)
  pen <- ifelse(is.na(ind$pension), 0, ind$pension)

  segs <- list(
    priv_formal = es_ocup & ind$pp04a == 2 & ind$pp07h == 1,
    publico = es_ocup & ind$pp04a == 1 & ind$pp07h == 1,
    jubilado = ind$estado != 1 & !is.na(ind$pension) & ind$pension > 0
  )

  do.call(rbind, lapply(names(segs), function(s) {
    u <- segs[[s]]
    ing <- if (s == "jubilado") pen else ing_lab + pen * (u & !is.na(ind$pension) & ind$pension > 0)
    # jubilados: solo el haber; asalariados que ademas cobran pension suman ambos
    data.frame(
      segmento = s,
      poblacion = sum(ind$pondera[u]),
      ingreso_medio = stats::weighted.mean(ing[u], ind$pondera[u])
    )
  }))
}
