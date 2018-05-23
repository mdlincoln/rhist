#' Collect command and session history
#'
#' A data frame with command text and session info
#'
#' @param rhist_path Path of rhist database
#'
#' @return A data frame
#'
#' @export
collect_rhist <- function(rhist_path = installed_rhist_path()) {
  db <- DBI::dbConnect(RSQLite::SQLite(), rhist_path)
  res <- DBI::dbGetQuery(db, "SELECT * FROM rhistory LEFT JOIN session_history USING (sid)")
  DBI::dbDisconnect(db)
  res$session_time <- as.POSIXct(res$session_time, origin = "1970-01-01")
  return(res)
}

#' @describeIn collect_rhist A data frame with package info for each session
#' @export
collect_session_packages <- function(rhist_path = installed_rhist_path()) {
  db <- DBI::dbConnect(RSQLite::SQLite(), rhist_path)
  res <- DBI::dbGetQuery(db, "SELECT * FROM session_packages LEFT JOIN package_info USING (pid)")
  DBI::dbDisconnect(db)
  res$date <- as.POSIXct(res$date, origin = "1970-01-01")
  return(res)
}
