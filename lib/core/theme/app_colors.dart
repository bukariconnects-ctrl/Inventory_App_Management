import 'package:flutter/material.dart';

/// لوحة ألوان نظام "مياه رواء" المستوحاة من قطاع المياه النظيفة:
/// درجات الأزرق المائي، رمادي فاتح، وأبيض، مع ألوان تنبيه واضحة.
abstract final class AppColors {
  /// اللون الأساسي (أزرق الماء الصافي).
  static const Color primary = Color(0xFF0077B6);

  /// أزرق داكن يُستخدم في العناوين والتدرجات العميقة.
  static const Color primaryDark = Color(0xFF023E8A);

  /// أزرق سماوي فاتح للعناصر المكمّلة.
  static const Color primaryLight = Color(0xFF48CAE4);

  /// سماوي مشبع للتمييز البصري (شارات، أيقونات).
  static const Color cyan = Color(0xFF00B4D8);

  /// أزرق باهت جدًا لخلفيات العناصر المميّزة.
  static const Color mist = Color(0xFFCAF0F8);

  /// خلفية الشاشات العامة (رمادي مزرق فاتح).
  static const Color background = Color(0xFFF5F9FC);

  /// خلفية البطاقات والحقول.
  static const Color surface = Color(0xFFFFFFFF);

  /// خلفية ثانوية للعناصر المحددة.
  static const Color surfaceVariant = Color(0xFFE8F1F7);

  /// النص الأساسي.
  static const Color textPrimary = Color(0xFF0B2A3D);

  /// النص الثانوي والوصف.
  static const Color textSecondary = Color(0xFF5B7A8C);

  /// حدود العناصر.
  static const Color outline = Color(0xFFD3E3EE);

  /// فواصل داخلية خفيفة.
  static const Color divider = Color(0xFFE4EEF5);

  /// نجاح (رصيد كافٍ، عملية مكتملة).
  static const Color success = Color(0xFF1E8E5A);

  /// تحذير (رصيد منخفض).
  static const Color warning = Color(0xFFF4A100);

  /// خطر (نقص حاد، إتلاف، خطأ).
  static const Color danger = Color(0xFFD64545);

  /// تعطيل.
  static const Color disabled = Color(0xFFB6C8D4);
}
