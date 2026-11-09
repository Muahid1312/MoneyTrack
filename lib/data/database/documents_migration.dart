import 'package:sqflite/sqflite.dart';
Future<void> migrateDocumentsV5(Database db) async {
  await db.execute('''CREATE TABLE attachments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    transaction_id INTEGER NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    file_name TEXT NOT NULL UNIQUE,
    original_name TEXT NOT NULL,
    mime TEXT NOT NULL CHECK(mime IN ('image/jpeg','image/png','application/pdf')),
    size INTEGER NOT NULL CHECK(size>0 AND size<=10485760),
    sha256 TEXT NOT NULL CHECK(length(sha256)=64),
    created_at INTEGER NOT NULL
  )''');
  await db.execute('CREATE INDEX idx_attachment_transaction ON attachments(transaction_id)');
}
