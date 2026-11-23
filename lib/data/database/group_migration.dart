import 'package:sqflite/sqflite.dart';

const groupTables = [
  'trip_groups',
  'trip_members',
  'trip_events',
  'trip_images',
];

Future<void> migrateGroupsV7(Database db) async {
  await db.execute('''CREATE TABLE trip_groups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    request_key TEXT NOT NULL UNIQUE CHECK(length(request_key)>0), request_hash TEXT NOT NULL CHECK(length(request_hash)=64),
    name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 120),
    currency TEXT NOT NULL CHECK(currency IN ('AFN','USD','EUR','PKR','JPY','KWD')),
    project_date INTEGER NOT NULL, location TEXT NOT NULL, description TEXT NOT NULL,
    expected_minor INTEGER NOT NULL CHECK(expected_minor BETWEEN 0 AND 99999999999),
    budget_minor INTEGER CHECK(budget_minor BETWEEN 0 AND 99999999999)
  )''');
  await db.execute('''CREATE TABLE trip_members (
    id INTEGER PRIMARY KEY AUTOINCREMENT, group_id INTEGER NOT NULL REFERENCES trip_groups(id),
    name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 120),
    expected_minor INTEGER NOT NULL CHECK(expected_minor BETWEEN 0 AND 99999999999),
    archived INTEGER NOT NULL DEFAULT 0 CHECK(archived IN (0,1)), UNIQUE(group_id,id)
  )''');
  await db.execute('''CREATE TABLE trip_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT, group_id INTEGER NOT NULL REFERENCES trip_groups(id),
    request_key TEXT NOT NULL UNIQUE CHECK(length(request_key)>0), request_hash TEXT NOT NULL CHECK(length(request_hash)=64), kind TEXT NOT NULL, member_id INTEGER,
    amount_minor INTEGER NOT NULL CHECK(amount_minor BETWEEN 0 AND 99999999999),
    occurred_at INTEGER NOT NULL, recorded_at INTEGER NOT NULL, related_id INTEGER,
    label TEXT NOT NULL, category TEXT NOT NULL, method TEXT NOT NULL, note TEXT NOT NULL,
    quantity INTEGER, unit_minor INTEGER, allocation TEXT NOT NULL,
    FOREIGN KEY(group_id,member_id) REFERENCES trip_members(group_id,id),
    FOREIGN KEY(group_id,related_id) REFERENCES trip_events(group_id,id), UNIQUE(group_id,id)
  )''');
  await db.execute('''CREATE TABLE trip_images (
    id INTEGER PRIMARY KEY AUTOINCREMENT, group_id INTEGER NOT NULL REFERENCES trip_groups(id),
    event_id INTEGER, data TEXT NOT NULL CHECK(length(data) BETWEEN 1 AND 1398104),
    FOREIGN KEY(group_id,event_id) REFERENCES trip_events(group_id,id)
  )''');
  await db.execute(
    'CREATE UNIQUE INDEX trip_cover ON trip_images(group_id) WHERE event_id IS NULL',
  );
  await db.execute(
    'CREATE UNIQUE INDEX trip_receipt ON trip_images(event_id) WHERE event_id IS NOT NULL',
  );
  await db.execute('CREATE INDEX trip_history ON trip_events(group_id,id)');
  await db.execute(
    '''CREATE TRIGGER trip_event_no_update BEFORE UPDATE ON trip_events
    BEGIN SELECT RAISE(ABORT,'Append a correction to the group journal'); END''',
  );
  await db.execute(
    '''CREATE TRIGGER trip_event_no_delete BEFORE DELETE ON trip_events
    BEGIN SELECT RAISE(ABORT,'Reverse the group entry and retain its history'); END''',
  );
  await db.execute(
    '''CREATE TRIGGER trip_currency_fixed BEFORE UPDATE OF currency ON trip_groups
    WHEN OLD.currency!=NEW.currency BEGIN SELECT RAISE(ABORT,'Group currency is fixed'); END''',
  );
}
