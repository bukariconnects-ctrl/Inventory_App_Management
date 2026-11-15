import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/services/backup_service.dart';
import '../../data/models/backup_models.dart';

/// يدير إنشاء النسخة الاحتياطية ومشاركتها، واختيار ملف واستعادته بأمان.
class BackupProvider extends ChangeNotifier {
  BackupProvider({BackupService? service})
    : _service = service ?? BackupService();

  final BackupService _service;

  bool _isExporting = false;
  bool _isRestoring = false;
  DatabaseStats? _stats;
  BackupFile? _lastBackup;
  String? _errorMessage;
  String? _successMessage;

  bool get isExporting => _isExporting;
  bool get isRestoring => _isRestoring;
  DatabaseStats? get stats => _stats;
  BackupFile? get lastBackup => _lastBackup;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;

  /// يمسح رسائل النجاح/الخطأ الحالية.
  void clearMessages() {
    if (_errorMessage == null && _successMessage == null) {
      return;
    }
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }

  /// يحمّل إحصائيات قاعدة البيانات للعرض في شاشة الإعدادات.
  Future<void> loadStats() async {
    try {
      _stats = await _service.getDatabaseStats();
      _errorMessage = null;
      notifyListeners();
    } catch (error) {
      debugPrint('BackupProvider.loadStats: $error');
      _errorMessage = 'تعذر قراءة إحصائيات قاعدة البيانات.';
      notifyListeners();
    }
  }

  /// ينشئ نسخة احتياطية ويفتح نافذة المشاركة.
  Future<BackupFile?> exportBackup() async {
    if (_isExporting) {
      return null;
    }
    _isExporting = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    try {
      final BackupFile backup = await _service.createBackup();
      _lastBackup = backup;
      _stats = await _service.getDatabaseStats();
      await _service.shareBackup(backup);
      _successMessage =
          'تم إنشاء النسخة الاحتياطية (${backup.sizeKb.round()} ك.ب) '
          'وهي جاهزة للحفظ أو المشاركة.';
      return backup;
    } catch (error) {
      debugPrint('BackupProvider.exportBackup: $error');
      _errorMessage = error is BackupException
          ? error.message
          : 'تعذر إنشاء النسخة الاحتياطية. تحقق من مساحة التخزين وحاول مرة أخرى.';
      return null;
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  /// يختار ملف نسخة احتياطية ويتحقق منه ثم يستعيده بعد تأكيد المستخدم.
  ///
  /// [confirmRestore] تعرض تفاصيل النسخة وتعيد `true` عند التأكيد النهائي.
  /// [onRestoreSuccess] تُستدعى بعد نجاح الاستعادة لتحديث بقية المزوّدات.
  Future<bool> pickAndRestoreBackup({
    required Future<void> Function() onRestoreSuccess,
    required Future<bool> Function(BackupValidationResult validation)
    confirmRestore,
  }) async {
    if (_isRestoring) {
      return false;
    }

    FilePickerResult? picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['db'],
        allowMultiple: false,
        withData: false,
      );
    } catch (error) {
      debugPrint('BackupProvider.pickFiles: $error');
      _errorMessage = 'تعذر فتح منتقي الملفات على هذا الجهاز.';
      notifyListeners();
      return false;
    }

    if (picked == null || picked.files.isEmpty) {
      return false;
    }
    final String? filePath = picked.files.single.path;
    if (filePath == null || filePath.isEmpty) {
      _errorMessage = 'تعذر الوصول إلى الملف المختار.';
      notifyListeners();
      return false;
    }

    _isRestoring = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    bool restored = false;
    try {
      final BackupValidationResult validation = await _service
          .validateBackupFile(filePath);
      if (!validation.isValid) {
        _errorMessage = validation.message;
        return false;
      }

      final bool confirmed = await confirmRestore(validation);
      if (!confirmed) {
        return false;
      }

      await _service.restoreBackup(filePath);
      restored = true;
      await onRestoreSuccess();
      _stats = await _service.getDatabaseStats();
      _successMessage = 'تمت استعادة البيانات من النسخة الاحتياطية بنجاح.';
      return true;
    } catch (error) {
      debugPrint('BackupProvider.restore: $error');
      _errorMessage = restored
          ? 'تمت استعادة البيانات، لكن تعذر تحديث الشاشات. أعد فتح التطبيق للتأكد.'
          : (error is BackupException
                ? error.message
                : 'تعذر استعادة النسخة الاحتياطية. بياناتك الحالية لم تتغير.');
      return false;
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }
}
