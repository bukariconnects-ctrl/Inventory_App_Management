import 'package:flutter/foundation.dart';

import '../../data/models/stakeholder_model.dart';
import '../../data/stakeholder_repository.dart';

/// يدير دليل المناديب/الموزعين وسائقي المصنع/الموردين.
class StakeholderProvider extends ChangeNotifier {
  StakeholderProvider({StakeholderRepository? repository})
    : _repository = repository ?? StakeholderRepository();

  final StakeholderRepository _repository;

  List<StakeholderModel> _distributors = <StakeholderModel>[];
  List<StakeholderModel> _drivers = <StakeholderModel>[];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  StakeholderModel? _lastSavedStakeholder;

  /// المناديب والموزعون النشطون.
  List<StakeholderModel> get distributors =>
      List<StakeholderModel>.unmodifiable(_distributors);

  /// سائقو المصنع والموردون النشطون.
  List<StakeholderModel> get drivers =>
      List<StakeholderModel>.unmodifiable(_drivers);

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;

  /// آخر جهة أُضيفت بنجاح (تُستخدم للاختيار التلقائي بعد الإضافة السريعة).
  StakeholderModel? get lastSavedStakeholder => _lastSavedStakeholder;

  int get totalCount => _distributors.length + _drivers.length;

  /// يحمّل القائمتين (المناديب والسائقون) معًا.
  Future<void> loadStakeholders({bool showLoader = true}) async {
    if (showLoader) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }
    try {
      final List<List<StakeholderModel>> lists = await Future.wait(
        <Future<List<StakeholderModel>>>[
          _repository.getDistributors(),
          _repository.getDrivers(),
        ],
      );
      _distributors = lists[0];
      _drivers = lists[1];
      _errorMessage = null;
    } catch (error) {
      debugPrint('StakeholderProvider.loadStakeholders: $error');
      _errorMessage = 'تعذر تحميل دليل المناديب والموردين. حاول مرة أخرى.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// يضيف جهة تعامل جديدة ثم يعيد تحميل القوائم.
  Future<bool> addStakeholder({
    required String name,
    required StakeholderType type,
    String? phone,
    String? vehicleNumber,
  }) {
    return _mutate(() async {
      final String? validation = _validate(name);
      if (validation != null) {
        _errorMessage = validation;
        return false;
      }
      _lastSavedStakeholder = await _repository.insertStakeholder(
        StakeholderModel(
          name: name.trim(),
          type: type,
          phone: _cleanOptional(phone),
          vehicleNumber: _cleanOptional(vehicleNumber),
          createdAt: DateTime.now(),
        ),
      );
      return true;
    });
  }

  /// يحدّث بيانات جهة تعامل قائمة.
  Future<bool> updateStakeholder(
    StakeholderModel stakeholder, {
    required String name,
    required StakeholderType type,
    String? phone,
    String? vehicleNumber,
  }) {
    return _mutate(() async {
      if (stakeholder.id == null) {
        _errorMessage = 'لا يمكن تعديل جهة تعامل غير محفوظة.';
        return false;
      }
      final String? validation = _validate(name);
      if (validation != null) {
        _errorMessage = validation;
        return false;
      }
      await _repository.updateStakeholder(
        StakeholderModel(
          id: stakeholder.id,
          name: name.trim(),
          type: type,
          phone: _cleanOptional(phone),
          vehicleNumber: _cleanOptional(vehicleNumber),
          isActive: stakeholder.isActive,
          createdAt: stakeholder.createdAt,
        ),
      );
      return true;
    });
  }

  /// يفعّل/يعطّل جهة تعامل.
  Future<bool> toggleStakeholder(StakeholderModel stakeholder) {
    return _mutate(() async {
      final int? id = stakeholder.id;
      if (id == null) {
        _errorMessage = 'لا يمكن تغيير حالة جهة غير محفوظة.';
        return false;
      }
      await _repository.toggleStatus(id, isActive: !stakeholder.isActive);
      return true;
    });
  }

  /// يحذف جهة تعامل نهائيًا.
  Future<bool> deleteStakeholder(StakeholderModel stakeholder) {
    return _mutate(() async {
      final int? id = stakeholder.id;
      if (id == null) {
        _errorMessage = 'لا يمكن حذف جهة غير محفوظة.';
        return false;
      }
      await _repository.deleteStakeholder(id);
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

  Future<bool> _mutate(Future<bool> Function() action) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final bool succeeded = await action();
      if (succeeded) {
        final List<List<StakeholderModel>> lists = await Future.wait(
          <Future<List<StakeholderModel>>>[
            _repository.getDistributors(),
            _repository.getDrivers(),
          ],
        );
        _distributors = lists[0];
        _drivers = lists[1];
      }
      return succeeded;
    } catch (error) {
      debugPrint('StakeholderProvider mutation: $error');
      _errorMessage = 'تعذر تنفيذ العملية. تحقق من البيانات وحاول مرة أخرى.';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  String? _validate(String name) {
    if (name.trim().isEmpty) {
      return 'اسم جهة التعامل مطلوب.';
    }
    return null;
  }

  /// يحوّل الحقل الاختياري إلى قيمة نظيفة أو `null`.
  String? _cleanOptional(String? value) {
    final String trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
