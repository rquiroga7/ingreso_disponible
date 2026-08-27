# Fase 2b — Serie A: ingreso real con IPC oficial (ENGHo 2004/05).
#
# real(t) = Y_nom(t) / IPC_oficial(t); rebase promedio ene-23:sep-23 = 100.
# Salida: output/serie_ingreso_real_ipc2004.csv (fecha, valor)

repo_root <- getOption("repo_root", ".")
source(file.path(repo_root, "R", "rebase_index.R"))

ynom <- read.csv(file.path(repo_root, "data", "work", "ynom_mensual.csv"))
ipc <- read.csv(file.path(repo_root, "data", "raw", "ipc", "148.3_INIVELNAL_DICI_M_26.csv"))
ipc$mes <- format(as.Date(ipc$fecha), "%Y-%m")
names(ipc)[2] <- "ipc"

m <- merge(transform(ynom, mes = substr(fecha, 1, 7)), ipc[, c("mes", "ipc")], by = "mes")
m <- m[order(m$mes), ]
real <- rebase_index(m$ynom_rel / m$ipc * 100, m$mes)

dir.create(file.path(repo_root, "output"), showWarnings = FALSE)
write.csv(data.frame(fecha = m$fecha, valor = as.numeric(real)),
          file.path(repo_root, "output", "serie_ingreso_real_ipc2004.csv"), row.names = FALSE)

cat("Serie A (IPC 2004/05) anclas | objetivo: feb-24 80+-1 / jun-25 94+-1 / jun-26 91.5+-0.3\n")
for (mm in c("2024-02", "2025-06", "2026-06")) cat(sprintf("  %s: %.1f\n", mm, real[[mm]]))
