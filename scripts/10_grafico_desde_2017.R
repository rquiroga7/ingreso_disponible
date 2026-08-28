# Fase 5d — grafico de reproduccion desde 2017 (cuando el IPC INDEC volvio a publicarse).
#
# Extension retroactiva de las tres series a 2017-01 con las mismas fuentes y
# parametros del pipeline (scripts 03/04/05/06), de modo que el tramo 2023+ sea
# identico a los graficos vigentes:
#   - ingreso nominal: SIPA mediana desestacionalizada (priv), IST publico (pub),
#     y para jubilados 2017..2022 el haber minimo encadenado al valor 2023-01 del
#     pipeline (que usa EPH interpolada + cola de haber minimo).
#   - IPC oficial (nivel general) e IPC 2017/18 reponderado, disponibles desde dic-2016.
#   - gastos fijos s(t) con aperturas IPC CABA (canasta fija, ref oct-2018), jul-2012+.
# Base ene-23:sep-23 = 100 (igual que el resto del proyecto).
#
# Salida: output/grafico_equilibra_desde_2017.png + serie_ingreso_*_desde_2017.csv

repo_root <- getOption("repo_root", ".")
source(file.path(repo_root, "R", "rebase_index.R"))

ventana <- sprintf("2023-0%d", 1:9)
desde <- "2017-01"
hasta <- "2026-06"
meses <- format(seq(as.Date(paste0(desde, "-01")), as.Date(paste0(hasta, "-01")), by = "month"), "%Y-%m")

## 1) Ingreso nominal
admin <- read.csv(file.path(repo_root, "data", "work", "admin_series.csv"))
admin$mes <- format(as.Date(admin$fecha), "%Y-%m")
ynom_ex <- read.csv(file.path(repo_root, "data", "work", "ynom_mensual.csv"))

# privado: SIPA mediana desestacionalizada (idem script 03)
sipa <- setNames(admin$sipa_med_priv, admin$mes)
sipa <- sipa[!is.na(sipa)]
stl_fit <- stl(ts(log(sipa), frequency = 12), s.window = "periodic", robust = TRUE)
desest <- exp(stl_fit$time.series[, "trend"] + stl_fit$time.series[, "remainder"])
names(desest) <- names(sipa)
priv <- rebase_index(desest, names(desest))
priv[["2026-05"]] <- priv[["2026-04"]] * (1 - 0.8 / 100)
priv[["2026-06"]] <- priv[["2026-05"]] * 1.01

# publico: IST publico nominal + cola con su m/m (idem script 03)
istv <- read.csv(file.path(repo_root, "data", "raw", "salarios", "variacion_indice_salarios.csv"),
                 sep = ";", dec = ",", na.strings = "NA")
istv$mes <- format(as.Date(istv$periodo, "%d/%m/%Y"), "%Y-%m")
mm_ist_pub <- setNames(istv$v_m_sector_publico, istv$mes)
extender_ist <- function(idx, mm_ist) {
  last <- max(names(idx)[!is.na(idx)])
  for (m in names(idx)[names(idx) > last]) {
    idx[[m]] <- if (!m %in% names(mm_ist) || is.na(mm_ist[[m]])) idx[[last]] else idx[[last]] * (1 + mm_ist[[m]] / 100)
    last <- m
  }
  idx
}
pub <- extender_ist(rebase_index(admin$ist_nom_pub, admin$mes), mm_ist_pub)

# jubilados: 2017..2022 con el haber minimo encadenado al 2023-01 del pipeline;
# 2023+ = serie existente (EPH interpolada + cola de haber minimo)
jub_ex <- setNames(ynom_ex$jub_rel, substr(ynom_ex$fecha, 1, 7))
minimo <- setNames(admin$haber_minimo, admin$mes)
pre <- meses[meses < "2023-01"]
jub_pre <- setNames(jub_ex[["2023-01"]] * minimo[pre] / minimo[["2023-01"]], pre)
jub <- c(jub_pre, jub_ex[meses[meses >= "2023-01"]])

# pesos por masa de ingreso SIPA (idem script 03)
w <- c(priv_formal = 6.1e6 * 1915878, publico = 3.5e6 * 1200000, jubilado = 5e6 * 450000)
w <- w / sum(w)
ynom <- rebase_index(w[["priv_formal"]] * priv[meses] + w[["publico"]] * pub[meses] + w[["jubilado"]] * jub, meses)

## 2) Deflactores
# IPC oficial nivel general (serie A)
ng <- read.csv(file.path(repo_root, "data", "raw", "ipc", "148.3_INIVELNAL_DICI_M_26.csv"))
ng$mes <- format(as.Date(ng$fecha), "%Y-%m")
NG <- setNames(ng[[2]], ng$mes)[meses]

# IPC 2017/18 reponderado (idem script 05)
ipc_series <- read.csv(file.path(repo_root, "data", "work", "ipc_series.csv"))
ipc_series$mes <- format(as.Date(ipc_series$fecha), "%Y-%m")
pesos <- read.csv(file.path(repo_root, "data", "dicts", "weights_engho_2017_18.csv"))
divs <- pesos[pesos$nivel == "division", ]
cols <- sprintf("div%02d_%s", as.integer(divs$codigo), c(
  "alimentos", "bebidas", "prendas", "vivienda", "equipamiento", "salud",
  "transporte", "comunicacion", "recreacion", "educacion", "restaurantes", "bienes_varios"
))
I <- setNames(lapply(cols, function(cc) setNames(ipc_series[[cc]], ipc_series$mes)), cols)
w17 <- divs$peso / sum(divs$peso)
# division 04 reponderada por grupos con aperturas CABA (idem script 05)
leer_caba <- function(archivo, f1, f2) {
  raw <- read.csv(archivo, fileEncoding = "latin1", check.names = FALSE)
  fc <- format(as.Date(as.character(unlist(raw[f1, -1])), "%m/%d/%Y"), "%Y-%m")
  m <- as.matrix(raw[f2:nrow(raw), -1]); mode(m) <- "numeric"
  rownames(m) <- trimws(as.character(raw[f2:nrow(raw), 1])); colnames(m) <- fc; m
}
viejo <- leer_caba(file.path(repo_root, "data", "work", "ipcba_aperturas_empalme.csv"), 3, 4)
nuevo <- leer_caba(file.path(repo_root, "data", "work", "ipcba_aperturas.csv"), 2, 3)
comun <- intersect(colnames(viejo), colnames(nuevo))
caba_serie <- function(nombre) {
  r <- c(viejo[nombre, colnames(viejo) < comun[1]], nuevo[nombre, ])
  r[!is.na(r)]
}
pesos04 <- c(alquiler = 3.0, conservacion = 1.1, agua = 2.5, elec_gas = 7.9)
grupos04 <- c(
  alquiler = "Alquiler de la vivienda",
  conservacion = "Mantenimiento y reparación de la vivienda",
  agua = "Suministro de agua y otros servicios relacionados con la vivienda",
  elec_gas = "Electricidad, gas y otros combustibles"
)
G <- sapply(grupos04, caba_serie)
div04_17 <- as.numeric(G %*% pesos04) / sum(pesos04)
names(div04_17) <- rownames(G)
div04_17 <- div04_17 * mean(I[["div04_vivienda"]][ventana]) / mean(div04_17[ventana])
I[["div04_vivienda"]] <- div04_17
ipc17_meses <- Reduce(intersect, list(names(I[[1]]), names(I[["div04_vivienda"]])))
ipc17_meses <- ipc17_meses[ipc17_meses >= desde & ipc17_meses <= hasta]
ipc17 <- rebase_index(Reduce(`+`, Map(function(Ii, wi) Ii[ipc17_meses] * wi, I, w17)), ipc17_meses)

## 3) s(t) gastos fijos (idem script 06)
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
pesos_cf <- c(alquiler = 1.5, expensas = 1.1, elec_gas = 9.4, agua = 2.5, salud = 6.4,
              transp_func = 8.1, transp_serv = 3.2, educacion = 3.1, comunicacion = 5.2)
factor <- nuevo[aperturas, comun, drop = FALSE] / viejo[aperturas, comun, drop = FALSE]
factor_esc <- factor[, 1]
viejo_aj <- sweep(viejo[aperturas, , drop = FALSE], 1, factor_esc, `*`)
pf_hist <- cbind(viejo_aj[, colnames(viejo_aj) < min(comun)], nuevo[aperturas, , drop = FALSE])
pf_hist <- pf_hist[, order(colnames(pf_hist))]
pf_rel <- as.numeric(t(pf_hist[aperturas[names(pesos_cf)], , drop = FALSE]) %*% as.numeric(pesos_cf / sum(pesos_cf)))
ng_caba <- pf_hist[aperturas[["nivel_general"]], ]
names(pf_rel) <- colnames(pf_hist); names(ng_caba) <- colnames(pf_hist)
g0 <- read.csv(file.path(repo_root, "data", "work", "g0_calibrado.csv"))$g0
ratio <- pf_rel / ng_caba
s <- g0 * ratio / ratio[["2018-10"]]
s <- s[names(s) >= desde & names(s) <= hasta]

## 4) Series finales
A <- rebase_index(ynom / NG * 100, meses)
B <- rebase_index(ynom[names(ipc17)] / ipc17 * 100, names(ipc17))
C <- rebase_index(B * (1 - s[names(B)]), names(B))

## 5) Cross-check del tramo 2023+ contra el pipeline (deben coincidir)
leer <- function(f) setNames(read.csv(file.path(repo_root, "output", f))$valor,
                             substr(read.csv(file.path(repo_root, "output", f))$fecha, 1, 7))
for (par in list(c("A", "serie_ingreso_real_ipc2004.csv"), c("B", "serie_ingreso_real_ipc2017.csv"), c("C", "serie_ingreso_disponible.csv"))) {
  ref <- leer(par[2]); v <- get(par[1])
  dif <- max(abs(v[names(ref)] - ref))
  cat(sprintf("Serie %s vs %s: dif max 2023+ = %.3f\n", par[1], par[2], dif))
}

dir.create(file.path(repo_root, "output"), showWarnings = FALSE)
for (par in list(c("A", "serie_ingreso_real_ipc2004_desde_2017.csv"),
                 c("B", "serie_ingreso_real_ipc2017_desde_2017.csv"),
                 c("C", "serie_ingreso_disponible_desde_2017.csv"))) {
  v <- get(par[1])
  write.csv(data.frame(fecha = as.Date(paste0(names(v), "-01")), valor = as.numeric(v)),
            file.path(repo_root, "output", par[2]), row.names = FALSE)
}

## 6) Grafico (mismo estilo que scripts/06, sin anclas, desde 2017)
cols <- c(ingreso_real_ipc2004 = "grey60", ingreso_real_ipc2017 = "black", ingreso_disponible_ipc2017 = "red2")
ylim <- range(c(A, B, C))
nota <- paste(
  "Ingreso real = ingreso del universo deflactado por el IPC. Ingreso disponible = ingreso real menos gastos fijos (alquiler, expensas, tarifas de luz/gas/agua, transporte, comunicaciones, educación y medicina prepaga).",
  "Universo 14,5M de personas: asalariados privados registrados, empleados públicos y jubilados, ponderados por masa de ingreso SIPA (priv 64% / pub 23% / jub 12%).",
  "Ingresos: mediana SIPA (Secretaría de Trabajo, desestacionalizada) para privados; IST público (INDEC) para públicos; EPH + haber mínimo para jubilados. Antes de 2023 el tramo jubilado se extiende con el haber mínimo.",
  "IPC 2017/18: reponderación ENGHo 2017/18 con división 04 (vivienda) por grupos CABA. Gasto fijo: g0 = 31% del ingreso (ENGHo 2017/18), actualizado con la inflación de la canasta fija vs el nivel general desde oct-2018.",
  "Base: promedio ene-23:sep-23 = 100. Por Rodrigo Quiroga @rquiroga777"
)
png(file.path(repo_root, "output", "grafico_equilibra_desde_2017.png"), width = 1100, height = 825, res = 110)
par(mar = c(5.2 + 0.75 * length(strwrap(nota, width = 178)), 4, 4, 1))
fechas <- as.Date(paste0(meses, "-01"))
jan <- fechas[format(fechas, "%m") == "01"]
plot(fechas, A, type = "n", ylim = ylim, xlim = range(fechas) + c(-5, 78),
     xaxt = "n", xlab = "", ylab = "Índice (prom ene-23:sep-23 = 100)",
     main = "Ingreso real registrado y disponible (14,5M personas)\nReconstrucción desde microdatos EPH + registros administrativos — desde 2017")
abline(h = axTicks(2), col = "grey90")
abline(v = jan, col = "grey92")
axis(1, at = jan, labels = format(jan, "%b-%y"), las = 2, cex.axis = 0.8)
lines(fechas, A, col = cols[["ingreso_real_ipc2004"]], lwd = 2.5)
lines(as.Date(paste0(names(B), "-01")), B, col = cols[["ingreso_real_ipc2017"]], lwd = 2.5)
lines(as.Date(paste0(names(C), "-01")), C, col = cols[["ingreso_disponible_ipc2017"]], lwd = 2.5)
abline(h = 100, col = "grey80", lty = 2)
legend("topright", bty = "n", lwd = 2.5, col = cols,
       legend = c("Ingreso Real (IPC INDEC ENGHo 2004/05)", "Ingreso Real (IPC ENGHo 2017/18)", "Ingreso Disponible (IPC ENGHo 2017/18)"))
x_etiqueta <- tail(fechas, 1) + 120
text(x_etiqueta, tail(A, 1), sprintf("%.1f", tail(A, 1)), adj = c(0.5, 0.5), cex = 1.05, font = 2, col = "grey40")
text(x_etiqueta, tail(B, 1), sprintf("%.1f", tail(B, 1)), adj = c(0.5, 0.5), cex = 1.05, font = 2, col = "black")
text(x_etiqueta, tail(C, 1), sprintf("%.1f", tail(C, 1)), adj = c(0.5, 0.5), cex = 1.05, font = 2, col = "red2")
lineas_nota <- strwrap(nota, width = 178)
for (i in seq_along(lineas_nota)) {
  mtext(lineas_nota[i], side = 1, line = 4.6 + (i - 1) * 0.7, cex = 0.62, adj = 0)
}
dev.off()

## Variante con mora de familias BCRA (eje derecho)
mora <- read.csv(file.path(repo_root, "data", "work", "bcra_mora_familias.csv"))
mora$fecha <- as.Date(mora$fecha)
mora$mes <- substr(mora$fecha, 1, 7)
mora <- mora[mora$mes >= desde & mora$mes <= hasta, ]
mora_col <- "blue3"
mora_base <- round(mean(mora$mora_familias[mora$mes %in% ventana]))
k <- 2
mora_primary <- 100 + (mora$mora_familias - mora_base) * k
ticks_mora <- seq(0, 14, 2)
tick_pos <- 100 + (ticks_mora - mora_base) * k

nota_bcra <- paste(
  "Ingreso disponible = ingreso real (del universo deflactado por el IPC) menos gastos fijos (alquiler, expensas, tarifas de luz/gas/agua, transporte, comunicaciones, educación y medicina prepaga).",
  "Universo 14,5M de personas: asalariados privados registrados, empleados públicos y jubilados, ponderados por masa de ingreso SIPA (priv 64% / pub 23% / jub 12%).",
  "Mora de familias (BCRA, eje derecho, en %): % de la cartera de crédito a hogares en situación irregular. El 100 del eje izquierdo coincide con la mora promedio ene-23:sep-23 (= 2%).",
  "Ingresos: mediana SIPA (Secretaría de Trabajo, desestacionalizada) para privados; IST público (INDEC) para públicos; EPH + haber mínimo para jubilados. Antes de 2023 el tramo jubilado se extiende con el haber mínimo.",
  "IPC 2017/18: reponderación ENGHo 2017/18 con división 04 (vivienda) por grupos CABA. Gasto fijo: g0 = 31% del ingreso (ENGHo 2017/18), actualizado con la inflación de la canasta fija vs el nivel general desde oct-2018.",
  "Base: promedio ene-23:sep-23 = 100. Por Rodrigo Quiroga @rquiroga777"
)
png(file.path(repo_root, "output", "grafico_equilibra_desde_2017_bcra.png"), width = 1100, height = 825, res = 110)
par(mar = c(5.2 + 0.75 * length(strwrap(nota_bcra, width = 178)), 4, 4, 4))
plot(fechas, A, type = "n", ylim = range(c(as.numeric(C), mora_primary)), xlim = range(fechas) + c(-5, 78),
     xaxt = "n", xlab = "", ylab = "Índice (prom ene-23:sep-23 = 100)",
     main = "Ingreso disponible (14,5M personas) y mora de familias\nReconstrucción desde microdatos EPH + registros administrativos — desde 2017")
abline(h = axTicks(2), col = "grey90")
abline(v = jan, col = "grey92")
axis(1, at = jan, labels = format(jan, "%b-%y"), las = 2, cex.axis = 0.8)
axis(4, at = tick_pos, labels = ticks_mora, las = 0, cex.axis = 0.9)
mtext("Mora de familias (% de crédito a hogares irregular)", side = 4, line = 2.6, cex = 0.85)
lines(as.Date(paste0(names(C), "-01")), C, col = cols[["ingreso_disponible_ipc2017"]], lwd = 2.5)
lines(mora$fecha, mora_primary, col = mora_col, lwd = 2.5)
abline(h = 100, col = "grey80", lty = 2)
legend("top", bty = "o", lwd = 2.5,
       col = c(cols[["ingreso_disponible_ipc2017"]], mora_col),
       legend = c("Ingreso Disponible (IPC ENGHo 2017/18)", "Mora de familias (BCRA, eje der.)"))
x_etiqueta <- tail(fechas, 1) + 120
text(x_etiqueta, tail(C, 1), sprintf("%.1f", tail(C, 1)), adj = c(0.5, 0.5), cex = 1.05, font = 2, col = "red2")
text(x_etiqueta, tail(mora_primary, 1), sprintf("%.0f%%", tail(mora$mora_familias, 1)), adj = c(0.5, 0.5), cex = 1.05, font = 2, col = mora_col)
lineas_nota <- strwrap(nota_bcra, width = 178)
for (i in seq_along(lineas_nota)) {
  mtext(lineas_nota[i], side = 1, line = 4.6 + (i - 1) * 0.7, cex = 0.62, adj = 0)
}
dev.off()
cat("Gráfico: output/grafico_equilibra_desde_2017.png\n")
cat("Gráfico: output/grafico_equilibra_desde_2017_bcra.png\n")
cat("Anclas (base 100):\n")
for (mm in c("2017-12", "2019-12", "2024-02", "2026-06")) {
  cat(sprintf("  %s: A %.1f | B %.1f | C %.1f\n", mm, A[[mm]], B[[mm]], C[[mm]]))
}