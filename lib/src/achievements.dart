part of '../main.dart';

const memoryActivityStorageKey = 'memory_activity_v1';

enum MemoryActivityType { review, browse, organize, event }

class MemoryActivityState {
  const MemoryActivityState({
    this.actionsByDate = const {},
    this.maxReviewYears = 0,
  });

  final Map<String, Set<String>> actionsByDate;
  final int maxReviewYears;

  int get totalDays =>
      actionsByDate.values.where((actions) => actions.isNotEmpty).length;

  Set<String> get allActions => {
        for (final actions in actionsByDate.values) ...actions,
      };

  bool completedOn(DateTime date) =>
      actionsByDate[dateKey(date)]?.isNotEmpty == true;

  int currentStreak(DateTime today) {
    var cursor = dateOnly(today);
    if (!completedOn(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (completedOn(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  int get longestStreak {
    final dates = actionsByDate.entries
        .where((entry) => entry.value.isNotEmpty)
        .map((entry) => DateTime.tryParse(entry.key))
        .whereType<DateTime>()
        .map(dateOnly)
        .toList()
      ..sort();
    var longest = 0;
    var current = 0;
    DateTime? previous;
    for (final date in dates) {
      if (previous != null && date.difference(previous).inDays == 1) {
        current++;
      } else {
        current = 1;
      }
      longest = math.max(longest, current);
      previous = date;
    }
    return longest;
  }

  Map<String, dynamic> toJson() => {
        'actions_by_date': {
          for (final entry in actionsByDate.entries)
            entry.key: entry.value.toList(),
        },
        'max_review_years': maxReviewYears,
      };

  static MemoryActivityState fromJson(Object? value) {
    if (value is! Map) return const MemoryActivityState();
    final rawActions = value['actions_by_date'];
    final actions = <String, Set<String>>{};
    if (rawActions is Map) {
      for (final entry in rawActions.entries) {
        if (entry.value is List) {
          actions[entry.key.toString()] =
              (entry.value as List).map((item) => item.toString()).toSet();
        }
      }
    }
    return MemoryActivityState(
      actionsByDate: actions,
      maxReviewYears:
          int.tryParse(value['max_review_years']?.toString() ?? '') ?? 0,
    );
  }
}

Future<MemoryActivityState> loadMemoryActivity() async {
  final preferences = await SharedPreferences.getInstance();
  final stored = preferences.getString(memoryActivityStorageKey);
  if (stored == null || stored.isEmpty) return const MemoryActivityState();
  try {
    return MemoryActivityState.fromJson(jsonDecode(stored));
  } catch (_) {
    return const MemoryActivityState();
  }
}

Future<MemoryActivityState> recordMemoryActivity(
  MemoryActivityType type, {
  DateTime? occurredAt,
  int reviewYears = 0,
}) async {
  final state = await loadMemoryActivity();
  final actions = {
    for (final entry in state.actionsByDate.entries)
      entry.key: Set<String>.from(entry.value),
  };
  actions
      .putIfAbsent(dateKey(occurredAt ?? DateTime.now()), () => <String>{})
      .add(type.name);
  final updated = MemoryActivityState(
    actionsByDate: actions,
    maxReviewYears: math.max(state.maxReviewYears, reviewYears),
  );
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(
    memoryActivityStorageKey,
    jsonEncode(updated.toJson()),
  );
  return updated;
}

class MemoryAchievement {
  const MemoryAchievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.unlocked,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final bool unlocked;
}

List<MemoryAchievement> memoryAchievements(MemoryActivityState state) {
  final actions = state.allActions;
  final longest = state.longestStreak;
  return [
    MemoryAchievement(
      id: 'first_trace',
      title: '第一次留痕',
      description: '完成第一次真实记录',
      icon: Icons.auto_awesome_outlined,
      unlocked: state.totalDays >= 1,
    ),
    MemoryAchievement(
      id: 'first_review',
      title: '时光回响',
      description: '第一次回顾往年的今天',
      icon: Icons.history_outlined,
      unlocked: actions.contains(MemoryActivityType.review.name),
    ),
    MemoryAchievement(
      id: 'first_browse',
      title: '重温一刻',
      description: '第一次浏览照片回忆',
      icon: Icons.photo_album_outlined,
      unlocked: actions.contains(MemoryActivityType.browse.name),
    ),
    MemoryAchievement(
      id: 'first_organize',
      title: '记忆整理师',
      description: '第一次整理真实照片',
      icon: Icons.auto_fix_high_outlined,
      unlocked: actions.contains(MemoryActivityType.organize.name),
    ),
    MemoryAchievement(
      id: 'first_event',
      title: '生活收藏家',
      description: '第一次添加真实事件',
      icon: Icons.bookmark_add_outlined,
      unlocked: actions.contains(MemoryActivityType.event.name),
    ),
    MemoryAchievement(
      id: 'streak_3',
      title: '三日微光',
      description: '连续留痕 3 天',
      icon: Icons.local_fire_department_outlined,
      unlocked: longest >= 3,
    ),
    MemoryAchievement(
      id: 'streak_7',
      title: '一周相伴',
      description: '连续留痕 7 天',
      icon: Icons.whatshot_outlined,
      unlocked: longest >= 7,
    ),
    MemoryAchievement(
      id: 'trace_30',
      title: '三十段日常',
      description: '累计留痕 30 天',
      icon: Icons.calendar_month_outlined,
      unlocked: state.totalDays >= 30,
    ),
    MemoryAchievement(
      id: 'echo_3_years',
      title: '三年前的今天',
      description: '回顾到至少 3 年前',
      icon: Icons.timelapse_outlined,
      unlocked: state.maxReviewYears >= 3,
    ),
    MemoryAchievement(
      id: 'echo_5_years',
      title: '五年回声',
      description: '回顾到至少 5 年前',
      icon: Icons.hourglass_bottom_outlined,
      unlocked: state.maxReviewYears >= 5,
    ),
  ];
}
