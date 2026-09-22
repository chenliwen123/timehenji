import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lunar/lunar.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'src/life_cards.dart';
part 'src/config_scope.dart';
part 'src/storage.dart';
part 'src/life_dates_editor.dart';
part 'src/auth.dart';
part 'src/home.dart';
part 'src/settings.dart';
part 'src/card_editor.dart';
part 'src/photo_matching.dart';
part 'src/photo_organize.dart';
part 'src/photo_browse.dart';
part 'src/memory_models.dart';
part 'src/achievements.dart';
part 'src/celebration.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SupabaseClient? client;
  String? startupError;
  if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
    startupError = '还没有配置 Supabase 地址和密钥。';
  } else {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabasePublishableKey,
      );
      client = Supabase.instance.client;
    } catch (error) {
      startupError = 'Supabase 初始化失败：$error';
    }
  }
  runApp(LifeAchievementsApp(client: client, startupError: startupError));
}
