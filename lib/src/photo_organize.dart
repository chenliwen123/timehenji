part of '../main.dart';

class PhotoOrganizationChoice {
  const PhotoOrganizationChoice({
    required this.cardId,
    required this.groupTitle,
    required this.matchSameDate,
  });

  final String cardId;
  final String groupTitle;
  final bool matchSameDate;
}

class UnorganizedPhotosPage extends StatefulWidget {
  const UnorganizedPhotosPage({super.key, this.client});

  final SupabaseClient? client;

  @override
  State<UnorganizedPhotosPage> createState() => _UnorganizedPhotosPageState();
}

class _UnorganizedPhotosPageState extends State<UnorganizedPhotosPage>
    with LifeConfigListener<UnorganizedPhotosPage> {
  List<MemoryPhoto> allPhotos = [];
  List<MemoryPhoto> photos = [];
  bool loading = true;
  bool syncing = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    initializePhotos();
  }

  Future<void> initializePhotos() async {
    final cached = await loadCachedMemoryPhotos();
    if (cached.isEmpty) {
      await syncPhotos();
      return;
    }
    final unorganized = await photosWithoutConfiguredGroupAsync(
      cached,
      lifeConfig.lifeCards,
    );
    if (!mounted) return;
    setState(() {
      allPhotos = cached;
      photos = unorganized;
      loading = false;
    });
  }

  Future<void> syncPhotos() async {
    if (syncing) return;
    setState(() => syncing = true);
    final imported = await syncAllMemoryPhotos(lifeConfig.config);
    if (!mounted) return;
    if (imported == null) {
      setState(() {
        loading = false;
        syncing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请允许 App 访问照片，才能显示待整理照片。')),
      );
      return;
    }
    final unorganized = await photosWithoutConfiguredGroupAsync(
      imported,
      lifeConfig.lifeCards,
    );
    if (!mounted) return;
    setState(() {
      allPhotos = imported;
      photos = unorganized;
      loading = false;
      syncing = false;
    });
  }

  Future<void> organizePhoto(MemoryPhoto photo) async {
    final enabledCards =
        lifeConfig.lifeCards.where((card) => card.enabled).toList();
    if (enabledCards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('还没有可用的分组卡片。先在「纪念日期」里填写日期，'
              '或在卡片的二级分组里新建一个分组。'),
        ),
      );
      return;
    }
    final choice = await showModalBottomSheet<PhotoOrganizationChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PhotoOrganizationSheet(
        photo: photo,
        cards: enabledCards,
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => saving = true);
    try {
      final cards = addPhotoDateGroup(
        cards: lifeConfig.lifeCards,
        cardId: choice.cardId,
        groupTitle: choice.groupTitle,
        captureDate: photo.captureDate,
        matchSameDate: choice.matchSameDate,
      );
      final card = cards.firstWhere((item) => item.id == choice.cardId);
      final subgroup = card.subgroups.firstWhere(
        (item) =>
            item.title == choice.groupTitle && item.rule == CustomCardRule.date,
      );
      final targetKeys = choice.matchSameDate
          ? allPhotos
              .where(
                (item) =>
                    dateKey(item.captureDate) == dateKey(photo.captureDate),
              )
              .map((item) => item.identityKey)
              .whereType<String>()
              .toSet()
          : {if (photo.identityKey != null) photo.identityKey!};
      final updatedPhotos = [
        for (final item in allPhotos)
          targetKeys.contains(item.identityKey)
              ? item.copyWith(
                  manualTopic: card.title,
                  manualTopicId: card.id,
                  manualCategory: choice.groupTitle,
                  manualCategoryId: subgroup.id,
                )
              : item,
      ];

      await saveLocalCustomCards(cards);
      await saveMemoryPhotos(updatedPhotos);
      await lifeConfig.replaceCards(cards);
      final config = lifeConfig.config;
      String? cloudWarning;
      if (widget.client != null) {
        try {
          await saveLifeDates(widget.client!, config);
        } catch (_) {
          cloudWarning = '，本地已保存，云端同步失败';
        }
      }
      final remaining = await photosWithoutConfiguredGroupAsync(
        updatedPhotos,
        cards,
      );
      if (!mounted) return;
      setState(() {
        allPhotos = updatedPhotos;
        photos = remaining;
        saving = false;
      });
      await recordMemoryActivity(MemoryActivityType.organize);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            choice.matchSameDate
                ? '已将当天照片保存到「${card.title} · ${choice.groupTitle}」${cloudWarning ?? ''}'
                : '已将这张照片保存到「${card.title} · ${choice.groupTitle}」${cloudWarning ?? ''}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('待整理照片'),
        actions: [
          IconButton(
            onPressed: syncing || saving ? null : syncPhotos,
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
          : photos.isEmpty
              ? _emptyState()
              : Stack(
                  children: [
                    GridView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                      itemCount: photos.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                        childAspectRatio: 1,
                      ),
                      itemBuilder: (context, index) {
                        final photo = photos[index];
                        return Material(
                          clipBehavior: Clip.antiAlias,
                          borderRadius: BorderRadius.circular(6),
                          child: InkWell(
                            onTap: saving ? null : () => organizePhoto(photo),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _buildPhotoImage(photo),
                                Positioned(
                                  left: 5,
                                  right: 5,
                                  bottom: 5,
                                  child: Text(
                                    formatDate(photo.captureDate),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
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
                          ),
                        );
                      },
                    ),
                    if (saving)
                      ColoredBox(
                        color: Colors.black.withValues(alpha: .16),
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.task_alt,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              '照片都整理好了',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('新照片同步后，如果没有命中分组，会显示在这里。'),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: syncing ? null : syncPhotos,
              icon: const Icon(Icons.sync),
              label: const Text('同步手机照片'),
            ),
          ],
        ),
      ),
    );
  }
}

class PhotoOrganizationSheet extends StatefulWidget {
  const PhotoOrganizationSheet({
    super.key,
    required this.photo,
    required this.cards,
  });

  final MemoryPhoto photo;
  final List<CustomLifeCard> cards;

  @override
  State<PhotoOrganizationSheet> createState() => _PhotoOrganizationSheetState();
}

class _PhotoOrganizationSheetState extends State<PhotoOrganizationSheet> {
  late final TextEditingController titleController;
  late String selectedCardId;
  bool matchSameDate = true;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController();
    selectedCardId = widget.cards.first.id;
  }

  @override
  void dispose() {
    titleController.dispose();
    super.dispose();
  }

  void save() {
    final title = titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请给这个二级分组起个名字。')),
      );
      return;
    }
    Navigator.of(context).pop(
      PhotoOrganizationChoice(
        cardId: selectedCardId,
        groupTitle: title,
        matchSameDate: matchSameDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: _buildPhotoImage(widget.photo),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '整理这张照片',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '拍摄日期：${formatDate(widget.photo.captureDate)}',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              initialValue: selectedCardId,
              decoration: const InputDecoration(
                labelText: '一级分类',
                prefixIcon: Icon(Icons.folder_outlined),
                border: OutlineInputBorder(),
              ),
              items: [
                for (final card in widget.cards)
                  DropdownMenuItem(value: card.id, child: Text(card.title)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => selectedCardId = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: titleController,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => save(),
              decoration: const InputDecoration(
                labelText: '二级分组名称',
                hintText: '例如：青岛旅行、宝宝第一次走路',
                prefixIcon: Icon(Icons.account_tree_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: matchSameDate,
              onChanged: (value) => setState(() => matchSameDate = value),
              title: const Text('添加当天所有照片'),
              subtitle: Text(
                matchSameDate ? '同一天拍摄的照片都会进入这个分组' : '只绑定当前这一张照片',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存分组'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
