import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import '../../core/constants/currency.dart';
import '../../features/groups/domain/group_fund.dart';
import '../database/app_database.dart';
import '../storage/access_guard.dart';
import '../storage/portable_snapshot.dart';

String groupRequestKey() => List.generate(
  16,
  (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
final _random = Random.secure();

class GroupRepository {
  GroupRepository(this.database);
  final AppDatabase database;
  static Future<GroupFund> read(DatabaseExecutor db, int id) async {
    final project = (await db.query(
      'trip_groups',
      where: 'id=?',
      whereArgs: [id],
    )).single;
    final members = await db.query(
      'trip_members',
      where: 'group_id=?',
      whereArgs: [id],
      orderBy: 'id',
    );
    final fund = GroupFund(project, {
      for (final m in members) m['id'] as int: TripMember.fromRow(m),
    });
    final rows = await db.query(
      'trip_events',
      where: 'group_id=?',
      whereArgs: [id],
      orderBy: 'id',
    );
    for (final r in rows) {
      fund.apply(r['id'] as int, TripEntry.fromRow(r));
    }
    return fund;
  }

  Future<GroupFund> get(int id) =>
      database.db.transaction((tx) => read(tx, id));
  Future<List<DataRow>> list() =>
      database.db.query('trip_groups', orderBy: 'project_date DESC,id DESC');
  static Future<void> validateAll(DatabaseExecutor db) async {
    for (final r in await db.query('trip_groups', columns: ['id'])) {
      final g = await read(db, r['id'] as int);
      requireFund(g.roster.isNotEmpty, 'Every group needs a member.');
      requireFund(
        g.events.values.every(
          (e) => e.member == null || !g.members[e.member]!.archived,
        ),
        'A member with financial records cannot be removed.',
      );
    }
  }

  static void _name(String text) {
    requireFund(
      text.trim().isNotEmpty && text.trim().length <= 120,
      'Enter a name of 1 to 120 characters.',
    );
  }

  static void _expected(int v) {
    requireFund(
      v >= 0 && v <= AppInfo.maxAmountMinor,
      'Enter a valid expected amount.',
    );
  }

  static Future<void> validateImage(Uint8List bytes) async {
    requireFund(
      bytes.isNotEmpty && bytes.length <= 1024 * 1024,
      'Choose a JPEG or PNG up to 1 MiB.',
    );
    requireFund(
      (await PortableSnapshot.validateContent(bytes)).startsWith('image/'),
      'Choose a JPEG or PNG image.',
    );
  }

  static Future<void> _image(
    DatabaseExecutor db,
    int group,
    int? event,
    Uint8List? bytes,
  ) async {
    if (bytes != null) {
      await validateImage(bytes);
      await db.insert('trip_images', {
        'group_id': group,
        'event_id': event,
        'data': base64Encode(bytes),
      });
    }
  }

  Future<Uint8List?> image(int group, int? event) async {
    final rows = await database.db.query(
      'trip_images',
      where: event == null
          ? 'group_id=? AND event_id IS NULL'
          : 'group_id=? AND event_id=?',
      whereArgs: [group, if (event != null) event],
    );
    return rows.isEmpty ? null : base64Decode(rows.single['data'] as String);
  }

  static Future<String> _requestHash(
    List<Object?> fields,
    Uint8List? image,
  ) async => PortableSnapshot.digest(
    utf8.encode(
      jsonEncode([
        ...fields,
        if (image != null) await PortableSnapshot.digest(image),
      ]),
    ),
  );

  Future<int> create({
    required String key,
    required String name,
    required AppCurrency currency,
    required DateTime date,
    required List<String> members,
    int expected = 0,
    int? budget,
    String location = '',
    String description = '',
    Uint8List? image,
  }) async {
    final fingerprint = await _requestHash([
      name.trim(),
      currency.code,
      date.millisecondsSinceEpoch,
      members.map((m) => m.trim()).toList(),
      expected,
      budget,
      location.trim(),
      description.trim(),
    ], image);
    _name(name);
    _expected(expected);
    if (budget != null) _expected(budget);
    requireFund(members.isNotEmpty, 'Enter at least one member name.');
    for (final m in members) {
      _name(m);
    }
    AccessGuard.writable();
    return database.db.transaction((tx) async {
      AccessGuard.writable();
      final prior = await tx.query(
        'trip_groups',
        where: 'request_key=?',
        whereArgs: [key],
      );
      if (prior.isNotEmpty) {
        requireFund(
          prior.single['request_hash'] == fingerprint,
          'This request was already used for another group.',
        );
        return prior.single['id'] as int;
      }
      final id = await tx.insert('trip_groups', {
        'request_key': key,
        'request_hash': fingerprint,
        'name': name.trim(),
        'currency': currency.code,
        'project_date': date.millisecondsSinceEpoch,
        'location': location.trim(),
        'description': description.trim(),
        'expected_minor': expected,
        'budget_minor': budget,
      });
      for (final m in members) {
        await tx.insert('trip_members', {
          'group_id': id,
          'name': m.trim(),
          'expected_minor': expected,
        });
      }
      await _image(tx, id, null, image);
      AccessGuard.writable();
      return id;
    });
  }

  Future<void> member(
    int group, {
    int? id,
    required String name,
    required int expected,
    bool remove = false,
  }) async {
    AccessGuard.writable();
    _name(name);
    _expected(expected);
    await database.db.transaction((tx) async {
      AccessGuard.writable();
      final g = await read(tx, group);
      requireFund(g.editable, 'Reopen the group before editing its members.');
      if (id == null) {
        await tx.insert('trip_members', {
          'group_id': group,
          'name': name.trim(),
          'expected_minor': expected,
        });
        return;
      }
      requireFund(
        g.members[id]?.archived == false,
        'Member no longer available.',
      );
      if (remove) {
        requireFund(
          g.roster.length > 1 &&
              !g.events.values.any(
                (e) => e.member == id || e.allocation.containsKey(id),
              ),
          'Keep at least one member. Members with financial history must stay on the roster.',
        );
      }
      await tx.update(
        'trip_members',
        {
          'name': name.trim(),
          'expected_minor': expected,
          'archived': remove ? 1 : 0,
        },
        where: 'id=? AND group_id=?',
        whereArgs: [id, group],
      );
    });
  }

  Future<int> post(
    int group,
    String key,
    TripEntry entry, {
    int? revision,
    Uint8List? image,
    TripEntry? replacement,
  }) async {
    AccessGuard.writable();
    final fingerprint = await _requestHash([
      group,
      entry.fields,
      replacement?.fields,
    ], image);
    return database.db.transaction((tx) async {
      AccessGuard.writable();
      final existing = await tx.query(
        'trip_events',
        where: 'request_key=?',
        whereArgs: [key],
      );
      if (existing.isNotEmpty) {
        final row = existing.single;
        requireFund(
          row['group_id'] == group && row['request_hash'] == fingerprint,
          'This request was already used for another entry.',
        );
        return row['id'] as int;
      }
      final g = await read(tx, group);
      if (revision != null || entry.kind == EntryKind.confirm) {
        requireFund(
          g.revision == revision,
          'The group changed. Review the current figures again.',
        );
      }
      Future<int> insert(String token, TripEntry e) async {
        requireFund(
          e.member == null || g.members[e.member]?.archived == false,
          'Choose an active member.',
        );
        final id = await tx.insert('trip_events', {
          'group_id': group,
          'request_key': token,
          'request_hash': fingerprint,
          ...e.fields,
          'recorded_at': DateTime.now().millisecondsSinceEpoch,
        });
        g.apply(id, e);
        return id;
      }

      final id = await insert(key, entry);
      var photoEvent = id;
      if (replacement != null) {
        final old = g.events[entry.related];
        requireFund(
          entry.kind == EntryKind.reverse &&
              old != null &&
              ((old.kind.purchase && replacement.kind.purchase) ||
                  (old.kind == EntryKind.contribution &&
                      replacement.kind == old.kind)),
          'Choose a matching replacement.',
        );
        photoEvent = await insert('$key/replacement', replacement);
        if (image == null) {
          await tx.rawInsert(
            'INSERT INTO trip_images(group_id,event_id,data) SELECT group_id,?,data FROM trip_images WHERE group_id=? AND event_id=?',
            [photoEvent, group, entry.related],
          );
        }
      }
      requireFund(
        image == null || g.events[photoEvent]!.kind.purchase,
        'Only a purchase can have a receipt.',
      );
      await _image(tx, group, photoEvent, image);
      AccessGuard.writable();
      return id;
    });
  }
}
