import 'dart:async';
import 'package:postgres_crdt/postgres_crdt.dart';

/// Convenience class to handle database creation and upgrades
class DbUtil {
  DbUtil._(); // Makes class not-instantiable

  static Future<void> createTables(SqlCrdt crdt) async {
    print('[+] Creating tables');
    await crdt.execute('''
      CREATE TABLE IF NOT EXISTS events (
        id char(26) NOT NULL,
        profile_id char(26) NOT NULL,
        event_type varchar(64) NOT NULL,
        event_action varchar(64) NOT NULL,
        event_time integer NOT NULL,
        param_int integer,
        note text,
        PRIMARY KEY (id)
      )
    ''');

    await crdt.execute('''
      CREATE TABLE IF NOT EXISTS profiles (
        id char(26) PRIMARY KEY,
        name varchar(255) NOT NULL
      )
    ''');
  }
}
