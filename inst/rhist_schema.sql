CREATE TABLE session_history(
  sid INTEGER PRIMARY KEY NOT NULL,
  version TEXT NOT NULL,
  system TEXT NOT NULL,
  ui TEXT NOT NULL,
  language TEXT NOT NULL,
  r_collate TEXT NOT NULL,
  session_time INTEGER NOT NULL
);
CREATE TABLE rhistory(
  cmd NOT NULL,
  sid INTEGER NOT NULL,
  FOREIGN KEY(sid) REFERENCES session_history(sid)
);
CREATE TABLE package_info(
  pid INTEGER PRIMARY KEY,
  package TEXT NOT NULL,
  version TEXT NOT NULL,
  date INTEGER NOT NULL,
  source TEXT NOT NULL,
  UNIQUE(package, version, date, source)
);
CREATE TABLE session_packages(
  pid INTEGER NOT NULL,
  sid INTEGER NOT NULL,
  FOREIGN KEY(pid) REFERENCES package_info(pid),
  FOREIGN KEY(sid) REFERENCES session_history(sid)
);
CREATE TABLE session_info_holder(
  package TEXT NOT NULL,
  version TEXT NOT NULL,
  date INTEGER NOT NULL,
  source TEXT NOT NULL
);
CREATE TABLE session_command_holder(cmd TEXT NOT NULL);
CREATE TRIGGER package_updater
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
  END;
CREATE TRIGGER history_update
AFTER INSERT ON session_command_holder
  BEGIN
    INSERT INTO rhistory
    SELECT
      cmd,
      (SELECT MAX(sid) FROM session_history) as sid
    FROM session_command_holder;

    DELETE FROM session_command_holder;
  END;
