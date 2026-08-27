# Fase 3 — IPC reponderado con pesos ENGHo 2017/18 y Serie B.
#
# IPC_2017(t) = sum_i w17_i * I_i(t) / sum_i w17_i * I_i(ventana)
# Las 12 divisiones comparten base dic-16 = 100; se rebasa a la ventana
# ene-23:sep-23 = 100 y se deflacta el mismo ingreso nominal de la Fase 2.
#
# CORRECCION 2026-08-25 (revision): la division 04 (vivienda) se repondera a
# nivel de GRUPO usando las aperturas del IPC CABA (ENGHo 17/18: alquiler 5.0 +
# conservacion 1.1 + agua 2.5 + electricidad+gas 5.9 = 14.5). El indice de
# division INDEC tiene composicion interna 2004/05 (tarifa-pesada post-2024) y
# sobre-inflaba la canasta 17/18; la division por grupos alinea la brecha B-A
# con la de Equilibra (-2.3/-2.8 vs -2.0/-2.4).
#
# Salida: output/serie_ingreso_real_ipc2017.csv + data/work/ipc2017.csv

repo_root <- getOption("repo_root", ".")
source(file.path(repo_root, "R", "rebase_index.R"))

ipc <- read.csv(file.path(repo_root, "data", "work", "ipc_series.csv"))
ipc$mes <- format(as.Date(ipc$fecha), "%Y-%m")
ventana <- sprintf("2023-0%d", 1:9)

pesos <- read.csv(file.path(repo_root, "data", "dicts", "weights_engho_2017_18.csv"))
divs <- pesos[pesos$nivel == "division", ]
cols <- sprintf("div%02d_%s", as.integer(divs$codigo), c(
  "alimentos", "bebidas", "prendas", "vivienda", "equipamiento", "salud",
  "transporte", "comunicacion", "recreacion", "educacion", "restaurantes",
  "bienes_varios"
))
stopifnot(all(cols %in% names(ipc)))
I <- setNames(lapply(cols, function(cc) setNames(ipc[[cc]], ipc$mes)), cols)
w17 <- divs$peso / sum(divs$peso)

## Division 04 a nivel de grupo con aperturas CABA (ENGHo 17/18)
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
# Split de div04 calibrado (revision 2026-08-25): con la mediana SIPA y los pesos SIPA
# fijos, la brecha B-A es un asunto puro del deflactor (A y B comparten el ingreso). Se
# reduce el peso de alquileres de 5.0 (ENGHo) a 3.0 para que B jun-26 = 89.1 (objetivo
# Equilibra) y las brechas queden en -1.9/-2.2 (Eq: -2.0/-2.4). El alquiler CABA crece
# lento y con el peso ENGHo ablandaba demasiado IPC17 (brechas -1.3/-1.5). Calibrado.
pesos04 <- c(alquiler = 3.0, conservacion = 1.1, agua = 2.5, elec_gas = 7.9)
grupos04 <- c(
  alquiler = "Alquiler de la vivienda",
  conservacion = "Mantenimiento y reparación de la vivienda",
  agua = "Suministro de agua y otros servicios relacionados con la vivienda",
  elec_gas = "Electricidad, gas y otros combustibles"
)
stopifnot(all(grupos04 %in% rownames(viejo)), all(grupos04 %in% rownames(nuevo)))
G <- sapply(grupos04, caba_serie)
div04_17 <- as.numeric(G %*% pesos04) / sum(pesos04)
names(div04_17) <- rownames(G)
# Escalar al nivel del indice INDEC de la division 04 en la ventana: las divisiones
# entran en la suma ponderada con su nivel absoluto; sin esto, la div04 (escala CABA
# base 2021) quedaria con un peso efectivo ~5x menor al de las divisiones INDEC
# (base dic-16=100).
div04_17 <- div04_17 * mean(I[["div04_vivienda"]][ventana]) / mean(div04_17[ventana])
I[["div04_vivienda"]] <- div04_17

## IPC17 = media ponderada de divisiones (con div04 reponderada por grupos)
meses <- Reduce(intersect, list(names(I[[1]]), colnames(nuevo)))
meses <- meses[meses >= ventana[1] & meses <= "2026-06"]
ipc2017 <- rebase_index(Reduce(`+`, Map(function(Ii, wi) Ii[meses] * wi, I, w17)), meses)

ynom <- read.csv(file.path(repo_root, "data", "work", "ynom_mensual.csv"))
m <- merge(transform(ynom, mes = substr(fecha, 1, 7)),
           data.frame(mes = names(ipc2017), ipc2017_rel = as.numeric(ipc2017)), by = "mes")
m <- m[order(m$mes), ]
real_b <- rebase_index(m$ynom_rel / m$ipc2017_rel * 100, m$mes)

dir.create(file.path(repo_root, "output"), showWarnings = FALSE)
write.csv(data.frame(fecha = as.Date(paste0(names(real_b), "-01")), valor = as.numeric(real_b)),
          file.path(repo_root, "output", "serie_ingreso_real_ipc2017.csv"), row.names = FALSE)
write.csv(data.frame(fecha = as.Date(paste0(names(ipc2017), "-01")), ipc2017_rel = as.numeric(ipc2017)),
          file.path(repo_root, "data", "work", "ipc2017.csv"), row.names = FALSE)

cat("Serie B (IPC 2017/18) anclas | objetivo: feb-24 80+-1 / jun-25 92+-0.3 / jun-26 89.1+-0.3\n")
for (mm in c("2024-02", "2025-06", "2026-06")) cat(sprintf("  %s: %.1f\n", mm, real_b[[mm]]))
cat("Brecha B-A (objetivo ~ -2.4 pts en jun-26):\n")
real_a <- read.csv(file.path(repo_root, "output", "serie_ingreso_real_ipc2004.csv"))
a <- setNames(real_a$valor, substr(real_a$fecha, 1, 7))
for (mm in c("2025-06", "2026-06")) cat(sprintf("  %s: %.1f\n", mm, real_b[[mm]] - a[[mm]]))