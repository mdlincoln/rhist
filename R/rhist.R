clear_history <- function() {
  tinytemp <- tempfile()
  write("", file = tinytemp)
  loadhistory(tinytemp)
}

insert_session_info <- function(db, si) {
  si_info <- si[["platform"]]
  si_info <- si_info[1:5]
  names(si_info)[5] <- "r_collate"
  si_info$session_time <- Sys.time()
  si_info <- as.data.frame(si_info, stringsAsFactors = FALSE)
  DBI::dbWriteTable(db, "session_history", si_info, append = TRUE)
}

insert_session_packages <- function(db, si) {
  si_packages <- as.data.frame(si[["packages"]], stringsAsFactors = FALSE)[,c(1,3:5)]
  si_packages[["date"]] <- as.POSIXct(si_packages[["date"]])

  DBI::dbWriteTable(db, "session_info_holder", si_packages, append = TRUE)
}

collect_session_commands <- function() {
  command_path <- tempfile()
  savehistory(file = command_path)
  readLines(command_path)
}

insert_session_commands <- function(db) {

  session_commands <- collect_session_commands()

  # If no commands were issued during the session, exit out early.
  if (length(session_commands) == 0) return()

  session_df <- data.frame(
    cmd = session_commands,
    stringsAsFactors = FALSE)

  DBI::dbWriteTable(db, "session_command_holder", session_df, append = TRUE)
}

#' Save current session history to specified SQLite database
#'
#' @param dbpath Path to rhist database.
#'
#' @export
save_session_history <- function(dbpath = installed_rhist_path()) {
  try({
    db <- DBI::dbConnect(RSQLite::SQLite(), dbpath)
    # Enforce foreign key checks
    DBI::dbExecute(db, "PRAGMA foreign_keys = ON")
    si <- devtools::session_info()

    res <- DBI::dbWithTransaction(db, {
      insert_session_info(db, si)
      insert_session_packages(db, si)
      insert_session_commands(db)
    })

    if (!is.null(res)) {
      if (res != TRUE) {
        warning("Saving session and command history to ", hist_dbpath, " failed.")
      }
    }

    DBI::dbDisconnect(db)

    # Clear History
    clear_history()
  })
}
