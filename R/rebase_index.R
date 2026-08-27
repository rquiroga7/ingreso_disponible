# Rebasa un indice para que el promedio de la ventana base sea `valor` (100).
#
# rebase_index(x, nombres, ventana) -> vector numerico con names = nombres.
#   ventana: character con los meses "YYYY-MM" de la ventana base.

rebase_index <- function(x, nombres, ventana = sprintf("2023-0%d", 1:9)) {
  x <- stats::setNames(as.numeric(x), nombres)
  base <- mean(x[ventana], na.rm = TRUE)
  x / base * 100
}
