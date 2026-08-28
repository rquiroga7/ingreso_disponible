# Fase 5b — ingreso disponible por segmento: privados registrados,
# público nacional y público provincial.
#
# Fuentes de ingreso por segmento:
#  - priv_formal : IST privado registrado nominal (data/work/admin_series.csv, script 02)
#  - pub_nac     : IST subsector publico nacional (variaciones m/m encadenadas desde ene-22)
#  - pub_prov    : IST subsector publico provincial (idem; incluye municipales, unico corte
#                  publicado por INDEC)
# Los subsectores se difunden desde jun-25 (series desde ene-22, excluyen universidades
# nacionales en el caso del nacional). Fuente:
#   https://www.indec.gob.ar/ftp/cuadros/sociedad/variacion_indice_salarios.csv
#
# Disponible por segmento: misma mecanica que scripts/06 (F2) con el g0 a priori ENGHo
# (data/work/g0_calibrado.csv) aplicado como proporcion del ingreso de cada
# segmento (supuesto: misma incidencia de gastos fijos; no hay canasta por segmento).
#
# Salida: output/grafico_disponible_segmentos.png
#         output/serie_disponible_segmentos.csv (fecha, priv_formal, pub_nacional, pub_provincial)

repo_root <- getOption("repo_root", ".")
source(file.path(repo_root, "R", "rebase_index.R"))

ventana <- sprintf("2023-0%d", 1:9)
target <- format(seq(as.Date("2023-01-01"), as.Date("2026-06-01"), by = "month"), "%Y-%m")

## 1) IST variaciones por subsector (cache-first)
cache_csv <- file.path(repo_root, "data", "raw", "salarios", "variacion_indice_salarios.csv")
dir.create(dirname(cache_csv), recursive = TRUE, showWarnings = FALSE)
if (!file.exists(cache_csv)) {
  download.file(
    "https://www.indec.gob.ar/ftp/cuadros/sociedad/variacion_indice_salarios.csv",
    cache_csv, quiet = TRUE
  )
}
istv <- read.csv(cache_csv, sep = ";", dec = ",", na.strings = "NA")
istv$mes <- format(as.Date(istv$periodo, "%d/%m/%Y"), "%Y-%m")

encadenar <- function(vm) {
  # indice nivel = producto acumulado de (1 + v_m/100); arranca en el primer mes con dato
  i0 <- which(!is.na(vm))[1]
  idx <- rep(NA_real_, length(vm))
  idx[i0] <- 100
  for (t in (i0 + 1):length(vm)) idx[t] <- idx[t - 1] * (1 + vm[t] / 100)
  setNames(idx, istv$mes)
}

pub_nac <- rebase_index(encadenar(istv$v_m_subsector_publico_nacional), istv$mes)
pub_prov <- rebase_index(encadenar(istv$v_m_subsector_publico_provincial), istv$mes)

## 2) Privado: misma serie del pipeline (script 03, cola may/jun-26 ya extendida)
ynom <- read.csv(file.path(repo_root, "data", "work", "ynom_mensual.csv"))
priv <- rebase_index(ynom$priv_rel, substr(ynom$fecha, 1, 7))

## 2b) Universidades: proxy con la escala salarial PROFASIS (CONICET, personal de apoyo)
##     — replica los acuerdos salariales universitarios (p.ej. +21,3% jun-26). La escala
##     es escalonada: el mes faltante se completa por arrastre del valor previo.
univ_raw <- read.csv("/home/rquiroga/github/salarios_CONICET/datos/crudo_profasis.csv")
univ_raw$mes <- format(as.Date(univ_raw$fecha), "%Y-%m")
univ <- setNames(univ_raw$salario, univ_raw$mes)
univ <- univ[order(names(univ))]
faltantes <- setdiff(target, names(univ))
for (m in faltantes) {
  prev <- max(names(univ)[names(univ) < m & !is.na(univ)])
  univ[[m]] <- univ[[prev]]
}
univ <- univ[order(names(univ))]
univ <- rebase_index(univ[target], target)

## 3) Cross-check: nac+prov ponderados por poblacion EPH (split t234, t231-33 no tienen
##    PP04A1) vs sector publico total del mismo archivo
num <- function(x) suppressWarnings(as.numeric(x))
ind234 <- read.table(file.path(repo_root, "data", "raw", "eph", "t234", "usu_individual_t234.txt"),
  sep = ";", dec = ",", header = TRUE, fill = TRUE, comment.char = "",
  colClasses = "character", fileEncoding = "UTF-8"
)
names(ind234) <- toupper(names(ind234))
est234 <- num(ind234$ESTADO) == 1 & num(ind234$CAT_OCUP) == 3 &
  num(ind234$PP04A) == 1 & num(ind234$PP07H) == 1
a1234 <- num(ind234$PP04A1)
pn234 <- num(ind234$PONDERA)
w_nac <- sum(pn234[est234 & a1234 == 1]) / sum(pn234[est234 & a1234 %in% c(1, 2, 3)])
pub_total <- rebase_index(istv$v_m_sector_publico |> encadenar(), istv$mes)
mezcla <- w_nac * pub_nac + (1 - w_nac) * pub_prov
cat(sprintf("Pesos publico (EPH t234): nacional %.1f%% / provincial+municipal %.1f%%\n", w_nac * 100, (1 - w_nac) * 100))
cat(sprintf("Cross-check jun-26: mezcla nac+prov %.1f vs publico total %.1f (dif %+.1f%%)\n",
            mezcla[["2026-06"]], pub_total[["2026-06"]], (mezcla[["2026-06"]] / pub_total[["2026-06"]] - 1) * 100))

## 4) Disponible por segmento: disp = B_seg * (1 - s(t)); s(t) de scripts/06 (ENGHo + precios relativos)
sdf <- read.csv(file.path(repo_root, "data", "work", "s_canasta_fija.csv"))
s <- setNames(sdf$s, sdf$mes)
ipc17 <- setNames(read.csv(file.path(repo_root, "data", "work", "ipc2017.csv"))$ipc2017_rel,
                  substr(read.csv(file.path(repo_root, "data", "work", "ipc2017.csv"))$fecha, 1, 7))

disponible <- function(idx) {
  B <- idx[target] / ipc17[target] * 100
  B <- B / mean(B[names(B) <= "2023-09"]) * 100
  rebase_index(B * (1 - s[target]), target)
}
disp_priv <- disponible(priv)
disp_nac <- disponible(pub_nac)
disp_prov <- disponible(pub_prov)
disp_univ <- disponible(univ)

## 5) Salidas
fechas <- as.Date(paste0(target, "-01"))
write.csv(data.frame(
  fecha = fechas,
  priv_formal = as.numeric(disp_priv),
  pub_nacional = as.numeric(disp_nac),
  pub_provincial = as.numeric(disp_prov),
  universidades = as.numeric(disp_univ)
), file.path(repo_root, "output", "serie_disponible_segmentos.csv"), row.names = FALSE)

png(file.path(repo_root, "output", "grafico_disponible_segmentos.png"), width = 1100, height = 825, res = 110)
nota <- paste(
  "Ingreso disponible = ingreso del segmento menos gastos fijos (alquiler, expensas, tarifas de luz/gas/agua, transporte, comunicaciones, educación y medicina prepaga), deflactado por IPC.",
  "Ingresos: Índice de Salarios INDEC — privados registrados; subsectores público nacional (sin universidades) y provincial (incluye municipales), series desde ene-2022.",
  "Universidades: serie salarial construida en base a actas de paritarias universitarias.",
  "Base: promedio ene-23:sep-23 = 100. Por Rodrigo Quiroga @rquiroga777"
)
lineas_nota <- strwrap(nota, width = 178)
par(mar = c(5.2 + 0.75 * length(lineas_nota), 4, 4, 1))
mes_lbl <- format(fechas, "%b-%y")
plot(fechas, disp_priv, type = "n",
     ylim = range(c(disp_priv, disp_nac, disp_prov, disp_univ)) + c(-1, 1),
     xlim = range(fechas) + c(-5, 65), xaxt = "n", xlab = "", ylab = "",
     main = "Ingreso disponible por segmento (IPC ENGHo 2017/18)\nPrivados registrados, público nacional, provincial y universidades")
mtext("Índice", side = 2, line = 2.2, cex = 1.3)
abline(h = axTicks(2), col = "grey90")
axis(1, at = fechas, labels = mes_lbl, las = 2, cex.axis = 0.85)
lines(fechas, disp_priv, col = "grey40", lwd = 2.5)
lines(fechas, disp_nac, col = "blue3", lwd = 2.5)
lines(fechas, disp_prov, col = "darkorange2", lwd = 2.5)
lines(fechas, disp_univ, col = "darkgreen", lwd = 2.5)
abline(h = 100, col = "grey80", lty = 2)
  text(tail(fechas, 1) + 40, tail(disp_priv, 1), sprintf("%.1f", tail(disp_priv, 1)), adj = c(0.5, 0.5), cex = 1.1, font = 2, col = "grey30")
  text(tail(fechas, 1) + 40, tail(disp_nac, 1), sprintf("%.1f", tail(disp_nac, 1)), adj = c(0.5, 0.5), cex = 1.1, font = 2, col = "blue3")
  text(tail(fechas, 1) + 40, tail(disp_prov, 1), sprintf("%.1f", tail(disp_prov, 1)), adj = c(0.5, 0.5), cex = 1.1, font = 2, col = "darkorange2")
  text(tail(fechas, 1) + 40, tail(disp_univ, 1), sprintf("%.1f", tail(disp_univ, 1)), adj = c(0.5, 0.5), cex = 1.1, font = 2, col = "darkgreen")
legend("topright", bty = "n", lwd = 2.5, col = c("grey40", "blue3", "darkorange2", "darkgreen"),
       legend = c("Asalariados privados registrados", "Público nacional (sin universidades)", "Público provincial y municipal", "Universidades"))
for (i in seq_along(lineas_nota)) {
  mtext(lineas_nota[i], side = 1, line = 4.8 + (i - 1) * 0.75, cex = 0.62, adj = 0)
}
dev.off()
cat("Gráfico: output/grafico_disponible_segmentos.png\n")
cat("Anclas por segmento:\n")
for (s in c("disp_priv", "disp_nac", "disp_prov", "disp_univ")) {
  d <- get(s)
  cat(sprintf("  %-10s feb-24 %.1f | jun-25 %.1f | jun-26 %.1f\n", s, d[["2024-02"]], d[["2025-06"]], d[["2026-06"]]))
}
