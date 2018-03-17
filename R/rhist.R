default_rhist_path <- function() {
  fs::path_home(".rhistory.sqlite")
}

installed_rhist_path <- function() {
  getOption("rhist.path")
}

install_rhist <- function(dbpath = default_rhist_path()) {
  initialize_rhist_db(dbpath)
  use_rhist()
}

generate_rhist_last <- function(dbpath) {
  sprintf(readLines("inst/rhist_last.R"), dbpath)
}

use_rhist <- usethis::use_(
  usethis::edit_r_profile,
  todo_text = "Add code to your .Rprofile that will specify the home for the R command history SQLite file, and save command history every time an interactive R sesison closes.",
  code = generate_rhist_last(dbpath)
)

verify_rhist_db <- function(dbpath) {
  if (is.null(dbpath))
    stop("No path set for rhist database. Run initialize_rhist_db().")

  !fs::file_exists(dbpath)
    stop()
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

  DBI::dbExecute(db, "CREATE TABLE package_info(
                 pid INTEGER PRIMARY KEY,
                 package TEXT NOT NULL,
                 version TEXT NOT NULL,
                 date INTEGER NOT NULL,
                 source TEXT NOT NULL,
                 UNIQUE (package, version, date, source))")

  DBI::dbExecute(db, "CREATE TABLE session_packages(
                 pid INTEGER NOT NULL,
                 sid INTEGER NOT NULL,
                 FOREIGN KEY (pid) REFERENCES package_info(pid),
                 FOREIGN KEY (sid) REFERENCES session_history(sid))")

  DBI::dbExecute(db, "CREATE TABLE rhistory(
                 cmd NOT NULL,
                 sid INTEGER NOT NULL,
                 FOREIGN KEY (sid) REFERENCES session_history(sid))")

  DBI::dbExecute(db, "CREATE TABLE session_info_holder(
                        package TEXT NOT NULL,
                        version TEXT NOT NULL,
                        date INTEGER NOT NULL,
                        source TEXT NOT NULL)")

  DBI::dbExecute(db, "CREATE TABLE session_command_holder(
                      cmd TEXT NOT NULL)")

  DBI::dbExecute(db,
"CREATE TRIGGER history_update
AFTER INSERT ON session_command_holder
  BEGIN
    INSERT INTO rhistory
    SELECT
      cmd,
      (SELECT MAX(sid) FROM session_history) as sid
    FROM session_command_holder;

    DELETE FROM session_command_holder;
  END;")

  DBI::dbExecute(db,
"CREATE TRIGGER package_updater
AFTER INSERT ON session_info_holder
  BEGIN
    INSERT INTO package_info
    SELECT
      NULL as pid,
      package, version, date, source
    FROM session_info_holder
    LEFT JOIN package_info USING(package, version, date, source)
    WHERE package_info.pid IS NULL;

    INSERT INTO session_packages
    SELECT
      package_info.pid as pid,
      (SELECT max(sid) from session_history) as sid
    FROM session_info_holder
    LEFT JOIN package_info USING(package, version, date, source);

    DELETE FROM session_info_holder;
  END;")

  DBI::dbDisconnect(db)
  invisible()
}

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
