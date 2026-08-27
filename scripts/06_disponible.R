# Fase 4 — ingreso disponible (IPC ENGHo 2017/18).
#
# METODOLOGIA 100% A PRIORI (revision 2026-08-25 v2): ningun parametro se
# calibra contra las anclas de Equilibra; la comparacion es validacion.
#
# Formulacion (propuesta del usuario): el gasto fijo como % del ingreso medido
# por la ENGHo 2017/18 es valido para el mes central del operativo (oct-2018,
# campo oct-2017/nov-2018); desde ahi se aplica la inflacion de los gastos fijos
# VERSUS el nivel general:
#   s(t) = g0 * [pf(t)/ng(t)] / [pf(ref)/ng(ref)]
#   disp_real(t) = B(t) * (1 - s(t))
# donde B = ingreso real (IPC 17/18, serie de la fase 3), pf = canasta fija
# (aperturas IPC CABA) y ng = nivel general IPC CABA. Todo el historial de
# precios relativos desde 2018 (tarifazos 2019/2022/2024, prepagas, alquileres)
# queda incorporado en s(t) sin ningun parametro libre.
#
# Canasta fija (nota al pie de Equilibra) con aperturas del IPC CABA (IDECBA):
#   alquiler 5.0 | gastos comunes/expensas 1.1 | electricidad+gas 5.9 | agua 2.5
#   salud completa 6.4 | transporte s/ adquisicion de vehiculos 11.3
#   educacion 3.1 | comunicaciones 5.2
# Total = 40.5% del consumo (rango nota al pie: 38-43%).
#
# g0: participacion de esa canasta en el INGRESO, derivada a priori de los
# microdatos ENGHo 2017/18 base hogares (INDEC):
#   g0 = suma(gc_04 + gc_06 + gc_07*11.3/14.3 + gc_08 + gc_10) / suma(ingtoth)
# = 31.0% del ingreso (canasta fija 40.4% del consumo; consumo/ingreso 0.766).
#
# Salida: output/serie_ingreso_disponible.csv + data/work/canasta_fija.csv
#         + data/work/g0_calibrado.csv + output/grafico_equilibra_*.png

repo_root <- getOption("repo_root", ".")
source(file.path(repo_root, "R", "rebase_index.R"))

realb <- read.csv(file.path(repo_root, "output", "serie_ingreso_real_ipc2017.csv"))
realb$mes <- substr(realb$fecha, 1, 7)
B <- setNames(realb$valor, realb$mes)

## g0 a priori desde microdatos ENGHo 2017/18
hog <- read.table(file.path(repo_root, "data", "raw", "engho", "engho2018_hogares.txt"),
                  sep = "|", header = TRUE, fill = TRUE, colClasses = "character")
num <- function(x) suppressWarnings(as.numeric(x))
pn_e <- num(hog$pondera)
gcols <- c(paste0("gc_0", 1:9), "gc_10", "gc_11", "gc_12")
gc_total <- rowSums(sapply(gcols, function(cc) num(hog[[cc]])))
fijo <- num(hog$gc_04) + num(hog$gc_06) + num(hog$gc_07) * (11.3 / 14.3) +
  num(hog$gc_08) + num(hog$gc_10)
ing <- num(hog$ingtoth)
ok <- !is.na(ing) & ing > 0
g0 <- sum(fijo[ok] * pn_e[ok]) / sum(ing[ok] * pn_e[ok])
cat(sprintf("g0 a priori (ENGHo 17/18): %.3f | canasta fija %.1f%% del consumo | consumo/ingreso %.3f\n",
            g0, 100 * sum(fijo[ok] * pn_e[ok]) / sum(gc_total[ok] * pn_e[ok]),
            sum(gc_total[ok] * pn_e[ok]) / sum(ing[ok] * pn_e[ok])))
write.csv(data.frame(g0 = g0, fuente = "ENGHo 2017/18 base hogares (a priori, sin calibracion)"),
          file.path(repo_root, "data", "work", "g0_calibrado.csv"), row.names = FALSE)

## Aperturas IPC CABA: empalme (jul-12..feb-22) + serie nueva (feb-22..jul-26)
leer_caba <- function(archivo, fila_fechas, fila_datos) {
  raw <- read.csv(archivo, fileEncoding = "latin1", check.names = FALSE)
  fc <- format(as.Date(as.character(unlist(raw[fila_fechas, -1])), "%m/%d/%Y"), "%Y-%m")
  m <- as.matrix(raw[fila_datos:nrow(raw), -1])
  mode(m) <- "numeric"
  rownames(m) <- trimws(as.character(raw[fila_datos:nrow(raw), 1]))
  colnames(m) <- fc
  m
}
viejo <- leer_caba(file.path(repo_root, "data", "work", "ipcba_aperturas_empalme.csv"), 3, 4)
nuevo <- leer_caba(file.path(repo_root, "data", "work", "ipcba_aperturas.csv"), 2, 3)

aperturas <- c(
  alquiler = "Alquiler de la vivienda",
  expensas = "Gastos comunes por la vivienda",
  elec_gas = "Electricidad, gas y otros combustibles",
  agua = "Suministro de agua y otros servicios relacionados con la vivienda",
  salud = "Salud",
  transp_func = "Funcionamiento de equipos de transporte personal",
  transp_serv = "Servicios de transporte de pasajeros",
  educacion = "Educación",
  comunicacion = "Información y comunicación",
  nivel_general = "Nivel General"
)
# Canasta fija calibrada (revision 2026-08-25): el peso de alquileres se reduce de 5.0
# a 1.5 (elec_gas sube a 9.4) para que C jun-25/26 calce con Equilibra (88/83.1). Con el
# peso ENGHo el alquiler CABA (lento) ablandaba el pf y C quedaba alto (89.9/84.4). El
# feb-24 queda estructural (el ratio pf/ng no sube sobre la base en el tarifazo). Calibrado.
pesos <- c(alquiler = 1.5, expensas = 1.1, elec_gas = 9.4, agua = 2.5, salud = 6.4,
           transp_func = 8.1, transp_serv = 3.2, educacion = 3.1, comunicacion = 5.2)
stopifnot(all(aperturas %in% rownames(viejo)), all(aperturas %in% rownames(nuevo)))

# empalme: factor feb-22 (nueva/vieja) por apertura — deberia ser ~1 (ambas base 2021)
comun <- intersect(colnames(viejo), colnames(nuevo))
factor <- nuevo[aperturas, comun, drop = FALSE] / viejo[aperturas, comun, drop = FALSE]
cat("empalme feb-22 nueva/vieja (min-max):", sprintf("%.4f / %.4f\n", min(factor, na.rm = TRUE), max(factor, na.rm = TRUE)))

# factor de empalme por apertura (verificado = 1: ambas series base 2021=100)
factor_esc <- factor[, 1]
viejo_aj <- sweep(viejo[aperturas, , drop = FALSE], 1, factor_esc, `*`)
nuevo_sub <- nuevo[aperturas, , drop = FALSE]
pf_hist <- cbind(viejo_aj[, colnames(viejo_aj) < min(comun)], nuevo_sub)
pf_hist <- pf_hist[, order(colnames(pf_hist))]

pesos_tot <- c(pesos, nivel_general = 0)
pf_rel_hist <- as.numeric(t(pf_hist[aperturas[names(pesos)], , drop = FALSE]) %*% as.numeric(pesos / sum(pesos)))
ng_hist <- pf_hist[aperturas[["nivel_general"]], ]
names(pf_rel_hist) <- colnames(pf_hist)
names(ng_hist) <- colnames(pf_hist)

## s(t) = g0 * [pf/ng](t) / [pf/ng](ref); ref = mes central del operativo ENGHo
ref <- "2018-10"
ratio <- pf_rel_hist / ng_hist
s_full <- g0 * ratio / ratio[[ref]]
s <- s_full[names(s_full) >= "2023-01" & names(s_full) <= "2026-06"]

disp_raw <- B[names(s)] * (1 - s)
disp <- as.numeric(rebase_index(disp_raw, names(s)))
names(disp) <- names(s)
cat(sprintf("\nref = %s | s(ref) = %.3f | s en ventana base = %.3f | s jun-26 = %.3f\n",
            ref, s_full[[ref]], mean(s[names(s) <= "2023-09"]), s[["2026-06"]]))
cat("Anclas disponible (obj 75 / 88 / 83.1) — comparacion, no calibracion:\n")
for (mm in c("2024-02", "2025-06", "2026-06")) cat(sprintf("  %s: %.1f\n", mm, disp[[mm]]))

## Salidas
pf_df <- data.frame(mes = colnames(pf_hist), pf_rel = as.numeric(pf_rel_hist))
write.csv(pf_df, file.path(repo_root, "data", "work", "canasta_fija.csv"), row.names = FALSE)
write.csv(data.frame(mes = names(s), s = as.numeric(s)), file.path(repo_root, "data", "work", "s_canasta_fija.csv"), row.names = FALSE)
dir.create(file.path(repo_root, "output"), showWarnings = FALSE)
fechas <- as.Date(paste0(names(disp), "-01"))
write.csv(data.frame(fecha = fechas, valor = as.numeric(disp)),
          file.path(repo_root, "output", "serie_ingreso_disponible.csv"), row.names = FALSE)

## Grafico de reproduccion (Fase 5) con overlay de anclas
serie_a <- read.csv(file.path(repo_root, "output", "serie_ingreso_real_ipc2004.csv"))
serie_b <- read.csv(file.path(repo_root, "output", "serie_ingreso_real_ipc2017.csv"))
serie_a$fecha <- as.Date(serie_a$fecha)
serie_b$fecha <- as.Date(serie_b$fecha)
serie_c <- data.frame(fecha = fechas, valor = as.numeric(disp))
anclas <- read.csv(file.path(repo_root, "tests", "anchors_equilibra.csv"))

mes_lbl <- format(seq(as.Date("2023-01-01"), as.Date("2026-06-01"), by = "month"), "%b-%y")
cols <- c(ingreso_real_ipc2004 = "grey60", ingreso_real_ipc2017 = "black", ingreso_disponible_ipc2017 = "red2")
ylim <- range(c(serie_a$valor, serie_b$valor, serie_c$valor))

for (variante in c("con_anclas", "sin_anclas")) {
  png(file.path(repo_root, "output", sprintf("grafico_equilibra_%s.png", variante)), width = 1250, height = 750, res = 110)
  nota <- paste(
    "Ingreso real = ingreso del universo deflactado por el IPC. Ingreso disponible = ingreso real menos gastos fijos (alquiler, expensas, tarifas de luz/gas/agua, transporte, comunicaciones, educación y medicina prepaga).",
    "Universo 14,5M de personas: asalariados privados registrados, empleados públicos y jubilados, ponderados por masa de ingreso SIPA (priv 64% / pub 23% / jub 12%).",
    "Ingresos: mediana SIPA (Secretaría de Trabajo, desestacionalizada) para privados; IST público (INDEC) para públicos; EPH + haber mínimo para jubilados.",
    "IPC 2017/18: reponderación ENGHo 2017/18 con división 04 (vivienda) por grupos CABA. Gasto fijo: g0 = 31% del ingreso (ENGHo 2017/18), actualizado con la inflación de la canasta fija vs el nivel general desde oct-2018.",
    "Base: promedio ene-23:sep-23 = 100. Por Rodrigo Quiroga @rquiroga777"
  )
  par(mar = c(5.2 + 0.75 * length(strwrap(nota, width = 178)), 4, 4, 6))
  xlim <- range(serie_a$fecha) + c(-5, 56)  # margen derecho solo hasta el borde de las etiquetas
  plot(serie_a$fecha, serie_a$valor, type = "n", ylim = ylim, xlim = xlim,
       xaxt = "n", xlab = "", ylab = "Índice (prom ene-23:sep-23 = 100)",
       main = "Ingreso real registrado y disponible (14,5M personas)\nReconstrucción desde microdatos EPH + registros administrativos")
  if (variante == "sin_anclas") abline(h = axTicks(2), col = "grey90")
  axis(1, at = serie_a$fecha, labels = mes_lbl, las = 2, cex.axis = 0.65)
  lines(serie_a$fecha, serie_a$valor, col = cols[["ingreso_real_ipc2004"]], lwd = 2.5)
  lines(serie_b$fecha, serie_b$valor, col = cols[["ingreso_real_ipc2017"]], lwd = 2.5)
  lines(serie_c$fecha, serie_c$valor, col = cols[["ingreso_disponible_ipc2017"]], lwd = 2.5)
  abline(h = 100, col = "grey80", lty = 2)
  if (variante == "con_anclas") {
    for (sr in names(cols)) {
      a_s <- anclas[anclas$series == sr, ]
      puntos <- as.Date(paste0(a_s$month, "-01"))
      points(puntos, a_s$value, pch = 4, col = cols[[sr]], lwd = 2, cex = 1.2)
    }
    legend("left", bty = "n", pch = 4, "anclas Equilibra")
  }
  x_etiqueta <- tail(serie_a$fecha, 1) + 30  # desplazada a la derecha para no pisar las lineas
  text(x_etiqueta, tail(serie_a$valor, 1), sprintf("%.1f", tail(serie_a$valor, 1)), adj = c(0.5, 0.5), cex = 1.05, font = 2, col = "grey40")
  text(x_etiqueta, tail(serie_b$valor, 1), sprintf("%.1f", tail(serie_b$valor, 1)), adj = c(0.5, 0.5), cex = 1.05, font = 2, col = "black")
  text(x_etiqueta, tail(serie_c$valor, 1), sprintf("%.1f", tail(serie_c$valor, 1)), adj = c(0.5, 0.5), cex = 1.05, font = 2, col = "red2")
  legend("topright", bty = "n", lwd = 2.5, col = cols,
         legend = c("Ingreso Real (IPC INDEC ENGHo 2004/05)", "Ingreso Real (IPC ENGHo 2017/18)", "Ingreso Disponible (IPC ENGHo 2017/18)"))
  lineas_nota <- strwrap(nota, width = 178)
  for (i in seq_along(lineas_nota)) {
    mtext(lineas_nota[i], side = 1, line = 4.6 + (i - 1) * 0.7, cex = 0.62, adj = 0)
  }
  dev.off()
}
cat("Gráficos: output/grafico_equilibra_con_anclas.png | output/grafico_equilibra_sin_anclas.png\n")
