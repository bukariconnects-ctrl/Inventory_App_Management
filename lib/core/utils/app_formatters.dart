import 'package:intl/intl.dart';

import '../constants/app_constants.dart';

/// أدوات تنسيق موحّدة للتواريخ والأرقام باللغة العربية.
///
/// يجب تهيئة بيانات التواريخ العربية مرة واحدة عند بدء التطبيق عبر
/// `initializeDateFormatting(AppConstants.localeCode)` (يتم ذلك في `main.dart`).
abstract final class AppFormatters {
  static final DateFormat _dateFormat = DateFormat(
    'yyyy/MM/dd',
    AppConstants.localeCode,
  );

  static final DateFormat _timeFormat = DateFormat(
    'hh:mm a',
    AppConstants.localeCode,
  );

  static final DateFormat _dateTimeFormat = DateFormat(
    'yyyy/MM/dd - hh:mm a',
    AppConstants.localeCode,
  );

  static final DateFormat _monthYearFormat = DateFormat(
    'MMMM yyyy',
    AppConstants.localeCode,
  );

  static final NumberFormat _integerFormat = NumberFormat.decimalPattern(
    AppConstants.localeCode,
  );

  /// تاريخ بصيغة `yyyy/MM/dd`.
  static String date(DateTime value) => _dateFormat.format(value);

  /// وقت بصيغة `hh:mm ص/م`.
  static String time(DateTime value) => _timeFormat.format(value);

  /// تاريخ ووقت معًا.
  static String dateTime(DateTime value) => _dateTimeFormat.format(value);

  /// شهر وسنة (يُستخدم في تقارير الأرشيف).
  static String monthYear(DateTime value) => _monthYearFormat.format(value);

  /// عدد صحيح بفواصل الآلاف العربية.
  static String number(num value) => _integerFormat.format(value);

  /// كمية بالكراتين مع الوحدة، مثال: `1,250 كرتون`.
  static String cartons(num value) =>
      '${_integerFormat.format(value)} ${AppConstants.cartonUnit}';

  /// تاريخ اليوم بصيغة `yyyy/MM/dd`.
  static String today() => _dateFormat.format(DateTime.now());
}
