part of '../main.dart';

class LifeAchievementsApp extends StatefulWidget {
  const LifeAchievementsApp({
    super.key,
    required this.client,
    this.startupError,
  });

  final SupabaseClient? client;
  final String? startupError;

  @override
  State<LifeAchievementsApp> createState() => _LifeAchievementsAppState();
}

class _LifeAchievementsAppState extends State<LifeAchievementsApp> {
  /// 整棵 widget 树共享的配置容器；首页负责首次加载与云端刷新。
  late final LifeConfigController controller =
      LifeConfigController(LifeDatesConfig.defaults);

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xff6750a4);
    return LifeConfigScope(
      controller: controller,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '时间痕迹',
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('en', 'US'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: primary),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xfffaf8ff),
        ),
        home: widget.client == null
            ? AuthGate(client: null, startupError: widget.startupError)
            : AuthGate(client: widget.client!),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.client, this.startupError});

  final SupabaseClient? client;
  final String? startupError;

  @override
  Widget build(BuildContext context) {
    final supabase = client;
    if (supabase == null) {
      return GuestEntryPage(message: startupError ?? '暂时无法连接云端账号。');
    }
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (supabase.auth.currentSession == null) {
          return LoginPage(client: supabase);
        }
        return LifeHomePage(client: supabase);
      },
    );
  }
}

class ConfigurationPage extends StatelessWidget {
  const ConfigurationPage({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class GuestEntryPage extends StatelessWidget {
  const GuestEntryPage({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LifeHomePage()),
                ),
                child: const Text('暂不登录，先看看'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.client});

  final SupabaseClient client;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isRegistering = false;
  bool loading = false;
  String? error;

  Future<void> submit() async {
    final email = emailController.text.trim();
    final password = passwordController.text;
    if (email.isEmpty || !email.contains('@') || password.length < 6) {
      setState(() => error = '请输入正确邮箱，密码至少 6 位。');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (isRegistering) {
        final response = await widget.client.auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: authRedirectUrl,
        );
        if (!mounted) return;
        if (response.session == null) {
          setState(() {
            loading = false;
            error = '注册成功，请先查收邮件并完成验证，再登录。';
          });
        }
      } else {
        await widget.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }
    } on AuthException catch (exception) {
      if (mounted) setState(() => error = authMessage(exception.message));
    } catch (exception) {
      if (mounted) setState(() => error = '操作失败：$exception');
    } finally {
      if (mounted && widget.client.auth.currentSession == null) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> signInAnonymously() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await widget.client.auth.signInAnonymously();
    } on AuthException catch (exception) {
      if (mounted) {
        setState(() {
          error = exception.message.contains('Anonymous sign-ins are disabled')
              ? '云端还没有开启匿名登录，请在 Supabase 的 Authentication → Providers 中开启 Anonymous Sign-Ins。'
              : authMessage(exception.message);
        });
      }
    } catch (exception) {
      if (mounted) setState(() => error = '免邮箱登录失败：$exception');
    } finally {
      if (mounted && widget.client.auth.currentSession == null) {
        setState(() => loading = false);
      }
    }
  }

  String authMessage(String message) {
    if (message.contains('Invalid login credentials')) return '邮箱或密码不正确。';
    if (message.contains('User already registered')) return '这个邮箱已经注册过了，请直接登录。';
    if (message.contains('Email not confirmed')) return '请先完成邮箱验证，再登录。';
    return message;
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.auto_awesome,
                      size: 64, color: colorScheme.primary),
                  const SizedBox(height: 16),
                  const Text(
                    '时间痕迹',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '登录后保存你的成就，也可以和妻子共享结婚空间。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: '邮箱',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '密码',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, style: TextStyle(color: colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: loading ? null : submit,
                    child: Text(
                      loading ? '处理中…' : (isRegistering ? '注册账号' : '登录'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: loading ? null : signInAnonymously,
                    icon: const Icon(Icons.flash_on_outlined),
                    label: const Text('免邮箱登录'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '无需收邮件，直接创建云端账号',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  TextButton(
                    onPressed: loading
                        ? null
                        : () => setState(() {
                              isRegistering = !isRegistering;
                              error = null;
                            }),
                    child: Text(isRegistering ? '已有账号？去登录' : '没有账号？注册一个'),
                  ),
                  OutlinedButton(
                    onPressed: loading
                        ? null
                        : () => Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                  builder: (_) => const LifeHomePage()),
                            ),
                    child: const Text('暂不登录'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
