import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:inventory_stock_app/core/constants/app_constants.dart';
import 'package:inventory_stock_app/core/database/database_helper.dart';
import 'package:inventory_stock_app/core/utils/app_formatters.dart';
import 'package:inventory_stock_app/features/stakeholders/data/models/stakeholder_model.dart';
import 'package:inventory_stock_app/features/stakeholders/data/stakeholder_repository.dart';
import 'package:inventory_stock_app/features/stakeholders/presentation/providers/stakeholder_provider.dart';

void main() {
  late DatabaseHelper helper;
  late StakeholderRepository repository;
  late StakeholderProvider provider;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    helper = DatabaseHelper.instance;
    await helper.resetForTesting();
    helper.overrideDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await helper.database;

    repository = StakeholderRepository(databaseHelper: helper);
    provider = StakeholderProvider(repository: repository);
  });

  tearDown(() async {
    await helper.close();
  });

  Future<StakeholderModel> addStakeholder({
    required String name,
    StakeholderType type = StakeholderType.distributor,
    String? phone,
    String? vehicleNumber,
  }) {
    return repository.insertStakeholder(
      StakeholderModel(
        name: name,
        type: type,
        phone: phone,
        vehicleNumber: vehicleNumber,
        createdAt: DateTime.now(),
      ),
    );
  }

  group('دليل المناديب والموردين', () {
    test('يضيف مندوبًا وسائقًا ويسترجعهما حسب النوع', () async {
      await addStakeholder(
        name: 'محمد المندوب',
        phone: '0501234567',
        vehicleNumber: '1234 أ ب ج',
      );
      await addStakeholder(
        name: 'سالم السائق',
        type: StakeholderType.driver,
        phone: '0559876543',
      );

      final List<StakeholderModel> distributors = await repository
          .getDistributors();
      final List<StakeholderModel> drivers = await repository.getDrivers();

      expect(distributors, hasLength(1));
      expect(distributors.single.name, 'محمد المندوب');
      expect(distributors.single.phone, '0501234567');
      expect(distributors.single.vehicleNumber, '1234 أ ب ج');
      expect(distributors.single.type, StakeholderType.distributor);

      expect(drivers, hasLength(1));
      expect(drivers.single.name, 'سالم السائق');
      expect(drivers.single.type, StakeholderType.driver);
    });

    test('يحدّث البيانات ويبدّل الحالة فيختفي غير النشط من القوائم', () async {
      final StakeholderModel created = await addStakeholder(
        name: 'خالد',
        phone: '0500000000',
      );

      await repository.updateStakeholder(
        StakeholderModel(
          id: created.id,
          name: 'خالد العتيبي',
          type: StakeholderType.distributor,
          phone: '0511111111',
          vehicleNumber: 'أ ب ج 99',
          createdAt: created.createdAt,
        ),
      );

      final StakeholderModel? updated = await repository.getById(created.id!);
      expect(updated, isNotNull);
      expect(updated!.name, 'خالد العتيبي');
      expect(updated.phone, '0511111111');
      expect(updated.vehicleNumber, 'أ ب ج 99');

      await repository.toggleStatus(created.id!, isActive: false);
      expect(await repository.getDistributors(), isEmpty);

      final List<StakeholderModel> all = await repository.getAll(
        type: StakeholderType.distributor,
      );
      expect(all.single.isActive, isFalse);
    });

    test('البحث يعمل بالاسم والهاتف ورقم اللوحة', () async {
      await addStakeholder(name: 'أحمد علي', phone: '0501112233');
      await addStakeholder(
        name: 'يوسف حسن',
        phone: '0509998877',
        vehicleNumber: '4433 س ص',
      );

      expect(await repository.searchStakeholders('يوسف'), hasLength(1));
      expect(await repository.searchStakeholders('050111'), hasLength(1));
      expect(await repository.searchStakeholders('4433'), hasLength(1));
      expect(await repository.searchStakeholders('غير موجود'), isEmpty);

      final List<StakeholderModel> onlyDrivers = await repository
          .searchStakeholders('050', type: StakeholderType.driver);
      expect(onlyDrivers, isEmpty);
    });

    test('يحذف جهة التعامل نهائيًا', () async {
      final StakeholderModel created = await addStakeholder(name: 'مؤقت');
      await repository.deleteStakeholder(created.id!);

      expect(await repository.getAll(), isEmpty);
      expect(await repository.getById(created.id!), isNull);
    });
  });

  group('إعدادات النظام', () {
    test('تُبذر قيمة أمين المخزن الافتراضية', () async {
      final String? value = await helper.getSetting(
        AppConstants.settingStorekeeperName,
      );
      expect(value, AppConstants.defaultStorekeeperName);
    });

    test('يحفظ اسم أمين المخزن ويسترجعه', () async {
      await helper.setSetting(
        AppConstants.settingStorekeeperName,
        'أحمد علي - مسؤول المخزن',
      );

      final String? saved = await helper.getSetting(
        AppConstants.settingStorekeeperName,
        defaultValue: 'افتراضي',
      );
      expect(saved, 'أحمد علي - مسؤول المخزن');
    });

    test('يعيد القيمة الافتراضية للمفتاح غير الموجود', () async {
      expect(
        await helper.getSetting('missing_key', defaultValue: 'بديل'),
        'بديل',
      );
      expect(await helper.getSetting('missing_key'), isNull);
    });
  });

  group('StakeholderProvider', () {
    test('يحمّل القائمتين ويضيف جهة جديدة', () async {
      await addStakeholder(name: 'مندوب أول');
      await provider.loadStakeholders();

      expect(provider.distributors, hasLength(1));
      expect(provider.drivers, isEmpty);

      final bool added = await provider.addStakeholder(
        name: 'سائق جديد',
        type: StakeholderType.driver,
        phone: '0505555555',
      );

      expect(added, isTrue);
      expect(provider.drivers, hasLength(1));
      expect(provider.drivers.single.name, 'سائق جديد');
    });

    test('يرفض الإضافة بدون اسم', () async {
      final bool added = await provider.addStakeholder(
        name: '   ',
        type: StakeholderType.distributor,
      );

      expect(added, isFalse);
      expect(provider.errorMessage, 'اسم جهة التعامل مطلوب.');
      expect(provider.totalCount, 0);
    });

    test('يعطّل المندوب فيختفي من القائمة النشطة', () async {
      await addStakeholder(name: 'مندوب للتعطيل');
      await provider.loadStakeholders();

      final bool toggled = await provider.toggleStakeholder(
        provider.distributors.single,
      );

      expect(toggled, isTrue);
      expect(provider.distributors, isEmpty);
    });
  });

  group('الوحدات المزدوجة (كرتون + عبوة)', () {
    test('يحسب العبوات من الكراتين (20 عبوة لكل كرتون)', () {
      expect(AppFormatters.bottlesCount(0), 0);
      expect(AppFormatters.bottlesCount(1), 20);
      expect(AppFormatters.bottlesCount(125), 2500);
      expect(AppFormatters.bottlesCount(2, bottlesPerCarton: 12), 24);
    });

    test('ينسّق الكمية بالوحدتين معًا', () {
      final String formatted = AppFormatters.formatQuantityWithBottles(1);

      expect(formatted, contains('كرتون'));
      expect(formatted, contains('عبوة'));
      expect(formatted, contains(RegExp(r'[\(\)]')));
    });
  });
}
