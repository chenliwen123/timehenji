// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:life_achievements/main.dart';

void main() {
  // 演示用日期，刻意使用不与任何真人对应的虚构值。
  final sampleDates = LifeDatesConfig(
    birthDate: DateTime(1990, 3, 5),
    marriageDate: DateTime(2015, 10, 1),
    graduationDate: DateTime(2012, 7, 1),
    workDate: DateTime(2018, 4, 16),
  );

  testWidgets('显示人生里程碑首页', (WidgetTester tester) async {
    await tester.pumpWidget(const LifeAchievementsApp(
      client: null,
      startupError: '测试配置提示',
    ));
    await tester.pump();

    expect(find.text('测试配置提示'), findsOneWidget);
  });

  testWidgets('未登录进入首页时配置容器对所有页面可用', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const LifeAchievementsApp(client: null, startupError: '未配置云端'),
    );
    await tester.pump();

    await tester.tap(find.text('暂不登录，先看看'));
    // 首页加载是异步的，且进度指示与庆祝动画都不会让 pumpAndSettle 收敛，
    // 所以这里用有限次数的 pump 推进。
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('时间痕迹'), findsWidgets);
    // 没填日期时首页给出填写引导，而不是展示别人的真实日期。
    expect(find.text('还没有纪念日期'), findsOneWidget);
    expect(find.text('填写纪念日期'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未登录也能进入纪念日期编辑器并看到四个可填项', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const LifeAchievementsApp(client: null, startupError: '未配置云端'),
    );
    await tester.pump();
    await tester.tap(find.text('暂不登录，先看看'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.text('填写纪念日期'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('生日'), findsOneWidget);
    expect(find.text('结婚纪念日'), findsOneWidget);
    expect(find.text('毕业纪念日'), findsOneWidget);
    expect(find.text('入职纪念日'), findsOneWidget);
    expect(find.text('卡片与账号设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('本机已有日期时首页直接显示天数和卡片', (tester) async {
    SharedPreferences.setMockInitialValues({
      localLifeDatesKey: '{"birth_date":"1990-03-05"}',
    });
    await tester.pumpWidget(
      const LifeAchievementsApp(client: null, startupError: '未配置云端'),
    );
    await tester.pump();
    await tester.tap(find.text('暂不登录，先看看'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('还没有纪念日期'), findsNothing);
    expect(find.text('来到这个世界'), findsOneWidget);
    expect(find.textContaining('这是你来到这个世界的第'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('旧版一级规则会迁移到二级分组', () {
    final card = CustomLifeCard.fromJson({
      'id': 'marriage',
      'title': '结婚',
      'subtitle': '和爱人在一起',
      'rule': 'date',
      'date_entries': [
        {'date': '2020-05-20'},
        {'date': '2026-09-12', 'label': '测试'},
      ],
    });

    expect(card, isNotNull);
    expect(card!.subgroups.map((subgroup) => subgroup.title), [
      '结婚纪念日',
      '测试',
    ]);
    expect(card.subgroups.first.dateEntries.single.date, DateTime(2020, 5, 20));
    expect(card.subgroups.last.dateEntries.single.date, DateTime(2026, 9, 12));
    expect(card.toJson()['subgroups'], isA<List<dynamic>>());
  });

  test('配置容器换掉卡片后首页数据源跟着换', () async {
    final customCard = CustomLifeCard(
      id: 'custom-card',
      title: '旅行',
      subtitle: '特别的日子',
      subgroups: [
        CustomLifeSubgroup(
          id: 'custom-subgroup',
          title: '第一次出发',
          rule: CustomCardRule.date,
          dateEntries: [
            CustomDateEntry(date: DateTime(2021, 4, 18)),
          ],
        ),
      ],
    );
    final controller = LifeConfigController(sampleDates);
    var notified = 0;
    controller.addListener(() => notified++);

    expect(
      controller.lifeCards.map((card) => card.id),
      ['birth', 'marriage', 'graduation', 'work'],
    );

    await controller.replaceCards([customCard]);

    expect(controller.lifeCards.single.title, '旅行');
    expect(notified, 1);
  });

  test('一个日期都没填时不生成内置卡片和里程碑', () {
    const config = LifeDatesConfig();

    expect(config.hasAnyLifeDate, isFalse);
    expect(config.effectiveLifeCards, isEmpty);
    expect(config.milestones, isEmpty);
    expect(config.latestMilestones, isEmpty);
    expect(config.annualMilestones, isEmpty);
    expect(config.classifyPhotoDate(DateTime(2024, 5, 20)), '其他照片');
    // 云端记录里没填的日期要显式写回 null，否则 upsert 清不掉旧值。
    expect(config.toJson()['birth_date'], isNull);
  });

  test('只填部分日期时只生成对应的卡片', () {
    final config = LifeDatesConfig.defaults.copyWith(
      birthDate: sampleDates.birthDate,
    );

    expect(config.effectiveLifeCards.map((card) => card.id), ['birth']);
    expect(
      config.classifyPhotoDate(DateTime(1990, 3, 5)),
      contains('生日'),
    );
  });

  test('未登录填的日期会留在本机，且不会被空的云端记录抹掉', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await saveLifeDates(null, sampleDates), isFalse);

    final local = await loadLocalLifeDates();
    expect(local.birthDate, sampleDates.birthDate);
    expect(local.effectiveLifeCards, hasLength(4));

    final merged = await configFromRemoteRow({'birth_date': null});
    expect(merged.birthDate, sampleDates.birthDate);
  });

  test('改完纪念日期后年度纪念日会重新计算', () {
    final first =
        LifeDatesConfig.defaults.copyWith(birthDate: DateTime(1990, 3, 5));
    expect(first.annualMilestones.single.date, DateTime(1990, 3, 5));

    final second = first.copyWith(birthDate: DateTime(1991, 6, 6));
    expect(second.annualMilestones.single.date, DateTime(1991, 6, 6));
    expect(second.milestones.any((milestone) => milestone.category == '人生'),
        isTrue);
  });

  test('多个节日可以作为独立二级分组保存', () {
    final card = CustomLifeCard.fromJson({
      'id': 'festivals',
      'title': '节日',
      'subtitle': '',
      'enabled': true,
      'subgroups': [
        {
          'id': 'spring',
          'title': '春节',
          'rule': 'festival',
          'festival': '春节',
        },
        {
          'id': 'mid-autumn',
          'title': '中秋节',
          'rule': 'festival',
          'festival': '中秋节',
        },
      ],
    });

    expect(card, isNotNull);
    expect(card!.subgroups, hasLength(2));
    expect(
      card.subgroups.map((subgroup) => subgroup.festival),
      ['春节', '中秋节'],
    );
  });

  test('精确日期分组不会匹配其他年份同一天', () {
    final card = CustomLifeCard(
      id: 'travel',
      title: '旅行',
      subtitle: '',
      subgroups: [
        CustomLifeSubgroup(
          id: 'qingdao',
          title: '青岛旅行',
          rule: CustomCardRule.date,
          dateEntries: [
            CustomDateEntry(date: DateTime(2025, 5, 1), annual: false),
          ],
        ),
      ],
    );
    final photos = [
      MemoryPhoto(
        assetId: 'exact',
        category: '其他照片',
        captureDate: DateTime(2025, 5, 1),
        addedAt: DateTime(2025, 5, 1),
      ),
      MemoryPhoto(
        assetId: 'other-year',
        category: '其他照片',
        captureDate: DateTime(2026, 5, 1),
        addedAt: DateTime(2026, 5, 1),
      ),
    ];

    expect(photosForTopic(photos, photoTopicForCustomCard(card)), hasLength(1));
    expect(
      photosWithoutConfiguredGroup(photos, [card]).single.assetId,
      'other-year',
    );
  });

  test('仅绑定当前照片的分组不会按日期自动匹配', () {
    final cards = addPhotoDateGroup(
      cards: [
        const CustomLifeCard(
          id: 'life',
          title: '生活',
          subtitle: '',
        ),
      ],
      cardId: 'life',
      groupTitle: '随手拍',
      captureDate: DateTime(2025, 6, 18),
      matchSameDate: false,
    );
    final subgroup = cards.single.subgroups.single;
    final photos = [
      MemoryPhoto(
        assetId: 'manual',
        category: '其他照片',
        captureDate: DateTime(2025, 6, 18),
        addedAt: DateTime(2025, 6, 18),
        manualTopicId: 'life',
        manualCategoryId: subgroup.id,
        manualCategory: '随手拍',
      ),
      MemoryPhoto(
        assetId: 'same-day',
        category: '其他照片',
        captureDate: DateTime(2025, 6, 18),
        addedAt: DateTime(2025, 6, 18),
      ),
    ];

    expect(subgroup.matchByDate, isFalse);
    expect(photosForTopic(photos, photoTopicForCustomCard(cards.single)),
        hasLength(1));
    expect(
        photosWithoutConfiguredGroup(photos, cards).single.assetId, 'same-day');
    expect(
      CustomLifeCard.fromJson(cards.single.toJson())!
          .subgroups
          .single
          .matchByDate,
      isFalse,
    );
  });

  test('一次性分组不按年份展示并能保存配置', () {
    final subgroup = CustomLifeSubgroup(
      id: 'first-hike',
      title: '阿宁第一次爬山',
      rule: CustomCardRule.date,
      groupByYear: false,
      dateEntries: [
        CustomDateEntry(
          date: DateTime(2025, 5, 1),
          annual: false,
        ),
      ],
    );
    final card = CustomLifeCard(
      id: 'life',
      title: '生活',
      subtitle: '',
      subgroups: [subgroup],
    );

    expect(photoGroupUsesYearSubgroups(card, '阿宁第一次爬山'), isFalse);
    final restored = CustomLifeCard.fromJson(card.toJson())!;
    expect(
      restored.subgroups.single.groupByYear,
      isFalse,
    );
    expect(
      photoGroupUsesYearSubgroups(restored, '阿宁第一次爬山'),
      isFalse,
    );
  });

  test('旧版精确日期自动视为一次性分组', () {
    final card = CustomLifeCard.fromJson({
      'id': 'life',
      'title': '生活',
      'subtitle': '',
      'subgroups': [
        {
          'id': 'first-hike',
          'title': '阿宁第一次爬山',
          'rule': 'date',
          'date_entries': [
            {'date': '2025-05-01', 'annual': false},
          ],
        },
      ],
    })!;

    expect(photoGroupUsesYearSubgroups(card, '阿宁第一次爬山'), isFalse);
  });

  test('每日回顾只查往年同月同日的已分组照片', () {
    final card = CustomLifeCard(
      id: 'life',
      title: '生活',
      subtitle: '',
      subgroups: [
        CustomLifeSubgroup(
          id: 'first-hike',
          title: '阿宁第一次爬山',
          rule: CustomCardRule.date,
          dateEntries: [
            CustomDateEntry(date: DateTime(2024, 9, 14)),
          ],
        ),
      ],
    );
    final photos = [
      MemoryPhoto(
        assetId: 'last-year',
        category: '其他照片',
        captureDate: DateTime(2025, 9, 14),
        addedAt: DateTime(2025, 9, 14),
      ),
      MemoryPhoto(
        assetId: 'this-year',
        category: '其他照片',
        captureDate: DateTime(2026, 9, 14),
        addedAt: DateTime(2026, 9, 14),
      ),
      MemoryPhoto(
        assetId: 'different-day',
        category: '其他照片',
        captureDate: DateTime(2025, 9, 15),
        addedAt: DateTime(2025, 9, 15),
      ),
    ];

    final memories = findDailyMemoryGroups(
      photos,
      [card],
      today: DateTime(2026, 9, 14),
    );
    expect(memories, hasLength(1));
    expect(memories.single.year, 2025);
    expect(memories.single.cardTitle, '生活');
    expect(memories.single.groupTitle, '阿宁第一次爬山');
    expect(memories.single.photos.map((photo) => photo.assetId), ['last-year']);
  });

  test('连续留痕允许今天未完成时延续到昨天', () {
    const state = MemoryActivityState(
      actionsByDate: {
        '2026-09-17': {'review'},
        '2026-09-18': {'browse'},
        '2026-09-19': {'organize'},
      },
    );

    expect(state.currentStreak(DateTime(2026, 9, 20)), 3);
    expect(state.longestStreak, 3);
    expect(state.totalDays, 3);
  });

  test('真实行为和连续记录会解锁对应成就', () {
    const state = MemoryActivityState(
      actionsByDate: {
        '2026-09-18': {'review'},
        '2026-09-19': {'browse'},
        '2026-09-20': {'organize', 'event'},
      },
      maxReviewYears: 5,
    );
    final unlocked = memoryAchievements(state)
        .where((achievement) => achievement.unlocked)
        .map((achievement) => achievement.id)
        .toSet();

    expect(
      unlocked,
      containsAll({
        'first_trace',
        'first_review',
        'first_browse',
        'first_organize',
        'first_event',
        'streak_3',
        'echo_3_years',
        'echo_5_years',
      }),
    );
    expect(unlocked, isNot(contains('streak_7')));
  });
}
