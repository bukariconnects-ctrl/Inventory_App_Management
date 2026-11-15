import 'package:flutter/foundation.dart';

import '../../data/models/warehouse_model.dart';
import '../../data/warehouse_repository.dart';

/// يدير قائمة المخازن وحالة التحميل والأخطاء، ويشعر الواجهات بأي تغيير.
class WarehouseProvider extends ChangeNotifier {
  WarehouseProvider({WarehouseRepository? repository})
    : _repository = repository ?? WarehouseRepository();

  final WarehouseRepository _repository;

  List<WarehouseModel> _warehouses = <WarehouseModel>[];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;

  /// كل المخازن (نشطة وغير نشطة).
  List<WarehouseModel> get warehouses =>
      List<WarehouseModel>.unmodifiable(_warehouses);

  /// هل يجري تحميل القائمة؟
  bool get isLoading => _isLoading;

  /// هل يجري حفظ (إضافة/تعديل/تغيير حالة)؟
  bool get isSaving => _isSaving;

  /// آخر رسالة خطأ عربية، أو `null` عند النجاح.
  String? get errorMessage => _errorMessage;

  int get totalCount => _warehouses.length;

  int get activeCount =>
      _warehouses.where((WarehouseModel w) => w.isActive).length;

  /// يعيد مخزنًا بالمعرّف من القائمة المحمّلة.
  WarehouseModel? warehouseById(int? id) {
    if (id == null) {
      return null;
    }
    for (final WarehouseModel warehouse in _warehouses) {
      if (warehouse.id == id) {
        return warehouse;
      }
    }
    return null;
  }

  /// يحمّل المخازن من قاعدة البيانات.
  Future<void> loadWarehouses({bool showLoader = true}) async {
    if (showLoader) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }
    try {
      _warehouses = await _repository.getAll();
      _errorMessage = null;
    } catch (error) {
      debugPrint('WarehouseProvider.loadWarehouses: $error');
      _errorMessage = 'تعذر تحميل قائمة المخازن. حاول مرة أخرى.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// يضيف مخزنًا جديدًا (مع تهيئة رصيد صفري لكل الأصناف) ويحدّث القائمة.
  Future<bool> addWarehouse({
    required String name,
    required String location,
    required int minAlertLimit,
  }) async {
    return _mutate(() async {
      final String? validation = _validate(
        name: name,
        location: location,
        minAlertLimit: minAlertLimit,
      );
      if (validation != null) {
        _errorMessage = validation;
        return false;
      }
      await _repository.create(
        WarehouseModel(
          name: name.trim(),
          location: location.trim(),
          minAlertLimit: minAlertLimit,
          createdAt: DateTime.now(),
        ),
      );
      return true;
    });
  }

  /// يحدّث بيانات مخزن قائم.
  Future<bool> updateWarehouse(
    WarehouseModel warehouse, {
    required String name,
    required String location,
    required int minAlertLimit,
  }) async {
    return _mutate(() async {
      if (warehouse.id == null) {
        _errorMessage = 'لا يمكن تعديل مخزن غير محفوظ.';
        return false;
      }
      final String? validation = _validate(
        name: name,
        location: location,
        minAlertLimit: minAlertLimit,
      );
      if (validation != null) {
        _errorMessage = validation;
        return false;
      }
      await _repository.update(
        warehouse.copyWith(
          name: name.trim(),
          location: location.trim(),
          minAlertLimit: minAlertLimit,
        ),
      );
      return true;
    });
  }

  /// يفعّل/يعطّل مخزنًا ثم يحدّث القائمة.
  Future<bool> toggleWarehouseStatus(WarehouseModel warehouse) async {
    return _mutate(() async {
      final int? id = warehouse.id;
      if (id == null) {
        _errorMessage = 'لا يمكن تغيير حالة مخزن غير محفوظ.';
        return false;
      }
      await _repository.setActive(id, isActive: !warehouse.isActive);
      return true;
    });
  }

  /// يمسح رسالة الخطأ الحالية.
  void clearError() {
    if (_errorMessage == null) {
      return;
    }
    _errorMessage = null;
    notifyListeners();
  }

  /// ينفّذ عملية تعديل ثم يعيد تحميل القائمة ويضبط حالة الخطأ.
  Future<bool> _mutate(Future<bool> Function() action) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final bool succeeded = await action();
      if (succeeded) {
        _warehouses = await _repository.getAll();
      }
      return succeeded;
    } catch (error) {
      debugPrint('WarehouseProvider mutation: $error');
      _errorMessage = 'تعذر تنفيذ العملية. تحقق من البيانات وحاول مرة أخرى.';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  String? _validate({
    required String name,
    required String location,
    required int minAlertLimit,
  }) {
    if (name.trim().isEmpty) {
      return 'اسم المخزن مطلوب.';
    }
    if (location.trim().isEmpty) {
      return 'موقع المخزن مطلوب.';
    }
    if (minAlertLimit < 0) {
      return 'حد التنبيه لا يمكن أن يكون سالبًا.';
    }
    return null;
  }
}
