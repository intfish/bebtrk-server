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

    await crdt.execute('drop view if exists event_intervals');
    await crdt.execute('''
      create or replace view event_intervals as
      with clean_events as (
          select
              *
          from (
              select
                  *
                  , (event_type = 'start' and (lead(event_type) over w <> 'start' or lead(event_type) over w is null)) as is_start
                  , (lag(event_type) over w is null or lag(event_type) over w = 'start') as is_prev_start
              from events
              where is_deleted = 0 and event_type != 'moment'
              window w as (PARTITION BY profile_id, event_action ORDER BY event_time DESC)
          ) as ts_pairs
          where
              is_start = true or (is_start = false and is_prev_start = true)
      )
      select
          *
          , (event_stop - event_start) as duration
      from (
          select
              *
              , event_time as event_start
              , lag(event_time) over w as event_stop
              , lag(id) over w as stop_id
          from clean_events
          window w as (PARTITION BY profile_id ORDER BY event_time DESC)
      ) as ts_pairs
      where ts_pairs.event_type = 'start'
    ''');
  }
}
