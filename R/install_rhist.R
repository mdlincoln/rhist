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
