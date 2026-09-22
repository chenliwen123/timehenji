part of '../main.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const authRedirectUrl = 'timehenji://login-callback/';

enum CustomCardRule { date, festival }

enum CalendarType { solar, lunar }

const builtInLifeCardIds = {'birth', 'marriage', 'graduation', 'work'};
const supportedFestivals = [
  '春节',
  '元宵节',
  '清明节',
  '端午节',
  '七夕节',
  '中元节',
  '中秋节',
  '重阳节',
  '腊八节',
  '小年',
  '除夕',
  '妇女节',
  '劳动节',
  '儿童节',
  '建党节',
  '建军节',
  '教师节',
  '国庆节',
  '圣诞节',
];

class CustomDateEntry {
  const CustomDateEntry({
    required this.date,
    this.label = '',
    this.calendar = CalendarType.solar,
    this.annual = true,
  });

  final DateTime date;
  final String label;
  final CalendarType calendar;
  final bool annual;

  Map<String, dynamic> toJson() => {
        'date': dateKey(date),
        'label': label,
        'calendar': calendar.name,
        if (!annual) 'annual': false,
      };

  static CustomDateEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final date = DateTime.tryParse(value['date']?.toString() ?? '');
    if (date == null) return null;
    return CustomDateEntry(
      date: dateOnly(date),
      label: value['label']?.toString().trim() ?? '',
      calendar: value['calendar'] == CalendarType.lunar.name
          ? CalendarType.lunar
          : CalendarType.solar,
      annual: value['annual'] is bool ? value['annual'] as bool : true,
    );
  }
}

class CustomLifeSubgroup {
  const CustomLifeSubgroup({
    required this.id,
    required this.title,
    required this.rule,
    this.enabled = true,
    this.dateEntries = const [],
    this.festival,
    this.matchByDate = true,
    this.groupByYear = true,
  });

  final String id;
  final String title;
  final CustomCardRule rule;
  final bool enabled;
  final List<CustomDateEntry> dateEntries;
  final String? festival;
  final bool matchByDate;
  final bool groupByYear;

  DateTime? get primaryDate =>
      dateEntries.isEmpty ? null : dateEntries.first.date;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'rule': rule.name,
        'enabled': enabled,
        if (dateEntries.isNotEmpty)
          'date_entries': dateEntries.map((entry) => entry.toJson()).toList(),
        if (festival != null && festival!.isNotEmpty) 'festival': festival,
        if (rule == CustomCardRule.date && !matchByDate) 'match_by_date': false,
        if (!groupByYear) 'group_by_year': false,
      };

  static CustomLifeSubgroup? fromJson(Object? value) {
    if (value is! Map) return null;
    final title = value['title']?.toString().trim() ?? '';
    if (title.isEmpty) return null;
    final id = value['id']?.toString().trim() ?? title;
    final rule = value['rule'] == CustomCardRule.festival.name
        ? CustomCardRule.festival
        : CustomCardRule.date;
    final dateEntries = value['date_entries'] is List
        ? (value['date_entries'] as List)
            .map(CustomDateEntry.fromJson)
            .whereType<CustomDateEntry>()
            .map(
              (entry) => CustomDateEntry(
                date: entry.date,
                calendar: entry.calendar,
                annual: entry.annual,
              ),
            )
            .toList()
        : <CustomDateEntry>[];
    final dates = value['dates'] is List
        ? (value['dates'] as List)
            .map((item) => DateTime.tryParse(item.toString()))
            .whereType<DateTime>()
            .map((date) => CustomDateEntry(date: dateOnly(date)))
            .toList()
        : <CustomDateEntry>[];
    final legacyDate = DateTime.tryParse(value['date']?.toString() ?? '');
    final entries = dateEntries.isNotEmpty
        ? dateEntries
        : dates.isNotEmpty
            ? dates
            : legacyDate == null
                ? const <CustomDateEntry>[]
                : [CustomDateEntry(date: dateOnly(legacyDate))];
    final festival = value['festival']?.toString().trim();
    if (rule == CustomCardRule.date && entries.isEmpty) return null;
    if (rule == CustomCardRule.festival &&
        (festival == null || festival.isEmpty)) {
      return null;
    }
    return CustomLifeSubgroup(
      id: id,
      title: title,
      rule: rule,
      enabled: value['enabled'] is bool ? value['enabled'] as bool : true,
      dateEntries: entries,
      festival: festival,
      matchByDate: value['match_by_date'] is bool
          ? value['match_by_date'] as bool
          : true,
      groupByYear: value['group_by_year'] is bool
          ? value['group_by_year'] as bool
          : rule == CustomCardRule.date
              ? entries.any((entry) => entry.annual)
              : true,
    );
  }

  CustomLifeSubgroup copyWith({
    String? title,
    CustomCardRule? rule,
    bool? enabled,
    List<CustomDateEntry>? dateEntries,
    String? festival,
    bool? matchByDate,
    bool? groupByYear,
  }) {
    return CustomLifeSubgroup(
      id: id,
      title: title ?? this.title,
      rule: rule ?? this.rule,
      enabled: enabled ?? this.enabled,
      dateEntries: dateEntries ?? this.dateEntries,
      festival: festival ?? this.festival,
      matchByDate: matchByDate ?? this.matchByDate,
      groupByYear: groupByYear ?? this.groupByYear,
    );
  }
}

class CustomLifeCard {
  const CustomLifeCard({
    required this.id,
    required this.title,
    required this.subtitle,
    this.enabled = true,
    this.subgroups = const [],
  });

  final String id;
  final String title;
  final String subtitle;
  final bool enabled;
  final List<CustomLifeSubgroup> subgroups;

  List<CustomLifeSubgroup> get enabledSubgroups =>
      subgroups.where((subgroup) => subgroup.enabled).toList();

  DateTime? get primaryDate {
    for (final subgroup in enabledSubgroups) {
      final date = subgroup.primaryDate;
      if (date != null) return date;
    }
    for (final subgroup in subgroups) {
      final date = subgroup.primaryDate;
      if (date != null) return date;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'enabled': enabled,
        'subgroups': subgroups.map((subgroup) => subgroup.toJson()).toList(),
      };

  static CustomLifeCard? fromJson(Object? value) {
    if (value is! Map) return null;
    final title = value['title']?.toString().trim() ?? '';
    final id = value['id']?.toString().trim() ?? '';
    if (id.isEmpty || title.isEmpty) return null;

    final rawSubgroups = value['subgroups'];
    if (rawSubgroups is List) {
      return CustomLifeCard(
        id: id,
        title: title,
        subtitle: value['subtitle']?.toString().trim() ?? '',
        enabled: value['enabled'] is bool ? value['enabled'] as bool : true,
        subgroups: rawSubgroups
            .map(CustomLifeSubgroup.fromJson)
            .whereType<CustomLifeSubgroup>()
            .toList(),
      );
    }

    return _fromLegacyJson(value, id: id, title: title);
  }

  static CustomLifeCard? _fromLegacyJson(
    Map value, {
    required String id,
    required String title,
  }) {
    final rule = value['rule'] == CustomCardRule.festival.name
        ? CustomCardRule.festival
        : CustomCardRule.date;
    final dateEntries = value['date_entries'] is List
        ? (value['date_entries'] as List)
            .map(CustomDateEntry.fromJson)
            .whereType<CustomDateEntry>()
            .toList()
        : <CustomDateEntry>[];
    final dates = value['dates'] is List
        ? (value['dates'] as List)
            .map((item) => DateTime.tryParse(item.toString()))
            .whereType<DateTime>()
            .map(dateOnly)
            .toList()
        : <DateTime>[];
    final legacyDate = DateTime.tryParse(value['date']?.toString() ?? '');
    final festival = value['festival']?.toString().trim();
    final subgroups = <CustomLifeSubgroup>[];

    if (rule == CustomCardRule.date) {
      final entries = <CustomDateEntry>[
        ...dateEntries,
        ...dates.map((date) => CustomDateEntry(date: date)),
        if (dateEntries.isEmpty && dates.isEmpty && legacyDate != null)
          CustomDateEntry(date: dateOnly(legacyDate)),
      ];
      final grouped = <String, List<CustomDateEntry>>{};
      for (final entry in entries) {
        final subgroupTitle = entry.label.trim().isEmpty
            ? _legacyDateSubgroupTitle(id, title)
            : entry.label.trim();
        grouped.putIfAbsent(subgroupTitle, () => []).add(
              CustomDateEntry(
                date: entry.date,
                calendar: entry.calendar,
                annual: entry.annual,
              ),
            );
      }
      for (final group in grouped.entries) {
        subgroups.add(
          CustomLifeSubgroup(
            id: '$id-${group.key}',
            title: group.key,
            rule: CustomCardRule.date,
            dateEntries: group.value,
          ),
        );
      }
    } else if (festival != null && festival.isNotEmpty) {
      subgroups.add(
        CustomLifeSubgroup(
          id: '$id-$festival',
          title: festival,
          rule: CustomCardRule.festival,
          festival: festival,
        ),
      );
    }

    if (subgroups.isEmpty) return null;
    return CustomLifeCard(
      id: id,
      title: title,
      subtitle: value['subtitle']?.toString().trim() ?? '',
      enabled: value['enabled'] is bool ? value['enabled'] as bool : true,
      subgroups: subgroups,
    );
  }

  CustomLifeCard copyWith({
    String? title,
    String? subtitle,
    bool? enabled,
    List<CustomLifeSubgroup>? subgroups,
  }) {
    return CustomLifeCard(
      id: id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      enabled: enabled ?? this.enabled,
      subgroups: subgroups ?? this.subgroups,
    );
  }
}

String _legacyDateSubgroupTitle(String id, String title) {
  return switch (id) {
    'birth' => '生日',
    'marriage' => '结婚纪念日',
    'graduation' => '毕业纪念日',
    'work' => '入职纪念日',
    _ => title,
  };
}

List<CustomLifeCard> parseCustomCards(Object? value) {
  Object? decoded = value;
  if (value is String && value.trim().isNotEmpty) {
    try {
      decoded = jsonDecode(value);
    } catch (_) {
      decoded = null;
    }
  }
  if (decoded is! List) return [];
  return decoded
      .map(
        (item) => item is CustomLifeCard ? item : CustomLifeCard.fromJson(item),
      )
      .whereType<CustomLifeCard>()
      .toList();
}

Future<List<CustomLifeCard>> loadMergedCustomCards(Object? remoteValue) async {
  final remoteCards = parseCustomCards(remoteValue);
  final localCards = parseCustomCards(await loadLocalCustomCards());
  return mergeCustomCardLists(remoteCards, localCards);
}

List<CustomLifeCard> mergeCustomCardLists(
  List<CustomLifeCard> primary,
  List<CustomLifeCard> override,
) {
  final merged = <String, CustomLifeCard>{
    for (final card in primary) card.id: card,
  };
  for (final card in override) {
    merged[card.id] = card;
  }
  return merged.values.toList();
}

/// 内置卡片由用户填写的日期生成；某个日期没填就不生成对应卡片。
/// 早期版本在这里写死了开发者本人的真实日期作为默认值，公开仓库里必须去掉。
List<CustomLifeCard> builtInLifeCards({
  DateTime? birth,
  DateTime? marriage,
  DateTime? graduation,
  DateTime? work,
}) {
  CustomLifeSubgroup dateSubgroup(String id, String title, DateTime date) {
    return CustomLifeSubgroup(
      id: '$id-date',
      title: title,
      rule: CustomCardRule.date,
      dateEntries: [CustomDateEntry(date: date)],
    );
  }

  return [
    if (birth != null)
      CustomLifeCard(
        id: 'birth',
        title: '来到这个世界',
        subtitle: '从出生到今天',
        subgroups: [dateSubgroup('birth', '生日', birth)],
      ),
    if (marriage != null)
      CustomLifeCard(
        id: 'marriage',
        title: '结婚',
        subtitle: '和爱人在一起',
        subgroups: [dateSubgroup('marriage', '结婚纪念日', marriage)],
      ),
    if (graduation != null)
      CustomLifeCard(
        id: 'graduation',
        title: '毕业',
        subtitle: '走出校园',
        subgroups: [dateSubgroup('graduation', '毕业纪念日', graduation)],
      ),
    if (work != null)
      CustomLifeCard(
        id: 'work',
        title: '加入公司',
        subtitle: '职业旅程',
        subgroups: [dateSubgroup('work', '入职纪念日', work)],
      ),
  ];
}

List<CustomLifeCard> normalizeLifeCards(
  List<CustomLifeCard> stored, {
  DateTime? birth,
  DateTime? marriage,
  DateTime? graduation,
  DateTime? work,
}) {
  final defaults = builtInLifeCards(
    birth: birth,
    marriage: marriage,
    graduation: graduation,
    work: work,
  );
  final byId = <String, CustomLifeCard>{
    for (final card in stored) card.id: card,
  };
  return [
    for (final card in defaults) byId[card.id] ?? card,
    for (final card in stored)
      if (!builtInLifeCardIds.contains(card.id)) card,
  ];
}

const localCustomCardsKey = 'custom_life_cards';
const localLifeDatesKey = 'life_memorial_dates';
const memoryPhotosStorageKey = 'marriage_memory_photos';
const dailyMemoryReviewEnabledKey = 'daily_memory_review_enabled';
const dailyMemoryReviewLastShownPrefix = 'daily_memory_review_last_shown_';
Future<List<MemoryPhoto>>? cachedMemoryPhotosFuture;
List<MemoryPhoto>? cachedMemoryPhotos;
final Map<String, Future<AssetEntity?>> memoryPhotoAssetFutures = {};

/// 读取相册实体时优先复用内存里已有的 asset；
/// 冷启动后只有 assetId 的照片会向相册查询一次并缓存，避免界面重建时重复查询。
Future<AssetEntity?> resolveMemoryPhotoAsset(MemoryPhoto photo) {
  final asset = photo.asset;
  if (asset != null) return Future.value(asset);
  final assetId = photo.assetId;
  if (assetId == null) return Future.value(null);
  return memoryPhotoAssetFutures.putIfAbsent(assetId, () async {
    try {
      return await AssetEntity.fromId(assetId);
    } catch (_) {
      memoryPhotoAssetFutures.remove(assetId);
      return null;
    }
  });
}
