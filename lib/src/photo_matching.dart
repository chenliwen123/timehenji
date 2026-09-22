part of '../main.dart';

enum PhotoTopicKind {
  birth,
  marriage,
  graduation,
  work,
  customDate,
  customFestival,
}

class PhotoTopic {
  const PhotoTopic({
    required this.title,
    required this.date,
    required this.kind,
    this.customCard,
  });

  final String title;
  final DateTime date;
  final PhotoTopicKind kind;
  final CustomLifeCard? customCard;
}

PhotoTopic photoTopicForCustomCard(CustomLifeCard card) {
  return PhotoTopic(
    title: card.title,
    date: card.primaryDate ?? dateOnly(DateTime.now()),
    kind: card.subgroups.any(
      (subgroup) => subgroup.rule == CustomCardRule.date,
    )
        ? PhotoTopicKind.customDate
        : PhotoTopicKind.customFestival,
    customCard: card,
  );
}

PhotoTopic photoTopicForLifeCard(CustomLifeCard card) {
  return photoTopicForCustomCard(card);
}

PhotoTopic photoTopicForTitle(List<CustomLifeCard> cards, String title) {
  final card = cards.where((item) => item.title == title).firstOrNull;
  if (card != null) return photoTopicForLifeCard(card);
  // 卡片可能被全部删掉，或日期还没配置导致内置卡片为空；
  // 这时按标题回退，调用方仍然能打开分组照片页而不是崩溃。
  return PhotoTopic(
    title: title,
    date: dateOnly(DateTime.now()),
    kind: PhotoTopicKind.customDate,
  );
}

List<MemoryPhoto> photosForTopic(
  List<MemoryPhoto> source,
  PhotoTopic topic,
) {
  final result = <MemoryPhoto>[];
  final matcher = _PhotoTopicMatcher(topic);
  for (final photo in source) {
    if (_isManuallyAssignedToTopic(photo, topic)) {
      final category = _manualCategoryForTopic(photo, topic);
      result.add(photo.copyWith(category: category));
      continue;
    }
    final categories = matcher.categoriesFor(photo.captureDate);
    for (final category in categories) {
      result.add(photo.copyWith(category: category));
    }
  }
  return result;
}

Future<List<MemoryPhoto>> photosForTopicAsync(
  List<MemoryPhoto> source,
  PhotoTopic topic,
) async {
  final result = <MemoryPhoto>[];
  final matcher = _PhotoTopicMatcher(topic);
  for (var index = 0; index < source.length; index++) {
    final photo = source[index];
    if (_isManuallyAssignedToTopic(photo, topic)) {
      final category = _manualCategoryForTopic(photo, topic);
      result.add(photo.copyWith(category: category));
    } else {
      final categories = matcher.categoriesFor(photo.captureDate);
      for (final category in categories) {
        result.add(photo.copyWith(category: category));
      }
    }
    if (index > 0 && index % 80 == 0) {
      await Future<void>.delayed(Duration.zero);
    }
  }
  return result;
}

bool _isManuallyAssignedToTopic(MemoryPhoto photo, PhotoTopic topic) {
  final topicId = topic.customCard?.id;
  return topicId != null && photo.manualTopicId == topicId ||
      photo.manualTopicId == null && photo.manualTopic == topic.title;
}

String _manualCategoryForTopic(MemoryPhoto photo, PhotoTopic topic) {
  final categoryId = photo.manualCategoryId;
  if (categoryId != null) {
    for (final subgroup in topic.customCard?.subgroups ?? const []) {
      if (subgroup.id == categoryId) return subgroup.title;
    }
  }
  return photo.manualCategory ?? topic.title;
}

List<MemoryPhoto> photosWithoutConfiguredGroup(
  List<MemoryPhoto> source,
  List<CustomLifeCard> cards,
) {
  final matcher = _ConfiguredPhotoMatcher(cards);
  return source.where((photo) => !matcher.matches(photo)).toList();
}

Future<List<MemoryPhoto>> photosWithoutConfiguredGroupAsync(
  List<MemoryPhoto> source,
  List<CustomLifeCard> cards,
) async {
  final matcher = _ConfiguredPhotoMatcher(cards);
  final result = <MemoryPhoto>[];
  for (var index = 0; index < source.length; index++) {
    final photo = source[index];
    if (!matcher.matches(photo)) result.add(photo);
    if (index > 0 && index % 80 == 0) {
      await Future<void>.delayed(Duration.zero);
    }
  }
  return result;
}

class _ConfiguredPhotoMatcher {
  _ConfiguredPhotoMatcher(List<CustomLifeCard> cards)
      : cards = cards.where((card) => card.enabled).toList(),
        matchers = [
          for (final card in cards.where((card) => card.enabled))
            _PhotoTopicMatcher(photoTopicForCustomCard(card)),
        ];

  final List<CustomLifeCard> cards;
  final List<_PhotoTopicMatcher> matchers;

  bool matches(MemoryPhoto photo) {
    final manualTopicId = photo.manualTopicId;
    if (manualTopicId != null &&
        cards.any((card) => card.id == manualTopicId)) {
      return true;
    }
    final manualTopic = photo.manualTopic;
    if (manualTopicId == null &&
        manualTopic != null &&
        cards.any((card) => card.title == manualTopic)) {
      return true;
    }
    return matchers.any(
      (matcher) => matcher.categoriesFor(photo.captureDate).isNotEmpty,
    );
  }
}

List<CustomLifeCard> addPhotoDateGroup({
  required List<CustomLifeCard> cards,
  required String cardId,
  required String groupTitle,
  required DateTime captureDate,
  required bool matchSameDate,
}) {
  return [
    for (final card in cards)
      if (card.id != cardId)
        card
      else
        card.copyWith(
          subgroups: _addPhotoSubgroup(
            card.subgroups,
            groupTitle: groupTitle,
            captureDate: captureDate,
            matchSameDate: matchSameDate,
          ),
        ),
  ];
}

List<CustomLifeSubgroup> _addPhotoSubgroup(
  List<CustomLifeSubgroup> subgroups, {
  required String groupTitle,
  required DateTime captureDate,
  required bool matchSameDate,
}) {
  final index = subgroups.indexWhere(
    (subgroup) =>
        subgroup.title == groupTitle && subgroup.rule == CustomCardRule.date,
  );
  final entry = CustomDateEntry(
    date: dateOnly(captureDate),
    annual: false,
  );
  if (index < 0) {
    return [
      ...subgroups,
      CustomLifeSubgroup(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: groupTitle,
        rule: CustomCardRule.date,
        dateEntries: [entry],
        matchByDate: matchSameDate,
        groupByYear: false,
      ),
    ];
  }

  final subgroup = subgroups[index];
  final entries = [...subgroup.dateEntries];
  if (matchSameDate &&
      !entries.any(
        (item) => !item.annual && dateKey(item.date) == dateKey(captureDate),
      )) {
    entries.add(entry);
  }
  final updated = [...subgroups];
  updated[index] = subgroup.copyWith(
    dateEntries: entries,
    matchByDate: subgroup.matchByDate || matchSameDate,
  );
  return updated;
}

String? classifyPhotoForTopic(DateTime captureDate, PhotoTopic topic) {
  final categories = classifyPhotoCategories(captureDate, topic);
  return categories.isEmpty ? null : categories.join(' · ');
}

bool photoGroupUsesYearSubgroups(
  CustomLifeCard? card,
  String groupTitle,
) {
  for (final subgroup in card?.subgroups ?? const []) {
    if (subgroup.title == groupTitle && subgroup.rule == CustomCardRule.date) {
      return subgroup.groupByYear;
    }
  }
  return true;
}

List<String> classifyPhotoCategories(
  DateTime captureDate,
  PhotoTopic topic,
) {
  return _PhotoTopicMatcher(topic).categoriesFor(captureDate);
}

class _PhotoTopicMatcher {
  _PhotoTopicMatcher(PhotoTopic topic) {
    final card = topic.customCard;
    if (card == null) return;
    for (final subgroup in card.enabledSubgroups) {
      if (subgroup.rule == CustomCardRule.date) {
        if (!subgroup.matchByDate) continue;
        for (final entry in subgroup.dateEntries) {
          final lunar = entry.calendar == CalendarType.lunar
              ? Lunar.fromDate(entry.date)
              : null;
          _dateRules.add(
            (
              title: subgroup.title,
              calendar: entry.calendar,
              annual: entry.annual,
              date: dateOnly(entry.date),
              month: lunar?.getMonth() ?? entry.date.month,
              day: lunar?.getDay() ?? entry.date.day,
            ),
          );
        }
      } else {
        final festival = subgroup.festival;
        if (festival != null && festival.isNotEmpty) {
          _festivalRules.add((title: subgroup.title, festival: festival));
        }
      }
    }
  }

  final _dateRules = <({
    String title,
    CalendarType calendar,
    bool annual,
    DateTime date,
    int month,
    int day,
  })>[];
  final _festivalRules = <({String title, String festival})>[];
  final _categoriesByDate = <String, List<String>>{};

  List<String> categoriesFor(DateTime captureDate) {
    final key = dateKey(captureDate);
    final cached = _categoriesByDate[key];
    if (cached != null) return cached;

    final capture = dateOnly(captureDate);
    final needsLunar = _dateRules.any(
          (rule) => rule.calendar == CalendarType.lunar,
        ) ||
        _festivalRules.isNotEmpty;
    final captureLunar = needsLunar ? Lunar.fromDate(capture) : null;
    final festivals =
        needsLunar ? captureLunar!.getFestivals() : const <String>[];
    final matches = <String>[];
    for (final rule in _dateRules) {
      final matched = !rule.annual
          ? capture == rule.date
          : rule.calendar == CalendarType.lunar
              ? captureLunar!.getMonth() == rule.month &&
                  captureLunar.getDay() == rule.day
              : capture.month == rule.month && capture.day == rule.day;
      if (matched) matches.add(rule.title);
    }
    for (final rule in _festivalRules) {
      if (festivals.any((festival) => festival.contains(rule.festival))) {
        matches.add(rule.title);
      }
    }
    final categories = matches.toSet().toList();
    _categoriesByDate[key] = categories;
    return categories;
  }
}
