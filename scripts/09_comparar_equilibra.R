# Fase 6 — comparacion con datos publicados de Equilibra (2026).
#
# Datos de Equilibra recopilados de notas (Perfil, ElArgentino, Bloomberg Linea,
# notiar, La Nacion) sobre los informes mensuales. Niveles publicados (base
# ene-sep-23 = 100) y variaciones por segmento. NO son series completas: se
# encadenan los m/m desde el nivel publicado de may-26 para el total, y los m/m
# por segmento se indexan por separado (forma, no nivel).
#
# Salida: output/grafico_comparacion_equilibra.png + tabla en consola

repo_root <- getOption("repo_root", ".")

## Datos Equilibra (fuentes: notas sobre informes mensuales 2026)
eq <- list(
  total = data.frame(
    mes = c("2026-03", "2026-04", "2026-05", "2026-06"),
    real_mm = c(0.1, 0.7, -1.4, -0.2),      # ingreso real IPC ENGHo 17/18, m/m %
    disp_mm = c(-0.4, 0.8, -2.1, -0.5)      # ingreso disponible, m/m %
  ),
  niveles = data.frame(                      # niveles publicados (base 100)
    mes = c("2026-05", "2026-06"),
    real = c(89.4, 89.1),
    disp = c(83.5, 83.1),
    real04 = c(91.6, 91.5)
  ),
  segmentos = data.frame(                    # disponible m/m % por segmento
    mes = c("2026-04", "2026-05", "2026-06", "2026-04", "2026-05", "2026-06", "2026-04", "2026-05", "2026-06"),
    seg = rep(c("priv", "pub", "jub"), each = 3),
    disp_mm = c(1.6, -3.0, -1.4, -1.1, -1.3, 2.1, -0.45, 1.35, 0.5)  # jub = promedio de min y resto
  )
)

## Encadenar el total desde el nivel de may-26
encadenar <- function(meses, mm, ancla_mes, ancla_valor) {
  idx <- which(meses == ancla_mes)
  v <- rep(NA_real_, length(meses))
  v[idx] <- ancla_valor
  for (i in (idx - 1):1) v[i] <- v[i + 1] / (1 + mm[i + 1] / 100)  # v[i] = v[i+1]/(1+mm[i+1])
  for (i in (idx + 1):length(meses)) v[i] <- v[i - 1] * (1 + mm[i] / 100)
  setNames(v, meses)
}
eq_total_real <- encadenar(eq$total$mes, eq$total$real_mm, "2026-05", 89.4)
eq_total_disp <- encadenar(eq$total$mes, eq$total$disp_mm, "2026-05", 83.5)

## Nuestras series
leer <- function(f) {
  d <- read.csv(file.path(repo_root, "output", f))
  setNames(d$valor, substr(d$fecha, 1, 7))
}
B <- leer("serie_ingreso_real_ipc2017.csv")
C <- leer("serie_ingreso_disponible.csv")
A <- leer("serie_ingreso_real_ipc2004.csv")

cat("Comparacion total (2026):\n")
cat("mes    | real Eq | real nuestro | disp Eq | disp nuestro\n")
for (m in c("2026-03", "2026-04", "2026-05", "2026-06")) {
  cat(sprintf("%s | %6.1f | %6.1f | %6.1f | %6.1f\n", m, eq_total_real[[m]], B[[m]], eq_total_disp[[m]], C[[m]]))
}

## Nuestros segmentos disponibles (m/m) para comparar con los de Equilibra
ynom <- read.csv(file.path(repo_root, "data", "work", "ynom_mensual.csv"))
ipc17 <- setNames(read.csv(file.path(repo_root, "data", "work", "ipc2017.csv"))$ipc2017_rel,
                  substr(read.csv(file.path(repo_root, "data", "work", "ipc2017.csv"))$fecha, 1, 7))
sdf <- read.csv(file.path(repo_root, "data", "work", "s_canasta_fija.csv"))
s <- setNames(sdf$s, sdf$mes)
mm_nuestro <- function(col, m) {
  v <- setNames(ynom[[col]], substr(ynom$fecha, 1, 7))
  r <- v / ipc17[names(v)] * 100
  d <- r * (1 - s[names(r)])
  (d[[m]] / d[[format(as.Date(paste0(m, "-01")) - 1, "%Y-%m")]] - 1) * 100
}
cat("\nDisponible m/m por segmento (Eq vs nuestro):\n")
cat("mes    | priv Eq | priv nro | pub Eq | pub nro | jub Eq | jub nro\n")
for (m in c("2026-04", "2026-05", "2026-06")) {
  eqv <- eq$segmentos[eq$segmentos$mes == m, ]
  cat(sprintf("%s | %+5.1f | %+5.1f | %+5.1f | %+5.1f | %+5.1f | %+5.1f\n", m,
      eqv$disp_mm[eqv$seg == "priv"], mm_nuestro("priv_rel", m),
      eqv$disp_mm[eqv$seg == "pub"], mm_nuestro("pub_rel", m),
      eqv$disp_mm[eqv$seg == "jub"], mm_nuestro("jub_rel", m)))
}

## Grafico comparativo total
png(file.path(repo_root, "output", "grafico_comparacion_equilibra.png"), width = 1250, height = 750, res = 110)
par(mar = c(6, 4, 4, 6))
meses_lbl <- format(seq(as.Date("2026-03-01"), as.Date("2026-06-01"), by = "month"), "%b-26")
fechas <- as.Date(paste0(c("2026-03", "2026-04", "2026-05", "2026-06"), "-01"))
plot(fechas, eq_total_real, type = "b", pch = 16, col = "black", ylim = c(80, 95),
     xaxt = "n", xlab = "", ylab = "Índice (base ene-sep-23 = 100)",
     main = "Comparación Equilibra (publicado) vs nuestra reconstrucción — 2026")
axis(1, at = fechas, labels = meses_lbl, las = 2)
lines(fechas, eq_total_disp, type = "b", pch = 16, col = "red2", lwd = 2)
lines(fechas, B[c("2026-03", "2026-04", "2026-05", "2026-06")], type = "b", pch = 1, col = "black", lty = 2)
lines(fechas, C[c("2026-03", "2026-04", "2026-05", "2026-06")], type = "b", pch = 1, col = "red2", lty = 2)
legend("bottomleft", bty = "n", lwd = 2,
       legend = c("Real Equilibra (puntos)", "Disponible Equilibra (puntos)", "Real nuestro (linea)", "Disponible nuestro (linea)"),
       col = c("black", "red2", "black", "red2"), lty = c(1, 1, 2, 2), pch = c(16, 16, 1, 1))
dev.off()
cat("\nGráfico: output/grafico_comparacion_equilibra.png\n")