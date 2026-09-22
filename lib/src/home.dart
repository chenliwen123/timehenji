part of '../main.dart';

class LifeHomePage extends StatefulWidget {
  const LifeHomePage({super.key, this.client});

  final SupabaseClient? client;

  @override
  State<LifeHomePage> createState() => _LifeHomePageState();
}

class _LifeHomePageState extends State<LifeHomePage>
    with LifeConfigListener<LifeHomePage> {
  DateTime today = dateOnly(DateTime.now());
  bool celebrating = false;
  bool loadingDates = true;
  bool loadingUnorganizedCount = true;
  int unorganizedCount = 0;
  MemoryActivityState activityState = const MemoryActivityState();
  Milestone? celebrationMilestone;
  String celebrationTitle = '牛逼，又活一天！';
  String celebrationMessage = '今天也平安抵达，继续过好这一天。';

  @override
  void initState() {
    super.initState();
    unawaited(loadCachedMemoryPhotos());
    _loadDates();
  }

  Future<void> _loadDates() async {
    LifeDatesConfig localConfig;
    try {
      localConfig = await loadLocalLifeDates().timeout(const Duration(seconds: 2));
    } catch (_) {
      localConfig = LifeDatesConfig.defaults;
    }

    // 先用本机数据渲染，避免网络慢时首页一直转圈；云端配置随后在后台加载。
    await lifeConfig.replace(localConfig);
    activityState = await loadMemoryActivity();

    final client = widget.client;
    if (client != null) {
      unawaited(_loadRemoteDates(client));
    }

    if (!mounted) return;
    setState(() => loadingDates = false);
    unawaited(_refreshUnorganizedCount());
    final dailyMemoryHandled = await _showDailyMemoryReview();
    if (!dailyMemoryHandled) await _showDailyCelebration();
  }

  Future<void> _loadRemoteDates(SupabaseClient client) async {
    try {
      final config =
          await loadLifeDates(client).timeout(const Duration(seconds: 20));
      // 云端读到的是最新副本，回写本机，下次冷启动首屏就是对的。
      await saveLocalLifeDates(config);
      await saveLocalCustomCards(config.customCards);
      await lifeConfig.replace(config);
      if (!mounted) return;
      setState(() {});
    } catch (_) {
      // 云端暂不可用时保留本地数据展示。
    }
  }

  Future<void> _refreshUnorganizedCount() async {
    final cards = lifeConfig.lifeCards;
    final source = await loadCachedMemoryPhotos();
    final photos = await photosWithoutConfiguredGroupAsync(source, cards);
    if (!mounted) return;
    setState(() {
      unorganizedCount = photos.length;
      loadingUnorganizedCount = false;
    });
  }

  Future<void> openUnorganizedPhotos() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => UnorganizedPhotosPage(client: widget.client),
      ),
    );
    if (!mounted) return;
    await _reloadMemoryActivity();
    await _refreshUnorganizedCount();
  }

  Future<void> _reloadMemoryActivity() async {
    final updated = await loadMemoryActivity();
    if (mounted) setState(() => activityState = updated);
  }

  Future<void> _recordActivity(
    MemoryActivityType type, {
    int reviewYears = 0,
  }) async {
    final wasCompleted = activityState.completedOn(DateTime.now());
    final updated = await recordMemoryActivity(
      type,
      reviewYears: reviewYears,
    );
    if (!mounted) return;
    setState(() => activityState = updated);
    if (!wasCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('今日留痕完成 · 已连续 ${updated.currentStreak(DateTime.now())} 天'),
        ),
      );
    }
  }

  Future<void> _showDailyCelebration() async {
    final preferences = await SharedPreferences.getInstance();
    final todayKey = dateKey(DateTime.now());
    final hasCelebratedToday =
        preferences.getString('last_celebration_date') == todayKey;
    if (hasCelebratedToday || !mounted) return;

    final config = lifeConfig.config;
    final todayHundredMilestones = config.milestones.where(
      (milestone) => daysSince(milestone.date) == milestone.days,
    );
    final todayMilestone =
        todayHundredMilestones.isEmpty ? null : todayHundredMilestones.first;
    final todayAnnualMilestone = config.annualMilestones.where(
      (milestone) => isAnnualMilestoneToday(milestone.date),
    );
    if (todayMilestone == null && todayAnnualMilestone.isEmpty) return;
    await preferences.setString('last_celebration_date', todayKey);
    if (!mounted) return;
    setState(() {
      celebrationMilestone = todayMilestone;
      if (todayAnnualMilestone.isNotEmpty) {
        celebrationTitle = '牛逼，又过了一年！';
        celebrationMessage = todayMilestone == null
            ? '今天是：${todayAnnualMilestone.first.title}'
            : '今天还达成了：${todayAnnualMilestone.first.title}和${todayMilestone.title}';
      } else if (todayMilestone != null) {
        celebrationTitle = todayMilestone.title;
        celebrationMessage = '今天达成了一个真实的时间里程碑。';
      }
      celebrating = true;
    });
  }

  Future<bool> _showDailyMemoryReview() async {
    final preferences = await SharedPreferences.getInstance();
    final enabled = preferences.getBool(dailyMemoryReviewEnabledKey) ?? true;
    if (!enabled) return false;

    final target = dateOnly(DateTime.now());
    final userId = widget.client?.auth.currentUser?.id ?? 'local';
    final shownKey =
        '$dailyMemoryReviewLastShownPrefix$userId-${dateKey(target)}';
    if (preferences.getBool(shownKey) == true) return true;

    final source = await loadCachedMemoryPhotos();
    final memories = findDailyMemoryGroups(
      source,
      lifeConfig.lifeCards,
      today: target,
    );
    if (memories.isEmpty) return false;

    await preferences.setBool(shownKey, true);
    await preferences.setString('last_celebration_date', dateKey(target));
    if (!mounted) return true;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => DailyMemoryReviewDialog(
        memories: memories,
        today: target,
      ),
    );
    await _recordActivity(
      MemoryActivityType.review,
      reviewYears:
          memories.map((memory) => target.year - memory.year).fold(0, math.max),
    );
    return true;
  }

  void refreshDate() {
    setState(() => today = dateOnly(DateTime.now()));
  }

  Future<void> openSettings() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LifeDatesEditorPage(client: widget.client),
      ),
    );
    if (!mounted) return;
    setState(() => today = dateOnly(DateTime.now()));
    await _reloadMemoryActivity();
    await _refreshUnorganizedCount();
  }

  void celebrate(Milestone milestone) {
    setState(() {
      celebrationMilestone = milestone;
      celebrationTitle = milestone.title;
      celebrationMessage = '这个成就值得再次庆祝一下。';
      celebrating = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = lifeConfig.config;
    final current = lifeConfig.lifeCards
        .where((card) => card.enabled)
        .map((card) => lifeCounterForCard(card))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('时间痕迹', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            onPressed: openSettings,
            icon: const Icon(Icons.tune),
            tooltip: '纪念日期',
          ),
          IconButton(
            onPressed: refreshDate,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新天数',
          ),
          IconButton(
            onPressed: widget.client == null
                ? null
                : () => widget.client!.auth.signOut(),
            icon: const Icon(Icons.logout),
            tooltip: '退出登录',
          ),
        ],
      ),
      body: Stack(
        children: [
          if (loadingDates)
            const Center(child: CircularProgressIndicator())
          else
            RefreshIndicator(
              onRefresh: () async {
                refreshDate();
                final client = widget.client;
                if (client != null) await _loadRemoteDates(client);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
                children: [
                  _header(context),
                  const SizedBox(height: 12),
                  _todayTraceCard(),
                  const SizedBox(height: 12),
                  _unorganizedPhotosCard(),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: current.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: .92,
                    ),
                    itemBuilder: (context, index) =>
                        _counterCard(current[index]),
                  ),
                  const SizedBox(height: 28),
                  _achievementSection(),
                  const SizedBox(height: 28),
                  ..._milestoneSection(config),
                ],
              ),
            ),
          if (celebrating)
            CelebrationOverlay(
              title: celebrationTitle,
              message: celebrationMessage,
              onDismiss: () => setState(() {
                celebrating = false;
                celebrationMilestone = null;
                celebrationTitle = '牛逼，又活一天！';
                celebrationMessage = '今天也平安抵达，继续过好这一天。';
              }),
            ),
        ],
      ),
    );
  }

  LifeCounter lifeCounterForCard(CustomLifeCard card) {
    final builtIn = switch (card.id) {
      'birth' => (Icons.auto_awesome, const Color(0xff6750a4)),
      'marriage' => (Icons.favorite, const Color(0xffc43d68)),
      'graduation' => (Icons.school, const Color(0xff006a6a)),
      'work' => (Icons.work, const Color(0xff9a4520)),
      _ => (
          card.subgroups.any((subgroup) => subgroup.rule == CustomCardRule.date)
              ? Icons.event_outlined
              : Icons.celebration_outlined,
          const Color(0xff536dfe),
        ),
    };
    return LifeCounter(
      title: card.title,
      subtitle: card.subtitle.isEmpty
          ? '${card.subgroups.length} 个二级分组'
          : card.subtitle,
      date: card.primaryDate ?? dateOnly(DateTime.now()),
      icon: builtIn.$1,
      color: builtIn.$2,
      topic: photoTopicForLifeCard(card),
    );
  }

  /// 里程碑区。一个日期都没填时用引导卡替代，避免出现 0/0 这种空数据。
  List<Widget> _milestoneSection(LifeDatesConfig config) {
    const title = Text(
      '时间里程碑',
      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
    );
    final latest = config.latestMilestones;
    if (latest.isEmpty) {
      return [
        title,
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('填写纪念日期后解锁'),
            subtitle: const Text('每满 100 天、每个周年都会在这里被记下来'),
            trailing: const Icon(Icons.chevron_right),
            onTap: openSettings,
          ),
        ),
      ];
    }
    final reached = latest
        .where((item) => daysSince(item.date) >= item.days)
        .length;
    return [
      Row(
        children: [
          const Expanded(child: title),
          Text(
            '$reached/${latest.length}',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
      const SizedBox(height: 12),
      ...latest.map(_milestoneTile),
    ];
  }

  Widget _header(BuildContext context) {
    final birthDate = lifeConfig.config.birthDate;
    if (birthDate == null) return _setupDatesCard(context);
    final livedDays = daysSince(birthDate);
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatNumber(livedDays),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontSize: 42,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '这是你来到这个世界的第 $livedDays 天',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '每一天都值得被记住。',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onPrimaryContainer
                    .withValues(alpha: .75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 一个日期都没填时的引导：旧版本这里写死了开发者的真实日期，
  /// 现在改成让每个用户填自己的。
  Widget _setupDatesCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '还没有纪念日期',
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '填上生日、结婚纪念日这类日子，这里就会显示已经走过的天数，'
              '相册里的照片也能按这些日子分组。',
              style: TextStyle(
                color: colorScheme.onPrimaryContainer.withValues(alpha: .8),
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: openSettings,
              icon: const Icon(Icons.event_available),
              label: const Text('填写纪念日期'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _unorganizedPhotosCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.secondaryContainer.withValues(alpha: .5),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: colorScheme.secondary.withValues(alpha: .14),
          foregroundColor: colorScheme.secondary,
          child: const Icon(Icons.photo_library_outlined),
        ),
        title: const Text(
          '待整理照片',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          loadingUnorganizedCount
              ? '正在统计未分组照片…'
              : unorganizedCount == 0
                  ? '暂无照片，点击可同步手机相册'
                  : '$unorganizedCount 张照片还没有分组',
        ),
        trailing: loadingUnorganizedCount
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right),
        onTap: openUnorganizedPhotos,
      ),
    );
  }

  Widget _todayTraceCard() {
    final theme = Theme.of(context);
    final completed = activityState.completedOn(today);
    final streak = activityState.currentStreak(today);
    final recentDays = [
      for (var offset = 6; offset >= 0; offset--)
        today.subtract(Duration(days: offset)),
    ];
    return Card(
      elevation: 0,
      color: completed
          ? const Color(0xffffead0)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: .55),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: completed
                      ? const Color(0xffff9f1c).withValues(alpha: .18)
                      : theme.colorScheme.primaryContainer,
                  foregroundColor: completed
                      ? const Color(0xffa64b00)
                      : theme.colorScheme.primary,
                  child: Icon(
                    completed
                        ? Icons.local_fire_department
                        : Icons.local_fire_department_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        completed ? '今日已留痕' : '今天还没有留痕',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        streak == 0 ? '完成一次真实回顾或记录即可点亮' : '连续留痕 $streak 天',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$streak',
                  style: const TextStyle(
                    color: Color(0xffd66500),
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 3),
                const Text('天'),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final date in recentDays)
                  Column(
                    children: [
                      Text(
                        _weekdayLabel(date),
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 5),
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: activityState.completedOn(date)
                            ? const Color(0xffff9f1c)
                            : theme.colorScheme.surface,
                        child: activityState.completedOn(date)
                            ? const Icon(Icons.check,
                                size: 15, color: Colors.white)
                            : Text(
                                '${date.day}',
                                style: const TextStyle(fontSize: 10),
                              ),
                      ),
                    ],
                  ),
              ],
            ),
            if (!completed) ...[
              const SizedBox(height: 14),
              Text(
                '查看往年的今天、浏览照片分组、整理照片或添加真实事件，任意一项都算完成。',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _weekdayLabel(DateTime date) => switch (date.weekday) {
        DateTime.monday => '一',
        DateTime.tuesday => '二',
        DateTime.wednesday => '三',
        DateTime.thursday => '四',
        DateTime.friday => '五',
        DateTime.saturday => '六',
        _ => '日',
      };

  Widget _achievementSection() {
    final theme = Theme.of(context);
    final achievements = memoryAchievements(activityState);
    final unlocked = achievements.where((item) => item.unlocked).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '回忆成就',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              '$unlocked/${achievements.length}',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '由真实发生的回顾和记录自然解锁',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: achievements.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.55,
          ),
          itemBuilder: (context, index) {
            final achievement = achievements[index];
            return Card(
              elevation: 0,
              color: achievement.unlocked
                  ? const Color(0xfffff0c7)
                  : theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: .38),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      achievement.unlocked
                          ? achievement.icon
                          : Icons.lock_outline,
                      color: achievement.unlocked
                          ? const Color(0xffa55b00)
                          : theme.colorScheme.outline,
                    ),
                    const Spacer(),
                    Text(
                      achievement.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      achievement.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _counterCard(LifeCounter counter) {
    final days = daysSince(counter.date);
    final card = Card(
      elevation: 0,
      color: counter.color.withValues(alpha: .10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: counter.color.withValues(alpha: .18),
              foregroundColor: counter.color,
              child: Icon(counter.icon),
            ),
            const Spacer(),
            Text(counter.title,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 3),
            Text(counter.subtitle,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
            const SizedBox(height: 8),
            Text(formatNumber(days),
                style: TextStyle(
                    color: counter.color,
                    fontSize: 28,
                    fontWeight: FontWeight.w800)),
            Text('天',
                style: TextStyle(
                    color: counter.color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MarriageMemoriesPage(
              topic: counter.topic ??
                  photoTopicForTitle(lifeConfig.lifeCards, counter.title),
            ),
          ),
        );
        await _reloadMemoryActivity();
      },
      child: card,
    );
  }

  Widget _milestoneTile(Milestone milestone) {
    final currentDays = daysSince(milestone.date);
    final achieved = currentDays >= milestone.days;
    final exact = currentDays == milestone.days;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              achieved ? const Color(0xffffd66b) : Colors.grey.shade200,
          child: Icon(
            achieved ? Icons.emoji_events : Icons.lock_outline,
            color: achieved ? const Color(0xff7a4d00) : Colors.grey.shade600,
          ),
        ),
        title: Text(milestone.title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle:
            Text('${milestone.category} · ${formatNumber(milestone.days)} 天'),
        trailing: exact
            ? const Text('今天达成 🎉',
                style: TextStyle(
                    color: Color(0xffc43d68), fontWeight: FontWeight.bold))
            : Icon(
                achieved ? Icons.check_circle : Icons.radio_button_unchecked,
                color: achieved ? Colors.green : Colors.grey.shade400,
              ),
        onTap: () {
          if (achieved) {
            celebrate(milestone);
          } else {
            final remaining = milestone.days - currentDays;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('距离「${milestone.title}」还差 $remaining 天')),
            );
          }
        },
      ),
    );
  }
}
