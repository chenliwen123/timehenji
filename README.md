# 时间痕迹

用照片和真实事件记录时间留下的痕迹。

安卓 App，Flutter 编写。它读取本机相册的全部照片，按拍摄日期自动归类到"人生卡片"上，并围绕这些日期做回顾和纪念。

## 它做什么

- 读取本机相册，按拍摄日期建立照片索引（照片不上云，只存本机）
- 按规则自动归类：人生第 N 天、结婚/毕业/工作周年与整百天、农历节日、生日
- 自定义卡片和二级分组，可以手动把照片绑到某个分组
- 每天第一次打开时回顾"往年的今天"，配上烟花庆祝动画
- 记录连续留痕并解锁成就
- 邮箱注册或免邮箱匿名登录，用于跨设备同步配置

## 哪些数据上云

只有 `life_settings` 表里的一行：几个纪念日期，以及卡片分组的 JSON（`custom_cards`）。

照片本体和照片索引（`assetId` + 拍摄日期）都存在设备本地 SharedPreferences，不上传、不同步。换设备后重新授予相册权限即可重建索引。

表结构和 RLS 策略见 `supabase_setup.sql`；从旧版本升级的库用 `supabase_cleanup_legacy.sql` 清理废弃对象。

## 项目结构

单库结构：`lib/main.dart` 用 `part` 声明把 `lib/src/` 下的文件拼成一个 Dart library。

| 文件 | 职责 |
| --- | --- |
| `main.dart` | 入口、Supabase 初始化 |
| `src/auth.dart` | Material 配置、登录/注册/匿名登录页 |
| `src/home.dart` | 首页：计数器、里程碑、成就、每日庆祝 |
| `src/life_cards.dart` | `CustomLifeCard` / 二级分组模型，按已填日期生成内置卡片 |
| `src/config_scope.dart` | `LifeConfigController` + `LifeConfigScope`，配置的单一来源 |
| `src/life_dates_editor.dart` | 纪念日期编辑页，未登录也能用（只写本机） |
| `src/card_editor.dart` | 卡片和分组的编辑界面 |
| `src/photo_matching.dart` | 照片与卡片规则的匹配引擎 |
| `src/memory_models.dart` | 日期计算、每日回顾分组、里程碑 |
| `src/photo_browse.dart` | 相册浏览 |
| `src/photo_organize.dart` | 待整理照片的归组流程 |
| `src/storage.dart` | `LifeDatesConfig` 读写：本机 + 云端 |
| `src/achievements.dart` | 留痕行为与成就解锁 |
| `src/celebration.dart` | 庆祝动画、每日回顾弹窗 |
| `src/settings.dart` | 设置页：日期入口、账号绑定、每日回顾开关 |

## 首次启动

App 不预置任何人的真实日期。四个纪念日期（生日、结婚纪念日、毕业纪念日、入职纪念日）
都是可空字段：没填就不生成对应卡片，首页会显示"还没有纪念日期"的填写引导。
自定义卡片可以随时增删，不依赖这四个日期。

## 开发

环境准备、Supabase 配置、运行和打包步骤见 [小白开始指南](小白开始指南.md)。

```powershell
flutter pub get
flutter run --dart-define-from-file=env.json   # env.json 不提交，参考 env.example.json
flutter analyze
flutter test
```
