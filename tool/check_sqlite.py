#!/usr/bin/env python3
"""Direct SQLite checks of extracted migration SQL; does not execute Dart code."""
import pathlib
import re
import sqlite3
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
DB_SOURCE = (ROOT / 'lib/data/database/app_database.dart').read_text()
LEGACY = re.search(r"_createLegacy\(Database db\) => db.execute\('\'\'(.*?)'\'\'\);", DB_SOURCE, re.S).group(1)
V2 = DB_SOURCE[DB_SOURCE.index('static Future<void> _upgradeV2'):]
MIGRATIONS = [V2] + [(ROOT / ('lib/data/database/' + name)).read_text() for name in
    ['project_migration.dart', 'planning_migration.dart', 'documents_migration.dart']]


def execute(db, source):
    statements = re.findall(r"await db.execute\(('\'\'.*?'\'\'|'(?:\\.|[^'\\])*')\);", source, re.S)
    for index, raw in enumerate(statements):
        sql = raw[3:-3] if raw.startswith("'" * 3) else raw[1:-1].replace("\\'", "'")
        sql = sql.replace('${currency.code}', 'USD')
        if '$event' in sql or '${event.toLowerCase()}' in sql:
            for event in ['INSERT', 'UPDATE']:
                db.execute(sql.replace('${event.toLowerCase()}', event.lower()).replace('$event', event))
        else:
            db.execute(sql)
        if source is V2 and index == 0:
            db.execute("INSERT INTO wallets(id,name,type,currency,opening_minor) VALUES(1,'Cash','cash','USD',0)")


def fresh():
    db = sqlite3.connect(':memory:')
    db.execute('PRAGMA foreign_keys=ON')
    db.execute(LEGACY)
    for migration in MIGRATIONS:
        execute(db, migration)
    return db


# Upgrade fixtures from every prior schema version. Preserve a populated ledger.
for old in [1, 2, 3, 4]:
    db = sqlite3.connect(':memory:')
    db.execute('PRAGMA foreign_keys=ON')
    db.execute(LEGACY)
    for migration in MIGRATIONS[:old - 1]:
        execute(db, migration)
    if old == 1:
        db.execute("INSERT INTO transactions VALUES(17,'income',700,'salary','Keep me',100,100,100)")
    else:
        db.execute("INSERT INTO transactions(id,type,amount_minor,category_id,note,occurred_at,created_at,updated_at,wallet_id,currency) VALUES(17,'income',700,'salary','Keep me',100,100,100,1,'USD')")
    db.commit()
    db.execute('BEGIN')
    for migration in MIGRATIONS[old - 1:]:
        execute(db, migration)
    db.execute('PRAGMA user_version=5')
    db.commit()
    assert db.execute('SELECT id,amount_minor,note FROM transactions').fetchall() == [(17, 700, 'Keep me')]
    assert db.execute('SELECT balance FROM wallet_positions WHERE id=1').fetchone() == (700,)
    assert db.execute('PRAGMA foreign_key_check').fetchall() == []
    db.close()
print('PASS: populated schema 1/2/3/4 → 5 SQL upgrade fixtures.')

db = fresh()
checks=0
def check(v):
 global checks
 assert v;checks+=1
# Real current-schema SQL: canonical ID and receipt metadata restore together.
db.execute('UPDATE wallets SET opening_minor=100000 WHERE id=1')
sql="INSERT INTO transactions(type,amount_minor,category_id,note,occurred_at,created_at,updated_at,wallet_id,currency) VALUES('expense',100,'other',?,100,100,100,1,'USD')"
id=db.execute(sql,('Undo receipt',)).lastrowid
name='a'*32+'.png';db.execute("INSERT INTO attachments(transaction_id,file_name,original_name,mime,size,sha256,created_at) VALUES(?,?,'Receipt','image/png',100,?,100)",(id,name,'b'*64))
row=db.execute('SELECT * FROM transactions WHERE id=?',(id,)).fetchone();attachment=db.execute('SELECT * FROM attachments').fetchone()
db.execute('DELETE FROM transactions WHERE id=?',(id,));check(db.execute('SELECT COUNT(*) FROM attachments').fetchone()[0]==0)
columns=[x[1] for x in db.execute('PRAGMA table_info(transactions)')];ac=[x[1] for x in db.execute('PRAGMA table_info(attachments)')]
restore=f"INSERT INTO transactions({','.join(columns)}) VALUES({','.join('?' for _ in columns)})";attach=f"INSERT INTO attachments({','.join(ac)}) VALUES({','.join('?' for _ in ac)})"
db.execute("CREATE TRIGGER fail_receipt BEFORE INSERT ON attachments BEGIN SELECT RAISE(ABORT,'Injected failure'); END")
db.commit();db.execute('BEGIN')
try:
 db.execute(restore,row);db.execute(attach,attachment)
except sqlite3.IntegrityError:db.rollback()
else:raise AssertionError('Failure injection did not fail')
check(db.execute('SELECT COUNT(*) FROM transactions WHERE id=?',(id,)).fetchone()[0]==0)
db.execute('DROP TRIGGER fail_receipt');db.commit();db.execute('BEGIN');db.execute(restore,row);db.execute(attach,attachment);db.commit()
check(db.execute('SELECT * FROM transactions WHERE id=?',(id,)).fetchone()==row);check(db.execute('SELECT * FROM attachments').fetchone()==attachment)
# Exercise large tied-date histories and the actual onOpen composite index.
db.execute('UPDATE wallets SET opening_minor=10000000 WHERE id=1')
db.executemany(sql,[(f'Entry {i}',) for i in range(25000)]);db.commit()
query='SELECT * FROM transactions ORDER BY occurred_at DESC,id DESC LIMIT 50'
before=[x[3] for x in db.execute('EXPLAIN QUERY PLAN '+query)]
source=DB_SOURCE;index=re.search(r"onOpen:.*?db.execute\('(.*?)'\)",source).group(1);db.execute(index)
after=[x[3] for x in db.execute('EXPLAIN QUERY PLAN '+query)]
check(any('idx_tx_history_order' in x for x in after));check(not any('TEMP B-TREE' in x for x in after))
start=time.perf_counter();result=db.execute(query).fetchall();elapsed=(time.perf_counter()-start)*1000
check(len(result)==50);check(all(result[i][0]>result[i+1][0] for i in range(49)))
check(db.execute("SELECT SUM(amount_minor) FROM transactions WHERE type='expense'").fetchone()[0]==2500100)
check(db.execute('PRAGMA foreign_key_check').fetchall()==[]);check(db.execute('PRAGMA integrity_check').fetchone()[0]=='ok')
print(f'PASS: {checks} Phase 5 direct SQLite rollback, receipt restoration and large-history checks.')
print(f'25,001-entry history: newest 50 rows fetched in {elapsed:.2f} ms on this host; this is not a Flutter profile.')
print('Query plan before:',before,'after:',after)
