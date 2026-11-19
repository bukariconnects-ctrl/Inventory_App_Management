import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import 'models/stakeholder_model.dart';

/// عمليات دليل المناديب والموزعين وسائقي المصنع على قاعدة البيانات.
class StakeholderRepository {
  StakeholderRepository({DatabaseHelper? databaseHelper})
    : _helper = databaseHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  /// كل الجهات مرتبة بالاسم، ويمكن حصرها بنوع أو بالنشطة فقط.
  Future<List<StakeholderModel>> getAll({
    StakeholderType? type,
    bool activeOnly = false,
  }) async {
    final Database db = await _helper.database;
    final List<String> conditions = <String>[
      if (type != null) 'type = ?',
      if (activeOnly) 'is_active = 1',
    ];
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseTables.stakeholders,
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: <Object?>[if (type != null) type.dbValue],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(StakeholderModel.fromMap).toList(growable: false);
  }

  /// المناديب والموزعون النشطون فقط.
  Future<List<StakeholderModel>> getDistributors() =>
      getAll(type: StakeholderType.distributor, activeOnly: true);

  /// سائقو المصنع والموردون النشطون فقط.
  Future<List<StakeholderModel>> getDrivers() =>
      getAll(type: StakeholderType.driver, activeOnly: true);

  /// جهة واحدة بالمعرّف، أو `null` إن لم توجد.
  Future<StakeholderModel?> getById(int id) async {
    final Database db = await _helper.database;
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseTables.stakeholders,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return StakeholderModel.fromMap(rows.first);
  }

  /// بحث بالاسم أو الهاتف أو رقم اللوحة، مع إمكانية حصر النوع.
  Future<List<StakeholderModel>> searchStakeholders(
    String query, {
    StakeholderType? type,
  }) async {
    final String term = query.trim();
    if (term.isEmpty) {
      return getAll(type: type);
    }
    final Database db = await _helper.database;
    final String pattern = '%$term%';
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseTables.stakeholders,
      where:
          '${type == null ? '' : 'type = ? AND '}'
          '(name LIKE ? OR phone LIKE ? OR vehicle_number LIKE ?)',
      whereArgs: <Object?>[
        if (type != null) type.dbValue,
        pattern,
        pattern,
        pattern,
      ],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(StakeholderModel.fromMap).toList(growable: false);
  }

  /// يضيف جهة تعامل جديدة ويعيدها بمعرّفها.
  Future<StakeholderModel> insertStakeholder(
    StakeholderModel stakeholder,
  ) async {
    final Database db = await _helper.database;
    final int id = await db.insert(
      DatabaseTables.stakeholders,
      stakeholder.toMap(),
    );
    return stakeholder.copyWith(id: id);
  }

  /// يحدّث جهة قائمة ويعيد عدد الصفوف المتأثرة.
  Future<int> updateStakeholder(StakeholderModel stakeholder) async {
    final int? id = stakeholder.id;
    if (id == null) {
      throw ArgumentError('لا يمكن تحديث جهة تعامل بدون معرّف (id).');
    }
    final Database db = await _helper.database;
    return db.update(
      DatabaseTables.stakeholders,
      stakeholder.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// يفعّل أو يعطّل جهة تعامل.
  Future<int> toggleStatus(int id, {bool? isActive}) async {
    final Database db = await _helper.database;
    final StakeholderModel? current = isActive == null
        ? await getById(id)
        : null;
    final bool nextValue = isActive ?? !(current?.isActive ?? true);
    return db.update(
      DatabaseTables.stakeholders,
      <String, Object?>{'is_active': nextValue ? 1 : 0},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// يحذف جهة تعامل نهائيًا.
  Future<int> deleteStakeholder(int id) async {
    final Database db = await _helper.database;
    return db.delete(
      DatabaseTables.stakeholders,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }
}
