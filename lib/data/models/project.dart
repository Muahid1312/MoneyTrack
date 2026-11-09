import '../../core/constants/currency.dart';

enum ProjectType {
  personal('Personal'), business('Business');
  const ProjectType(this.label);
  final String label;
}

enum ProjectStatus {
  planned('Planned'), active('Active'), onHold('On hold'),
  completed('Completed'), archived('Archived');
  const ProjectStatus(this.label);
  final String label;
}

class Project {
  const Project({this.id, required this.name, this.description = '',
    required this.type, this.clientName = '', required this.currency,
    this.budgetMinor, this.contractMinor, required this.startDate,
    this.deadline, this.status = ProjectStatus.planned,
    this.color = 0xFF10B981, this.icon = 'folder',
    required this.createdAt, required this.updatedAt});

  final int? id;
  final String name, description, clientName, icon;
  final ProjectType type;
  final AppCurrency currency;
  final int? budgetMinor, contractMinor;
  final DateTime startDate, createdAt, updatedAt;
  final DateTime? deadline;
  final ProjectStatus status;
  final int color;
  bool get isArchived => status == ProjectStatus.archived;

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'name': name.trim(), 'description': description.trim(), 'type': type.name,
    'client_name': type == ProjectType.business ? clientName.trim() : '',
    'currency': currency.code, 'budget_minor': budgetMinor,
    'contract_minor': type == ProjectType.business ? contractMinor : null,
    'start_date': startDate.millisecondsSinceEpoch,
    'deadline': deadline?.millisecondsSinceEpoch, 'status': status.name,
    'color': color, 'icon': icon,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  factory Project.fromMap(Map<String, Object?> m) => Project(
    id: m['id'] as int, name: m['name'] as String,
    description: m['description'] as String, type: ProjectType.values.byName(m['type'] as String),
    clientName: m['client_name'] as String, currency: AppCurrency.requireCode(m['currency'] as String),
    budgetMinor: m['budget_minor'] as int?, contractMinor: m['contract_minor'] as int?,
    startDate: DateTime.fromMillisecondsSinceEpoch(m['start_date'] as int),
    deadline: m['deadline'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['deadline'] as int),
    status: ProjectStatus.values.byName(m['status'] as String),
    color: m['color'] as int, icon: m['icon'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
  );
}

class ProjectCategory {
  const ProjectCategory({required this.id, required this.projectId, required this.name});
  final int id, projectId;
  final String name;
  factory ProjectCategory.fromMap(Map<String, Object?> m) => ProjectCategory(
    id: m['id'] as int, projectId: m['project_id'] as int, name: m['name'] as String);
}

/// A planning earmark denominated in the project's immutable currency.
/// It neither moves wallet money nor creates an income transaction.
class ProjectAllocation {
  const ProjectAllocation({required this.id, required this.projectId,
    required this.amountMinor, required this.note, required this.occurredAt});
  final int id, projectId, amountMinor;
  final String note;
  final DateTime occurredAt;
  factory ProjectAllocation.fromMap(Map<String, Object?> m) => ProjectAllocation(
    id: m['id'] as int, projectId: m['project_id'] as int,
    amountMinor: m['amount_minor'] as int, note: m['note'] as String,
    occurredAt: DateTime.fromMillisecondsSinceEpoch(m['occurred_at'] as int));
}
