part of '../main.dart';

class _SubgroupInlineEditor extends StatefulWidget {
  const _SubgroupInlineEditor({
    super.key,
    required this.existing,
    required this.onCancel,
    required this.onCommit,
  });

  final CustomLifeSubgroup? existing;
  final VoidCallback onCancel;
  final ValueChanged<List<CustomLifeSubgroup>> onCommit;

  @override
  State<_SubgroupInlineEditor> createState() => _SubgroupInlineEditorState();
}

class _SubgroupInlineEditorState extends State<_SubgroupInlineEditor> {
  late final TextEditingController titleController;
  late CustomCardRule rule;
  late List<CustomDateEntry> selectedEntries;
  late List<String> selectedFestivals;
  late bool groupByYear;
  int? editingDateIndex;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    titleController = TextEditingController(text: existing?.title ?? '');
    rule = existing?.rule ?? CustomCardRule.date;
    groupByYear = existing?.groupByYear ?? true;
    selectedEntries = List<CustomDateEntry>.from(
      existing?.dateEntries ??
          [CustomDateEntry(date: dateOnly(DateTime.now()))],
    );
    selectedFestivals = existing?.rule == CustomCardRule.festival &&
            existing?.festival != null &&
            existing!.festival!.isNotEmpty
        ? [existing.festival!]
        : [];
  }

  @override
  void dispose() {
    titleController.dispose();
    super.dispose();
  }

  void addDate() {
    setState(() {
      selectedEntries.add(
        CustomDateEntry(date: dateOnly(DateTime.now()), annual: groupByYear),
      );
      editingDateIndex = selectedEntries.length - 1;
    });
  }

  void removeDate(int index) {
    setState(() {
      selectedEntries.removeAt(index);
      if (editingDateIndex == index) {
        editingDateIndex = null;
      } else if (editingDateIndex != null && editingDateIndex! > index) {
        editingDateIndex = editingDateIndex! - 1;
      }
    });
  }

  List<CustomLifeSubgroup>? collect() {
    final title = titleController.text.trim();
    if (rule == CustomCardRule.date && title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写二级分组名称。')),
      );
      return null;
    }
    if (rule == CustomCardRule.festival && selectedFestivals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一个节日。')),
      );
      return null;
    }
    if (rule == CustomCardRule.date) {
      return [
        CustomLifeSubgroup(
          id: widget.existing?.id ??
              DateTime.now().microsecondsSinceEpoch.toString(),
          title: title,
          rule: rule,
          enabled: widget.existing?.enabled ?? true,
          dateEntries: [
            for (final entry in selectedEntries)
              CustomDateEntry(
                date: entry.date,
                label: entry.label,
                calendar: entry.calendar,
                annual: groupByYear,
              ),
          ],
          matchByDate: widget.existing?.matchByDate ?? true,
          groupByYear: groupByYear,
        ),
      ];
    }
    return [
      for (var index = 0; index < selectedFestivals.length; index++)
        CustomLifeSubgroup(
          id: index == 0 && widget.existing != null
              ? widget.existing!.id
              : '${DateTime.now().microsecondsSinceEpoch}-$index',
          title: selectedFestivals[index],
          rule: CustomCardRule.festival,
          enabled: widget.existing?.enabled ?? true,
          festival: selectedFestivals[index],
        ),
    ];
  }

  void commit() {
    final collected = collect();
    if (collected != null && mounted) widget.onCommit(collected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .35),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing == null ? '新二级分组' : '编辑二级分组',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SegmentedButton<CustomCardRule>(
              segments: const [
                ButtonSegment(
                  value: CustomCardRule.date,
                  label: Text('按日期'),
                  icon: Icon(Icons.event_outlined),
                ),
                ButtonSegment(
                  value: CustomCardRule.festival,
                  label: Text('按节日'),
                  icon: Icon(Icons.celebration_outlined),
                ),
              ],
              selected: {rule},
              onSelectionChanged: (values) =>
                  setState(() => rule = values.first),
            ),
            const SizedBox(height: 10),
            if (rule == CustomCardRule.date) ...[
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: '二级分组名称',
                  hintText: '例如：结婚纪念日、妻子生日',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: groupByYear,
                onChanged: (value) => setState(() => groupByYear = value),
                title: Text(groupByYear ? '按年份分组' : '一次性分组'),
                subtitle: Text(
                  groupByYear ? '每年按月日归入对应的年份' : '只匹配设置的完整日期，不再拆分年份',
                ),
                secondary: Icon(
                  groupByYear
                      ? Icons.calendar_view_month_outlined
                      : Icons.event_available_outlined,
                ),
              ),
              for (var index = 0; index < selectedEntries.length; index++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_formatSubgroupDate(selectedEntries[index])),
                  subtitle: Text(
                    '${selectedEntries[index].calendar == CalendarType.lunar ? '阴历' : '阳历'}'
                    '${groupByYear ? '，每年按月日匹配' : '，仅匹配这个完整日期'}',
                  ),
                  leading: Icon(
                    selectedEntries[index].calendar == CalendarType.lunar
                        ? Icons.brightness_2_outlined
                        : Icons.event_outlined,
                  ),
                  trailing: IconButton(
                    tooltip: '删除日期',
                    onPressed: selectedEntries.length == 1
                        ? null
                        : () => removeDate(index),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  onTap: () => setState(() => editingDateIndex = index),
                ),
              if (editingDateIndex != null)
                _InlineDatePickerPanel(
                  key: ValueKey('subgroup-date-$editingDateIndex'),
                  initial: selectedEntries[editingDateIndex!],
                  onChanged: (entry) => setState(
                    () => selectedEntries[editingDateIndex!] = entry,
                  ),
                  onCollapse: () => setState(() => editingDateIndex = null),
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: addDate,
                    icon: const Icon(Icons.add),
                    label: const Text('添加日期'),
                  ),
                ),
            ] else ...[
              const Text('选择节日（可多选）'),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    selectedFestivals.isEmpty
                        ? '尚未选择'
                        : '已选择 ${selectedFestivals.length} 个',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: selectedFestivals.isEmpty
                        ? null
                        : () => setState(() => selectedFestivals.clear()),
                    child: const Text('清空'),
                  ),
                ],
              ),
              Text(
                '每个勾选的节日会自动生成一条独立的二级分组。',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: .45),
                child: Column(
                  children: [
                    for (final festival in supportedFestivals)
                      CheckboxListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        title: Text(festival),
                        value: selectedFestivals.contains(festival),
                        onChanged: (selected) {
                          setState(() {
                            if (selected == true) {
                              if (!selectedFestivals.contains(festival)) {
                                selectedFestivals.add(festival);
                              }
                            } else {
                              selectedFestivals.remove(festival);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: commit,
                  child: Text(widget.existing == null ? '添加分组' : '完成'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatSubgroupDate(CustomDateEntry entry) {
    if (entry.calendar == CalendarType.lunar) {
      final lunar = Lunar.fromDate(entry.date);
      return '农历${lunar.getMonth()}月${lunar.getDay()}日';
    }
    return formatDate(entry.date);
  }
}

class CustomLifeCardEditorPage extends StatefulWidget {
  const CustomLifeCardEditorPage({super.key, this.existing});

  final CustomLifeCard? existing;

  @override
  State<CustomLifeCardEditorPage> createState() =>
      _CustomLifeCardEditorPageState();
}

class _CustomLifeCardEditorPageState extends State<CustomLifeCardEditorPage> {
  late final TextEditingController titleController;
  late final TextEditingController subtitleController;
  late List<CustomLifeSubgroup> subgroups;
  GlobalKey<_SubgroupInlineEditorState>? draftEditorKey;
  CustomLifeSubgroup? draftSubgroup;
  int? draftSubgroupIndex;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    titleController = TextEditingController(text: existing?.title ?? '');
    subtitleController = TextEditingController(text: existing?.subtitle ?? '');
    subgroups = List<CustomLifeSubgroup>.from(existing?.subgroups ?? const []);
    if (existing == null) {
      // 新建卡片时直接展开一条空白分组，一页就能填完。
      draftEditorKey = GlobalKey<_SubgroupInlineEditorState>();
      draftSubgroup = newSubgroupDraft();
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    subtitleController.dispose();
    super.dispose();
  }

  CustomLifeSubgroup newSubgroupDraft() {
    return CustomLifeSubgroup(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: '',
      rule: CustomCardRule.date,
      dateEntries: [CustomDateEntry(date: dateOnly(DateTime.now()))],
    );
  }

  void openSubgroupDraft([CustomLifeSubgroup? existing, int? index]) {
    setState(() {
      draftEditorKey = GlobalKey<_SubgroupInlineEditorState>();
      draftSubgroup = existing ?? newSubgroupDraft();
      draftSubgroupIndex = index;
    });
  }

  void closeSubgroupDraft() {
    setState(() {
      draftEditorKey = null;
      draftSubgroup = null;
      draftSubgroupIndex = null;
    });
  }

  List<CustomLifeSubgroup> mergeSubgroups(
    List<CustomLifeSubgroup> base,
    List<CustomLifeSubgroup> edited,
    int? index,
  ) {
    if (index == null) {
      final existingFestivals = base
          .where((item) => item.rule == CustomCardRule.festival)
          .map((item) => item.festival)
          .whereType<String>()
          .toSet();
      return [
        ...base,
        ...edited.where(
          (item) =>
              item.rule != CustomCardRule.festival ||
              !existingFestivals.contains(item.festival),
        ),
      ];
    }
    final target = base[index];
    final existingFestivals = base
        .where(
          (item) =>
              item.rule == CustomCardRule.festival && item.id != target.id,
        )
        .map((item) => item.festival)
        .whereType<String>()
        .toSet();
    final replacements = edited.where(
      (item) =>
          item.rule != CustomCardRule.festival ||
          !existingFestivals.contains(item.festival),
    );
    return [...base]
      ..removeAt(index)
      ..insertAll(index, replacements);
  }

  void commitSubgroupDraft(List<CustomLifeSubgroup> edited) {
    setState(() {
      subgroups = mergeSubgroups(subgroups, edited, draftSubgroupIndex);
      draftEditorKey = null;
      draftSubgroup = null;
      draftSubgroupIndex = null;
    });
  }

  void save() {
    var result = subgroups;
    if (draftSubgroup != null) {
      // 正在填写的分组会随卡片一起保存，不需要先单独点“添加分组”。
      final editorState = draftEditorKey?.currentState;
      if (editorState == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先完成正在填写的二级分组。')),
        );
        return;
      }
      final collected = editorState.collect();
      if (collected == null) return;
      result = mergeSubgroups(result, collected, draftSubgroupIndex);
    }
    final title = titleController.text.trim();
    if (title.isEmpty || result.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写卡片名称，并至少添加一个二级分组。')),
      );
      return;
    }
    Navigator.of(context).pop(
      CustomLifeCard(
        id: widget.existing?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        subtitle: subtitleController.text.trim(),
        enabled: widget.existing?.enabled ?? true,
        subgroups: result,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '添加自定义卡片' : '编辑自定义卡片'),
        actions: [
          TextButton(
            onPressed: save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        children: [
          TextField(
            controller: titleController,
            autofocus: widget.existing == null,
            decoration: const InputDecoration(
              labelText: '卡片名称',
              hintText: '例如：第一次见面',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: subtitleController,
            decoration: const InputDecoration(
              labelText: '卡片说明（可选）',
              hintText: '例如：和爱人在一起',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '二级分组',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (draftSubgroup == null)
                TextButton.icon(
                  onPressed: () => openSubgroupDraft(),
                  icon: const Icon(Icons.add),
                  label: const Text('添加分组'),
                ),
            ],
          ),
          Text(
            '一级卡片是主题，按日期或节日的规则配置在二级分组中。',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 8),
          if (draftSubgroup == null && subgroups.isEmpty)
            Card(
              elevation: 0,
              child: ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: const Text('还没有二级分组'),
                subtitle: const Text('例如：结婚纪念日、妻子生日'),
                trailing: const Icon(Icons.add),
                onTap: () => openSubgroupDraft(),
              ),
            )
          else ...[
            for (var index = 0; index < subgroups.length; index++)
              if (draftSubgroup != null && draftSubgroupIndex == index)
                _SubgroupInlineEditor(
                  key: draftEditorKey,
                  existing: draftSubgroup,
                  onCancel: closeSubgroupDraft,
                  onCommit: commitSubgroupDraft,
                )
              else
                _subgroupTile(index),
            if (draftSubgroup != null && draftSubgroupIndex == null)
              _SubgroupInlineEditor(
                key: draftEditorKey,
                existing: null,
                onCancel: closeSubgroupDraft,
                onCommit: commitSubgroupDraft,
              ),
          ],
        ],
      ),
    );
  }

  Widget _subgroupTile(int index) {
    final subgroup = subgroups[index];
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          subgroup.rule == CustomCardRule.date
              ? Icons.event_outlined
              : Icons.celebration_outlined,
        ),
        title: Text(subgroup.title),
        subtitle: Text(_subgroupDescription(subgroup)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '编辑',
              visualDensity: VisualDensity.compact,
              onPressed: () => openSubgroupDraft(subgroup, index),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: '删除',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(
                () => subgroups = [...subgroups]..removeAt(index),
              ),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        onTap: () => openSubgroupDraft(subgroup, index),
      ),
    );
  }

  String _subgroupDescription(CustomLifeSubgroup subgroup) {
    if (subgroup.rule == CustomCardRule.festival) {
      return '按节日 · ${subgroup.festival ?? ''} · 按年份分组';
    }
    final calendar = subgroup.dateEntries
        .map((entry) => entry.calendar == CalendarType.lunar ? '阴历' : '阳历')
        .toSet()
        .join('、');
    return '按日期 · ${subgroup.dateEntries.length} 个日期'
        '${calendar.isEmpty ? '' : ' · $calendar'}'
        ' · ${subgroup.groupByYear ? '按年份分组' : '一次性分组'}'
        '${subgroup.matchByDate ? '' : ' · 仅手动添加'}';
  }
}

class _InlineDatePickerPanel extends StatefulWidget {
  const _InlineDatePickerPanel({
    super.key,
    required this.initial,
    required this.onChanged,
    required this.onCollapse,
  });

  final CustomDateEntry initial;
  final ValueChanged<CustomDateEntry> onChanged;
  final VoidCallback onCollapse;

  @override
  State<_InlineDatePickerPanel> createState() => _InlineDatePickerPanelState();
}

class _InlineDatePickerPanelState extends State<_InlineDatePickerPanel> {
  late final TextEditingController lunarMonthController;
  late final TextEditingController lunarDayController;
  late final int referenceYear;
  late DateTime selectedDate;
  late CalendarType calendar;
  String? lunarError;

  @override
  void initState() {
    super.initState();
    final lunar = Lunar.fromDate(widget.initial.date);
    lunarMonthController =
        TextEditingController(text: lunar.getMonth().toString());
    lunarDayController = TextEditingController(text: lunar.getDay().toString());
    referenceYear = widget.initial.date.year;
    selectedDate = widget.initial.date;
    calendar = widget.initial.calendar;
  }

  @override
  void dispose() {
    lunarMonthController.dispose();
    lunarDayController.dispose();
    super.dispose();
  }

  void applySolar(DateTime value) {
    final date = dateOnly(value);
    setState(() => selectedDate = date);
    widget.onChanged(
      CustomDateEntry(
        date: date,
        calendar: CalendarType.solar,
        annual: widget.initial.annual,
      ),
    );
  }

  void applyLunar() {
    final month = int.tryParse(lunarMonthController.text.trim());
    final day = int.tryParse(lunarDayController.text.trim());
    if (month == null ||
        day == null ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 30) {
      setState(() => lunarError = '农历月份填 1-12，日期填 1-30。');
      return;
    }
    try {
      final solar = Lunar.fromYmd(referenceYear, month, day).getSolar();
      final date = DateTime(solar.getYear(), solar.getMonth(), solar.getDay());
      setState(() {
        selectedDate = date;
        lunarError = null;
      });
      widget.onChanged(
        CustomDateEntry(
          date: date,
          calendar: CalendarType.lunar,
          annual: widget.initial.annual,
        ),
      );
    } catch (_) {
      setState(() => lunarError = '这个农历日期不存在，请检查月份和日期。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .45),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '选择日期',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: widget.onCollapse,
                  child: const Text('收起'),
                ),
              ],
            ),
            SegmentedButton<CalendarType>(
              segments: const [
                ButtonSegment(
                  value: CalendarType.solar,
                  label: Text('阳历'),
                  icon: Icon(Icons.sunny),
                ),
                ButtonSegment(
                  value: CalendarType.lunar,
                  label: Text('阴历'),
                  icon: Icon(Icons.nightlight_outlined),
                ),
              ],
              selected: {calendar},
              onSelectionChanged: (values) =>
                  setState(() => calendar = values.first),
            ),
            const SizedBox(height: 8),
            if (calendar == CalendarType.solar)
              CalendarDatePicker(
                initialDate: selectedDate,
                firstDate: DateTime(1900),
                lastDate: DateTime(2100),
                onDateChanged: applySolar,
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: lunarMonthController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '农历月份',
                        suffixText: '月',
                      ),
                      onChanged: (_) => applyLunar(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: lunarDayController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '农历日期',
                        suffixText: '日',
                      ),
                      onChanged: (_) => applyLunar(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                lunarError ?? '按农历月日匹配，例如正月十五填 1 月 15 日。',
                style: TextStyle(
                  color: lunarError == null
                      ? Colors.grey.shade700
                      : theme.colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
