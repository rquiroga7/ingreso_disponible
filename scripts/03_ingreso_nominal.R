# Fase 2 — ingreso nominal mensual del universo (hibrido admin + EPH).
#
# Decision metodologica (METHODOLOGY.md 3.2): la nota de Equilibra describe
# dinamicas por segmento coherentes con registros administrativos (Secretaria
# de Trabajo para salarios, ANSES para haberes). Las medias de encuesta EPH
# puras sobrestiman la recuperacion 2024-25 (deriva de composicion + imputacion
# caliente; ver sensibilidad en METHODOLOGY.md). Se construye:
#   - priv_formal : IST privado registrado nominal (INDEC, hasta abr-26 en la API);
#                   cola may/jun-26 con el m/m del PROPIO IST (variacion_indice_
#                   salarios.csv, que ya publica jun-26). Revision 2026-08-25: el
#                   RIPTE (imponible, volatil) daba un salto artificial en jun-26
#                   (+3.6% m/m); el IST real es +1.9%.
#   - publico     : IST publico registrado nominal; cola may/jun-26 con su m/m.
#   - jubilados   : media previsional EPH trimestral interpolada entre centros;
#                   cola feb-26 en adelante con m/m del IST publico (proxy de
#                   politica salarial estatal).
# Agregacion: pesos fijos de poblacion por segmento (ventana base t231:t233).
#
# Salida: data/work/ynom_mensual.csv (fecha, ynom_rel, priv_rel, pub_rel, jub_rel)

repo_root <- getOption("repo_root", ".")
source(file.path(repo_root, "R", "read_eph_individual.R"))
source(file.path(repo_root, "R", "eph_segmento_stats.R"))
source(file.path(repo_root, "R", "rebase_index.R"))

trimestres <- sprintf("t%d%d", rep(23:25, each = 4), 1:4)
ventana <- sprintf("2023-0%d", 1:9)
target <- format(seq(as.Date("2023-01-01"), as.Date("2026-06-01"), by = "month"), "%Y-%m")

## 1) EPH: poblacion por segmento (pesos) y media previsional trimestral
stats <- do.call(rbind, lapply(trimestres, function(id) {
  st <- eph_segmento_stats(read_eph_individual(repo_root, id))
  q <- as.integer(substr(id, 4, 4))
  data.frame(
    mes = sprintf("20%s-%02d", substr(id, 2, 3), c(2, 5, 8, 11)[q]),
    segmento = st$segmento, poblacion = st$poblacion, ingreso_medio = st$ingreso_medio
  )
}))

# Pesos por MASA DE INGRESO del universo formal, segun registros SIPA (revision
# 2026-08-25): la masa salarial real (6.1M privados registrados x RIPTE jun-26 +
# ~3.5M publicos x salario medio + ~5M jubilados x haber medio) da 64.4/23.2/12.4.
# Los pesos EPH (47.3/27.2/25.4) subrepresentan al privado y hacian que el agregado
# subiera en jun-26 (cuando Equilibra cae): el privado pesa mas en la masa real.
stats$masa <- stats$poblacion * stats$ingreso_medio
pob_base <- sapply(c("priv_formal", "publico", "jubilado"), function(s) {
  mean(stats$poblacion[stats$segmento == s & stats$mes <= "2023-09"])
})
masa_sipa <- c(priv_formal = 6.1e6 * 1915878, publico = 3.5e6 * 1200000, jubilado = 5e6 * 450000)
w <- masa_sipa / sum(masa_sipa)
cat(sprintf("Universo ventana base (EPH): %.2f M | pesos SIPA: %.1f%% priv / %.1f%% pub / %.1f%% jub\n",
            sum(pob_base) / 1e6, w[[1]] * 100, w[[2]] * 100, w[[3]] * 100))

jt <- setNames(
  stats$ingreso_medio[stats$segmento == "jubilado"],
  stats$mes[stats$segmento == "jubilado"]
)

## 2) Series administrativas
admin <- read.csv(file.path(repo_root, "data", "work", "admin_series.csv"))
admin$mes <- format(as.Date(admin$fecha), "%Y-%m")

# PRIVADO: SIPA remuneracion promedio de asalariados privados registrados (SST).
# Revision 2026-08-25: Equilibra usa el SIPA (Secretaria de Trabajo), que capta bonos,
# premios y no-remunerativos (por eso difiere del IST/RIPTE) y cayo en 2026 (may -4.9%
# bruto; jun-26 -0.9% real desestacionalizado segun el informe SST). Se desestacionaliza
# con STL (descomposicion Loess, base de R; multiplicativo via log, s.window periodico)
# y se extiende a jun-26 con el anticipado oficial (~+1% nominal m/m).
# MEDIANA SIPA (revision 2026-08-25): representa al trabajador tipico (la media la
# tiran los altos ingresos) y da mejor nivel (A jun-26 91.3 vs objetivo 91.5). El
# promedio sobreestimaba el nivel (A jun-26 94.5). Ambos suben en feb-24 (caracteristica
# del SIPA, no bonos).
sipa <- setNames(admin$sipa_med_priv, admin$mes)
sipa <- sipa[!is.na(sipa)]
stl_fit <- stl(ts(log(sipa), frequency = 12), s.window = "periodic", robust = TRUE)
desest_sipa <- exp(stl_fit$time.series[, "trend"] + stl_fit$time.series[, "remainder"])
names(desest_sipa) <- names(sipa)
priv <- rebase_index(desest_sipa, names(desest_sipa))
# SIPA provisional de la SST (lo que usa Equilibra) para los meses recientes:
#  - may-26: nominal -0.8% m/m (real desest -2.9% + IPC 2.1%); la definitiva 153.1 da
#    -4.9% nominal (real -6.3%), mucho mas volatil que el -2.1% que reporta Equilibra.
#  - jun-26: anticipado +1.0% nominal (real desest -0.9% + IPC 1.9%), mes sin definitiva.
priv[["2026-05"]] <- priv[["2026-04"]] * (1 - 0.8 / 100)
priv[["2026-06"]] <- priv[["2026-05"]] * 1.01

# m/m del IST publicados por INDEC (CSV oficial, hasta jun-26): se usan para extender
# la serie de niveles de la API (que llega a abr-26) con el propio IST.
istv <- read.csv(file.path(repo_root, "data", "raw", "salarios", "variacion_indice_salarios.csv"),
                 sep = ";", dec = ",", na.strings = "NA")
istv$mes <- format(as.Date(istv$periodo, "%d/%m/%Y"), "%Y-%m")
mm_ist_pub <- setNames(istv$v_m_sector_publico, istv$mes)

extender_ist <- function(idx, mm_ist) {
  last <- max(names(idx)[!is.na(idx)])
  for (m in names(idx)[names(idx) > last]) {
    if (!m %in% names(mm_ist) || is.na(mm_ist[[m]])) {
      idx[[m]] <- idx[[last]]
    } else {
      idx[[m]] <- idx[[last]] * (1 + mm_ist[[m]] / 100)
    }
    last <- m
  }
  idx
}

pub <- extender_ist(rebase_index(admin$ist_nom_pub, admin$mes), mm_ist_pub)

jm <- setNames(
  approx(as.numeric(as.Date(paste0(names(jt), "-01"))), jt,
         as.numeric(as.Date(paste0(target, "-01"))), rule = 2)$y,
  target
)
cc <- max(names(jt))
# cola de jubilados con el HABER MINIMO + BONO ANSES (jubilaciones), no el IST publico:
# revision 2026-08-28 — se suma el bono extraordinario ($7k en sept-22 -> $70k fijo desde
# mar-24; consta hasta jun-26), que es parte del ingreso efectivo de la jubilacion minima.
# El IST publico incluye el aumento universitario de jun-26 (+21%), que las jubilaciones
# no reciben; el haber minimo + bono refleja la movilidad real.
bono <- read.csv(file.path(repo_root, "data", "work", "bono_anses.csv"))
bono <- setNames(bono$bono, bono$mes)
minimo_bono <- setNames(admin$haber_minimo + bono[admin$mes], admin$mes)
for (m in target[target > cc]) {
  jm[[m]] <- jm[[cc]] * minimo_bono[[m]] / minimo_bono[[cc]]
}
jm <- jm / mean(jm[ventana]) * 100

## 3) Agregacion con pesos fijos de MASA DE INGRESO de la ventana base
ynom <- rebase_index(w[["priv_formal"]] * priv[target] +
  w[["publico"]] * pub[target] +
  w[["jubilado"]] * jm[target], target)

dir.create(file.path(repo_root, "data", "work"), showWarnings = FALSE)
write.csv(data.frame(
  fecha = paste0(target, "-01"),
  ynom_rel = as.numeric(ynom),
  priv_rel = as.numeric(priv[target]),
  pub_rel = as.numeric(pub[target]),
  jub_rel = as.numeric(jm[target])
), file.path(repo_root, "data", "work", "ynom_mensual.csv"), row.names = FALSE)

cat("Nominal relativo (cross-check nota Equilibra ~234 / ~504 / ~656):\n")
cat(sprintf("  feb-24: %.0f | jun-25: %.0f | jun-26: %.0f\n",
            ynom[["2024-02"]], ynom[["2025-06"]], ynom[["2026-06"]]))
