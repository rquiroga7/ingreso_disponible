# Fase 5c — ingreso real y disponible por segmento (priv, pub, jub).
#
# Los tres segmentos del universo (MASA DE INGRESO de la ventana base):
#   priv = SIPA remuneracion promedio priv registrado (SST, desestacionalizado STL)
#   pub  = IST publico registrado (INDEC, cola con m/m propio)
#   jub  = media previsional EPH interpolada + cola con haber minimo
#
#   real(t) = seg_rel(t) / ipc17(t)            (rebase ventana = 100)
#   disp(t) = real(t) * (1 - s(t))             (rebase ventana = 100)
# donde s(t) = g0 * [pf/ng](t)/[pf/ng](oct-2018) de scripts/06 (ENGHo + precios relativos).
#
# Salida: output/grafico_ingreso_real_segmentos.png
#         output/grafico_ingreso_disponible_segmentos.png

repo_root <- getOption("repo_root", ".")
source(file.path(repo_root, "R", "rebase_index.R"))

ventana <- sprintf("2023-0%d", 1:9)
target <- format(seq(as.Date("2023-01-01"), as.Date("2026-06-01"), by = "month"), "%Y-%m")

ynom <- read.csv(file.path(repo_root, "data", "work", "ynom_mensual.csv"))
ipc17 <- setNames(read.csv(file.path(repo_root, "data", "work", "ipc2017.csv"))$ipc2017_rel,
                  substr(read.csv(file.path(repo_root, "data", "work", "ipc2017.csv"))$fecha, 1, 7))
sdf <- read.csv(file.path(repo_root, "data", "work", "s_canasta_fija.csv"))
s <- setNames(sdf$s, sdf$mes)

segmentos <- c(priv = "priv_rel", pub = "pub_rel", jub = "jub_rel")

real_seg <- lapply(segmentos, function(col) {
  v <- setNames(ynom[[col]], substr(ynom$fecha, 1, 7))[target]
  rebase_index(v / ipc17[target] * 100, target)
})
disp_seg <- lapply(real_seg, function(r) {
  rebase_index(r * (1 - s[target]), target)
})

colores <- c(priv = "grey40", pub = "blue3", jub = "darkorange2")
etiquetas <- c(priv = "Asalariados privados registrados", pub = "Empleados públicos", jub = "Jubilados y pensionados")

graficar <- function(series, titulo, archivo, nota) {
  fechas <- as.Date(paste0(names(series[[1]]), "-01"))
  mes_lbl <- format(fechas, "%b-%y")
  lineas_nota <- strwrap(nota, width = 178)
  png(file.path(repo_root, "output", archivo), width = 1250, height = 820, res = 110)
  par(mar = c(5.2 + 0.75 * length(lineas_nota), 4, 4, 6))
  ylim <- range(unlist(series), na.rm = TRUE)
  plot(fechas, series[[1]], type = "n", ylim = ylim,
       xlim = range(fechas) + c(-5, 56), xaxt = "n", xlab = "", ylab = "",
       main = titulo)
  mtext("Índice", side = 2, line = 2.2, cex = 1.3)
  abline(h = axTicks(2), col = "grey90")
  axis(1, at = fechas, labels = mes_lbl, las = 2, cex.axis = 0.85)
  for (seg in names(series)) {
    lines(fechas, series[[seg]], col = colores[[seg]], lwd = 2.5)
    text(tail(fechas, 1) + 30, tail(series[[seg]], 1), sprintf("%.1f", tail(series[[seg]], 1)),
         adj = c(0.5, 0.5), cex = 1.1, font = 2, col = colores[[seg]])
  }
  abline(h = 100, col = "grey80", lty = 2)
  legend("bottomleft", bty = "n", lwd = 2.5, col = colores[names(series)],
         legend = etiquetas[names(series)])
  for (i in seq_along(lineas_nota)) {
    mtext(lineas_nota[i], side = 1, line = 4.8 + (i - 1) * 0.75, cex = 0.62, adj = 0)
  }
  dev.off()
}

nota_real <- paste(
  "Ingreso real por segmento = ingreso del segmento deflactado por el IPC ENGHo 2017/18 (división 04 reponderada por grupos).",
  "Ingresos: SIPA (SST) para privados registrados; IST público (INDEC) para empleados públicos; EPH + haber mínimo para jubilados.",
  "Pesos por masa de ingreso SIPA (priv 64% / pub 23% / jub 12%). Base: promedio ene-23:sep-23 = 100.",
  "Por Rodrigo Quiroga @rquiroga777"
)
graficar(real_seg, "Ingreso real por segmento (IPC ENGHo 2017/18)\nPrivados registrados, empleados públicos y jubilados",
         "grafico_ingreso_real_segmentos.png", nota_real)

nota_disp <- paste(
  "Ingreso disponible por segmento = ingreso real menos gastos fijos (alquiler, expensas, tarifas de luz/gas/agua, transporte, comunicaciones, educación y medicina prepaga).",
  "La participación de los gastos fijos en el ingreso (g0 = 31% de la ENGHo 2017/18) se actualiza con la inflación de la canasta fija vs el nivel general desde oct-2018.",
  "Ingresos: SIPA (SST) privados registrados; IST público (INDEC); EPH + haber mínimo jubilados. Base: promedio ene-23:sep-23 = 100.",
  "Por Rodrigo Quiroga @rquiroga777"
)
graficar(disp_seg, "Ingreso disponible por segmento (IPC ENGHo 2017/18)\nPrivados registrados, empleados públicos y jubilados",
         "grafico_ingreso_disponible_segmentos.png", nota_disp)

cat("Gráficos: output/grafico_ingreso_real_segmentos.png | output/grafico_ingreso_disponible_segmentos.png\n")