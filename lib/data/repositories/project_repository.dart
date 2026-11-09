import '../storage/access_guard.dart';
import '../../core/constants/currency.dart';
import '../database/app_database.dart';
import '../models/project.dart';
import '../models/transaction.dart';

class ProjectSnapshot {
  const ProjectSnapshot({required this.projects, required this.categories,
    required this.allocations, required this.transactions});
  final List<Project> projects;
  final List<ProjectCategory> categories;
  final List<ProjectAllocation> allocations;
  final List<TransactionModel> transactions;
}

class ProjectRepository {
  ProjectRepository(this.database);
  final AppDatabase database;

  Future<ProjectSnapshot> fetch() => database.db.transaction((txn) async {
    return ProjectSnapshot(
      projects: (await txn.query('projects', orderBy: 'updated_at DESC,id DESC')).map(Project.fromMap).toList(),
      categories: (await txn.query('project_categories', orderBy: 'name')).map(ProjectCategory.fromMap).toList(),
      allocations: (await txn.query('project_allocations', orderBy: 'occurred_at DESC,id DESC')).map(ProjectAllocation.fromMap).toList(),
      transactions: (await txn.query('transactions', where: 'project_id IS NOT NULL',
        orderBy: 'occurred_at DESC,id DESC')).map(TransactionModel.fromMap).toList(),
    );
  });

  Future<int> save(Project project) async {
    if (project.name.trim().isEmpty || project.name.trim().length > 100 ||
        project.description.length > 2000 || project.clientName.length > 100 ||
        (project.budgetMinor != null && (project.budgetMinor! < 0 || project.budgetMinor! > AppInfo.maxAmountMinor)) ||
        (project.contractMinor != null && (project.contractMinor! < 0 || project.contractMinor! > AppInfo.maxAmountMinor)) ||
        (project.deadline != null && project.deadline!.isBefore(project.startDate))) {
      throw ArgumentError('Enter valid project details, amounts and dates');
    }
    return database.db.transaction((txn) async {
    AccessGuard.writable();
      final map = project.toMap();
      if (project.id == null) {
        if (project.isArchived) throw ArgumentError('Create an unarchived project first');
        final id = await txn.insert('projects', map);
        for (final name in ['Materials', 'Labor', 'Services', 'Equipment', 'Other']) {
          await txn.insert('project_categories', {'project_id': id, 'name': name});
        }
        return id;
      }
      // Archive/restore has its own command so the previous status is retained.
      final rows = await txn.query('projects', where: 'id=?', whereArgs: [project.id]);
      if (rows.isEmpty) throw StateError('Project no longer exists');
      final previous = Project.fromMap(rows.single);
      if (project.isArchived != previous.isArchived) throw ArgumentError('Use archive or restore');
      map.remove('created_at');
      if (await txn.update('projects', map, where: 'id=?', whereArgs: [project.id]) != 1) {
        throw StateError('Project no longer exists');
      }
      return project.id!;
    });
  }

  Future<void> setArchived(int id, bool archived) => database.db.transaction((txn) async {
    AccessGuard.writable();
    final rows = await txn.query('projects', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) throw StateError('Project not found');
    final row = rows.single;
    final current = row['status'] as String;
    if (archived == (current == 'archived')) return;
    await txn.update('projects', {
      'status': archived ? 'archived' : row['archived_from'] ?? 'active',
      'archived_from': archived ? current : null,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, where: 'id=?', whereArgs: [id]);
  });

  Future<void> addCategory(int projectId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 60) throw ArgumentError('Enter a category name (1–60 characters)');
    await database.db.transaction((txn) async {
    AccessGuard.writable();
      final rows = await txn.query('projects', where: "id=? AND status != 'archived'", whereArgs: [projectId]);
      if (rows.isEmpty) throw StateError('Restore the project before adding categories');
      await txn.insert('project_categories', {'project_id': projectId, 'name': trimmed});
    });
  }

  Future<void> allocate(int projectId, int amountMinor, String note) async {
    if (amountMinor <= 0 || amountMinor > AppInfo.maxAmountMinor || note.length > 240) {
      throw ArgumentError('Enter a valid positive allocation');
    }
    await database.db.transaction((txn) async {
    AccessGuard.writable();
      await txn.insert('project_allocations', {'project_id': projectId,
        'amount_minor': amountMinor, 'note': note.trim(),
        'occurred_at': DateTime.now().millisecondsSinceEpoch});
    });
  }

  Future<void> removeAllocation(int id) async {
    await database.db.transaction((txn) async {
    AccessGuard.writable();
      await txn.delete('project_allocations', where: 'id=?', whereArgs: [id]);
    });
  }
}
