part of '../main.dart';

class MarriageMemoriesPage extends StatefulWidget {
  const MarriageMemoriesPage({
    super.key,
    required this.topic,
  });

  final PhotoTopic topic;

  @override
  State<MarriageMemoriesPage> createState() => _MarriageMemoriesPageState();
}

class _MarriageMemoriesPageState extends State<MarriageMemoriesPage>
    with LifeConfigListener<MarriageMemoriesPage> {
  List<MemoryPhoto> photos = [];
  List<MemoryPhoto> allPhotos = [];
  final expandedGroups = <String, bool>{};
  bool loading = true;
  bool classifying = false;
  bool syncing = false;
  bool browseActivityRecorded = false;

  @override
  void initState() {
    super.initState();
    initializePhotos();
  }

  Future<void> initializePhotos() async {
    final cached = await loadCachedMemoryPhotos();
    if (mounted && cached.isNotEmpty) {
      setState(() {
        allPhotos = cached;
        loading = false;
        classifying = true;
      });
      await Future<void>.delayed(Duration.zero);
      final categorized = await photosForTopicAsync(cached, widget.topic);
      if (!mounted) return;
      setState(() {
        photos = categorized;
        classifying = false;
      });
      await _recordBrowseActivity(categorized);
    }
    if (cached.isEmpty) {
      await syncPhotos();
    }
  }

  Future<void> syncPhotos() async {
    if (syncing) return;
    setState(() => syncing = true);
    final imported = await syncAllMemoryPhotos(lifeConfig.config);
    if (!mounted) return;
    if (imported == null) {
      setState(() {
        loading = false;
        classifying = false;
        syncing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请允许 App 访问照片，才能显示手机相册中的全部照片。')),
      );
      return;
    }
    final categorized = await photosForTopicAsync(imported, widget.topic);
    if (!mounted) return;
    setState(() {
      allPhotos = imported;
      photos = categorized;
      loading = false;
      classifying = false;
      syncing = false;
    });
    await _recordBrowseActivity(categorized);
  }

  Future<void> _recordBrowseActivity(List<MemoryPhoto> categorized) async {
    if (browseActivityRecorded || categorized.isEmpty) return;
    browseActivityRecorded = true;
    await recordMemoryActivity(MemoryActivityType.browse);
  }

  Future<void> removePhoto(int index) async {
    final photo = photos[index];
    allPhotos.removeWhere(
      (item) => item.assetId == photo.assetId && item.path == photo.path,
    );
    cacheMemoryPhotos(allPhotos);
    photos = await photosForTopicAsync(allPhotos, widget.topic);
    await saveMemoryPhotos(allPhotos);
    if (mounted) setState(() {});
  }

  Future<void> addPhotosToGroup(
    String eventTitle,
    int year,
    List<int> currentIndexes,
  ) async {
    final center = targetDateForGroup(
      eventTitle,
      year,
      fallback: photos[currentIndexes.first].captureDate,
    );
    final start = dateOnly(center.subtract(const Duration(days: 7)));
    final end = dateOnly(center.add(const Duration(days: 7)));
    final candidates = allPhotos.where((photo) {
      final date = dateOnly(photo.captureDate);
      return !date.isBefore(start) && !date.isAfter(end);
    }).toList()
      ..sort((left, right) => left.captureDate.compareTo(right.captureDate));

    final selected = await showModalBottomSheet<List<MemoryPhoto>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PhotoAddSheet(
        title: '$eventTitle · $year年',
        centerDate: center,
        candidates: candidates,
      ),
    );
    if (selected == null || selected.isEmpty) return;

    final selectedKeys =
        selected.map((photo) => photo.identityKey).whereType<String>().toSet();
    final subgroup = widget.topic.customCard?.subgroups
        .where((item) => item.title == eventTitle)
        .firstOrNull;
    allPhotos = [
      for (final photo in allPhotos)
        selectedKeys.contains(photo.identityKey)
            ? photo.copyWith(
                manualTopic: widget.topic.title,
                manualTopicId: widget.topic.customCard?.id,
                manualCategory: eventTitle,
                manualCategoryId: subgroup?.id,
              )
            : photo,
    ];
    await saveMemoryPhotos(allPhotos);
    if (!mounted) return;
    setState(() {
      photos = photosForTopic(allPhotos, widget.topic);
    });
  }

  DateTime targetDateForGroup(
    String eventTitle,
    int year, {
    required DateTime fallback,
  }) {
    CustomLifeSubgroup? subgroup;
    for (final item in widget.topic.customCard?.subgroups ?? const []) {
      if (item.title == eventTitle && item.rule == CustomCardRule.date) {
        subgroup = item;
        break;
      }
    }
    if (subgroup == null || subgroup.dateEntries.isEmpty) return fallback;

    final targetDates = <DateTime>[];
    for (final entry in subgroup.dateEntries) {
      try {
        if (entry.calendar == CalendarType.lunar) {
          final lunar = Lunar.fromDate(entry.date);
          final solar = Lunar.fromYmd(
            year,
            lunar.getMonth(),
            lunar.getDay(),
          ).getSolar();
          targetDates.add(
            DateTime(solar.getYear(), solar.getMonth(), solar.getDay()),
          );
        } else {
          targetDates.add(DateTime(year, entry.date.month, entry.date.day));
        }
      } catch (_) {
        continue;
      }
    }
    if (targetDates.isEmpty) return fallback;
    targetDates.sort(
      (left, right) => left
          .difference(fallback)
          .inDays
          .abs()
          .compareTo(right.difference(fallback).inDays.abs()),
    );
    return targetDates.first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: syncing ? null : syncPhotos,
            icon: syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            tooltip: '同步手机全部照片',
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : classifying
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('正在整理照片…'),
                    ],
                  ),
                )
              : photos.isEmpty
                  ? _emptyState()
                  : CustomScrollView(
                      slivers: [
                        ..._groupedPhotoSlivers(),
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 100),
                        ),
                      ],
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: syncing ? null : syncPhotos,
        icon: const Icon(Icons.sync),
        label: const Text('同步全部照片'),
      ),
    );
  }

  List<Widget> _groupedPhotoSlivers() {
    final groups = _photoGroups();
    return [
      for (final group in groups) ..._photoGroupSlivers(group.key, group.value),
    ];
  }

  List<MapEntry<String, List<int>>> _photoGroups() {
    final groups = <String, List<int>>{};
    for (var index = 0; index < photos.length; index++) {
      groups.putIfAbsent(photos[index].category, () => []).add(index);
    }
    final configuredOrder = {
      for (var index = 0;
          index < (widget.topic.customCard?.subgroups.length ?? 0);
          index++)
        widget.topic.customCard!.subgroups[index].title: index,
    };
    return groups.entries.toList()
      ..sort((left, right) {
        final leftOrder = configuredOrder[left.key];
        final rightOrder = configuredOrder[right.key];
        if (leftOrder != null || rightOrder != null) {
          if (leftOrder == null) return 1;
          if (rightOrder == null) return -1;
          return leftOrder.compareTo(rightOrder);
        }
        if (left.key == '其他照片') return 1;
        if (right.key == '其他照片') return -1;
        return 0;
      });
  }

  List<Widget> _photoGroupSlivers(String title, List<int> indexes) {
    final expanded = expandedGroups['subgroup:$title'] ?? false;
    final usesYearSubgroups = photoGroupUsesYearSubgroups(
      widget.topic.customCard,
      title,
    );
    final years = <int, List<int>>{};
    for (final index in indexes) {
      years.putIfAbsent(photos[index].captureDate.year, () => []).add(index);
    }
    final yearEntries = years.entries.toList()
      ..sort((left, right) => right.key.compareTo(left.key));
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        sliver: SliverToBoxAdapter(
          child: _photoGroupHeaderCard(title, indexes, expanded),
        ),
      ),
      if (expanded && usesYearSubgroups)
        for (final yearEntry in yearEntries)
          ..._photoYearSlivers(title, yearEntry.key, yearEntry.value),
      if (expanded && !usesYearSubgroups) ..._photoDateSlivers(title, indexes),
    ];
  }

  Widget _photoGroupHeaderCard(String title, List<int> indexes, bool expanded) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        visualDensity: const VisualDensity(vertical: -1),
        onTap: () => setState(
          () => expandedGroups['subgroup:$title'] = !expanded,
        ),
        leading: const Icon(Icons.account_tree_outlined),
        title: Row(
          children: [
            Flexible(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${indexes.length} 张',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        trailing: Icon(
          expanded ? Icons.expand_less : Icons.expand_more,
        ),
      ),
    );
  }

  Widget _photoGridSliver({
    required List<int> indexes,
    required int columns,
    required bool canAddPhoto,
    required String groupTitle,
    required VoidCallback onAddTap,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == indexes.length) {
              return _addPhotoCard(onTap: onAddTap);
            }
            return _photoCard(
              indexes[index],
              groupTitle: groupTitle,
              groupPhotoIndex: index,
            );
          },
          childCount: indexes.length + (canAddPhoto ? 1 : 0),
        ),
      ),
    );
  }

  List<Widget> _photoDateSlivers(String eventTitle, List<int> indexes) {
    final dates = indexes
        .map((index) => dateOnly(photos[index].captureDate))
        .toSet()
        .toList()
      ..sort();
    final dateText = dates.length == 1
        ? formatDate(dates.first)
        : '${formatDate(dates.first)} 至 ${formatDate(dates.last)}';
    final canAddPhoto = indexes.length <= 2;
    final columns = indexes.length == 1 ? 2 : 4;
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(60, 0, 20, 6),
        sliver: SliverToBoxAdapter(
          child: Text(
            dateText,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
        ),
      ),
      _photoGridSliver(
        indexes: indexes,
        columns: columns,
        canAddPhoto: canAddPhoto,
        groupTitle: '${widget.topic.title} · $eventTitle',
        onAddTap: () => addPhotosToGroup(eventTitle, dates.first.year, indexes),
      ),
    ];
  }

  List<Widget> _photoYearSlivers(
    String eventTitle,
    int year,
    List<int> indexes,
  ) {
    final groupKey = 'year:${widget.topic.title}:$eventTitle:$year';
    final expanded = expandedGroups[groupKey] ?? true;
    final canAddPhoto = indexes.length <= 2;
    final columns = indexes.length == 1 ? 2 : 4;
    return [
      SliverToBoxAdapter(
        child: ListTile(
          contentPadding: const EdgeInsets.only(left: 60, right: 20),
          visualDensity: const VisualDensity(vertical: -3),
          onTap: () => setState(
            () => expandedGroups[groupKey] = !expanded,
          ),
          title: Row(
            children: [
              Text('$year年'),
              const SizedBox(width: 8),
              Text(
                '${indexes.length} 张',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          trailing: Icon(
            expanded ? Icons.expand_less : Icons.expand_more,
            size: 20,
          ),
        ),
      ),
      if (expanded)
        _photoGridSliver(
          indexes: indexes,
          columns: columns,
          canAddPhoto: canAddPhoto,
          groupTitle: '${widget.topic.title} · $eventTitle · $year年',
          onAddTap: () => addPhotosToGroup(eventTitle, year, indexes),
        ),
    ];
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined,
                size: 72, color: Colors.pink.shade300),
            const SizedBox(height: 16),
            const Text('还没有纪念照片',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('${widget.topic.title}暂时没有符合条件的照片。'),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: syncing ? null : syncPhotos,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('重新同步手机照片'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoCard(
    int index, {
    required String groupTitle,
    required int groupPhotoIndex,
  }) {
    final photo = photos[index];
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: () => _showPhotoPreview(
          groupTitle: groupTitle,
          groupPhotoIndex: groupPhotoIndex,
        ),
        onLongPress: () => removePhoto(index),
        child: _photoImage(
          photo,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    );
  }

  Widget _addPhotoCard({required VoidCallback onTap}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: .55),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: .35),
              width: 1.2,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 28,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  '添加附近照片',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '前后 7 天',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer.withValues(alpha: .7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPhotoPreview({
    required String groupTitle,
    required int groupPhotoIndex,
  }) {
    final groups = _photoPreviewGroups();
    final previewItems = <PhotoPreviewItem>[];
    var initialPage = 0;
    for (final group in groups) {
      for (var index = 0; index < group.value.length; index++) {
        if (group.key == groupTitle && index == groupPhotoIndex) {
          initialPage = previewItems.length;
        }
        previewItems.add(
          PhotoPreviewItem(
            groupTitle: group.key,
            photo: photos[group.value[index]],
          ),
        );
      }
    }
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .92),
      builder: (_) => PhotoPreviewDialog(
        items: previewItems,
        initialPage: initialPage,
      ),
    );
  }

  Widget _photoImage(
    MemoryPhoto photo, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    bool original = false,
  }) {
    final asset = photo.asset;
    if (asset != null) {
      return AssetEntityImage(
        asset,
        isOriginal: original,
        thumbnailSize: original ? null : const ThumbnailSize.square(320),
        thumbnailFormat: ThumbnailFormat.jpeg,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined, size: 42),
        ),
      );
    }
    if (photo.assetId != null) {
      return FutureBuilder<AssetEntity?>(
        future: resolveMemoryPhotoAsset(photo),
        builder: (context, snapshot) {
          final entity = snapshot.data;
          if (entity == null) {
            return const Center(
                child: CircularProgressIndicator(strokeWidth: 2));
          }
          return AssetEntityImage(
            entity,
            isOriginal: original,
            thumbnailSize: original ? null : const ThumbnailSize.square(320),
            thumbnailFormat: ThumbnailFormat.jpeg,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_outlined, size: 42),
            ),
          );
        },
      );
    }
    return Image.file(
      File(photo.path!),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_outlined, size: 42),
      ),
    );
  }

  List<MapEntry<String, List<int>>> _photoPreviewGroups() {
    final result = <String, List<int>>{};
    for (final eventGroup in _photoGroups()) {
      if (!photoGroupUsesYearSubgroups(
        widget.topic.customCard,
        eventGroup.key,
      )) {
        result['${widget.topic.title} · ${eventGroup.key}'] = eventGroup.value;
        continue;
      }
      final years = <int, List<int>>{};
      for (final index in eventGroup.value) {
        years.putIfAbsent(photos[index].captureDate.year, () => []).add(index);
      }
      final yearEntries = years.entries.toList()
        ..sort((left, right) => right.key.compareTo(left.key));
      for (final yearEntry in yearEntries) {
        result['${widget.topic.title} · ${eventGroup.key} · ${yearEntry.key}年'] =
            yearEntry.value;
      }
    }
    return result.entries.toList();
  }
}

class PhotoPreviewItem {
  const PhotoPreviewItem({
    required this.groupTitle,
    required this.photo,
  });

  final String groupTitle;
  final MemoryPhoto photo;
}

class PhotoPreviewDialog extends StatefulWidget {
  const PhotoPreviewDialog({
    super.key,
    required this.items,
    required this.initialPage,
  });

  final List<PhotoPreviewItem> items;
  final int initialPage;

  @override
  State<PhotoPreviewDialog> createState() => _PhotoPreviewDialogState();
}

class _PhotoPreviewDialogState extends State<PhotoPreviewDialog> {
  late final PageController controller = PageController(
    initialPage: widget.initialPage,
  );
  late String currentGroup = widget.items[widget.initialPage].groupTitle;
  Timer? hintTimer;
  bool showingHint = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadAround(widget.initialPage);
    });
  }

  @override
  void dispose() {
    hintTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  void handlePageChanged(int page) {
    _preloadAround(page);
    final group = widget.items[page].groupTitle;
    if (group == currentGroup || !mounted) return;
    hintTimer?.cancel();
    setState(() {
      currentGroup = group;
      showingHint = true;
    });
    hintTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => showingHint = false);
    });
  }

  Future<AssetEntity?> _resolveEntity(MemoryPhoto photo) =>
      resolveMemoryPhotoAsset(photo);

  Future<void> _preloadAround(int page) async {
    for (final index in [page - 1, page, page + 1]) {
      if (index >= 0 && index < widget.items.length) {
        await _preloadPhoto(index);
      }
    }
  }

  Future<void> _preloadPhoto(int index) async {
    final photo = widget.items[index].photo;
    final asset = await _resolveEntity(photo);
    if (!mounted) return;
    if (asset != null) {
      await precacheImage(
        AssetEntityImageProvider(
          asset,
          isOriginal: true,
          thumbnailSize: null,
          thumbnailFormat: ThumbnailFormat.jpeg,
        ),
        context,
      );
      return;
    }
    final path = photo.path;
    if (path != null) {
      await precacheImage(FileImage(File(path)), context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(8),
      child: Stack(
        children: [
          PageView.builder(
            controller: controller,
            itemCount: widget.items.length,
            onPageChanged: handlePageChanged,
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return Center(
                child: InteractiveViewer(
                  minScale: .8,
                  maxScale: 5,
                  child: _buildPhotoImage(
                    item.photo,
                    fit: BoxFit.contain,
                    original: true,
                    entityFuture: _resolveEntity(item.photo),
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: showingHint ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .68),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Text(
                        currentGroup,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: '关闭预览',
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildPhotoImage(
  MemoryPhoto photo, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  bool original = false,
  Future<AssetEntity?>? entityFuture,
}) {
  final asset = photo.asset;
  if (asset != null) {
    return AssetEntityImage(
      asset,
      isOriginal: original,
      thumbnailSize: original ? null : const ThumbnailSize.square(320),
      thumbnailFormat: ThumbnailFormat.jpeg,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_outlined, size: 42),
      ),
    );
  }
  if (photo.assetId != null) {
    return FutureBuilder<AssetEntity?>(
      future: entityFuture ?? resolveMemoryPhotoAsset(photo),
      builder: (context, snapshot) {
        final entity = snapshot.data;
        if (entity == null) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        return AssetEntityImage(
          entity,
          isOriginal: original,
          thumbnailSize: original ? null : const ThumbnailSize.square(320),
          thumbnailFormat: ThumbnailFormat.jpeg,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image_outlined, size: 42),
          ),
        );
      },
    );
  }
  if (photo.path == null) {
    return const Center(child: Icon(Icons.broken_image_outlined, size: 42));
  }
  return Image.file(
    File(photo.path!),
    width: width,
    height: height,
    fit: fit,
    errorBuilder: (_, __, ___) => const Center(
      child: Icon(Icons.broken_image_outlined, size: 42),
    ),
  );
}

class PhotoAddSheet extends StatefulWidget {
  const PhotoAddSheet({
    super.key,
    required this.title,
    required this.centerDate,
    required this.candidates,
  });

  final String title;
  final DateTime centerDate;
  final List<MemoryPhoto> candidates;

  @override
  State<PhotoAddSheet> createState() => _PhotoAddSheetState();
}

class _PhotoAddSheetState extends State<PhotoAddSheet> {
  final selectedKeys = <String>{};

  void togglePhoto(MemoryPhoto photo) {
    final key = photo.identityKey;
    if (key == null) return;
    setState(() {
      if (!selectedKeys.add(key)) selectedKeys.remove(key);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rangeStart = widget.centerDate.subtract(const Duration(days: 7));
    final rangeEnd = widget.centerDate.add(const Duration(days: 7));
    return FractionallySizedBox(
      heightFactor: .84,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '添加到 ${widget.title}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${formatDate(rangeStart)} 至 ${formatDate(rangeEnd)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: selectedKeys.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(
                              widget.candidates
                                  .where(
                                    (photo) => selectedKeys.contains(
                                      photo.identityKey,
                                    ),
                                  )
                                  .toList(),
                            ),
                    child: Text(
                      selectedKeys.isEmpty
                          ? '完成'
                          : '完成 (${selectedKeys.length})',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: widget.candidates.isEmpty
                  ? _emptyCandidates(theme)
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: widget.candidates.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1,
                      ),
                      itemBuilder: (context, index) {
                        final photo = widget.candidates[index];
                        final key = photo.identityKey;
                        final selected =
                            key != null && selectedKeys.contains(key);
                        return GestureDetector(
                          onTap: () => togglePhoto(photo),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildPhotoImage(photo),
                              if (selected)
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary
                                        .withValues(alpha: .35),
                                    border: Border.all(
                                      color: theme.colorScheme.primary,
                                      width: 3,
                                    ),
                                  ),
                                  child: Align(
                                    alignment: Alignment.topRight,
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: CircleAvatar(
                                        radius: 12,
                                        backgroundColor:
                                            theme.colorScheme.primary,
                                        child: const Icon(
                                          Icons.check,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Positioned(
                                left: 6,
                                right: 6,
                                bottom: 6,
                                child: Text(
                                  '${photo.captureDate.month}月${photo.captureDate.day}日',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    shadows: [
                                      Shadow(
                                        blurRadius: 4,
                                        color: Colors.black,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCandidates(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            const Text('附近 14 天没有找到照片'),
            const SizedBox(height: 4),
            Text(
              '可以先把照片同步到 App，再回来添加。',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
