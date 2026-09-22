part of '../main.dart';

class LifeDatesSettingsPage extends StatefulWidget {
  const LifeDatesSettingsPage({super.key, required this.client});

  final SupabaseClient client;

  @override
  State<LifeDatesSettingsPage> createState() => _LifeDatesSettingsPageState();
}

class _LifeDatesSettingsPageState extends State<LifeDatesSettingsPage>
    with LifeConfigListener<LifeDatesSettingsPage> {
  final emailController = TextEditingController();
  final emailCodeController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final emailCodeFocusNode = FocusNode();
  bool loading = true;
  bool saving = false;
  bool sendingEmailCode = false;
  bool bindingEmail = false;
  bool emailCodeSent = false;
  bool bindingNeedsPassword = true;
  bool editingPassword = false;
  int emailCodeCooldown = 0;
  Timer? emailCodeTimer;
  String? boundEmail;
  String? accountMessage;
  bool accountMessageIsError = false;
  String? error;
  bool dailyMemoryReviewEnabled = true;
  List<CustomLifeCard> customCards = [];

  @override
  void initState() {
    super.initState();
    final user = widget.client.auth.currentUser;
    bindingNeedsPassword = user?.isAnonymous ?? true;
    if (user != null &&
        !user.isAnonymous &&
        user.emailConfirmedAt != null &&
        user.email?.isNotEmpty == true) {
      boundEmail = user.email;
    }
    _load();
  }

  @override
  void dispose() {
    emailCodeTimer?.cancel();
    emailController.dispose();
    emailCodeController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    emailCodeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final dates = lifeConfig.config;
    final preferences = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        dailyMemoryReviewEnabled =
            preferences.getBool(dailyMemoryReviewEnabledKey) ?? true;
      });
    }
    final localCards = parseCustomCards(await loadLocalCustomCards());
    if (mounted && localCards.isNotEmpty) {
      setState(() {
        customCards = normalizeLifeCards(
          localCards,
          birth: dates.birthDate,
          marriage: dates.marriageDate,
          graduation: dates.graduationDate,
          work: dates.workDate,
        );
        loading = false;
      });
    }
    try {
      final config = await loadLifeDates(widget.client);
      if (!mounted) return;
      final loadedCards = customCards.isEmpty
          ? config.customCards
          : mergeCustomCardLists(config.customCards, customCards);
      setState(() {
        customCards = loadedCards;
        loading = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        loading = false;
        if (customCards.isEmpty) customCards = lifeConfig.lifeCards;
        error = exception is PostgrestException &&
                isMissingLifeSettingsTable(exception)
            ? '云端还没有 life_settings 表，当前只显示本机配置。请在 Supabase SQL Editor 执行 supabase_setup.sql。'
            : '读取配置失败：$exception';
      });
    }
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final config = lifeConfig.config.copyWith(customCards: customCards);
      await saveLifeDates(widget.client, config);
      await lifeConfig.replace(config);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = exception is PostgrestException &&
                isMissingLifeSettingsTable(exception)
            ? '云端还没有 life_settings 表，请先在 Supabase SQL Editor 执行 supabase_setup.sql。'
            : '保存失败：$exception';
      });
    }
  }

  Future<void> updateCustomCards(List<CustomLifeCard> cards) async {
    if (!mounted) return;
    final previousSubgroupIds = {
      for (final card in customCards)
        for (final subgroup in card.subgroups) '${card.id}:${subgroup.id}',
    };
    final hasNewEvent = cards.any(
      (card) => card.subgroups.any(
        (subgroup) =>
            !previousSubgroupIds.contains('${card.id}:${subgroup.id}'),
      ),
    );
    setState(() => customCards = cards);
    await lifeConfig.replaceCards(cards);
    await saveLocalCustomCards(cards);
    if (hasNewEvent) await recordMemoryActivity(MemoryActivityType.event);
  }

  Future<void> updateDailyMemoryReview(bool enabled) async {
    setState(() => dailyMemoryReviewEnabled = enabled);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(dailyMemoryReviewEnabledKey, enabled);
  }

  Future<void> reviewTodayMemory() async {
    final target = dateOnly(DateTime.now());
    final source = await loadCachedMemoryPhotos();
    final memories = findDailyMemoryGroups(
      source,
      lifeConfig.lifeCards,
      today: target,
    );
    if (!mounted) return;
    if (memories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('今天没有找到往年的同一天分组照片。')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => DailyMemoryReviewDialog(
        memories: memories,
        today: target,
      ),
    );
    await recordMemoryActivity(
      MemoryActivityType.review,
      reviewYears:
          memories.map((memory) => target.year - memory.year).fold(0, math.max),
    );
  }

  Future<void> sendEmailCode() async {
    final email = emailController.text.trim();
    if (!email.contains('@')) {
      _showAccountMessage('请输入正确的邮箱地址。', isError: true);
      return;
    }
    setState(() {
      sendingEmailCode = true;
      accountMessage = null;
    });
    try {
      bindingNeedsPassword =
          widget.client.auth.currentUser?.isAnonymous ?? true;
      await widget.client.auth.updateUser(
        UserAttributes(email: email),
        emailRedirectTo: authRedirectUrl,
      );
      if (!mounted) return;
      emailCodeController.clear();
      setState(() {
        emailCodeSent = true;
        accountMessage = '验证码已发送到 $email，请输入邮件中的 6 位验证码。';
        accountMessageIsError = false;
      });
      _startEmailCodeCooldown();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) emailCodeFocusNode.requestFocus();
      });
    } on AuthException catch (exception) {
      if (mounted) {
        _showAccountMessage(
          '发送验证码失败：${_accountAuthMessage(exception.message)}',
          isError: true,
        );
      }
    } catch (exception) {
      if (mounted) {
        _showAccountMessage('发送验证码失败：$exception', isError: true);
      }
    } finally {
      if (mounted) setState(() => sendingEmailCode = false);
    }
  }

  Future<void> bindEmail() async {
    final email = emailController.text.trim();
    final code = emailCodeController.text.trim();
    final password = passwordController.text;
    final confirmPassword = confirmPasswordController.text;
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _showAccountMessage('请输入邮件中的 6 位数字验证码。', isError: true);
      return;
    }
    if (bindingNeedsPassword && password.length < 6) {
      _showAccountMessage('登录密码至少需要 6 位。', isError: true);
      return;
    }
    if (bindingNeedsPassword && password != confirmPassword) {
      _showAccountMessage('两次输入的密码不一致。', isError: true);
      return;
    }
    setState(() {
      bindingEmail = true;
      accountMessage = null;
    });
    var emailVerified = false;
    try {
      await widget.client.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.emailChange,
      );
      emailVerified = true;
      if (bindingNeedsPassword) {
        await widget.client.auth.updateUser(
          UserAttributes(password: password),
        );
      }
      if (!mounted) return;
      emailCodeTimer?.cancel();
      setState(() {
        boundEmail = widget.client.auth.currentUser?.email ?? email;
        bindingNeedsPassword = false;
        emailCodeSent = false;
        emailCodeCooldown = 0;
        accountMessage = '邮箱绑定成功，以后可以使用邮箱和密码登录。';
        accountMessageIsError = false;
      });
      emailCodeController.clear();
      passwordController.clear();
      confirmPasswordController.clear();
    } on AuthException catch (exception) {
      if (!mounted) return;
      if (emailVerified) {
        setState(() {
          boundEmail = widget.client.auth.currentUser?.email ?? email;
          bindingNeedsPassword = false;
          emailCodeSent = false;
          editingPassword = true;
          accountMessage =
              '邮箱已验证，但密码设置失败：${_accountAuthMessage(exception.message)}';
          accountMessageIsError = true;
        });
      } else {
        _showAccountMessage(
          '验证失败：${_accountAuthMessage(exception.message)}',
          isError: true,
        );
      }
    } catch (exception) {
      if (mounted) {
        _showAccountMessage('绑定失败：$exception', isError: true);
      }
    } finally {
      if (mounted) setState(() => bindingEmail = false);
    }
  }

  Future<void> updateLoginPassword() async {
    final password = passwordController.text;
    if (password.length < 6) {
      _showAccountMessage('登录密码至少需要 6 位。', isError: true);
      return;
    }
    if (password != confirmPasswordController.text) {
      _showAccountMessage('两次输入的密码不一致。', isError: true);
      return;
    }
    setState(() {
      bindingEmail = true;
      accountMessage = null;
    });
    try {
      await widget.client.auth.updateUser(UserAttributes(password: password));
      if (!mounted) return;
      passwordController.clear();
      confirmPasswordController.clear();
      setState(() {
        editingPassword = false;
        accountMessage = '登录密码已更新。';
        accountMessageIsError = false;
      });
    } on AuthException catch (exception) {
      if (mounted) {
        _showAccountMessage(
          '密码设置失败：${_accountAuthMessage(exception.message)}',
          isError: true,
        );
      }
    } catch (exception) {
      if (mounted) {
        _showAccountMessage('密码设置失败：$exception', isError: true);
      }
    } finally {
      if (mounted) setState(() => bindingEmail = false);
    }
  }

  void _startEmailCodeCooldown() {
    emailCodeTimer?.cancel();
    setState(() => emailCodeCooldown = 60);
    emailCodeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (emailCodeCooldown <= 1) {
        timer.cancel();
        setState(() => emailCodeCooldown = 0);
      } else {
        setState(() => emailCodeCooldown--);
      }
    });
  }

  void _changeBindingEmail() {
    emailCodeTimer?.cancel();
    emailCodeController.clear();
    passwordController.clear();
    confirmPasswordController.clear();
    setState(() {
      emailCodeSent = false;
      emailCodeCooldown = 0;
      accountMessage = null;
    });
  }

  void _showAccountMessage(String message, {required bool isError}) {
    if (!mounted) return;
    setState(() {
      accountMessage = message;
      accountMessageIsError = isError;
    });
  }

  String _accountAuthMessage(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('token') &&
        (normalized.contains('expired') || normalized.contains('invalid'))) {
      return '验证码错误或已过期，请重新获取。';
    }
    if (normalized.contains('already registered') ||
        normalized.contains('already been registered')) {
      return '这个邮箱已经绑定了其他账号。';
    }
    if (normalized.contains('rate limit')) {
      return '操作太频繁，请稍后再试。';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
              children: [
                _datesEntrySection(),
                const SizedBox(height: 12),
                _accountSection(),
                const SizedBox(height: 12),
                _dailyMemoryReviewSection(),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                _customCardsSection(),
                if (error != null) ...[
                  const SizedBox(height: 14),
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_done_outlined),
                  label: Text(saving ? '保存中…' : '保存到云端'),
                ),
              ],
            ),
    );
  }

  /// 日期编辑放在独立的页面里（未登录也能用），这里只做入口和概览。
  Widget _datesEntrySection() {
    final dates = lifeConfig.config;
    final filled = LifeDateField.values
        .where((field) => dateForField(dates, field) != null)
        .length;
    return Card(
      elevation: 0,
      child: ListTile(
        leading: const Icon(Icons.event_outlined),
        title: const Text(
          '纪念日期',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          filled == 0
              ? '还没有填写，例如生日、结婚纪念日'
              : '已填写 $filled / ${LifeDateField.values.length} 项',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => LifeDatesEditorPage(client: widget.client),
            ),
          );
          if (mounted) setState(() => customCards = lifeConfig.lifeCards);
        },
      ),
    );
  }

  Widget _dailyMemoryReviewSection() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            SwitchListTile(
              value: dailyMemoryReviewEnabled,
              onChanged: saving ? null : updateDailyMemoryReview,
              secondary: const Icon(Icons.history_outlined),
              title: const Text(
                '每日回顾',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('每天第一次打开 App 时，回顾往年的今天和相关照片'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12, bottom: 4),
                child: TextButton.icon(
                  onPressed: reviewTodayMemory,
                  icon: const Icon(Icons.history_toggle_off_outlined),
                  label: const Text('重新查看今天的回忆'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountSection() {
    final theme = Theme.of(context);
    final currentEmail = boundEmail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '账号与安全',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (currentEmail != null)
          Card(
            elevation: 0,
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_outlined,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('邮箱已绑定',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(currentEmail),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '可以使用这个邮箱和密码在新手机登录。',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (!editingPassword)
                    OutlinedButton.icon(
                      onPressed: bindingEmail
                          ? null
                          : () => setState(() {
                                editingPassword = true;
                                accountMessage = null;
                              }),
                      icon: const Icon(Icons.lock_reset_outlined),
                      label: const Text('设置或更新登录密码'),
                    )
                  else ...[
                    _passwordFields(),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: bindingEmail
                              ? null
                              : () {
                                  passwordController.clear();
                                  confirmPasswordController.clear();
                                  setState(() => editingPassword = false);
                                },
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: bindingEmail ? null : updateLoginPassword,
                          child: Text(bindingEmail ? '保存中…' : '保存密码'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:
                  theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_outlined),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '当前是免邮箱账号。绑定邮箱不会丢失现有照片配置，绑定后可在新手机登录。',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: emailController,
            readOnly: emailCodeSent,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              labelText: '绑定邮箱',
              hintText: '请输入能正常收信的邮箱',
              prefixIcon: const Icon(Icons.email_outlined),
              suffixIcon: emailCodeSent
                  ? IconButton(
                      onPressed: bindingEmail ? null : _changeBindingEmail,
                      tooltip: '更换邮箱',
                      icon: const Icon(Icons.edit_outlined),
                    )
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: sendingEmailCode ||
                    bindingEmail ||
                    saving ||
                    emailCodeCooldown > 0
                ? null
                : sendEmailCode,
            icon: sendingEmailCode
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.mark_email_read_outlined),
            label: Text(
              sendingEmailCode
                  ? '发送中…'
                  : emailCodeCooldown > 0
                      ? '$emailCodeCooldown 秒后可重新发送'
                      : emailCodeSent
                          ? '重新发送验证码'
                          : '发送邮箱验证码',
            ),
          ),
          if (emailCodeSent) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.primary),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '确认邮箱',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('输入邮件中的验证码，再设置以后登录使用的密码。'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailCodeController,
                    focusNode: emailCodeFocusNode,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '6 位验证码',
                      prefixIcon: Icon(Icons.password_outlined),
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                  if (bindingNeedsPassword) ...[
                    const SizedBox(height: 10),
                    _passwordFields(),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: bindingEmail || saving ? null : bindEmail,
                    icon: bindingEmail
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_user_outlined),
                    label: Text(bindingEmail ? '确认中…' : '确认绑定'),
                  ),
                ],
              ),
            ),
          ],
        ],
        if (accountMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            accountMessage!,
            style: TextStyle(
              color: accountMessageIsError
                  ? theme.colorScheme.error
                  : Colors.green.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _passwordFields() {
    return Column(
      children: [
        TextField(
          controller: passwordController,
          obscureText: true,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          decoration: const InputDecoration(
            labelText: '登录密码（至少 6 位）',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: confirmPasswordController,
          obscureText: true,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) {
            if (!bindingEmail) {
              if (boundEmail == null) {
                bindEmail();
              } else {
                updateLoginPassword();
              }
            }
          },
          decoration: const InputDecoration(
            labelText: '再次输入密码',
            prefixIcon: Icon(Icons.lock_person_outlined),
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _customCardsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '自定义卡片',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              onPressed: () async {
                final card = await _openCardEditor();
                if (card != null) {
                  await updateCustomCards([...customCards, card]);
                }
              },
              icon: const Icon(Icons.add_circle_outline),
              tooltip: '添加卡片',
            ),
          ],
        ),
        Text(
          '一级卡片是主题，按日期或节日的规则配置在二级分组中。',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (customCards.isEmpty)
          Card(
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('还没有自定义卡片'),
              subtitle: const Text('例如：旅行、第一次见面、春节'),
              trailing: const Icon(Icons.add),
              onTap: () async {
                final card = await _openCardEditor();
                if (card != null) {
                  await updateCustomCards([...customCards, card]);
                }
              },
            ),
          )
        else
          for (var index = 0; index < customCards.length; index++)
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.folder_special_outlined),
                ),
                title: Text(customCards[index].title),
                subtitle: Text(
                  _customCardDescription(customCards[index]),
                ),
                onTap: () async {
                  final edited = await _openCardEditor(customCards[index]);
                  if (edited != null) {
                    final updated = List<CustomLifeCard>.from(customCards);
                    updated[index] = edited;
                    await updateCustomCards(updated);
                  }
                },
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'delete') {
                      final card = customCards[index];
                      if (builtInLifeCardIds.contains(card.id)) {
                        final updated = List<CustomLifeCard>.from(customCards);
                        updated[index] = CustomLifeCard(
                          id: card.id,
                          title: card.title,
                          subtitle: card.subtitle,
                          subgroups: card.subgroups,
                          enabled: false,
                        );
                        await updateCustomCards(updated);
                      } else {
                        final updated = List<CustomLifeCard>.from(customCards)
                          ..removeAt(index);
                        await updateCustomCards(updated);
                      }
                    } else {
                      final edited = await _openCardEditor(customCards[index]);
                      if (edited != null) {
                        final updated = List<CustomLifeCard>.from(customCards);
                        updated[index] = edited;
                        await updateCustomCards(updated);
                      }
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  String _customCardDescription(CustomLifeCard card) {
    final names = card.subgroups
        .map((subgroup) => subgroup.title)
        .where((title) => title.trim().isNotEmpty)
        .join('、');
    final subgroupSummary = names.isEmpty ? '还没有二级分组' : names;
    return '${card.subtitle.isEmpty ? '自定义主题' : card.subtitle} · $subgroupSummary'
        '${card.enabled ? '' : ' · 已隐藏'}';
  }

  Future<CustomLifeCard?> _openCardEditor([CustomLifeCard? existing]) async {
    return Navigator.of(context).push<CustomLifeCard>(
      MaterialPageRoute(
        builder: (_) => CustomLifeCardEditorPage(existing: existing),
      ),
    );
  }
}

String formatCustomDateEntry(CustomDateEntry entry) {
  if (entry.calendar == CalendarType.lunar) {
    final lunar = Lunar.fromDate(entry.date);
    return '${entry.label.isEmpty ? '' : '${entry.label} · '}'
        '农历${lunar.getMonth()}月${lunar.getDay()}日';
  }
  return '${entry.label.isEmpty ? '' : '${entry.label} · '}${formatDate(entry.date)}';
}
