"# Set path for R history database"
options("rhist.path" = "%s")

.Last <- function() {
  if (interactive()) {
    exec_time <- system.time({
      rhist::save_session_history()
    }, gcFirst = FALSE)
    message("Saved R history in ", exec_time[3], " seconds")
  }
}
