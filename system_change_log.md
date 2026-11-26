# سجل التغييرات — نظام إدارة مخازن مياه رواء

> **الحالة:** ✅✅ **Phase 13 Completed (ERP Tabular PDF Redesign)** — **All 13 Phases 100% Done** — النظام مكتمل وجاهز للنشر الميداني في مصنع مياه رواء
> **المراحل:** Phase 1 (التأسيس) • Phase 2 (قاعدة البيانات) • Phase 3 (الواجهات) • Phase 4 (الاستلام والصرف) • Phase 5 (الإتلاف والجرد) • Phase 6 (محرك PDF) • Phase 7 (الأرشيف والتقارير) • Phase 8 (النسخ الاحتياطي والإعدادات) • Phase 9 (دليل جهات التعامل والإعدادات والوحدات المزدوجة) • Phase 10 (القوائم المنسدلة ودورة اعتماد بدل التالف والإتلاف) • Phase 11 (الترويسة الرسمية والعلامة المائية ومقاس A5 والتواقيع المطبوعة) • Phase 12 (كشف مسحوبات المندوب واليومية المخزنية الشاملة بمقاس A4) • Phase 13 (إعادة تصميم مستندات PDF بالنمط المحاسبي المؤطر الجدولي ERP)
> **تاريخ التوثيق:** 19 نوفمبر 2026
> **البيئة:** Flutter 3.32.0 • Dart 3.8.0 • sqflite 2.4.2 • sqflite_common_ffi 2.3.6 (سطح المكتب) • provider 6.1.5+1 • pdf 3.11.3 • printing 5.14.3

---

## 1. الحالة الحالية للنظام

- أمين المخزن ينفّذ الآن **أربع عمليات** كاملة من التطبيق: استلام من المصنع، صرف لمندوب،
  إتلاف/هدر، وجرد وتسوية.
- سند الإتلاف يتطلب سببًا (شرائح جاهزة + تفاصيل) واسم المسؤول، ويُخصم من الرصيد بنفس
  الحماية الذرية المطبقة في الصرف.
- الجرد يعرض الرصيد الدفتري، ويحسب **الفارق لحظيًا** أثناء الكتابة (مطابق / فائض / عجز)
  ويطلب تبريرًا إلزاميًا عند وجود فارق، مع تأكيد نهائي قبل الاعتماد.
- سجل الجرد السابق يُعرض لكل مخزن (التاريخ، قبل، الفعلي، الفارق، الملاحظات).
- لوحة التحكم تضم شبكة إجراءات من 4 أزرار، وبطاقة كل مخزن فيها خيار «جرد هذا المخزن».
- كل سند مخزني (استلام/صرف/إتلاف/تسوية) ومحضر جرد قابل للطباعة PDF عربي رسمي
  ومشاركته عبر تطبيقات الجهاز.
- تبويب رابع «السجل والتقارير»: بحث فوري، شرائح نوع، تصفية بالمخزن والفترة،
  وإعادة طباعة/مشاركة أي سند قديم.
- تقارير الفترة (وارد/منصرف/تالف/صافي التغير) وقائمة أكثر المناديب سحبًا،
  مع تصدير تقرير المخزون العام PDF.
- نسخ احتياطي كامل لقاعدة البيانات ومشاركته، واستعادة آمنة بعد تحقق من الملف
  وتأكيد صريح، مع شاشة إعدادات وإحصائيات تشخيصية.
- 56 اختبارًا آليًا ناجحًا، والتحليل الثابت بلا أي ملاحظة.

---

## 2. سند الإتلاف / الهدر

### 2.1 `TransactionProvider.createDamageVoucher(...)`

| العنصر | التفصيل |
|---|---|
| المدخلات | `warehouseId`, `quantity`, `reason`, `responsibleName`, `notes?` |
| التحقق | السبب إلزامي، اسم المسؤول إلزامي، الكمية > 0 (في المستودع)، والرصيد كافٍ |
| الاستدعاء | `TransactionRepository.createDamage` داخل `db.transaction()` |
| معالجة النقص | `InsufficientStockException` → «الكمية المطلوبة تتجاوز الرصيد المتوفر في المخزن بمقدار Y كرتون…» |
| بعد النجاح | `inventoryProvider.refresh()` + `lastCreatedTransaction` |

### 2.2 شاشة سند الإتلاف — `damage_voucher_screen.dart`

- AppBar: «سند إتلاف / هدر كراتين» + شارة رقم السند المتوقع (`DMG-…`).
- اختيار المخزن النشط، ومؤشر «الرصيد المتاح في هذا المخزن: X كرتون».
- حقل الكمية التالفة مع **فحص رصيد لحظي** (تنبيه أحمر + تعطيل زر الحفظ عند التجاوز).
- **شرائح أسباب التلف:** كسر وتمزق كراتين / تسريب عبوات / سوء تخزين / عيب تصنيعي / أخرى،
  مع حقل «تفاصيل إضافية» يُدمج مع السبب في السجل (ويصبح إلزاميًا عند اختيار «أخرى»).
- اسم أمين المخزن/المسؤول (إلزامي) + ملاحظات (اختياري).
- زر حفظ بلون تحذيري «تأكيد وقيد التالف» (أحمر `AppColors.danger`) مع مؤشر تحميل،
  ثم `TransactionSuccessDialog` والرجوع تلقائيًا.

---

## 3. الجرد والتسوية

### 3.1 `StocktakeProvider` — `lib/features/stocktake/presentation/providers/stocktake_provider.dart`

| العنصر | التفصيل |
|---|---|
| الحالة | `isLoading`, `isSubmitting`, `stocktakesHistory`, `errorMessage`, `lastStocktake` |
| `loadWarehouseStocktakes(warehouseId)` | يجلب سجل الجرد للمخزن من `TransactionRepository.listStocktakes`. |
| `performStocktake(warehouseId, actualQuantity, notes)` | يتحقق من القيمة، ويلزم تبرير الفارق عند `difference != 0`، ثم `adjustStocktake` ثم `inventoryProvider.refresh()` ثم إعادة تحميل السجل. |
| `attachInventoryProvider(...)` | الربط عبر `ChangeNotifierProxyProvider` في `main.dart`. |

### 3.2 `TransactionRepository.listStocktakes({warehouseId, limit})`

استعلام جديد على جدول `stocktakes` مرتبًا بالأحدث، يُستخدم لسجل الجرد في الواجهة.

### 3.3 شاشة `StocktakeScreen` — `stocktake_screen.dart`

- تُفتح من لوحة التحكم، أو من بطاقة مخزن مع **تحديد مسبق** لذلك المخزن (`initialWarehouseId`).
- اختيار المخزن من القائمة النشطة (اختيار تلقائي عند وجود مخزن واحد).
- **بطاقة الرصيد الدفتري** بتدرّج أزرق تعرض الكمية الحالية في النظام.
- حقل «الكمية الفعلية الموجودة على الواقع» (أرقام فقط).
- **بطاقة الفارق اللحظي** تتحدث مع كل ضغطة مفتاح:
  | الحالة | اللون | النص |
  |---|---|---|
  | لا إدخال | رمادي | «أدخل الكمية الفعلية — سيُحسب الفارق تلقائيًا» |
  | مطابق (0) | أخضر | «الرصيد الفعلي مطابق تمامًا للرصيد الدفتري» |
  | فائض (+X) | أزرق | «يوجد فائض في المخزن بمقدار +X كرتون» |
  | عجز (−X) | أحمر | «يوجد عجز ونقص بمقدار −X كرتون» |
- حقل «ملاحظات وتبرير الفارق»: **إلزامي** عند وجود فارق، اختياري عند المطابقة.
- زر «اعتماد وتسوية الجرد» + **نافذة تأكيد نهائية** توضح المخزن والرصيد قبل وبعد.
- بعد النجاح: رسالة تأكيد، تفريغ الحقول، وتحديث سجل الجرد والأرصدة تلقائيًا.
- قسم «سجل عمليات الجرد السابقة» يعرض لكل جرد: التاريخ والوقت، الفارق بشارة ملوّنة،
  الرصيد قبل/الفعلي، والملاحظات (مع حالة فراغ مناسبة).

### 3.4 منطق حساب الفارق

```
difference = actualQuantity − bookQuantity
bookQuantity = رصيد المخزن في stock_balances (عبر InventoryProvider)
```
- في الواجهة: يُحسب عند كل تغيير على الحقل لعرض البطاقة اللونية وتفعيل/تعطيل الالتزام بالتبرير.
- في المزوّد: يُعاد حسابه قبل الحفظ للتحقق من التبرير ومنع الاعتماد عند نقص الملاحظات.
- في المستودع: يُحسب مرة أخرى **داخل المعاملة** (`systemQuantity` من قاعدة البيانات) لتسجيل
  `stocktakes.system_quantity` و`difference` وتحديث الرصيد على القيمة الفعلية، وإنشاء حركة
  `ADJUSTMENT` بقيمة الفارق (تُستثنى حركة الصفر احترامًا لقيد `quantity <> 0`).

---

## 4. نقاط الوصول (Navigation Entry Points)

1. **لوحة التحكم:** قسم «إجراءات سريعة» أصبح شبكة 2×2:
   - توريد كراتين من المصنع (سماوي → أزرق)
   - صرف كراتين للمناديب (أزرق → أزرق داكن)
   - تسجيل تالف (برتقالي → أحمر) → `DamageVoucherScreen`
   - جرد وتسوية (أزرق داكن → سماوي) → `StocktakeScreen`
2. **بطاقة المخزن:** عنصر جديد في القائمة المنسدلة «جرد هذا المخزن» يفتح `StocktakeScreen`
   مع تمرير المخزن وتحديده مسبقًا.

---

## 5. الملفات المنشأة والمعدّلة في المرحلة 5

### منشأة

| الملف | الوصف |
|---|---|
| `lib/features/transactions/presentation/screens/damage_voucher_screen.dart` | شاشة سند الإتلاف مع الشرائح والفحص اللحظي. |
| `lib/features/stocktake/presentation/providers/stocktake_provider.dart` | مزوّد الجرد والتسوية والسجل. |
| `lib/features/stocktake/presentation/screens/stocktake_screen.dart` | شاشة الجرد مع بطاقة الفارق والسجل. |
| `test/damage_and_stocktake_test.dart` | 6 اختبارات للإتلاف والجرد. |

### معدّلة

| الملف | التعديل |
|---|---|
| `lib/features/transactions/presentation/providers/transaction_provider.dart` | إضافة `createDamageVoucher`. |
| `lib/features/transactions/data/transaction_repository.dart` | إضافة `listStocktakes({warehouseId, limit})`. |
| `lib/main.dart` | تسجيل `StocktakeProvider` عبر `ChangeNotifierProxyProvider`. |
| `lib/features/home/presentation/widgets/dashboard_view.dart` | صف الإجراءات الثاني + إصلاح تجاوز أفقي في رأس «حالة المخازن السريعة» (`Expanded` + `ellipsis`). |
| `lib/features/warehouses/presentation/widgets/warehouse_card.dart` | خيار «جرد هذا المخزن» و`onStocktake`. |
| `lib/features/warehouses/presentation/screens/warehouses_screen.dart` | فتح شاشة الجرد مع تمرير المخزن. |
| `test/widget_test.dart` | تكبير مساحة الاختبار لعرض كل أقسام اللوحة. |

---

## 6. نتائج فحص المرحلة 5 (تاريخية)

| الأمر | النتيجة |
|---|---|
| `dart format lib test` | 39 ملفًا، 0 تغييرات (Exit 0) |
| `flutter analyze` | **No issues found!** (Exit 0) |
| `flutter test` | **All tests passed! — 30/30** (Exit 0) |

### توزيع الاختبارات

| الملف | العدد | التغطية |
|---|---|---|
| `test/database_test.dart` | 8 | البذر والحركات الذرية والترقيم والمخازن. |
| `test/providers_test.dart` | 8 | مزوّدا المخازن والمخزون. |
| `test/transactions_ui_test.dart` | 5 | استلام/صرف/منع التجاوز + واجهة الاستلام وفحص الصرف اللحظي. |
| `test/damage_and_stocktake_test.dart` | 6 | إتلاف يخصم، منع إتلاف يتجاوز الرصيد، جرد بفائض، جرد بعجز، جرد مطابق دون حركة تسوية، إلزام تبرير الفارق. |
| `test/widget_test.dart` | 3 | شاشة البداية، لوحة التحكم (إجراءات + تنبيه)، التنقل. |

**ملاحظة على الاختبار:** اختبار لوحة التحكم كشف تجاوزًا أفقيًا في صف رأس «حالة المخازن السريعة»
عند العرض الضيق (خط الاختبار الافتراضي أعرض)، وتم إصلاحه بجعل العنوان داخل `Expanded`
مع `TextOverflow.ellipsis` — وهو تحسين حقيقي للشاشات الصغيرة وتكبير الخط.

**لم يُنفَّذ:** بناء APK على جهاز/محاكي، ومراجعة بصرية على جهاز حقيقي.

---

## 7. محرك PDF العربي — `PdfService`

**الملف:** `lib/core/services/pdf_service.dart`

### 7.1 الخط العربي والتشبيك دون إنترنت

| العنصر | التفصيل |
|---|---|
| الخط المضمّن | `assets/fonts/Cairo-Regular.ttf` (Cairo Variable TTF) مسجّل في `pubspec.yaml` ويُحمَّل عبر `rootBundle`. |
| الترتيب | المحلي أولًا (ضمان العمل بلا شبكة) ← `PdfGoogleFonts.cairoRegular()` / `cairoBold()` عند غياب الأصل ← خط PDF الافتراضي كحل أخير. |
| الحقن | `PdfService(regularFont:, boldFont:, allowNetworkFonts: false)` تسمح للاختبارات باستخدام خط محلي بلا أي طلب شبكة. |
| الاتجاه والتشبيك | `pw.MultiPage(textDirection: TextDirection.rtl)` + `textDirection` على كل نص؛ تشبيك الحروف وترتيب bidi يتولاه محرك `pdf` المدمج. |
| الرخصة | `assets/fonts/OFL.txt` مرفق مع الخط. |

### 7.2 `generateTransactionVoucher(...)`

| العنصر | التفصيل |
|---|---|
| المدخلات | `TransactionModel`, `WarehouseModel`, `ItemModel` |
| الصفحة | A4 بهوامش 26/24، ترويسة كحلية داكنة تحمل اسم المصنع ونوع السند ورقمه. |
| شارات السند | نوع السند (استلام/صرف/إتلاف/تسوية) بلون مميّز، رقم السند، تاريخ ووقت الإصدار، المخزن وموقعه. |
| شريط الكمية | كمية كبيرة بلون النوع + الوحدة (كرتون)، وتُوسم «(عجز)» في التسويات السالبة. |
| جدول البيانات | استلام: الصنف، المواصفات (20×75 مل)، الكمية المستلمة، مسلّم المصنع، رقم الإذن. صرف: رقم أمر الصرف، الصنف، الكمية، المندوب، لوحة السيارة. إتلاف: الصنف، الكمية، سبب الإتلاف، المسؤول. تسوية: الصنف، الكمية، نوع التسوية، السبب، المسؤول. |
| الملاحظات | صندوق مستقل يظهر فقط عند وجود ملاحظات. |
| التوقيعات | صندوقا توقيع: «أمين المخزن» + الطرف المعني (مسلّم المصنع / المستلم / المعتمد / لجنة الجرد). |
| التذييل | «وثيقة صادرة آلياً من نظام إدارة مخازن مياه رواء - لا يعتد بها بدون التوقيع والختم» + اسم النظام والإصدار ورقم الصفحة. |

### 7.3 `generateStocktakeReport(...)`

- المدخلات: `StocktakeModel`, `WarehouseModel`, `ItemModel`.
- يعرض: المخزن المجرود، تاريخ الجرد، الرصيد الدفتري، الرصيد الفعلي، الفارق (عجز/فائض/مطابق)،
  وحالة الجرد بلون تحذيري، ومبرر الفارق الإلزامي.
- توقيعات «أمين المخزن» و«لجنة الجرد / المعتمد»، وتذييل اعتماد رسمي.

### 7.4 أدوات مساعدة

| الدالة | الوصف |
|---|---|
| `PdfService.fileNameForVoucher(String)` | اسم ملف آمن مثل `ISS-20261113-001.pdf` مع تنظيف الرموز. |
| `PdfService.stocktakeReference(StocktakeModel)` | مرجع محضر الجرد مثل `STK-20261113-004`. |

---

## 8. شاشة المعاينة والطباعة والمشاركة

**الملف:** `lib/features/transactions/presentation/screens/voucher_preview_screen.dart`

- تستقبل عنوان السند، رقم السند، ودالة بناء المستند (`documentBuilder`).
- توليد مسبق للبايتات قبل العرض مع مؤشر تحميل «جارٍ توليد السند...»، وحالة خطأ
  مع زر «إعادة المحاولة» بدل الشاشة البيضاء.
- `PdfPreview` من حزمة `printing`: معاينة A4، طباعة مباشرة، مشاركة (واتساب/بريد/حفظ)
  وتنزيل الملف، مع تعطيل تغيير المقاس والاتجاه للحفاظ على القالب الرسمي.
- زر مشاركة في شريط التطبيق عبر `Printing.sharePdf(bytes:, filename:)`، واسم الملف
  الافتراضي هو رقم السند (`REC-… / ISS-… / DMG-… / ADJ-….pdf`).
- معالجة فشل المشاركة برسالة عربية بدل استثناء صامت.

### 8.1 ربط نافذة النجاح

- `TransactionSuccessDialog` صار يستقبل كائن `WarehouseModel` و`ItemModel` (اختياريًا مع
  بدائل آمنة) إلى جانب الاسم والرصيد.
- زر «معاينة وطباعة / مشاركة السند» أصبح زرًا رئيسيًا مفعّلًا (`success_print_voucher_button`)
  يفتح شاشة المعاينة فوق نافذة النجاح، فيعود المستخدم إلى النافذة بعد الإغلاق.
- الشاشات الثلاث (استلام/صرف/إتلاف) تمرّر المخزن والصنف الفعليين للسند.

---

## 9. الملفات المنشأة والمعدّلة في المرحلة 6

### منشأة

| الملف | الوصف |
|---|---|
| `lib/core/services/pdf_service.dart` | محرك PDF عربي RTL لقوالب السندات ومحضر الجرد + إدارة الخطوط. |
| `lib/features/transactions/presentation/screens/voucher_preview_screen.dart` | معاينة السند والطباعة والمشاركة. |
| `assets/fonts/Cairo-Regular.ttf` + `assets/fonts/OFL.txt` | خط عربي محلي ورخصته. |
| `test/pdf_service_test.dart` | 6 اختبارات لتوليد المستندات وأسماء الملفات. |

### معدّلة

| الملف | التعديل |
|---|---|
| `pubspec.yaml` | تسجيل `assets/fonts/Cairo-Regular.ttf`. |
| `lib/features/transactions/presentation/widgets/transaction_success_dialog.dart` | تفعيل زر PDF وتمرير المخزن/الصنف وفتح المعاينة. |
| `lib/features/transactions/presentation/screens/inbound_voucher_screen.dart` | تمرير المخزن والصنف للنافذة. |
| `lib/features/transactions/presentation/screens/outbound_voucher_screen.dart` | تمرير المخزن والصنف للنافذة. |
| `lib/features/transactions/presentation/screens/damage_voucher_screen.dart` | تمرير المخزن والصنف للنافذة. |

---

## 10. نتائج فحص المرحلة 6 (تاريخية)

| الأمر | النتيجة |
|---|---|
| `dart format lib test` | 42 ملفًا، 0 تغييرات (Exit 0) |
| `flutter analyze` | **No issues found!** (Exit 0) |
| `flutter test` | **All tests passed! — 36/36** (Exit 0) |

| ملف الاختبار | العدد | التغطية |
|---|---|---|
| `test/pdf_service_test.dart` | 6 | سند استلام/صرف/إتلاف، محضر جرد بعجز/فائض/مطابق، تنقية اسم الملف. |
| اختبارات المراحل السابقة | 30 | قاعدة البيانات، المزوّدات، الواجهات، الإتلاف والجرد. |

**التحقق البصري:** تم توليد عينات PDF للسندات ومحضر الجرد (استلام/صرف/جرد) وفحصها كصور:
العربية متصلة، الاتجاه RTL، الجداول والتوقيعات والتذييل في مواضعها. أوضح الفحص خللين وتم إصلاحهما:
(1) رمز مفقود أمام الفارق السالب بسبب إشارة الطرح — استُبدلت بوسم «(عجز)»؛
(2) تراكب الفاصلة النقطية في الترويسة/التذييل — استُبدلت بفاصل `|`.

**لم يُنفَّذ:** الطباعة على طابعة فعلية أو المشاركة عبر واتساب على جهاز حقيقي، وبناء APK.

---

## 11. استعلامات الأرشيف والتقارير

**الملف:** `lib/features/transactions/data/transaction_repository.dart`

| الدالة | التفصيل |
|---|---|
| `filterTransactions(...)` | فلاتر: `warehouseId`, `transactionType`, `startDate`, `endDate`, `searchQuery`, `limit`, `offset`. البحث يشمل رقم السند/اسم الطرف/أمر الصرف، والترتيب `created_at DESC, id DESC`. شروط وقيم مُعاملة (لا حقن SQL)، والنوع غير المعروف يُرفض. |
| `getPeriodSummaryMetrics(...)` | استعلام تجميعي واحد يعيد الوارد والمنصرف والتالف وعدد السندات؛ `netChange = inbound − outbound − damaged`. |
| `getTopRepresentatives(...)` | تجميع سندات الصرف حسب `party_name` مع إجمالي الكميات وعدد السندات، مرتبة تنازليًا وحدّ أقصى للعدد. |

المقاييس والمناديب تُحسب للفترة والمخزن فقط — فلتر نوع السند يخص قائمة السجل وحدها.

---

## 12. مزوّد السجل والتقارير — `ReportsProvider`

**الملف:** `lib/features/reports/presentation/providers/reports_provider.dart`

| العنصر | التفصيل |
|---|---|
| الحالة | الحركات المفلترة، المقاييس، المناديب، المخزن/النوع/الفترة/البحث، `isLoading`, `errorMessage` |
| الفلاتر | `applyFilters(...)` (استبدال كامل)، `setWarehouseFilter`, `setTypeFilter`, `setDateRange`, `setSearchQuery`, `clearFilters` |
| التحميل | `loadReportsData()` ينفّذ الاستعلامات الثلاثة معًا، و`refresh()` بدون مؤشر تحميل كامل |
| حماية التسابق | عدّاد طلبات يهمل النتائج القديمة عند تبديل الفلاتر بسرعة |
| التحديث التلقائي | `attachTransactionProvider` يستمع لأي سند جديد ويعيد التحميل، مربوط في `main.dart` عبر `ChangeNotifierProxyProvider` |

---

## 13. شاشات الأرشيف والتقارير

### 13.1 سجل الحركات — `transactions_archive_screen.dart`

- بحث فوري بتأخير 350ms برقم السند أو اسم المندوب أو أمر الصرف.
- شرائح أفقية: الكل / استلام من المصنع / صرف للمناديب / إتلاف وهدر / تسوية جرد.
- تصفية متقدمة في BottomSheet: المخزن + نطاق زمني (اليوم، آخر 7 أيام، هذا الشهر،
  فترة مخصصة عبر `showDateRangePicker`) مع شارة بعدد الفلاتر وزر إعادة تعيين.
- بطاقة كل حركة: رقم السند، شارة النوع الملوّنة، التاريخ والوقت، المخزن والطرف،
  والكمية بإشارة (+/−) ولون أخضر/أحمر.
- النقر يفتح تفاصيل كاملة في BottomSheet + زر **«معاينة وطباعة السند PDF»**
  يعيد توليد السند من البيانات المحفوظة ويفتح `VoucherPreviewScreen` للطباعة/المشاركة.

### 13.2 التقارير والإحصائيات — `reports_screen.dart`

- شرائح فورية للفترة (كل الفترات / اليوم / آخر 7 أيام / هذا الشهر) تشارك نفس فلتر المخزن.
- أربع بطاقات: إجمالي الوارد، المنصرف، التالف، وصافي التغير (انخفاض/زيادة).
- قائمة أكثر المناديب سحبًا: الترتيب، الاسم، الكميات، عدد السندات، شريط نسبة من إجمالي الصرف.
- زر **«تصدير تقرير المخزون العام PDF»** يبني المستند ثم يفتح المعاينة للطباعة/المشاركة.

### 13.3 التبويب والتنقل

- تبويب رابع في الشريط السفلي «السجل والتقارير» بأيقونة `receipt_long_rounded`.
- `ReportsHubScreen` بتبويبين علويين: «سجل الحركات» و«التقارير والإحصائيات».
- لوحة التحكم فيها بطاقة «سجل الحركات والتقارير» تنقل مباشرة إلى التبويب.

---

## 14. تقرير المخزون العام PDF

**المضاف في `PdfService`:** `generateInventorySummaryReportPdf(...)`

- المدخلات: المقاييس، المناديب، الصنف، تاريخ الإصدار، المخزن (أو كل المخازن)، والفترة.
- صفحة A4 رسمية: ترويسة الإدارة، نطاق التقرير والفترة وعدد السندات، أربع بطاقات مقاييس،
  سطر ملخص الصنف، جدول مسحوبات المناديب بالنسب، توقيعا أمين المخزن والإدارة، والتذييل.
- مرجع التقرير `INV-YYYYMMDD-HHMM` واسم الملف `INV-REPORT-…pdf`.

---

## 15. الملفات المنشأة والمعدّلة في المرحلة 7

### منشأة

| الملف | الوصف |
|---|---|
| `lib/features/reports/data/models/report_models.dart` | `DateRange`, `PeriodSummaryMetrics`, `RepresentativeSummary`. |
| `lib/features/reports/presentation/providers/reports_provider.dart` | مزوّد السجل والمقاييس والمناديب. |
| `lib/features/reports/presentation/screens/transactions_archive_screen.dart` | البحث والفلاتر والبطاقات وإعادة الطباعة. |
| `lib/features/reports/presentation/screens/reports_screen.dart` | الإحصائيات والمناديب وتصدير PDF. |
| `lib/features/reports/presentation/screens/reports_hub_screen.dart` | تبويبا السجل والتقارير. |
| `test/reports_and_archive_test.dart` | 13 اختبارًا للأرشيف والمقاييس والمناديب والمزوّد وتقرير PDF. |

### معدّلة

| الملف | التعديل |
|---|---|
| `lib/features/transactions/data/transaction_repository.dart` | إضافة الاستعلامات الثلاثة وأدوات الفلترة. |
| `lib/core/services/pdf_service.dart` | إضافة تقرير المخزون العام ومرجعه واسم ملفه. |
| `lib/main.dart` | تسجيل `ReportsProvider` عبر `ChangeNotifierProxyProvider`. |
| `lib/features/home/presentation/screens/home_screen.dart` | التبويب الرابع وتحديث السجل عند فتحه. |
| `lib/features/home/presentation/widgets/dashboard_view.dart` | بطاقة «سجل الحركات والتقارير». |
| `test/widget_test.dart` | إضافة `ReportsProvider` واختبار عنصر التنقل الجديد. |

---

## 16. نتائج الفحص والاختبارات (المرحلة 7)

| الأمر | النتيجة |
|---|---|
| `dart format lib test` | 48 ملفًا، 0 تغييرات (Exit 0) |
| `flutter analyze` | **No issues found!** (Exit 0) |
| `flutter test` | **All tests passed! — 49/49** (Exit 0) |

| ملف الاختبار | العدد | التغطية |
|---|---|---|
| `test/reports_and_archive_test.dart` | 13 | الفلترة بالنوع/المخزن/الفترة/البحث، الترتيب وlimit/offset، المقاييس، المناديب، المزوّد، تقرير PDF. |
| اختبارات المراحل السابقة | 36 | قاعدة البيانات، المزوّدات، الواجهات، الإتلاف والجرد، محرك PDF. |

**التحقق البصري:** تم توليد تقرير المخزون العام كعينة وفحصه كصورة؛ أوضح الفحص أن التقرير
كان يمتد لصفحة ثانية شبه فارغة (تكرار جدول المقاييس)، فتم استبداله بسطر ملخص مختصر
وأصبح التقرير في صفحة واحدة بتوقيعاته. لم تُجرَّب الشاشات الجديدة بصريًا على جهاز/محاكي.

**لم يُنفَّذ:** تصفح الشاشات على جهاز حقيقي، والطباعة الفعلية أو مشاركة الواتساب، وبناء APK.

---

## 17. محرك النسخ الاحتياطي والاستعادة — `BackupService`

**الملف:** `lib/core/services/backup_service.dart`

| الدالة | التفصيل |
|---|---|
| `createBackup()` | يشغّل `PRAGMA wal_checkpoint(FULL)` لطمأنة الكتابة، ثم ينسخ `rawaa_wms.db` إلى مجلد مؤقت باسم `rawaa_wms_backup_YYYYMMDD_HHMM.db` ويعيد `BackupFile` (المسار/الوقت/الحجم). |
| `shareBackup(BackupFile)` | يفتح نافذة المشاركة عبر `SharePlus.instance.share(ShareParams(files: [XFile(...)]))` بعنوان «نسخة احتياطية - نظام مخازن مياه رواء» (واتساب/Drive/حفظ). |
| `validateBackupFile(path)` | يتحقق من ترويسة SQLite، وفتح القاعدة للقراءة فقط، ووجود جداول `warehouses/items/stock_balances/transactions`، ونجاح `PRAGMA integrity_check`، ويعيد عدد الحركات/المخازن/الأصناف/سجلات الجرد. |
| `restoreBackup(path)` | يعيد التحقق أولًا ويرفض الملفات غير الصالحة، ينشئ نسخة أمان من القاعدة الحالية، يغلق الاتصال، يحذف ملفات `-wal/-shm/-journal`، يستبدل الملف، يفحص السلامة، ثم يعيد الفتح؛ وعند أي فشل يعيد ملف الأمان تلقائيًا. |
| `getDatabaseStats()` | حجم القاعدة بالكيلوبايت، عدد الحركات والمخازن وسجلات الجرد، وتاريخ آخر حركة. |

النسخ الاحتياطي والاستعادة يعملان بلا إنترنت، والتحقق يمنع استيراد ملفات غريبة أو تالفة.

---

## 18. مزوّد النسخ الاحتياطي وشاشة الإعدادات

### 18.1 `BackupProvider`

- الحالة: `isExporting`, `isRestoring`, `stats`, `lastBackup`, `errorMessage`, `successMessage`.
- `exportBackup()`: إنشاء النسخة + المشاركة + تحديث الإحصائيات ورسالة نجاح عربية.
- `pickAndRestoreBackup(...)`: يفتح منتقي ملفات `.db` (`FilePicker.pickFiles`)، يتحقق من الملف،
  يعرض تأكيدًا عبر `confirmRestore`، ثم يستعيد ويستدعي `onRestoreSuccess` لتحديث بقية المزوّدات.
- رسائل فشل واضحة (ملف غير صالح/تعذرت الاستعادة) مع الحفاظ على البيانات الحالية.

### 18.2 `SettingsScreen`

- **معلومات النظام:** اسم المصنع، الصنف (20×75 مل)، الإصدار 1.0.0، التشغيل المحلي بالكامل،
  وحجم قاعدة البيانات وعدد الحركات والمخازن وسجلات الجرد وآخر حركة.
- **تصدير النسخة:** شرح مبسط + زر «إنشاء نسخة احتياطية ومشاركتها» بمؤشر تحميل.
- **الاستعادة:** صندوق تحذير أحمر + زر «استعادة البيانات من ملف» + حوار تأكيد صريح
  يعرض اسم الملف وحجمه وعدد الحركات والمخازن وسجلات الجرد قبل الاستبدال.
- **إرشادات ميدانية:** نسخ أسبوعي، جرد دوري، طباعة وتوقيع السندات فور التسليم.
- الوصول: أيقونة الإعدادات في شريط تطبيق الشاشة الرئيسية.
- بعد الاستعادة تُحدَّث `WarehouseProvider` و`InventoryProvider` و`ReportsProvider`
  و`BackupProvider` فورًا دون إعادة تشغيل التطبيق.

---

## 19. الملفات المنشأة والمعدّلة في المرحلة 8

### منشأة

| الملف | الوصف |
|---|---|
| `lib/core/services/backup_service.dart` | إنشاء/مشاركة/تحقق/استعادة آمنة وإحصائيات. |
| `lib/features/backup/data/models/backup_models.dart` | `BackupFile`, `BackupValidationResult`, `DatabaseStats`, `BackupException`. |
| `lib/features/backup/presentation/providers/backup_provider.dart` | إدارة التصدير والاختيار والاستعادة والرسائل. |
| `lib/features/backup/presentation/screens/settings_screen.dart` | شاشة الإعدادات والنسخ الاحتياطي والإرشادات. |
| `test/backup_service_test.dart` | 7 اختبارات للإنشاء والتحقق والاستعادة والإحصائيات. |

### معدّلة

| الملف | التعديل |
|---|---|
| `lib/core/database/database_helper.dart` | كشف `factory` و`databasePath` لاستخدامهما في النسخ/الاستعادة. |
| `lib/main.dart` | تسجيل `BackupProvider`. |
| `lib/features/home/presentation/screens/home_screen.dart` | أيقونة الإعدادات في الـ AppBar. |
| `pubspec.yaml` | إضافة `path_provider` كاعتماد مباشر للمجلد المؤقت. |

---

## 20. نتائج الفحص النهائية

| الأمر | النتيجة |
|---|---|
| `dart format lib test` | 53 ملفًا، 0 تغييرات (Exit 0) |
| `flutter analyze` | **No issues found!** (Exit 0) |
| `flutter test` | **All tests passed! — 56/56** (Exit 0) |

| ملف الاختبار | العدد | التغطية |
|---|---|---|
| `test/backup_service_test.dart` | 7 | إنشاء نسخة صالحة، قبول/رفض الملفات، استعادة كاملة، رفض ملف تالف دون تغيير البيانات، الإحصائيات. |
| اختبارات المراحل 1–7 | 49 | قاعدة البيانات، المزوّدات، الواجهات، الحركات، الإتلاف والجرد، محرك PDF، الأرشيف والتقارير. |

**لم يُنفَّذ:** التجربة على جهاز/محاكي حقيقي، نافذة المشاركة الفعلية (واتساب/Drive)،
اختيار ملف من منتقي النظام، والطباعة على طابعة فعلية، وبناء APK.

---

## 21. الخلاصة النهائية — جاهزية الإنتاج

✅ **اكتملت المراحل الثماني بالكامل.**

| المجال | الحالة |
|---|---|
| الاستلام، الصرف، الإتلاف، الجرد والتسوية | ✅ مع حماية الرصيد والذرّية |
| تعدد المخازن والتنبيهات | ✅ |
| سندات PDF عربية RTL ومحاضر جرد | ✅ |
| الطباعة والمشاركة | ✅ عبر `printing` و`share_plus` |
| أرشيف الحركات والبحث والتصفية | ✅ |
| التقارير والإحصائيات وتقرير المخزون العام PDF | ✅ |
| النسخ الاحتياطي والاستعادة والتحقق | ✅ مع نسخة أمان عند الفشل |
| الإعدادات والإحصائيات التشخيصية | ✅ |
| الجودة | ✅ 56/56 اختبارًا • `flutter analyze` بلا ملاحظات • 53 ملف Dart |

### بناء نسخة الإصدار (APK)

من داخل مجلد `inventory_stock_app`:

```bash
flutter build apk --release
```

الناتج: `build/app/outputs/flutter-apk/app-release.apk`

> يُنصح قبل التوزيع بتجربة التطبيق على جهاز أندرويد حقيقي: إنشاء نسخة احتياطية ومشاركتها،
> استعادتها من منتقي الملفات، ثم طباعة سند واحد للتأكد من نافذة الطباعة الأصلية.

---

## 22. إصلاح فتح قاعدة البيانات على سطح المكتب (Windows/macOS/Linux)

### المشكلة

عند تشغيل التطبيق على Windows كان يفشل بخطأ:

```
Bad state: databaseFactory not initialized. When using sqflite_common_ffi
you must call databaseFactory = databaseFactoryFfi;
```

السبب: حزمة `sqflite` لا تملك تنفيذًا أصليًا على سطح المكتب؛ المحرك المتاح هناك هو
`sqflite_common_ffi`، وكانت الحزمة موجودة في `dev_dependencies` فقط (للاختبارات)
ولم تُهيَّأ `databaseFactory` قبل أول وصول للقاعدة، فظهرت الواجهة بحالة «تعذر التحميل».

### الحل

| الملف | التعديل |
|---|---|
| `pubspec.yaml` | نقل `sqflite_common_ffi: ^2.3.6` من `dev_dependencies` إلى `dependencies`. |
| `lib/main.dart` | بعد `WidgetsFlutterBinding.ensureInitialized()` استدعاء `_initializeDatabaseFactory()`: إذا كانت المنصة Windows أو macOS أو Linux يتم تنفيذ `sqfliteFfiInit()` ثم `databaseFactory = databaseFactoryFfi`؛ أندرويد وiOS يبقيان على `sqflite` الأصلي. |

`DatabaseHelper` لم يحتج تغييرًا: يستخدم `databaseFactory` العام عبر الخاصية `factory`،
فيورث المصنع المهيّأ على كل المنصات ويعمل مع التوجيه الخاص بالاختبارات (`overrideDatabase`) كما هو.

### النتيجة

- التطبيق يقلع على Windows ويعرض لوحة التحكم والمخازن والأرصدة مباشرة دون أخطاء تحميل.
- أندرويد وiOS بلا أي تغيير في السلوك: `sqflite` الأصلي.
- `flutter pub get` ناجح، `flutter analyze` بلا ملاحظات، `flutter test` **56/56**.

> ملاحظة: لإصدار Windows بوضع `--release` مع `sqflite_common_ffi` 2.3.x يجب أن يكون
> `sqlite3.dll` بجوار ملف `.exe` (في وضع التطوير يكون مضمّنًا داخل الحزمة).
> أندرويد — هدف التوزيع الأساسي — لا يتأثر بذلك.

### حماية Web

`_initializeDatabaseFactory()` تبدأ بـ `if (kIsWeb) return;` فلا يُلمس `Platform` إطلاقًا داخل
المتصفح (استدعاؤه هناك يرمي `Unsupported operation`)؛ وتم الاستيراد بـ `import 'dart:io' show Platform`
مع `package:flutter/foundation.dart` من أجل `kIsWeb`. سطح المكتب كما هو: `sqfliteFfiInit` + `databaseFactoryFfi`.

تم التحقق أن `flutter build web --release` يُكمل بنجاح (Exit 0)، أي أن استيراد `dart:io`
لا يمنع بناء الويب، وأن استدعاء `Platform` لا يحدث هناك. قاعدة البيانات على الويب
غير مدعومة أصلًا (تحتاج `sqflite_common_ffi_web`)، والتطبيق الحالي هدفه أندرويد/سطح المكتب.

**لم يُنفَّذ:** `flutter build windows` متوقف على إعداد الجهاز:
«Building with plugins requires symlink support — enable Developer Mode» (إعداد نظام يتطلب إذن المستخدم).
المحاولة على Windows تحتاج تفعيل وضع المطوّر ثم `flutter run -d windows`.

---

# المرحلة 9 — دليل جهات التعامل، ملف أمين المخزن، والوحدات المزدوجة

## 23. ترقية مخطط قاعدة البيانات (الإصدار 2)

| العنصر | التفصيل |
|---|---|
| `stakeholders` | `id` • `name` (إلزامي) • `phone` • `type` (`DISTRIBUTOR`/`DRIVER`) • `vehicle_number` • `is_active` • `created_at`، مع فهرس على `type`. |
| `app_settings` | `key` (مفتاح أساسي) • `value`، ويُبذر فيه `storekeeper_name = أمين المخزن`. |
| الترقية | `AppConstants.databaseVersion = 2` مع `onUpgrade`: أي قاعدة قديمة تُنشأ فيها الجدولان وتُبذر الإعدادات دون فقد بيانات. القواعد الجديدة تنشئهما في `onCreate` مباشرة. |
| دوال الإعدادات | `DatabaseHelper.getSetting(key, {defaultValue})` و`setSetting(key, value)` باستخدام `ConflictAlgorithm.replace`. |

## 24. النماذج والمستودع والمزوّد

- `StakeholderType` (enum): `distributor` = «مندوب / موزّع»، `driver` = «سائق مصنع / مورّد» مع تحويل آمن من قيمة قاعدة البيانات.
- `StakeholderModel`: `id`, `name`, `phone`, `type`, `vehicleNumber`, `isActive`, `createdAt`، مع `toMap`/`fromMap`/`copyWith` وخصائص `hasPhone` و`phoneDigits` (أرقام فقط لروابط الاتصال).
- `StakeholderRepository`: `insertStakeholder`, `updateStakeholder`, `deleteStakeholder`, `toggleStatus`, `getById`, `getAll`, `getDistributors` (نشطون فقط), `getDrivers` (نشطون فقط), `searchStakeholders(query, {type})` على الاسم/الهاتف/اللوحة.
- `StakeholderProvider`: يحمّل القائمتين معًا، ويوفر `addStakeholder`/`updateStakeholder`/`toggleStakeholder`/`deleteStakeholder` مع تحقق من الاسم ورسائل خطأ عربية وإعادة تحميل تلقائية بعد كل تغيير، ومسجّل في `MultiProvider` بـ `main.dart`.

## 25. شاشة دليل المناديب والموردين

- `StakeholdersScreen` بتبويبين: **المناديب** (عددهم في العنوان) و**السائقون**، وزر إضافة عائم يفتح النوع المناسب للتبويب.
- كل بطاقة تعرض: الاسم، النوع، رقم اللوحة، رقم الهاتف، شارة «غير نشط» عند التعطيل،
  وأزرار **اتصال** (`tel:`) و**واتساب** (`wa.me`) عند وجود رقم، مع قائمة خيارات (تعديل/تعطيل/حذف).
  الاتصال والواتساب يُفتحان عبر `url_launcher` في التطبيق الخارجي مع رسالة عربية عند الفشل.
- `AddEditStakeholderDialog`: الاسم (إلزامي بتحقق)، الهاتف، رقم اللوحة، ونوع الجهة عبر `SegmentedButton`، ويُستخدم للإضافة والتعديل معًا.
- الوصول من: أيقونة الإعدادات → «دليل المناديب والموردين»، وبطاقة وصول سريع في لوحة التحكم.

## 26. اسم أمين المخزن والإعدادات

- بطاقة **«بيانات أمين المخزن المسؤول»** في أعلى `SettingsScreen`: حقل اسم + زر حفظ يكتب في `app_settings` برسالة نجاح/خطأ، ويُقرأ تلقائيًا عند فتح الشاشة.
- `ListTile` للانتقال المباشر إلى دليل المناديب والموردين من الإعدادات.
- بطاقة وصول سريع للدليل في `DashboardView` إلى جانب سجل الحركات والتقارير.

## 27. الوحدات المزدوجة (كرتون + عبوة)

| الدالة | الناتج |
|---|---|
| `AppFormatters.bottlesCount(cartons, {bottlesPerCarton = 20})` | عدد العبوات الإجمالي. |
| `AppFormatters.formatBottles(int)` | `25,000 عبوة`. |
| `AppFormatters.bottlesFor(cartons)` | عدد العبوات المقابل للكراتين. |
| `AppFormatters.formatQuantityWithBottles(cartons)` | `1,250 كرتون (25,000 عبوة)`. |

وتُستخدم في بطاقة «إجمالي كراتين المياه» بلوحة التحكم لعرض المقابل بالعبوات.

## 28. الملفات

### منشأة

`lib/features/stakeholders/data/models/stakeholder_model.dart` •
`lib/features/stakeholders/data/stakeholder_repository.dart` •
`lib/features/stakeholders/presentation/providers/stakeholder_provider.dart` •
`lib/features/stakeholders/presentation/widgets/add_edit_stakeholder_dialog.dart` •
`lib/features/stakeholders/presentation/screens/stakeholders_screen.dart` •
`test/stakeholders_test.dart`

### معدّلة

`lib/core/database/database_tables.dart` • `lib/core/database/database_helper.dart` •
`lib/core/constants/app_constants.dart` • `lib/core/utils/app_formatters.dart` •
`lib/main.dart` • `lib/features/home/presentation/widgets/dashboard_view.dart` •
`lib/features/backup/presentation/screens/settings_screen.dart` • `pubspec.yaml` (إضافة `url_launcher`)

## 29. نتائج الفحص

| الأمر | النتيجة |
|---|---|
| `flutter pub get` | ناجح |
| `dart format lib test` | 0 تغييرات |
| `flutter analyze` | **No issues found!** (Exit 0) |
| `flutter test` | **All tests passed! — 68/68** (Exit 0) |

الاختبارات الجديدة (12) في `test/stakeholders_test.dart`: إضافة واسترجاع المناديب والسائقين حسب النوع،
التحديث وتعطيل الحالة فاختفاء الجهة من القوائم النشطة، البحث بالاسم/الهاتف/اللوحة مع حصر النوع،
الحذف، بذر إعداد أمين المخزن وحفظه واسترجاعه والقيمة الافتراضية للمفاتيح الغائبة،
تحميل المزوّد وإضافة جهة ورفض الاسم الفارغ وتعطيل مندوب، وحساب وتنسيق الوحدات المزدوجة.

**لم يُنفَّذ:** فتح تطبيق الاتصال أو واتساب فعليًا على جهاز (تحتاج جهازًا ورقمًا حقيقيًا)،
ولا تصفح الشاشات على محاكي/جهاز.

---

## 30. جاهزية المرحلة 10

✅ **النظام جاهز للانتقال إلى «المرحلة 10: دورة العمليات المحدثة وسندات التالف وبدل التالف مع نظام التعليق والاعتماد».**

- دليل جهات التعامل أصبح مرجعًا موحّدًا لهواتف المناديب والسائقين يمكن ربطه بسندات الصرف والاستلام لاحقًا.
- جدول `app_settings` جاهز لتخزين إعدادات المرحلة القادمة (حدود الاعتماد، صلاحيات التعليق، إعدادات السندات).
- طبقة الترقية (`onUpgrade`) تسمح بإضافة أعمدة وجداول الاعتماد والتالف الجديدة دون فقد بيانات العملاء الحاليين.

---

## 31. ترقية المخطط إلى الإصدار 3

| العنصر | التفصيل |
|---|---|
| إصدار القاعدة | `AppConstants.databaseVersion = 3`. |
| `status` | `TEXT NOT NULL DEFAULT 'APPROVED' CHECK (status IN ('APPROVED','PENDING','REJECTED'))` في جدول `transactions`. |
| `rejection_reason` | `TEXT` اختياري يُحفظ عند الرفض فقط. |
| نوع حركة جديد | `TransactionTypes.marketReplacement = 'MARKET_REPLACEMENT'` ببادئة سند `REP` (الإتلاف الداخلي يبقى `DAMAGE` ببادئة `DMG`). |
| الترقية الآمنة | SQLite لا يسمح بتعديل قيد `CHECK` عبر `ALTER TABLE`، لذلك يبني `_upgradeTransactionsToV3` جدولًا جديدًا، ينسخ كل السندات القديمة بحالة `APPROVED` صريحة، يستبدل الجدول ويعيد إنشاء الفهارس — دون فقد أي بيانات. |
| الفهرس | `idx_transactions_status` لتسريع استعلام الطلبات المعلقة. |

كما أُضيفت `TransactionStatus` (`approved`/`pending`/`rejected`) مع `label(...)` العربية، و`TransactionTypes.requiresApproval(...)`، وحقلا `status`/`rejectionReason` في `TransactionModel` مع `isPending`/`isRejected`/`isApproved`/`isMarketReplacement`.

## 32. دورة الاعتماد اليدوي وحماية الرصيد

| الدالة (`TransactionRepository`) | السلوك |
|---|---|
| `createPendingMarketReplacement(...)` | سند `MARKET_REPLACEMENT` بحالة `PENDING`؛ **لا يخصم أي رصيد**. يرفض غياب المندوب أو أمر الصرف أو المبرر. |
| `createPendingInternalDamage(...)` | سند `DAMAGE` بحالة `PENDING` باسم أمين المخزن؛ **لا يخصم أي رصيد**. |
| `approvePendingTransaction(id)` | داخل `db.transaction()`: يجلب السند ويتحقق أنه `PENDING`، يفحص الرصيد (`InsufficientStockException`)، يخصم الكمية من `stock_balances`، ثم يحوّل الحالة إلى `APPROVED`. أي فشل يترك الرصيد والحالة كما هما. |
| `rejectPendingTransaction(id, reason)` | يتحقق أن السند معلق، يسجل `REJECTED` + `rejection_reason` دون لمس الرصيد. |
| `getPendingTransactions({warehouseId})` / `countPendingTransactions` | المعلقة فقط مرتبة بالأحدث. |

`TransactionProvider` يضيف: `pendingTransactions`, `pendingCount`, `isLoadingPending`, `processingTransactionId`, `createMarketReplacementRequest`, `createInternalDamageRequest`, `loadPendingApprovals`, `approvePending`, `rejectPending`؛ ويعيد تحميل الأرصدة وقائمة المعلقات تلقائيًا بعد كل اعتماد أو رفض.

## 33. القوائم المنسدلة والإضافة السريعة (+) وشاشة الاعتمادات

- **سند الاستلام:** حقل السائق الحر أصبح `DropdownButtonFormField<StakeholderModel>` لسائقي المصنع النشطين، مع زر (+) يفتح `AddEditStakeholderDialog` بنوع `DRIVER` ويختار السائق الجديد تلقائيًا (عبر `StakeholderProvider.lastSavedStakeholder`)، وسطر «الكمية بالوحدتين» أسفل حقل الكمية.
- **سند الصرف:** قائمة منسدلة للمناديب النشطين + زر (+)، وتعبئة «رقم لوحة السيارة» تلقائيًا من بيانات المندوب عند اختياره، وعرض الرصيد المتاح بالكرتون والعبوات.
- **`MarketReplacementVoucherScreen`** (جديد): المخزن، المندوب المستفيد بزر (+)، رقم أمر الصرف الإلزامي، الكمية مع العبوات، مبرر التلف المرتجع، ثم «رفع طلب صرف بدل تالف (قيد الاعتماد)» الذي ينشئ سندًا `PENDING`.
- **`DamageVoucherScreen`** (محدّث): يسجّل الإتلاف بحالة `PENDING` باسم أمين المخزن المقروء من `app_settings` (بطاقة للقراءة فقط مع تنبيه أنه يُعدَّل من الإعدادات)، وتنبيه أن تجاوز الرصيد قد يمنع الاعتماد لاحقًا، وزر «رفع محضر إتلاف (قيد الاعتماد)».
- **`PendingApprovalsScreen`** (جديد): بطاقات لكل طلب تعرض النوع ورقم السند والطرف والمخزن والكمية بالوحدتين والسبب وشارة «بانتظار الاعتماد»؛ والنقر يفتح التفاصيل بزر أخضر **[اعتماد وتأكيد الخصم]** وزر أحمر **[رفض الطلب]** (يطلب سبب الرفض كتابةً).
- **`PendingRequestDialog`** (جديد): نافذة تأكيد موحّدة بعد رفع أي طلب معلق توضح أن الرصيد لم يُخصم.
- **لوحة التحكم:** شريط «N طلب معلق بانتظار الاعتماد» يفتح شاشة الاعتمادات، وبطاقتا إجراء سريع جديدتان: «صرف بدل تالف» و«الطلبات المعلقة».

## 34. الملفات

### منشأة

`lib/features/transactions/presentation/screens/market_replacement_voucher_screen.dart` •
`lib/features/transactions/presentation/screens/pending_approvals_screen.dart` •
`lib/features/transactions/presentation/widgets/pending_request_dialog.dart` •
`test/damage_approvals_test.dart`

### معدّلة

`lib/core/constants/app_constants.dart` • `lib/core/database/database_helper.dart` •
`lib/features/transactions/data/models/transaction_model.dart` •
`lib/features/transactions/data/transaction_repository.dart` •
`lib/features/transactions/presentation/providers/transaction_provider.dart` •
`lib/features/transactions/presentation/screens/inbound_voucher_screen.dart` •
`lib/features/transactions/presentation/screens/outbound_voucher_screen.dart` •
`lib/features/transactions/presentation/screens/damage_voucher_screen.dart` •
`lib/features/stakeholders/presentation/providers/stakeholder_provider.dart` •
`lib/features/home/presentation/widgets/dashboard_view.dart` •
`lib/features/home/presentation/screens/home_screen.dart` •
`test/transactions_ui_test.dart` • `test/widget_test.dart`

## 35. نتائج الفحص وجاهزية المرحلة 11

| الأمر | النتيجة |
|---|---|
| `dart format lib test` | 0 تغييرات في آخر تشغيل |
| `flutter analyze` | **No issues found!** (Exit 0) |
| `flutter test` | **All tests passed! — 77/77** (Exit 0) |

اختبارات `test/damage_approvals_test.dart` (9): بقاء الرصيد ثابتًا عند إنشاء بدل التالف والإتلاف الداخلي، رفض البيانات الناقصة،
الاعتماد الذي يخصم الرصيد ذريًا ويحوّل الحالة إلى `APPROVED`، منع الاعتماد المزدوج،
فشل الاعتماد لنقص الرصيد مع بقاء الرصيد والحالة، الرفض مع حفظ السبب دون خصم،
إلزام سبب الرفض ومنع رفض سند معتمد، واستعلامات المعلقات والترتيب والعدّ.

**لم يُنفَّذ:** لم تُجرَّب الشاشات على محاكي/جهاز حقيقي، ولم يُبنَ APK أو نسخة Windows في هذه المرحلة،
ولم يُختبر ترحيل قاعدة إصدار 2 فعلية إلى 3 على جهاز العميل (يُغطى منطقيًا بإعادة بناء الجدول في `onUpgrade`).

## 36. محرك PDF الرسمي بمقاس A5 (المرحلة 11)

| العنصر | التفصيل |
|---|---|
| `buildOfficialLetterhead(...)` | ترويسة رسمية داخل إطار بحدود دائرية: اليمين بيانات المصنع بالعربية، الوسط شعار رواء مع «مياه رواء - صحة ودواء»، اليسار البيانات الإنجليزية، ثم خط فاصل وعنوان السند ورقمه في الوسط. |
| شعار المصنع | أُضيف `assets/images/rawaa_logo.png` (مشتق من شعار المصنع المرفق، بخلفية شفافة) ويُحمَّل من الأصول محليًا، مع شعار نصي بديل عند فشل التحميل. |
| العلامة المائية | شعار قطرة رواء في منتصف خلفية كل صفحة بشفافية ~0.07. |
| حالة التعليق | السند `PENDING` يحمل نصًا مائيًا عريضًا بلون أحمر فاتح: «طلب معلّق - غير معتمد» و«( بانتظار اعتماد الإدارة )»، إضافة إلى شريط حالة أعلى السند. |
| مقاس السندات | `PdfPageFormat.a5` رأسي (148 × 210 مم) لهوامش 10–15 pt: الاستلام، الصرف، بدل التالف (`MARKET_REPLACEMENT`)، الإتلاف الداخلي، ومحضر الجرد. |
| مقاس التقارير | تقرير حركة المخزون العام يبقى `PdfPageFormat.a4` (الملخص الإداري المجمع). |
| الاكتمال | عُولجت المساحات بحيث يُطبع كل سند/محضر في **صفحة A5 واحدة** (يُتحقق منه آليًا في الاختبارات). |

## 37. التواقيع والأسماء المطبوعة آليًا

- **صندوق أمين المخزن:** «أمين المخزن المسؤول: [الاسم]» يُقرأ من `app_settings.storekeeper_name`، ويمكن حقنه صراحة (`storekeeperName`) عند الطباعة من الأرشيف.
- **صندوق الطرف الآخر:** «المندوب المستلم:» في الصرف وبدل التالف، أو «مسلّم المصنع / السائق:» في الاستلام، مع اسم `transaction.partyName` ورقم اللوحة/أمر الصرف إن وُجد.
- **صندوق اعتماد الإدارة:** «اعتماد مدير المصنع / الإدارة» + «رقم أمر/إذن الصرف: [رقم الأمر أو رقم السند]» + «الاعتماد والختم: ........».
- كل صندوق يحوي سطر «التوقيع: ........» منقّطًا فقط للتوقيع اليدوي والختم.

## 38. الوحدات المزدوجة في جدول السند

- الكميات في شريط الكمية وجدول التفاصيل تُعرض بـ `AppFormatters.formatQuantityWithBottles`، مثال: `150 كرتون (3,000 عبوة)`.
- سطر «سعة الكرتون: 20 قنينة × 75 مل» مطبوع في شريط الكمية، ويُحسب من بيانات الصنف (`bottleCount` / `bottleVolumeMl`) مع القيم الافتراضية.

## 39. الملفات

### منشأة

`assets/images/rawaa_logo.png`

### معدّلة

`lib/core/services/pdf_service.dart` • `pubspec.yaml` (تعريف أصل الشعار) • `test/pdf_service_test.dart`

## 40. نتائج الفحص وجاهزية المرحلة 12

| الأمر | النتيجة |
|---|---|
| `dart format lib test` | 0 تغييرات في آخر تشغيل |
| `flutter analyze` | **No issues found!** (Exit 0) |
| `flutter test` | **All tests passed — 82/82** (Exit 0) |

اختبارات PDF الجديدة: مقاس A5 للسندات و A4 للتقارير مع قراءة `/MediaBox` من البايتات، بيانات الترويسة الرسمية (تعز - الضباب - سوق الأحد والهواتف)، طباعة أسماء أمين المخزن والمندوب في خانة التوقيع، سند `PENDING` بالنص المائي «طلب معلّق - غير معتمد»، وسند بدل تالف `MARKET_REPLACEMENT` بصفحة A5 واحدة والوحدتين المزدوجتين.

**لم يُنفَّذ:** لم تُجرَّب الطباعة الورقية الفعلية على طابعة حقيقية، ولم يُبنَ APK/Windows في هذه المرحلة.

## 41. استعلامات التقارير المتقدمة (`TransactionRepository`)

| الدالة | السلوك |
|---|---|
| `getRepresentativeLedger({representativeName, startDate, endDate, warehouseId?})` | يعيد `RepresentativeLedger` بكل سندات `OUTBOUND` و`MARKET_REPLACEMENT` **المعتمدة** (`status = APPROVED`) للمندوب داخل الفترة، مرتبة زمنيًا. تُطبَّع الفترة بأيام كاملة (00:00 → 23:59:59.999). يرفض الاسم الفارغ والفترة المقلوبة بـ `ArgumentError`. السندات المعلقة والمرفوضة مستبعدة لأنها لم تخصم من الرصيد. |
| `getDailyJournalReport({date, warehouseId?})` | يعيد `DailyJournalReport` لكل الحركات المعتمدة في اليوم (استلام، صرف، بدل تالف، إتلاف، تسويات جرد). رصيد الإغلاق = مجموع `stock_balances` الحالي − صافي الحركات بعد نهاية اليوم، ورصيد البداية = الإغلاق − صافي حركة اليوم؛ وبذلك تكون أرقام الأيام السابقة صحيحة وليست مجرد انعكاس للرصيد الحالي. |
| `_totalQuantity` / `_netQuantity` / `_signedQuantity` | أدوات داخلية: مجموع الأرصدة، صافي الحركات بعد لحظة (بـ `CASE` يمنح الاستلام والتسوية إشارة موجبة والصرف/التالف سالبة)، وأثر الحركة على الرصيد. |

النموذجان الجديدان في `report_models.dart`: `RepresentativeLedger` (`totalCartons`, `voucherCount`, `outboundCount`, `replacementCount`, `isEmpty`) و`DailyJournalReport` (`openingBalance`, `closingBalance`, تجميعات كل نوع، `damagedAndReplacementCartons`, `netChange`, `voucherCount`).

## 42. مزوّد التقارير (`ReportsProvider`)

- **كشف المندوب:** `selectedDistributor`, `distributorLedger`, `distributorLedgerTransactions`, `distributorTotalCartons`, `distributorTotalBottles`, `distributorVoucherCount`, `isLoadingDistributor`, `distributorError` + `loadRepresentativeLedger(name, {start, end, warehouseId})` مع حماية `requestId` من نتائج الطلبات المتأخرة.
- **اليومية المخزنية:** `selectedJournalDate`, `dailyJournalData`, `isLoadingJournal`, `journalError` + `loadDailyJournal(date, {warehouseId})`.
- كل الدوال تلتقط الأخطاء برسائل عربية واضحة دون إسقاط الواجهة.

## 43. كشف مسحوبات المندوب (A4)

`PdfService.generateRepresentativeStatementPdf(...)` — ترويسة مصنع رواء الرسمية، عنوان «كشف مسحوبات موزع / مندوب»، مرجع `RST-YYYYMMDD-HHMM` وملف `REP-STATEMENT-….pdf`:

- بطاقتا تعريف: المندوب (الاسم + الهاتف واللوحة من دليل المناديب) والفترة والنطاق.
- بطاقتا بيانات: تاريخ الإصدار وعدد السندات، وسعة الكرتون والصنف.
- ثلاث بطاقات إجماليات: إجمالي الكراتين، إجمالي العبوات (20×)، وعدد السندات.
- جدول السندات: التاريخ والوقت، رقم السند، المخزن، النوع (صرف عادي / بدل تالف)، أمر الصرف، الكراتين، العبوات — يُقسَّم إلى كتل من 14 صفًا برأس مكرر كي يتوزع على صفحات A4 دون قصّ.
- سطر صافي المسحوبات بالوحدتين وعدد سندات الصرف وبدل التالف.
- ثلاث خانات توقيع: أمين المخزن (الاسم من الإعدادات)، المندوب للمطابقة (الاسم مطبوع آليًا)، واعتماد مدير المصنع / الإدارة مع سطر الختم.

`RepresentativeLedgerScreen` — قائمة منسدلة للمناديب من `StakeholderProvider`، شرائح [اليوم] [آخر 7 أيام] [هذا الشهر] [فترة مخصصة]، بطاقات الإجماليات، قائمة السندات، وزرّا معاينة/تصدير PDF (AppBar + زر أسفل الصفحة) عبر `VoucherPreviewScreen`.

## 44. اليومية المخزنية الشاملة (A4)

`PdfService.generateDailyJournalPdf(...)` — عنوان «اليومية المخزنية لحركة البضائع»، مرجع `DJ-YYYYMMDD` وملف `DAILY-JOURNAL-YYYYMMDD.pdf`:

- بطاقات: اليوم المخزني وعدد الحركات، المخزن والصنف، أمين المخزن وسعة الكرتون، تاريخ الطباعة وصافي الحركة.
- **ميزان اليوم** في ست بطاقات: رصيد البداية، الوارد، المنصرف، التالف والبدل، تسويات الجرد، رصيد النهاية — مع سطر المعادلة المحاسبية.
- جدول تفصيلي زمني: الوقت، رقم السند، النوع، السائق/المندوب، أمر الصرف، الكراتين، العبوات (كتل 14 صفًا برأس مكرر).
- تواقيع: أمين المخزن المسؤول + اعتماد الإدارة.

`DailyJournalScreen` — منتقي تاريخ افتراضي على اليوم، قائمة مخزن (كل المخازن أو مخزن محدد)، بطاقة إغلاق اليوم بالتدرج الأزرق مع صافي الحركة، أربع بطاقات ميزان (بداية/وارد/منصرف/تالف وبدل)، قائمة الحركات بشارات نوع ملوّنة، وزر **[معاينة وطباعة اليومية المخزنية كـ PDF]**.

## 45. الربط والملفات

- `ReportsScreen`: قسم «تقارير رقابية متقدمة» ببطاقتين — [كشف مسحوبات مندوب] بأيقونة `person_search_rounded` و[اليومية المخزنية] بأيقونة `today_rounded`.
- `DashboardView`: رابط سريع «اليومية المخزنية الشاملة» بلمسة واحدة من لوحة التحكم، إضافة إلى رابط السجل والتقارير.

### منشأة

`lib/features/reports/presentation/screens/representative_ledger_screen.dart` •
`lib/features/reports/presentation/screens/daily_journal_screen.dart` •
`test/advanced_reports_test.dart`

### معدّلة

`lib/features/reports/data/models/report_models.dart` •
`lib/features/transactions/data/transaction_repository.dart` •
`lib/features/reports/presentation/providers/reports_provider.dart` •
`lib/core/services/pdf_service.dart` •
`lib/features/reports/presentation/screens/reports_screen.dart` •
`lib/features/home/presentation/widgets/dashboard_view.dart`

## 46. نتائج الفحص النهائي وجاهزية الإنتاج

| الأمر | النتيجة |
|---|---|
| `dart format lib test` | 0 تغييرات في آخر تشغيل |
| `flutter analyze` | **No issues found!** (0 warnings, 0 errors — Exit 0) |
| `flutter test` | **All tests passed — 92/92** (Exit 0) |

اختبارات `test/advanced_reports_test.dart` (10): تجميع كشف المندوب للصرف وبدل التالف المعتمد فقط واستبعاد المعلّق والمرفوض وما قبل الفترة، احترام حدود الأيام، رفض الاسم الفارغ والفترة المقلوبة، دقة ميزان اليوم (بداية/وارد/منصرف/تالف وبدل/نهاية)، صحة يومية يوم سابق مع الحركات اللاحقة، تحديد المخزن، حالة المزوّد، توليد كشف PDF وA4 وأسماء التواقيع والمراجع، اليومية PDF A4، والمستندات الفارغة.

### مكوّنات النظام المكتملة

1. قاعدة بيانات SQLite محلية (مخازن، أصناف، أرصدة، حركات، جرد، جهات تعامل، إعدادات) بإصدار مخطط 3.
2. استلام وصرف وإتلاف وجرد وتسوية بمعاملات ذرّية وحماية من الرصيد السالب.
3. دورة اعتماد يدوي لبدل التالف والإتلاف (PENDING → APPROVED/REJECTED) دون خصم مسبق.
4. دليل مناديب وموردين مع قوائم منسدلة وإضافة سريعة واتصال/واتساب.
5. أرشيف بحث وتصفية متقدمة وإعادة طباعة أي سند.
6. محرك PDF رسمي: سندات A5 بترويسة المصنع وعلامة مائية وتواقيع مطبوعة، وتقارير A4.
7. تقارير الفترة ومسحوبات المناديب وكشف المندوب واليومية المخزنية الشاملة.
8. نسخ احتياطي واستعادة آمنة وإعدادات ورقم إصدار.
9. واجهة عربية RTL تعمل بالكامل دون إنترنت.

### أمر البناء النهائي

```bash
flutter build apk --release
```

**لم يُنفَّذ في هذه المرحلة:** بناء APK/Windows، أو الطباعة على طابعة ورقية حقيقية، أو تشغيل الشاشات الجديدة على جهاز فعلي (تُغطى منطقياً باختبارات المستودع وتوليد PDF؛ واجهات الشاشات لم تُشغَّل تفاعلياً).

## 47. المرحلة 13 — إعادة تصميم PDF بالنمط المحاسبي الجدولي (ERP Tabular Redesign)

**الحالة:** ✅ **Phase 13 Completed (ERP Tabular PDF Redesign)**

استُبدل تصميم البطاقات المنفصلة وحواف الموبايل في `lib/core/services/pdf_service.dart`
بتصميم محاسبي رسمي مؤطر بجداول، مطابق للنموذج الورقي المعتمد (الصورتان 2 و3)،
مع الحفاظ الكامل على كل واجهة عامة يعتمد عليها التطبيق والاختبارات
(`generateTransactionVoucher`, `generateStocktakeReport`, `generateInventorySummaryReportPdf`,
`generateRepresentativeStatementPdf`, `generateDailyJournalPdf`, `buildOfficialLetterhead`,
`voucherPageFormat`, `reportPageFormat`, `fileNameFor*`, `*Reference`, وكل الثوابت النصية).

### 47.1 السندات الفردية A5 (استلام / صرف لمندوب / بدل تالف / إتلاف)

| العنصر | التنفيذ |
|---|---|
| الإطار | ترويسة رواء المزدوجة مع الشعار داخل إطار، ثم شريط عنوان السند المؤطر في المنتصف |
| شبكة البيانات | `_erpInfoGrid` بجدول مؤطر من عمودين: يمين (رقم السند، التاريخ، المرجع/أمر الصرف، المخزن والموقع) ويسار (نوع الحركة، البيان/المستلم، السبب/الملاحظات، رقم اللوحة) |
| جدول الصنف | `pw.Table` بحدود `PdfColors.black` بعرض 0.8 وأعمدة: م • رقم الصنف • اسم الصنف • المواصفات • الوحدة • الكمية (كرتون) • إجمالي العبوات، ورأس بخلفية فاتحة مكرر عبر الصفحات |
| إجمالي العبوات | شريط مؤطر أسفل الجدول: «إجمالي العبوات = الكراتين × 20 عبوة» |
| التواقيع | سطر محاسبي موحد بثلاث خانات مؤطرة: المستخدم/أمين المخزن • المستلم/المندوب/السائق • اعتماد مدير المصنع والختم |
| الحالة المعلّقة | شريط أحمر «طلب معلّق - غير معتمد» + العلامة المائية في الخلفية (كما كان) |

محضر الجرد A5 يستخدم الهيكل نفسه: شبكة بيانات (رقم المحضر، التاريخ، المخزن المجرود،
نتيجة المطابقة، الملاحظات) + جدول الصنف + شريط (الرصيد الدفتري / الفعلي / الفارق) + التواقيع.

### 47.2 التقارير A4 (كشف المندوب / اليومية / تقرير المخزون العام)

- **شريط تعريف مؤطر:** `رقم الصنف` | `اسم الصنف والمواصفات` | `الفترة` | `المخزن`.
  كشف المندوب يضيف شريطًا ثانيًا: المندوب | بيانات التواصل | عدد السندات.
- **جدول الحركة التحليلي** `_ledgerTable` بحدود كاملة 0.6 وأعمدة (من اليمين):
  رقم المستند • التاريخ • نوع المستند (تحويل وارد / أمر صرف / بدل تالف / إتلاف مخزني / تسوية جرد)
  • البيان • الوحدة • الوارد • التصريف/المنصرف • الرصيد.
- **الرصيد التراكمي سطرًا بسطر:** كشف المندوب يبدأ من صفر ويجمع الكميات المطلقة،
  واليومية تبدأ من `journal.openingBalance` وتجمع `_signedQuantity`
  (موجب للاستلام والتسوية الموجبة، سالب للصرف والتالف وبدل التالف) لتطابق `closingBalance`.
- **سطر الإجمالي الختامي:** «إجمالي كميات» + إجمالي الوارد + إجمالي المنصرف + الرصيد الختامي،
  بخلفية رمادية فاتحة وخط عريض، ويليه شريط «إجمالي العبوات = مجموع الكراتين × 20 عبوة».
- **تذييل رسمي من 3 أقسام:** يمين «طبع بواسطة : أمين المخزن» • وسط «الصفحة x / y»
  • يسار «تاريخ التقرير : YYYY/MM/DD HH:mm:ss» مع خط فاصل علوي.
- **اليومية المخزنية:** شريط أرصدة مؤطر (بداية اليوم / إجمالي الوارد / إجمالي المنصرف / رصيد نهاية اليوم)
  فوق جدول الحركة.
- **تقرير المخزون العام:** شريط التعريف + جدول مقاييس مؤطر (الوارد / المنصرف / التالف / صافي التغير /
  عدد السندات) + جدول مسحوبات المناديب مع سطر إجمالي، ثم التواقيع والتذييل.

### 47.3 المقاسات وتكرار الرؤوس

- السندات ومحاضر الجرد تبقى `PdfPageFormat.a5` (419.53 × 595.28 pt) وتُملأ بلا صفحات زائدة.
- التقارير تبقى `PdfPageFormat.a4` (595.28 × 841.89 pt).
- رأس كل جدول يُكرَّر تلقائيًا في كل صفحة عبر `pw.TableRow(repeat: true)`
  (بدل تقسيم الجدول يدويًا إلى كتل).

### 47.4 الملفات المعدّلة

`lib/core/services/pdf_service.dart` (إعادة كتابة كاملة للطبقة المرئية) •
`system_change_log.md`.

### 47.5 نتائج الفحص

| الأمر | النتيجة |
|---|---|
| `dart format lib test` | Exit 0 |
| `flutter analyze` | **No issues found!** (0 warnings, 0 errors) |
| `flutter test` | **All tests passed — 92/92** |

**لم يُنفَّذ:** معاينة بصرية مطبوعة للمستندات الجديدة على ورق أو صورة (التحقق تم آليًا
عبر صحة PDF ومقاس الصفحات وصفحة واحدة للسندات)؛ ولا `flutter build windows`
(ما زال يتطلب تفعيل وضع المطور لدعم الروابط الرمزية للملحقات).

✅ **اكتمل مشروع «نظام إدارة مخازن مياه رواء» بنسبة 100% وجاهز للنشر الميداني.**
