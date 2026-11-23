import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_exceptions.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../reports/data/models/report_models.dart';
import '../../stocktake/data/models/stocktake_model.dart';
import 'models/transaction_model.dart';

/// ينفّذ الحركات المخزنية داخل `db.transaction()` لضمان الذرّية والتوازن.
///
/// كل عملية تُدرج السند وتحدّث الرصيد في نفس المعاملة: إما أن تنجح
/// بالكامل أو تُلغى بالكامل (rollback) دون أي أثر جزئي.
class TransactionRepository {
  TransactionRepository({DatabaseHelper? databaseHelper})
    : _helper = databaseHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  // ---------------------------------------------------------------------------
  // سند استلام (INBOUND)
  // ---------------------------------------------------------------------------

  /// يسجّل استلام كمية من المصنع ويزيد رصيد المخزن.
  Future<TransactionModel> createInbound({
    required int warehouseId,
    required int itemId,
    required int quantity,
    String? partyName,
    String? orderReference,
    String? vehicleNumber,
    String? notes,
    DateTime? createdAt,
  }) async {
    _validatePositiveQuantity(quantity);
    final DateTime timestamp = createdAt ?? DateTime.now();
    final Database db = await _helper.database;

    return db.transaction<TransactionModel>((Transaction txn) async {
      final int current = await _currentQuantity(txn, warehouseId, itemId);
      final String voucherNumber = await _nextVoucherNumber(
        txn,
        TransactionTypes.inbound,
        timestamp,
      );

      final TransactionModel transaction = TransactionModel(
        transactionType: TransactionTypes.inbound,
        voucherNumber: voucherNumber,
        warehouseId: warehouseId,
        itemId: itemId,
        quantity: quantity,
        partyName: partyName,
        orderReference: orderReference,
        vehicleNumber: vehicleNumber,
        notes: notes,
        createdAt: timestamp,
      );

      final int id = await txn.insert(
        DatabaseTables.transactions,
        transaction.toMap(),
      );
      await _setQuantity(
        txn,
        warehouseId: warehouseId,
        itemId: itemId,
        newQuantity: current + quantity,
        updatedAt: timestamp,
      );

      return transaction.copyWith(id: id);
    });
  }

  // ---------------------------------------------------------------------------
  // سند صرف (OUTBOUND)
  // ---------------------------------------------------------------------------

  /// يسجّل صرف كمية لموزّع/مندوب ويخصمها من الرصيد.
  ///
  /// يرمي [InsufficientStockException] إذا كانت الكمية أكبر من الرصيد المتاح.
  Future<TransactionModel> createOutbound({
    required int warehouseId,
    required int itemId,
    required int quantity,
    String? partyName,
    String? orderReference,
    String? vehicleNumber,
    String? notes,
    DateTime? createdAt,
  }) async {
    _validatePositiveQuantity(quantity);
    final DateTime timestamp = createdAt ?? DateTime.now();
    final Database db = await _helper.database;

    return db.transaction<TransactionModel>((Transaction txn) async {
      final int current = await _currentQuantity(txn, warehouseId, itemId);
      if (current < quantity) {
        throw InsufficientStockException(
          availableQuantity: current,
          requestedQuantity: quantity,
          warehouseId: warehouseId,
          itemId: itemId,
          operationType: TransactionTypes.outbound,
        );
      }

      final String voucherNumber = await _nextVoucherNumber(
        txn,
        TransactionTypes.outbound,
        timestamp,
      );

      final TransactionModel transaction = TransactionModel(
        transactionType: TransactionTypes.outbound,
        voucherNumber: voucherNumber,
        warehouseId: warehouseId,
        itemId: itemId,
        quantity: quantity,
        partyName: partyName,
        orderReference: orderReference,
        vehicleNumber: vehicleNumber,
        notes: notes,
        createdAt: timestamp,
      );

      final int id = await txn.insert(
        DatabaseTables.transactions,
        transaction.toMap(),
      );
      await _setQuantity(
        txn,
        warehouseId: warehouseId,
        itemId: itemId,
        newQuantity: current - quantity,
        updatedAt: timestamp,
      );

      return transaction.copyWith(id: id);
    });
  }

  // ---------------------------------------------------------------------------
  // سند إتلاف (DAMAGE)
  // ---------------------------------------------------------------------------

  /// يسجّل إتلاف كمية تالفة ويخصمها من الرصيد.
  ///
  /// [reason] إلزامي لتوثيق سبب الهدر، ويرمي [InsufficientStockException]
  /// إذا كانت الكمية أكبر من الرصيد المتاح.
  Future<TransactionModel> createDamage({
    required int warehouseId,
    required int itemId,
    required int quantity,
    required String reason,
    String? partyName,
    String? notes,
    DateTime? createdAt,
  }) async {
    _validatePositiveQuantity(quantity);
    if (reason.trim().isEmpty) {
      throw ArgumentError('سبب الإتلاف مطلوب ولا يمكن تركه فارغًا.');
    }
    final DateTime timestamp = createdAt ?? DateTime.now();
    final Database db = await _helper.database;

    return db.transaction<TransactionModel>((Transaction txn) async {
      final int current = await _currentQuantity(txn, warehouseId, itemId);
      if (current < quantity) {
        throw InsufficientStockException(
          availableQuantity: current,
          requestedQuantity: quantity,
          warehouseId: warehouseId,
          itemId: itemId,
          operationType: TransactionTypes.damage,
        );
      }

      final String voucherNumber = await _nextVoucherNumber(
        txn,
        TransactionTypes.damage,
        timestamp,
      );

      final TransactionModel transaction = TransactionModel(
        transactionType: TransactionTypes.damage,
        voucherNumber: voucherNumber,
        warehouseId: warehouseId,
        itemId: itemId,
        quantity: quantity,
        partyName: partyName,
        reason: reason.trim(),
        notes: notes,
        createdAt: timestamp,
      );

      final int id = await txn.insert(
        DatabaseTables.transactions,
        transaction.toMap(),
      );
      await _setQuantity(
        txn,
        warehouseId: warehouseId,
        itemId: itemId,
        newQuantity: current - quantity,
        updatedAt: timestamp,
      );

      return transaction.copyWith(id: id);
    });
  }

  // ---------------------------------------------------------------------------
  // الطلبات المعلقة ودورة الاعتماد
  // ---------------------------------------------------------------------------

  /// يسجّل طلب صرف بدل تالف لمندوب بحالة `PENDING`.
  ///
  /// **قاعدة صارمة:** لا يُخصم أي رصيد من `stock_balances` عند الإنشاء؛
  /// الخصم يتم فقط عند اعتماد الطلب عبر [approvePendingTransaction].
  Future<TransactionModel> createPendingMarketReplacement({
    required int warehouseId,
    required int itemId,
    required int quantity,
    required String partyName,
    required String orderReference,
    required String reason,
    String? vehicleNumber,
    String? notes,
    DateTime? createdAt,
  }) async {
    _validatePositiveQuantity(quantity);
    if (partyName.trim().isEmpty) {
      throw ArgumentError('اسم المندوب المستفيد مطلوب.');
    }
    if (orderReference.trim().isEmpty) {
      throw ArgumentError('رقم أمر الصرف الإداري مطلوب.');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('مبرر بدل التالف مطلوب.');
    }

    return _insertPendingRequest(
      transactionType: TransactionTypes.marketReplacement,
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: quantity,
      partyName: partyName.trim(),
      orderReference: orderReference.trim(),
      vehicleNumber: _cleanOptional(vehicleNumber),
      reason: reason.trim(),
      notes: _cleanOptional(notes),
      timestamp: createdAt ?? DateTime.now(),
    );
  }

  /// يسجّل محضر إتلاف مخزني داخلي بحالة `PENDING` باسم أمين المخزن.
  ///
  /// **قاعدة صارمة:** لا يُخصم أي رصيد عند الإنشاء.
  Future<TransactionModel> createPendingInternalDamage({
    required int warehouseId,
    required int itemId,
    required int quantity,
    required String reason,
    required String responsibleName,
    String? notes,
    DateTime? createdAt,
  }) async {
    _validatePositiveQuantity(quantity);
    if (reason.trim().isEmpty) {
      throw ArgumentError('سبب الإتلاف مطلوب.');
    }
    if (responsibleName.trim().isEmpty) {
      throw ArgumentError('اسم أمين المخزن المسؤول مطلوب.');
    }

    return _insertPendingRequest(
      transactionType: TransactionTypes.damage,
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: quantity,
      partyName: responsibleName.trim(),
      reason: reason.trim(),
      notes: _cleanOptional(notes),
      timestamp: createdAt ?? DateTime.now(),
    );
  }

  /// يعتمد طلبًا معلقًا: يتحقق من الرصيد، يخصمه، ثم يحوّل الحالة إلى
  /// `APPROVED` — كل ذلك داخل معاملة واحدة (ذرّية بالكامل).
  ///
  /// يرمي [InsufficientStockException] إذا لم يعد الرصيد كافيًا، و
  /// [ArgumentError] إذا لم يكن السند معلقًا أو غير موجود.
  Future<TransactionModel> approvePendingTransaction(int transactionId) async {
    final Database db = await _helper.database;

    return db.transaction<TransactionModel>((Transaction txn) async {
      final TransactionModel pending = await _requirePending(
        txn,
        transactionId,
      );

      final int current = await _currentQuantity(
        txn,
        pending.warehouseId,
        pending.itemId,
      );
      if (current < pending.quantity) {
        throw InsufficientStockException(
          availableQuantity: current,
          requestedQuantity: pending.quantity,
          warehouseId: pending.warehouseId,
          itemId: pending.itemId,
          operationType: pending.transactionType,
        );
      }

      final DateTime approvedAt = DateTime.now();
      await _setQuantity(
        txn,
        warehouseId: pending.warehouseId,
        itemId: pending.itemId,
        newQuantity: current - pending.quantity,
        updatedAt: approvedAt,
      );
      await txn.update(
        DatabaseTables.transactions,
        <String, Object?>{
          'status': TransactionStatus.approved,
          'rejection_reason': null,
        },
        where: 'id = ?',
        whereArgs: <Object?>[transactionId],
      );

      return pending.copyWith(status: TransactionStatus.approved);
    });
  }

  /// يرفض طلبًا معلقًا ويسجّل سبب الرفض دون أي مساس بالرصيد.
  Future<TransactionModel> rejectPendingTransaction(
    int transactionId,
    String reason,
  ) async {
    final String rejectionReason = reason.trim();
    if (rejectionReason.isEmpty) {
      throw ArgumentError('سبب الرفض مطلوب.');
    }

    final Database db = await _helper.database;

    return db.transaction<TransactionModel>((Transaction txn) async {
      final TransactionModel pending = await _requirePending(
        txn,
        transactionId,
      );

      await txn.update(
        DatabaseTables.transactions,
        <String, Object?>{
          'status': TransactionStatus.rejected,
          'rejection_reason': rejectionReason,
        },
        where: 'id = ?',
        whereArgs: <Object?>[transactionId],
      );

      return pending.copyWith(
        status: TransactionStatus.rejected,
        rejectionReason: rejectionReason,
      );
    });
  }

  /// كل السندات المعلقة (الأحدث أولًا)، مع إمكانية حصرها بمخزن واحد.
  Future<List<TransactionModel>> getPendingTransactions({
    int? warehouseId,
  }) async {
    final Database db = await _helper.database;
    final List<String> conditions = <String>['status = ?'];
    final List<Object?> args = <Object?>[TransactionStatus.pending];
    if (warehouseId != null) {
      conditions.add('warehouse_id = ?');
      args.add(warehouseId);
    }

    final List<Map<String, Object?>> rows = await db.query(
      DatabaseTables.transactions,
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(TransactionModel.fromMap).toList(growable: false);
  }

  /// عدد الطلبات المعلقة (للعرض في لوحة التحكم).
  Future<int> countPendingTransactions({int? warehouseId}) async {
    final Database db = await _helper.database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ${DatabaseTables.transactions}
      WHERE status = ?${warehouseId == null ? '' : ' AND warehouse_id = ?'}
    ''',
      <Object?>[
        TransactionStatus.pending,
        if (warehouseId != null) warehouseId,
      ],
    );
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  /// يُدرج سندًا بحالة معلقة دون لمس الأرصدة.
  Future<TransactionModel> _insertPendingRequest({
    required String transactionType,
    required int warehouseId,
    required int itemId,
    required int quantity,
    required String partyName,
    required String reason,
    required DateTime timestamp,
    String? orderReference,
    String? vehicleNumber,
    String? notes,
  }) async {
    final Database db = await _helper.database;

    return db.transaction<TransactionModel>((Transaction txn) async {
      final String voucherNumber = await _nextVoucherNumber(
        txn,
        transactionType,
        timestamp,
      );

      final TransactionModel request = TransactionModel(
        transactionType: transactionType,
        voucherNumber: voucherNumber,
        warehouseId: warehouseId,
        itemId: itemId,
        quantity: quantity,
        partyName: partyName,
        orderReference: orderReference,
        vehicleNumber: vehicleNumber,
        reason: reason,
        notes: notes,
        status: TransactionStatus.pending,
        createdAt: timestamp,
      );

      final int id = await txn.insert(
        DatabaseTables.transactions,
        request.toMap(),
      );
      return request.copyWith(id: id);
    });
  }

  /// يجلب سندًا معلقًا أو يرمي خطأً عربيًا واضحًا.
  Future<TransactionModel> _requirePending(
    DatabaseExecutor executor,
    int transactionId,
  ) async {
    final List<Map<String, Object?>> rows = await executor.query(
      DatabaseTables.transactions,
      where: 'id = ?',
      whereArgs: <Object?>[transactionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw ArgumentError('السند المطلوب غير موجود.');
    }

    final TransactionModel transaction = TransactionModel.fromMap(rows.first);
    if (transaction.status != TransactionStatus.pending) {
      throw ArgumentError(
        'لا يمكن تنفيذ العملية: السند حالته '
        '"${TransactionStatus.label(transaction.status)}".',
      );
    }
    return transaction;
  }

  // ---------------------------------------------------------------------------
  // الجرد والتسوية (ADJUSTMENT)
  // ---------------------------------------------------------------------------

  /// يعتمد جردًا فعليًا: يحفظ سجل الجرد، ينشئ حركة تسوية بالفارق،
  /// ويجعل رصيد النظام مطابقًا للرصيد الفعلي — كل ذلك في معاملة واحدة.
  ///
  /// لا تُنشأ حركة تسوية عندما يكون الفارق صفرًا (لا يوجد ما يُسوّى).
  Future<StocktakeModel> adjustStocktake({
    required int warehouseId,
    required int itemId,
    required int actualQuantity,
    String? notes,
    DateTime? createdAt,
  }) async {
    if (actualQuantity < 0) {
      throw ArgumentError.value(
        actualQuantity,
        'actualQuantity',
        'الرصيد الفعلي لا يمكن أن يكون سالبًا.',
      );
    }
    final DateTime timestamp = createdAt ?? DateTime.now();
    final Database db = await _helper.database;

    return db.transaction<StocktakeModel>((Transaction txn) async {
      final int systemQuantity = await _currentQuantity(
        txn,
        warehouseId,
        itemId,
      );
      final int difference = actualQuantity - systemQuantity;

      final StocktakeModel stocktake = StocktakeModel(
        warehouseId: warehouseId,
        itemId: itemId,
        systemQuantity: systemQuantity,
        actualQuantity: actualQuantity,
        difference: difference,
        notes: notes,
        createdAt: timestamp,
      );

      final int stocktakeId = await txn.insert(
        DatabaseTables.stocktakes,
        stocktake.toMap(),
      );

      if (difference != 0) {
        final String voucherNumber = await _nextVoucherNumber(
          txn,
          TransactionTypes.adjustment,
          timestamp,
        );
        final TransactionModel adjustment = TransactionModel(
          transactionType: TransactionTypes.adjustment,
          voucherNumber: voucherNumber,
          warehouseId: warehouseId,
          itemId: itemId,
          quantity: difference,
          reason: (notes == null || notes.trim().isEmpty)
              ? 'تسوية جرد'
              : notes.trim(),
          notes: notes,
          createdAt: timestamp,
        );
        await txn.insert(DatabaseTables.transactions, adjustment.toMap());
      }

      await _setQuantity(
        txn,
        warehouseId: warehouseId,
        itemId: itemId,
        newQuantity: actualQuantity,
        updatedAt: timestamp,
      );

      return stocktake.copyWith(id: stocktakeId);
    });
  }

  // ---------------------------------------------------------------------------
  // استعلامات مساعدة
  // ---------------------------------------------------------------------------

  /// يعاين رقم السند التالي دون حجز أو إنشاء أي سجل.
  Future<String> nextVoucherNumber({
    required String transactionType,
    DateTime? date,
  }) async {
    if (!TransactionTypes.isKnown(transactionType)) {
      throw ArgumentError.value(
        transactionType,
        'transactionType',
        'نوع حركة غير معروف.',
      );
    }
    final Database db = await _helper.database;
    return _nextVoucherNumber(db, transactionType, date ?? DateTime.now());
  }

  /// حركات مخزن محدد (الأحدث أولًا) مع إمكانية حصرها بنوع واحد.
  Future<List<TransactionModel>> listTransactions({
    int? warehouseId,
    String? transactionType,
    int? limit,
  }) async {
    final Database db = await _helper.database;
    final List<String> conditions = <String>[];
    final List<Object?> args = <Object?>[];

    if (warehouseId != null) {
      conditions.add('warehouse_id = ?');
      args.add(warehouseId);
    }
    if (transactionType != null) {
      conditions.add('transaction_type = ?');
      args.add(transactionType);
    }

    final List<Map<String, Object?>> rows = await db.query(
      DatabaseTables.transactions,
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(TransactionModel.fromMap).toList(growable: false);
  }

  /// سجلات الجرد السابقة (الأحدث أولًا) لمخزن محدد أو لكل المخازن.
  Future<List<StocktakeModel>> listStocktakes({
    int? warehouseId,
    int? limit,
  }) async {
    final Database db = await _helper.database;
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseTables.stocktakes,
      where: warehouseId == null ? null : 'warehouse_id = ?',
      whereArgs: warehouseId == null ? null : <Object?>[warehouseId],
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(StocktakeModel.fromMap).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // الأرشيف والتقارير
  // ---------------------------------------------------------------------------

  /// فلترة الحركات بالمخزن/النوع/الفترة/البحث (الأحدث أولًا).
  ///
  /// البحث يشمل رقم السند واسم الطرف وأمر الصرف. التاريخ بدقة المللي ثانية؛
  /// لشمول يوم كامل مرّر `DateRange.endOfDay` في [endDate].
  Future<List<TransactionModel>> filterTransactions({
    int? warehouseId,
    String? transactionType,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
    int? limit,
    int? offset,
  }) async {
    _validateTransactionType(transactionType);
    final _QueryFilter filter = _buildFilter(
      warehouseId: warehouseId,
      transactionType: transactionType,
      startDate: startDate,
      endDate: endDate,
      searchQuery: searchQuery,
    );

    final Database db = await _helper.database;
    // SQLite يحتاج `LIMIT` قبل `OFFSET`؛ القيمة -1 تعني بلا حد.
    final int? effectiveLimit = limit ?? (offset == null ? null : -1);
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseTables.transactions,
      where: filter.conditions.isEmpty ? null : filter.conditions.join(' AND '),
      whereArgs: filter.arguments.isEmpty ? null : filter.arguments,
      orderBy: 'created_at DESC, id DESC',
      limit: effectiveLimit,
      offset: offset,
    );
    return rows.map(TransactionModel.fromMap).toList(growable: false);
  }

  /// مقاييس الفترة: الوارد والصرف والتالف وصافي التغير وعدد السندات.
  Future<PeriodSummaryMetrics> getPeriodSummaryMetrics({
    int? warehouseId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final _QueryFilter filter = _buildFilter(
      warehouseId: warehouseId,
      startDate: startDate,
      endDate: endDate,
    );
    final Database db = await _helper.database;
    final String where = filter.conditions.isEmpty
        ? ''
        : 'WHERE ${filter.conditions.join(' AND ')}';

    final List<Map<String, Object?>> rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN transaction_type = '${TransactionTypes.inbound}'
          THEN ABS(quantity) ELSE 0 END), 0) AS total_inbound,
        COALESCE(SUM(CASE WHEN transaction_type = '${TransactionTypes.outbound}'
          THEN ABS(quantity) ELSE 0 END), 0) AS total_outbound,
        COALESCE(SUM(CASE WHEN transaction_type = '${TransactionTypes.damage}'
          THEN ABS(quantity) ELSE 0 END), 0) AS total_damaged,
        COUNT(*) AS voucher_count
      FROM ${DatabaseTables.transactions}
      $where
    ''', filter.arguments);

    final Map<String, Object?> row = rows.first;
    return PeriodSummaryMetrics(
      totalInbound: (row['total_inbound'] as num?)?.toInt() ?? 0,
      totalOutbound: (row['total_outbound'] as num?)?.toInt() ?? 0,
      totalDamaged: (row['total_damaged'] as num?)?.toInt() ?? 0,
      voucherCount: (row['voucher_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// المناديب/الموزعون الأكثر سحبًا للكراتين خلال الفترة.
  Future<List<RepresentativeSummary>> getTopRepresentatives({
    int? warehouseId,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 5,
  }) async {
    final _QueryFilter filter = _buildFilter(
      warehouseId: warehouseId,
      transactionType: TransactionTypes.outbound,
      startDate: startDate,
      endDate: endDate,
    );
    final List<String> conditions = <String>[
      ...filter.conditions,
      "party_name IS NOT NULL",
      "TRIM(party_name) <> ''",
    ];

    final Database db = await _helper.database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT party_name,
             SUM(ABS(quantity)) AS total_quantity,
             COUNT(*) AS voucher_count
      FROM ${DatabaseTables.transactions}
      WHERE ${conditions.join(' AND ')}
      GROUP BY party_name
      ORDER BY total_quantity DESC, voucher_count DESC
      LIMIT ?
    ''',
      <Object?>[...filter.arguments, limit],
    );

    return rows
        .map(
          (Map<String, Object?> row) => RepresentativeSummary(
            name: (row['party_name'] as String? ?? '').trim(),
            totalQuantity: (row['total_quantity'] as num?)?.toInt() ?? 0,
            voucherCount: (row['voucher_count'] as num?)?.toInt() ?? 0,
          ),
        )
        .where((RepresentativeSummary item) => item.name.isNotEmpty)
        .toList(growable: false);
  }

  /// كشف مسحوبات مندوب محدد: كل سندات الصرف وبدل التالف **المعتمدة** خلال الفترة.
  ///
  /// تُحتسب الفترة بأيام كاملة: من 00:00 يوم [startDate] حتى نهاية يوم [endDate].
  /// السندات المعلقة أو المرفوضة لا تظهر لأنها لم تُخصم من رصيد المخزن.
  Future<RepresentativeLedger> getRepresentativeLedger({
    required String representativeName,
    required DateTime startDate,
    required DateTime endDate,
    int? warehouseId,
  }) async {
    final String name = representativeName.trim();
    if (name.isEmpty) {
      throw ArgumentError('اسم المندوب مطلوب لعرض كشف المسحوبات.');
    }

    final DateTime start = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final DateTime end = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      23,
      59,
      59,
      999,
    );
    if (end.isBefore(start)) {
      throw ArgumentError('تاريخ نهاية الكشف يسبق تاريخ بدايته.');
    }

    final List<String> conditions = <String>[
      'party_name = ?',
      'status = ?',
      'transaction_type IN (?, ?)',
      'created_at >= ?',
      'created_at <= ?',
    ];
    final List<Object?> args = <Object?>[
      name,
      TransactionStatus.approved,
      TransactionTypes.outbound,
      TransactionTypes.marketReplacement,
      start.toIso8601String(),
      end.toIso8601String(),
    ];
    if (warehouseId != null) {
      conditions.add('warehouse_id = ?');
      args.add(warehouseId);
    }

    final Database db = await _helper.database;
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseTables.transactions,
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at ASC, id ASC',
    );

    return RepresentativeLedger(
      representativeName: name,
      startDate: start,
      endDate: DateTime(endDate.year, endDate.month, endDate.day),
      transactions: rows.map(TransactionModel.fromMap).toList(growable: false),
      warehouseId: warehouseId,
    );
  }

  /// اليومية المخزنية الشاملة ليوم واحد (كل المخازن أو مخزن محدد).
  ///
  /// تعتمد فقط على الحركات **المعتمدة** لأنها وحدها تغيّر الأرصدة:
  /// الاستلام، الصرف، بدل التالف المعتمد، الإتلاف المعتمد، وتسويات الجرد.
  /// يُحسب إغلاق اليوم من الرصيد الحالي مطروحاً منه حركة ما بعده، ثم يُشتق
  /// رصيد البداية من الإغلاق مطروحاً منه صافي حركة اليوم.
  Future<DailyJournalReport> getDailyJournalReport({
    required DateTime date,
    int? warehouseId,
  }) async {
    final DateTime start = DateTime(date.year, date.month, date.day);
    final DateTime end = DateTime(
      date.year,
      date.month,
      date.day,
      23,
      59,
      59,
      999,
    );

    final List<String> conditions = <String>[
      'status = ?',
      'created_at >= ?',
      'created_at <= ?',
    ];
    final List<Object?> args = <Object?>[
      TransactionStatus.approved,
      start.toIso8601String(),
      end.toIso8601String(),
    ];
    if (warehouseId != null) {
      conditions.add('warehouse_id = ?');
      args.add(warehouseId);
    }

    final Database db = await _helper.database;
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseTables.transactions,
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at ASC, id ASC',
    );
    final List<TransactionModel> transactions = rows
        .map(TransactionModel.fromMap)
        .toList(growable: false);

    final int currentBalance = await _totalQuantity(db, warehouseId);
    final int netAfter = await _netQuantity(
      db,
      warehouseId: warehouseId,
      after: end,
    );
    final int netToday = transactions.fold<int>(
      0,
      (int sum, TransactionModel t) => sum + _signedQuantity(t),
    );
    final int closingBalance = currentBalance - netAfter;

    return DailyJournalReport(
      date: start,
      warehouseId: warehouseId,
      transactions: transactions,
      openingBalance: closingBalance - netToday,
      closingBalance: closingBalance,
    );
  }

  /// يبني شروط الاستعلام وقيمه معًا لتجنّب تكرار الكود أو حقن SQL.
  _QueryFilter _buildFilter({
    int? warehouseId,
    String? transactionType,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  }) {
    final List<String> conditions = <String>[];
    final List<Object?> arguments = <Object?>[];

    if (warehouseId != null) {
      conditions.add('warehouse_id = ?');
      arguments.add(warehouseId);
    }
    if (transactionType != null && transactionType.trim().isNotEmpty) {
      conditions.add('transaction_type = ?');
      arguments.add(transactionType.trim());
    }
    if (startDate != null) {
      conditions.add('created_at >= ?');
      arguments.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      conditions.add('created_at <= ?');
      arguments.add(endDate.toIso8601String());
    }

    final String query = searchQuery?.trim() ?? '';
    if (query.isNotEmpty) {
      conditions.add(
        '(voucher_number LIKE ? OR party_name LIKE ? OR order_reference LIKE ?)',
      );
      final String pattern = '%$query%';
      arguments.addAll(<Object?>[pattern, pattern, pattern]);
    }

    return _QueryFilter(conditions: conditions, arguments: arguments);
  }

  void _validateTransactionType(String? transactionType) {
    if (transactionType == null || transactionType.trim().isEmpty) {
      return;
    }
    if (!TransactionTypes.isKnown(transactionType)) {
      throw ArgumentError.value(
        transactionType,
        'transactionType',
        'نوع حركة غير معروف.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // أدوات داخلية
  // ---------------------------------------------------------------------------

  String? _cleanOptional(String? value) {
    final String? trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  void _validatePositiveQuantity(int quantity) {
    if (quantity <= 0) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'الكمية يجب أن تكون أكبر من صفر.',
      );
    }
  }

  /// مجموع أرصدة كل الأصناف في المخزن المحدد أو في كل المخازن.
  Future<int> _totalQuantity(
    DatabaseExecutor executor,
    int? warehouseId,
  ) async {
    final List<Map<String, Object?>> rows = await executor.rawQuery('''
      SELECT COALESCE(SUM(current_quantity), 0) AS total
      FROM ${DatabaseTables.stockBalances}
      ${warehouseId == null ? '' : 'WHERE warehouse_id = ?'}
    ''', warehouseId == null ? null : <Object?>[warehouseId]);
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  /// صافي الحركة المؤثرة على الرصيد بعد لحظة محددة (الحركات المعتمدة فقط).
  Future<int> _netQuantity(
    DatabaseExecutor executor, {
    required DateTime after,
    int? warehouseId,
  }) async {
    final List<Map<String, Object?>> rows = await executor.rawQuery(
      '''
      SELECT COALESCE(SUM(
        CASE
          WHEN transaction_type IN ('${TransactionTypes.inbound}',
                                    '${TransactionTypes.adjustment}')
            THEN quantity
          ELSE -ABS(quantity)
        END
      ), 0) AS net
      FROM ${DatabaseTables.transactions}
      WHERE status = ?
        AND created_at > ?
        ${warehouseId == null ? '' : 'AND warehouse_id = ?'}
    ''',
      <Object?>[
        TransactionStatus.approved,
        after.toIso8601String(),
        if (warehouseId != null) warehouseId,
      ],
    );
    return (rows.first['net'] as num?)?.toInt() ?? 0;
  }

  /// أثر الحركة على الرصيد: موجب للاستلام والتسوية، سالب للصرف والتالف.
  int _signedQuantity(TransactionModel transaction) {
    if (transaction.transactionType == TransactionTypes.inbound ||
        transaction.transactionType == TransactionTypes.adjustment) {
      return transaction.quantity;
    }
    return -transaction.quantity.abs();
  }

  /// الرصيد الحالي، أو صفر إذا لم يكن للصنف سجل رصيد في هذا المخزن بعد.
  Future<int> _currentQuantity(
    DatabaseExecutor executor,
    int warehouseId,
    int itemId,
  ) async {
    final List<Map<String, Object?>> rows = await executor.query(
      DatabaseTables.stockBalances,
      columns: <String>['current_quantity'],
      where: 'warehouse_id = ? AND item_id = ?',
      whereArgs: <Object?>[warehouseId, itemId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return 0;
    }
    return rows.first['current_quantity'] as int? ?? 0;
  }

  /// يضبط الرصيد بالقيمة الجديدة، وينشئ سجل الرصيد إن لم يكن موجودًا.
  Future<void> _setQuantity(
    DatabaseExecutor executor, {
    required int warehouseId,
    required int itemId,
    required int newQuantity,
    required DateTime updatedAt,
  }) async {
    final int updated = await executor.update(
      DatabaseTables.stockBalances,
      <String, Object?>{
        'current_quantity': newQuantity,
        'last_updated': updatedAt.toIso8601String(),
      },
      where: 'warehouse_id = ? AND item_id = ?',
      whereArgs: <Object?>[warehouseId, itemId],
    );

    if (updated == 0) {
      await executor.insert(DatabaseTables.stockBalances, <String, Object?>{
        'warehouse_id': warehouseId,
        'item_id': itemId,
        'current_quantity': newQuantity,
        'last_updated': updatedAt.toIso8601String(),
      });
    }
  }

  /// يبني رقم سند تسلسليًا بصيغة `PREFIX-YYYYMMDD-NNN`.
  Future<String> _nextVoucherNumber(
    DatabaseExecutor executor,
    String transactionType,
    DateTime date,
  ) async {
    final String prefix = TransactionTypes.voucherPrefix(transactionType);
    final String day =
        '${date.year}${_twoDigits(date.month)}${_twoDigits(date.day)}';
    final String base = '$prefix-$day-';

    final List<Map<String, Object?>> rows = await executor.query(
      DatabaseTables.transactions,
      columns: <String>['voucher_number'],
      where: 'voucher_number LIKE ?',
      whereArgs: <Object?>['$base%'],
      orderBy: 'id DESC',
      limit: 1,
    );

    int nextSerial = 1;
    if (rows.isNotEmpty) {
      final String lastNumber = rows.first['voucher_number'] as String? ?? '';
      final String serialPart = lastNumber.substring(base.length);
      final int? lastSerial = int.tryParse(serialPart);
      if (lastSerial != null) {
        nextSerial = lastSerial + 1;
      }
    }

    return '$base${nextSerial.toString().padLeft(3, '0')}';
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

/// شروط استعلام جاهزة مع قيمها.
class _QueryFilter {
  const _QueryFilter({required this.conditions, required this.arguments});

  final List<String> conditions;
  final List<Object?> arguments;
}
