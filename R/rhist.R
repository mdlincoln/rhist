default_rhist_path <- function() {
  fs::path_home(".rhistory.sqlite")
}


install_rhist <- function() {
  use_rhist_path()
  initialize_rhist_db(dbpath = installed_rhist_path())
}

use_rhist_path <- usethis::use_(
  usethis::edit_r_profile,
  todo_text = "Specify the home for the R command history SQLite file in your .Rprofile",
  code = c(
    "# Set path for R history database",
    paste0('options("rhist.path" = "', default_rhist_path(), '")')
  ),
  .return =
)

installed_rhist_path <- function() {
  getOption("rhist.path")
}

initialize_rhist_db <- function(dbpath) {
  db <- DBI::dbConnect(RSQLite::SQLite(), dbpath)

  DBI::dbExecute(db, "CREATE TABLE session_history(
                 sid INTEGER PRIMARY KEY NOT NULL,
                 version TEXT NOT NULL,
                 system TEXT NOT NULL,
                 ui TEXT NOT NULL,
                 language TEXT NOT NULL,
                 r_collate TEXT NOT NULL,
                 session_time INTEGER NOT NULL)")

  DBI::dbExecute(db, "CREATE TABLE session_packages(
                 package TEXT NOT NULL,
                 version TEXT NOT NULL,
                 date INTEGER NOT NULL,
                 source TEXT NOT NULL,
                 sid INTEGER NOT NULL,
                 FOREIGN KEY (sid) REFERENCES session_history(sid))")

  DBI::dbExecute(db, "CREATE TABLE rhistory(
                 cmd NOT NULL,
                 sid INTEGER NOT NULL,
                 FOREIGN KEY (sid) REFERENCES session_history(sid))")

  DBI::dbDisconnect(db)
  invisible()
}

clear_history <- function() {
  tinytemp <- tempfile()
  write("", file = tinytemp)
  loadhistory(tinytemp)
}

.Last <- function() {

  exec_time <- system.time({
    hist_dbpath <- "~/.rhistory.sqlite"
    db <- DBI::dbConnect(RSQLite::SQLite(), hist_dbpath)
    DBI::dbExecute(db, "PRAGMA foreign_keys = ON")
    res <- DBI::dbWithTransaction(db, {
      si <- devtools::session_info()
      si_info <- si[["platform"]]
      si_info <- si_info[1:5]
      names(si_info)[5] <- "r_collate"
      si_info$session_time <- Sys.time()
      si_info <- as.data.frame(si_info, stringsAsFactors = FALSE)
      DBI::dbWriteTable(db, "session_history", si_info, append = TRUE)
      session_id <- DBI::dbGetQuery(db, "SELECT max(sid) FROM session_history")[1,1]

      si_packages <- si[["packages"]][,c(1,3:5)]
      si_packages$sid <- rep(session_id, nrow(si_packages))

      si_packages[["date"]] <- as.POSIXct(si_packages[["date"]])
      si_packages <- as.data.frame(si_packages)

      DBI::dbWriteTable(db, "session_packages", si_packages, append = TRUE)

      command_path <- tempfile()
      savehistory(file = command_path)
      session_commands <- readLines(command_path)

      session_df <- data.frame(
        cmd = session_commands,
        sid = session_id,
        stringsAsFactors = FALSE
      )
      DBI::dbWriteTable(db, "rhistory", session_df, append = TRUE)
    })
    if (res != 1) warning("Saving command history to ", hist_dbpath, " failed.")
    DBI::dbDisconnect(db)
    # Clear History
    clear_history()

  }, gcFirst = FALSE)
  message("Saved R history in ", exec_time[3], " seconds")
}
