part of '../main.dart';

/// 应用唯一的配置持有者。
///
/// 替代原先散落在各页面的顶层可变日期变量：配置本身仍是不可变的
/// [LifeDatesConfig]，改动一律通过 [replace] 广播，页面只读不写全局。
class LifeConfigController extends ChangeNotifier {
  LifeConfigController(this._config);

  LifeDatesConfig _config;

  LifeDatesConfig get config => _config;

  /// 当前生效的卡片列表：用户未自定义时回落到内置四张卡。
  List<CustomLifeCard> get lifeCards => _config.effectiveLifeCards;

  Future<void> replace(LifeDatesConfig next) async {
    if (identical(next, _config)) return;
    _config = next;
    notifyListeners();
  }

  Future<void> replaceCards(List<CustomLifeCard> cards) =>
      replace(_config.copyWith(customCards: cards));
}

/// 把控制器挂在 [MaterialApp] 外层，让任意页面（包括 Navigator 新推入的
/// 路由）都能取到同一个实例，用法和 [Theme.of] 一致。
class LifeConfigScope extends InheritedWidget {
  const LifeConfigScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final LifeConfigController controller;

  /// 取回控制器。这里刻意用不注册依赖的 [BuildContext.getInheritedWidgetOfExactType]：
  /// 重建由 [LifeConfigController] 这个 [ChangeNotifier] 负责广播，因此可以在
  /// [State.initState] 之后的异步回调里安全持有并使用它。
  static LifeConfigController of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<LifeConfigScope>();
    assert(scope != null, '未找到 LifeConfigScope：它必须包裹在 MaterialApp 外层。');
    return scope!.controller;
  }

  @override
  bool updateShouldNotify(LifeConfigScope oldWidget) =>
      controller != oldWidget.controller;
}

/// 需要跟随配置刷新的页面混入它。
///
/// 用监听器而不是在 build 里查 InheritedWidget，是为了让异步回调也能安全取值：
/// 只有在 [initState] 期间读过一次 context，之后都持有控制器实例。
mixin LifeConfigListener<T extends StatefulWidget> on State<T> {
  late final LifeConfigController lifeConfig;

  @override
  void initState() {
    super.initState();
    lifeConfig = LifeConfigScope.of(context);
    lifeConfig.addListener(_onLifeConfigChanged);
  }

  void _onLifeConfigChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    lifeConfig.removeListener(_onLifeConfigChanged);
    super.dispose();
  }
}
