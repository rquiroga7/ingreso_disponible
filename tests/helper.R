# Minimal test helpers shared by all tests in this directory.
# Sourced by tests/run_all.R (into globalenv) and by each test when run standalone.

test_env_new <- function(name) {
  e <- new.env(parent = globalenv())
  e$TEST_NAME <- name
  e$TEST_STATUS <- "PASS"
  e$TEST_MSGS <- character(0)
  e
}

# Los tests usan: e <- test_setup("nombre"). El runner inyecta su env via
# options(test_env=); al correr un test standalone se crea uno propio.
test_setup <- function(name) getOption("test_env") %||% test_env_new(name)

# Footer para corrida standalone (el runner imprime por su cuenta).
test_finish <- function(e) {
  if (is.null(getOption("test_env"))) {
    cat("\n=====", e$TEST_NAME, "->", e$TEST_STATUS, "\n")
    if (length(e$TEST_MSGS) > 0) {
      cat(paste(e$TEST_MSGS, collapse = "\n"), "\n")
    }
  }
  invisible(NULL)
}

test_ok <- function(e, msg) {
  e$TEST_MSGS <- c(e$TEST_MSGS, paste0("   ok   ", msg))
  invisible(NULL)
}

test_fail <- function(e, msg) {
  e$TEST_STATUS <- "FAIL"
  e$TEST_MSGS <- c(e$TEST_MSGS, paste0("   FAIL ", msg))
  invisible(NULL)
}

test_skip <- function(e, reason) {
  if (e$TEST_STATUS == "PASS") {
    e$TEST_STATUS <- "SKIP"
  }
  e$TEST_MSGS <- c(e$TEST_MSGS, paste0("   skip ", reason))
  invisible(NULL)
}

# cond: logical (NA allowed). Records ok/fail accordingly.
test_assert <- function(e, cond, ok_msg, fail_msg) {
  if (is.na(cond)) {
    test_fail(e, paste0(fail_msg, " (resultado NA)"))
  } else if (cond) {
    test_ok(e, ok_msg)
  } else {
    test_fail(e, fail_msg)
  }
  invisible(NULL)
}
