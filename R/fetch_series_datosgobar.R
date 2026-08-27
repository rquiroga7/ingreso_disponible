# Descarga (con cache) una o mas series de la API de datos.gob.ar.
#
# fetch_series_datosgobar(ids, cache_dir) -> data.frame(fecha, <serie_id>, ...)
#   fecha: Date (primer dia del mes); una columna numerica por serie.
# Si existe el CSV cacheado en cache_dir se lo usa tal cual; si no, se baja y
# se cachea como <id>.csv (columnas fecha,valor). Para refrescar, borrar el CSV.

fetch_series_datosgobar <- function(ids, cache_dir = "data/raw/ipc") {
  stopifnot(is.character(ids), length(ids) > 0)
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)

  columnas <- lapply(ids, function(id) {
    csv <- file.path(cache_dir, paste0(id, ".csv"))
    df <- NULL
    if (file.exists(csv)) {
      df <- tryCatch(read.csv(csv, colClasses = c("character", "numeric")), error = function(e) NULL)
    }
    if (is.null(df)) {
      url <- sprintf(
        "https://apis.datos.gob.ar/series/api/series/?ids=%s&format=json&limit=1000",
        id
      )
      # suppressWarnings: la API manda JSON sin newline final ("incomplete final line"), inofensivo
      txt <- tryCatch(suppressWarnings(readLines(url(url), warn = FALSE)), error = function(e) NULL)
      js <- if (!is.null(txt)) tryCatch(jsonlite::fromJSON(paste(txt, collapse = "\n")), error = function(e) NULL) else NULL
      if (is.null(js) || is.null(js$data) || length(js$data) == 0) {
        stop(sprintf("No se pudo obtener la serie %s de datos.gob.ar", id))
      }
      df <- data.frame(
        fecha = as.Date(js$data[, 1]),
        valor = as.numeric(js$data[, 2]),
        stringsAsFactors = FALSE
      )
      write.csv(df, csv, row.names = FALSE)
    }
    names(df) <- c("fecha", id)
    df
  })

  out <- columnas[[1]]
  if (length(ids) > 1) {
    for (i in 2:length(ids)) {
      out <- merge(out, columnas[[i]], by = "fecha", all = TRUE)
    }
  }
  out[order(out$fecha), ]
}
