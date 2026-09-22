part of '../main.dart';

/// 由纪念日期派生出来的规则。全部写成 [LifeDatesConfig] 的成员，
/// 是为了让每次读取都基于当前配置重新计算——原先的顶层 final
/// [annualMilestones] 会在首次访问时把日期永久缓存下来，改完日期不刷新。
extension LifeDateSummary on LifeDatesConfig {
  String classifyPhotoDate(DateTime captureDate) {
    final lunarFestivals = Lunar.fromDate(captureDate).getFestivals();
    if (lunarFestivals.contains('除夕')) {
      return '春节 · 除夕 ${captureDate.year}';
    }
    if (birthDate != null &&
        captureDate.month == birthDate!.month &&
        captureDate.day == birthDate!.day) {
      return '生日 · ${captureDate.year}';
    }
    final events = [
      (label: '人生第', date: birthDate),
      (label: '结婚', date: marriageDate),
      (label: '毕业', date: graduationDate),
      (label: '工作', date: workDate),
    ].where((event) => event.date != null).toList();
    final matches = <String>[];
    for (final event in events) {
      final date = event.date!;
      final days = daysBetweenInclusive(date, captureDate);
      if (days > 0 && days % 100 == 0) {
        matches.add('${event.label}${formatNumber(days)}天');
      }
      final years = completedYearsOnDate(date, captureDate);
      if (years > 0 &&
          captureDate.month == date.month &&
          captureDate.day == date.day) {
        matches.add('${event.label}$years周年');
      }
    }
    return matches.isEmpty ? '其他照片' : matches.join(' · ');
  }

  List<Milestone> get milestones {
    final result = <Milestone>[];
    final categories = _milestoneCategories;
    for (final item in categories) {
      final currentDays = daysSince(item.date);
      final lastMilestone = ((currentDays + 99) ~/ 100) * 100;
      for (var days = 100; days <= lastMilestone; days += 100) {
        result.add(
          Milestone(
            title: '${item.prefix} ${formatNumber(days)} 天',
            category: item.category,
            date: item.date,
            days: days,
          ),
        );
      }
    }
    return result;
  }

  /// 只包含用户真正填过的日期；未填的分类不出现在列表里，
  /// 也就不会被首页的纪念日卡片和进度条引用。
  List<({String category, String prefix, DateTime date})>
      get _milestoneCategories => [
            if (birthDate != null)
              (category: '人生', prefix: '人生第', date: birthDate!),
            if (marriageDate != null)
              (category: '婚姻', prefix: '结婚', date: marriageDate!),
            if (graduationDate != null)
              (category: '毕业', prefix: '毕业', date: graduationDate!),
            if (workDate != null)
              (category: '工作', prefix: '工作', date: workDate!),
          ];

  /// 每个已配置分类返回一个里程碑：优先取最近达成的，一个都还没达成时
  /// 返回即将到来的第一个，这样首页仍然能显示"还差多少天"。
  /// 没填日期的分类不会出现在结果里。
  List<Milestone> get latestMilestones {
    final all = milestones;
    final result = <Milestone>[];
    for (final category in _milestoneCategories.map((item) => item.category)) {
      final items = all
          .where((milestone) => milestone.category == category)
          .toList();
      if (items.isEmpty) continue;
      final reached = items
          .where((milestone) => daysSince(milestone.date) >= milestone.days)
          .toList();
      result.add(reached.isEmpty ? items.first : reached.last);
    }
    return result;
  }

  List<AnnualMilestone> get annualMilestones => [
        if (birthDate != null)
          AnnualMilestone(title: '来到这个世界', date: birthDate!),
        if (marriageDate != null)
          AnnualMilestone(title: '结婚纪念日', date: marriageDate!),
        if (graduationDate != null)
          AnnualMilestone(title: '毕业纪念日', date: graduationDate!),
        if (workDate != null)
          AnnualMilestone(title: '入职纪念日', date: workDate!),
      ];
}

int daysBetweenInclusive(DateTime start, DateTime end) {
  return dateOnly(end).toUtc().difference(dateOnly(start).toUtc()).inDays + 1;
}

int completedYearsOnDate(DateTime start, DateTime end) {
  final target = dateOnly(end);
  var years = target.year - start.year;
  if (DateTime(target.year, start.month, start.day).isAfter(target)) years--;
  return math.max(0, years);
}

String formatDate(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

class MemoryPhoto {
  const MemoryPhoto({
    this.path,
    this.assetId,
    this.asset,
    required this.category,
    required this.captureDate,
    required this.addedAt,
    this.manualTopic,
    this.manualTopicId,
    this.manualCategory,
    this.manualCategoryId,
  });

  final String? path;
  final String? assetId;
  final AssetEntity? asset;
  final String category;
  final DateTime captureDate;
  final DateTime addedAt;
  final String? manualTopic;
  final String? manualTopicId;
  final String? manualCategory;
  final String? manualCategoryId;

  String? get identityKey => assetId ?? path;

  MemoryPhoto copyWith({
    String? category,
    String? manualTopic,
    String? manualTopicId,
    String? manualCategory,
    String? manualCategoryId,
  }) {
    return MemoryPhoto(
      path: path,
      assetId: assetId,
      asset: asset,
      category: category ?? this.category,
      captureDate: captureDate,
      addedAt: addedAt,
      manualTopic: manualTopic ?? this.manualTopic,
      manualTopicId: manualTopicId ?? this.manualTopicId,
      manualCategory: manualCategory ?? this.manualCategory,
      manualCategoryId: manualCategoryId ?? this.manualCategoryId,
    );
  }

  Map<String, dynamic> toJson() => {
        if (path != null) 'path': path,
        if (assetId != null) 'assetId': assetId,
        'category': category,
        'captureDate': captureDate.toIso8601String(),
        'addedAt': addedAt.toIso8601String(),
        if (manualTopic != null) 'manualTopic': manualTopic,
        if (manualTopicId != null) 'manualTopicId': manualTopicId,
        if (manualCategory != null) 'manualCategory': manualCategory,
        if (manualCategoryId != null) 'manualCategoryId': manualCategoryId,
      };

  static MemoryPhoto? fromJson(Object? value) {
    if (value is! Map) return null;
    final path = value['path'];
    final assetId = value['assetId'];
    final category = value['category'];
    final captureDate = DateTime.tryParse(
      value['captureDate']?.toString() ?? value['addedAt']?.toString() ?? '',
    );
    final addedAt = DateTime.tryParse(value['addedAt']?.toString() ?? '');
    final manualTopic = value['manualTopic'];
    final manualTopicId = value['manualTopicId'];
    final manualCategory = value['manualCategory'];
    final manualCategoryId = value['manualCategoryId'];
    if (path is! String && assetId is! String ||
        category is! String ||
        captureDate == null ||
        addedAt == null) {
      return null;
    }
    return MemoryPhoto(
      path: path is String ? path : null,
      assetId: assetId is String ? assetId : null,
      category: category,
      captureDate: captureDate,
      addedAt: addedAt,
      manualTopic: manualTopic is String ? manualTopic : null,
      manualTopicId: manualTopicId is String ? manualTopicId : null,
      manualCategory: manualCategory is String ? manualCategory : null,
      manualCategoryId: manualCategoryId is String ? manualCategoryId : null,
    );
  }
}

class DailyMemoryGroup {
  const DailyMemoryGroup({
    required this.year,
    required this.cardTitle,
    required this.groupTitle,
    required this.photos,
  });

  final int year;
  final String cardTitle;
  final String groupTitle;
  final List<MemoryPhoto> photos;
}

List<DailyMemoryGroup> findDailyMemoryGroups(
  List<MemoryPhoto> source,
  List<CustomLifeCard> cards, {
  DateTime? today,
}) {
  final target = dateOnly(today ?? DateTime.now());
  final groupedPhotos = <String, List<MemoryPhoto>>{};
  final groupInfo =
      <String, ({int year, String cardTitle, String groupTitle})>{};
  final seenPhotos = <String, Set<String>>{};

  for (var index = 0; index < source.length; index++) {
    final photo = source[index];
    final captureDate = dateOnly(photo.captureDate);
    if (captureDate.year >= target.year ||
        captureDate.month != target.month ||
        captureDate.day != target.day) {
      continue;
    }

    final photoKey = photo.identityKey ?? '${dateKey(captureDate)}:$index';
    for (final card in cards.where((card) => card.enabled)) {
      final labels = _dailyMemoryGroupTitles(photo, card);
      for (final groupTitle in labels.toSet()) {
        if (groupTitle.trim().isEmpty) continue;
        final groupKey = '${captureDate.year}|${card.id}|${groupTitle.trim()}';
        final groupPhotos = groupedPhotos.putIfAbsent(groupKey, () => []);
        final groupPhotoKeys = seenPhotos.putIfAbsent(groupKey, () => {});
        if (groupPhotoKeys.add(photoKey)) groupPhotos.add(photo);
        groupInfo[groupKey] = (
          year: captureDate.year,
          cardTitle: card.title,
          groupTitle: groupTitle.trim(),
        );
      }
    }
  }

  final result = [
    for (final entry in groupedPhotos.entries)
      DailyMemoryGroup(
        year: groupInfo[entry.key]!.year,
        cardTitle: groupInfo[entry.key]!.cardTitle,
        groupTitle: groupInfo[entry.key]!.groupTitle,
        photos: entry.value,
      ),
  ];
  result.sort((left, right) {
    final yearOrder = right.year.compareTo(left.year);
    if (yearOrder != 0) return yearOrder;
    final cardOrder = left.cardTitle.compareTo(right.cardTitle);
    if (cardOrder != 0) return cardOrder;
    return left.groupTitle.compareTo(right.groupTitle);
  });
  return result;
}

List<String> _dailyMemoryGroupTitles(
  MemoryPhoto photo,
  CustomLifeCard card,
) {
  final manuallyAssigned = photo.manualTopicId == card.id ||
      photo.manualTopicId == null && photo.manualTopic == card.title;
  if (manuallyAssigned) {
    String? groupTitle;
    if (photo.manualCategoryId != null) {
      for (final subgroup in card.subgroups) {
        if (subgroup.id == photo.manualCategoryId) {
          groupTitle = subgroup.title;
          break;
        }
      }
    }
    groupTitle ??= photo.manualCategory;
    return groupTitle == null || groupTitle.trim().isEmpty
        ? const []
        : [groupTitle.trim()];
  }
  return _PhotoTopicMatcher(photoTopicForCustomCard(card))
      .categoriesFor(photo.captureDate);
}

class LifeCounter {
  const LifeCounter({
    required this.title,
    required this.subtitle,
    required this.date,
    required this.icon,
    required this.color,
    this.topic,
  });

  final String title;
  final String subtitle;
  final DateTime date;
  final IconData icon;
  final Color color;
  final PhotoTopic? topic;
}

class Milestone {
  const Milestone({
    required this.title,
    required this.category,
    required this.date,
    required this.days,
  });

  final String title;
  final String category;
  final DateTime date;
  final int days;
}

class AnnualMilestone {
  const AnnualMilestone({required this.title, required this.date});

  final String title;
  final DateTime date;
}

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

int daysSince(DateTime start) {
  final today = dateOnly(DateTime.now());
  return today.toUtc().difference(dateOnly(start).toUtc()).inDays + 1;
}

bool isAnnualMilestoneToday(DateTime start) {
  final today = dateOnly(DateTime.now());
  return today.year > start.year &&
      today.month == start.month &&
      today.day == start.day;
}

int completedYearsSince(DateTime start) {
  final today = dateOnly(DateTime.now());
  var years = today.year - start.year;
  final anniversary = DateTime(today.year, start.month, start.day);
  if (anniversary.isAfter(today)) years--;
  return math.max(0, years);
}

String formatNumber(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < text.length; index++) {
    if (index > 0 && (text.length - index) % 3 == 0) buffer.write(',');
    buffer.write(text[index]);
  }
  return buffer.toString();
}
