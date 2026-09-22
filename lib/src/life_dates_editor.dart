part of '../main.dart';

/// 可编辑的纪念日期。每一项对应一张内置卡片，没填的项不会产生卡片。
enum LifeDateField { birth, marriage, graduation, work }

extension LifeDateFieldInfo on LifeDateField {
  String get label => switch (this) {
        LifeDateField.birth => '生日',
        LifeDateField.marriage => '结婚纪念日',
        LifeDateField.graduation => '毕业纪念日',
        LifeDateField.work => '入职纪念日',
      };

  String get cardTitle => switch (this) {
        LifeDateField.birth => '来到这个世界',
        LifeDateField.marriage => '结婚',
        LifeDateField.graduation => '毕业',
        LifeDateField.work => '加入公司',
      };

  String get hint => switch (this) {
        LifeDateField.birth => '首页的"来到这个世界的第 N 天"依赖这个日期',
        LifeDateField.marriage => '填了才会出现"结婚"卡片',
        LifeDateField.graduation => '填了才会出现"毕业"卡片',
        LifeDateField.work => '填了才会出现"加入公司"卡片',
      };
}

DateTime? dateForField(LifeDatesConfig config, LifeDateField field) {
  return switch (field) {
    LifeDateField.birth => config.birthDate,
    LifeDateField.marriage => config.marriageDate,
    LifeDateField.graduation => config.graduationDate,
    LifeDateField.work => config.workDate,
  };
}

/// 重建配置而不是 copyWith：copyWith 无法把日期清空。
LifeDatesConfig configWithDate(
  LifeDatesConfig config,
  LifeDateField field,
  DateTime? value,
) {
  return LifeDatesConfig(
    birthDate: field == LifeDateField.birth ? value : config.birthDate,
    marriageDate: field == LifeDateField.marriage ? value : config.marriageDate,
    graduationDate:
        field == LifeDateField.graduation ? value : config.graduationDate,
    workDate: field == LifeDateField.work ? value : config.workDate,
    customCards: config.customCards,
  );
}

/// 纪念日期编辑器。未登录也能用，配置只写本机；登录后才会同步到
/// Supabase 的 life_settings 表（相册数据永远留在本机）。
class LifeDatesEditorPage extends StatefulWidget {
  const LifeDatesEditorPage({super.key, this.client});

  final SupabaseClient? client;

  @override
  State<LifeDatesEditorPage> createState() => _LifeDatesEditorPageState();
}

class _LifeDatesEditorPageState extends State<LifeDatesEditorPage>
    with LifeConfigListener<LifeDatesEditorPage> {
  late LifeDatesConfig draft = lifeConfig.config;
  bool saving = false;

  bool get signedIn => widget.client?.auth.currentUser != null;

  Future<void> _pick(LifeDateField field) async {
    final current = dateForField(draft, field);
    final selected = await showDatePicker(
      context: context,
      initialDate: current ?? dateOnly(DateTime.now()),
      firstDate: DateTime(1900),
      lastDate: DateTime(dateOnly(DateTime.now()).year + 100),
      helpText: '选择${field.label}',
    );
    if (selected != null) await _apply(field, dateOnly(selected));
  }

  /// 选完即存，避免用户改完直接返回导致丢失；
  /// saveLifeDates 会先写本机再同步云端，所以云端失败也不会丢数据。
  Future<void> _apply(LifeDateField field, DateTime? value) async {
    final next = configWithDate(draft, field, value);
    setState(() {
      draft = next;
      saving = true;
    });
    String message;
    try {
      final synced = await saveLifeDates(widget.client, next);
      message = synced ? '已保存到云端' : '已保存在本机，登录后会自动同步到云端';
    } catch (exception) {
      message = '云端同步失败，已保存在本机';
    }
    await lifeConfig.replace(next);
    if (!mounted) return;
    setState(() => saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _dateTile(LifeDateField field) {
    final value = dateForField(draft, field);
    return Card(
      elevation: 0,
      child: ListTile(
        leading: Icon(value == null ? Icons.add_circle_outline : Icons.event),
        title: Text(field.label),
        subtitle: Text(
          value == null
              ? field.hint
              : '${formatDate(value)} · 卡片「${field.cardTitle}」',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value != null)
              IconButton(
                onPressed: saving ? null : () => _apply(field, null),
                icon: const Icon(Icons.close),
                tooltip: '清除${field.label}',
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: saving ? null : () => _pick(field),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filled = LifeDateField.values
        .where((field) => dateForField(draft, field) != null)
        .length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('纪念日期'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('完成'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            '已经填写 $filled / ${LifeDateField.values.length} 项。每改一项都会立刻保存。'
            '日期只用于统计天数和分组照片，'
            '${signedIn ? '并同步到你登录的云端账号。' : '目前保存在本机，登录后会同步到云端。'}',
            style: TextStyle(color: Colors.grey.shade700, height: 1.5),
          ),
          const SizedBox(height: 12),
          ...LifeDateField.values.map(_dateTile),
          if (draft.customCards.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              '自定义卡片 ${draft.customCards.length} 张',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '自定义卡片${draft.customCards.map((card) => card.title).join('、')}不受这里的影响，'
              '到"卡片与账号设置"里可以继续增删。',
              style: TextStyle(color: Colors.grey.shade600, height: 1.5),
            ),
          ],
          const SizedBox(height: 20),
          Card(
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('卡片与账号设置'),
              subtitle: Text(
                signedIn ? '编辑自定义卡片、绑定邮箱和每日回忆' : '登录后可用',
              ),
              trailing: const Icon(Icons.chevron_right),
              enabled: signedIn,
              onTap: signedIn
                  ? () async {
                      await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) =>
                              LifeDatesSettingsPage(client: widget.client!),
                        ),
                      );
                      if (mounted) setState(() => draft = lifeConfig.config);
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
