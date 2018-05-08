#' Install rhist
#'
#' Initializes a new .rhistory.sqlite db and provides code to add a .Last
#' function to your .Rprofile
#'
#' @param dbpath Character. The path where an SQLite database should be
#'   installed. Defaults to the user's home directory.
#'
#' @export
install_rhist <- function(dbpath = default_rhist_path()) {

  if (dbpath == "")
    stop("rhist needs a persistent DB")

  if (fs::file_exists(dbpath)) {
    res <- try({
      db <- DBI::dbConnect(RSQLite::SQLite(), dbpath)
      tbls <- DBI::dbListTables(db)
      all(tbls %in% c("package_info",
                      "rhistory",
                      "session_command_holder",
                      "session_history",
                      "session_info_holder",
                      "session_packages"))
    }, silent = TRUE)

    if (class(res) == "try-error")
      stop("File is present but appears to be invalid. Delete ", dbpath, " and run install_rhist() again")
    if (!res)
      stop("File is present but appears to be invalid. Delete ", dbpath, " and run install_rhist() again")
    if (res) {
      message("It looks like a valid rhist database is already installed at ", dbpath, ". No action has been taken.")
    }
  } else {
    message("Initializing new rhist database at ", dbpath)
    initialize_rhist_db(dbpath)
  }
  use_rhist()
}

#' Create a default path for db within the user's home directory
#' @export
default_rhist_path <- function() {
  fs::path_home(".rhistory.sqlite")
}

#' Retrieve path of installed db
#' @export
installed_rhist_path <- function() {
  getOption("rhist.path")
}

# Function to generate the code needed in .Rprofile to save to rhistory based on
# a specified path
generate_rhist_last <- function(dbpath) {
  sprintf(readLines("inst/rhist_last.R"), dbpath)
}

use_rhist <- usethis::use_(
  usethis::edit_r_profile,
  todo_text = "Add code to your .Rprofile that will specify the home for the R command history SQLite file, and save command history every time an interactive R sesison closes.",
  code = generate_rhist_last(dbpath)
)

initialize_rhist_db <- function(dbpath) {
  db <- DBI::dbConnect(RSQLite::SQLite(), dbpath)

  DBI::dbWithTransaction(db, code = {

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

  })

  DBI::dbDisconnect(db)
  invisible()
}
