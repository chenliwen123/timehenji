part of '../main.dart';

class LifeDatesConfig {
  const LifeDatesConfig({
    this.birthDate,
    this.marriageDate,
    this.graduationDate,
    this.workDate,
    this.customCards = const [],
  });

  /// 四个纪念日都可为空：空表示用户还没填，此时不生成对应的内置卡片，
  /// 也不参与照片归类——过去它们被写死成开发者本人的真实日期。
  final DateTime? birthDate;
  final DateTime? marriageDate;
  final DateTime? graduationDate;
  final DateTime? workDate;
  final List<CustomLifeCard> customCards;

  static const defaults = LifeDatesConfig();

  bool get hasAnyLifeDate =>
      birthDate != null ||
      marriageDate != null ||
      graduationDate != null ||
      workDate != null;

  factory LifeDatesConfig.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(String key) =>
        DateTime.tryParse(json[key]?.toString() ?? '');
    final birth = parseDate('birth_date');
    final marriage = parseDate('marriage_date');
    final graduation = parseDate('graduation_date');
    final work = parseDate('work_date');
    final storedCards = parseCustomCards(json['custom_cards']);
    return LifeDatesConfig(
      birthDate: birth,
      marriageDate: marriage,
      graduationDate: graduation,
      workDate: work,
      customCards: normalizeLifeCards(
        storedCards,
        birth: birth,
        marriage: marriage,
        graduation: graduation,
        work: work,
      ),
    );
  }

  Map<String, dynamic> datesJson() => {
        if (birthDate != null) 'birth_date': dateKey(birthDate!),
        if (marriageDate != null) 'marriage_date': dateKey(marriageDate!),
        if (graduationDate != null) 'graduation_date': dateKey(graduationDate!),
        if (workDate != null) 'work_date': dateKey(workDate!),
      };

  /// 写回云端时用：四个键始终存在，未填写的写 null。
  /// upsert 只会更新请求里出现的列，省略 key 会让"清除某个日期"失效。
  Map<String, dynamic> toJson() => {
        'birth_date': birthDate == null ? null : dateKey(birthDate!),
        'marriage_date': marriageDate == null ? null : dateKey(marriageDate!),
        'graduation_date':
            graduationDate == null ? null : dateKey(graduationDate!),
        'work_date': workDate == null ? null : dateKey(workDate!),
        'custom_cards': customCards.map((card) => card.toJson()).toList(),
      };

  /// 只做"填入新值"，无法把某个日期清空回未填状态；
  /// 需要清空时（纪念日编辑器里的"清除"）直接重新构造 [LifeDatesConfig]。
  LifeDatesConfig copyWith({
    DateTime? birthDate,
    DateTime? marriageDate,
    DateTime? graduationDate,
    DateTime? workDate,
    List<CustomLifeCard>? customCards,
  }) {
    return LifeDatesConfig(
      birthDate: birthDate ?? this.birthDate,
      marriageDate: marriageDate ?? this.marriageDate,
      graduationDate: graduationDate ?? this.graduationDate,
      workDate: workDate ?? this.workDate,
      customCards: customCards ?? this.customCards,
    );
  }

  /// 用户没自定义任何卡片时展示内置卡片。
  List<CustomLifeCard> get effectiveLifeCards => customCards.isEmpty
      ? builtInLifeCards(
          birth: birthDate,
          marriage: marriageDate,
          graduation: graduationDate,
          work: workDate,
        )
      : customCards;
}

/// 本机保存的纪念日期。未登录时这是唯一数据来源；登录后它用来在云端
/// 返回之前先把首页渲染出来。
Future<LifeDatesConfig> loadLocalLifeDates() async {
  final preferences = await SharedPreferences.getInstance();
  final stored = preferences.getString(localLifeDatesKey);
  Map<String, dynamic> dates = const {};
  if (stored != null) {
    try {
      final decoded = jsonDecode(stored);
      if (decoded is Map) dates = Map<String, dynamic>.from(decoded);
    } catch (_) {
      dates = const {};
    }
  }
  return LifeDatesConfig.fromJson({
    ...dates,
    'custom_cards': await loadMergedCustomCards(null),
  });
}

Future<void> saveLocalLifeDates(LifeDatesConfig config) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(
    localLifeDatesKey,
    jsonEncode(config.datesJson()),
  );
}

Future<LifeDatesConfig> loadLifeDates(SupabaseClient client) async {
  try {
    final row = await client.from('life_settings').select().maybeSingle();
    return await configFromRemoteRow(row);
  } on PostgrestException catch (exception) {
    if (isMissingCustomCardsColumn(exception)) {
      final row = await client
          .from('life_settings')
          .select(
            'birth_date,marriage_date,graduation_date,work_date',
          )
          .maybeSingle();
      return await configFromRemoteRow(row, withRemoteCards: false);
    }
    if (isMissingLifeSettingsTable(exception)) {
      return await loadLocalLifeDates();
    }
    rethrow;
  }
}

/// 合并云端记录和本机数据：
/// - 云端没有记录时完全用本机；
/// - 云端有记录但一个日期都没填时保留本机日期，
///   避免"另一台设备只同步了卡片"就把这台设备填好的日期抹掉。
Future<LifeDatesConfig> configFromRemoteRow(
  Map<String, dynamic>? row, {
  bool withRemoteCards = true,
}) async {
  if (row == null) return await loadLocalLifeDates();
  final remote = LifeDatesConfig.fromJson({
    ...row,
    'custom_cards': await loadMergedCustomCards(
      withRemoteCards ? row['custom_cards'] : null,
    ),
  });
  if (remote.hasAnyLifeDate) return remote;
  final local = await loadLocalLifeDates();
  if (!local.hasAnyLifeDate) return remote;
  return LifeDatesConfig(
    birthDate: local.birthDate,
    marriageDate: local.marriageDate,
    graduationDate: local.graduationDate,
    workDate: local.workDate,
    customCards: remote.customCards,
  );
}

/// 保存配置。无论是否登录都会写本机；只有在已登录时同步到云端。
/// 返回 true 表示云端同步成功，false 表示仅保存在本机。
Future<bool> saveLifeDates(
  SupabaseClient? client,
  LifeDatesConfig config,
) async {
  await saveLocalCustomCards(config.customCards);
  await saveLocalLifeDates(config);
  final user = client?.auth.currentUser;
  final userId = user?.id;
  if (client == null || userId == null) return false;
  try {
    await client.from('life_settings').upsert({
      'owner_id': userId,
      ...config.toJson(),
    });
  } on PostgrestException catch (exception) {
    if (!isMissingCustomCardsColumn(exception)) rethrow;
    await client.from('life_settings').upsert({
      'owner_id': userId,
      ...config.toJson()..remove('custom_cards'),
    });
  }
  return true;
}

Future<List<Map<String, dynamic>>> loadLocalCustomCards() async {
  final preferences = await SharedPreferences.getInstance();
  final value = preferences.getString(localCustomCardsKey);
  if (value == null) return [];
  final decoded = jsonDecode(value);
  return decoded is List
      ? decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
      : [];
}

Future<void> saveLocalCustomCards(List<CustomLifeCard> cards) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(
    localCustomCardsKey,
    jsonEncode(cards.map((card) => card.toJson()).toList()),
  );
}

Future<List<MemoryPhoto>> loadCachedMemoryPhotos() {
  final existing = cachedMemoryPhotos;
  if (existing != null) return Future.value(existing);
  return cachedMemoryPhotosFuture ??= _readCachedMemoryPhotos();
}

Future<List<MemoryPhoto>> _readCachedMemoryPhotos() async {
  final preferences = await SharedPreferences.getInstance();
  final stored = preferences.getStringList('marriage_memory_photos') ?? [];
  final cached = <MemoryPhoto>[];
  for (var index = 0; index < stored.length; index++) {
    try {
      final photo = MemoryPhoto.fromJson(jsonDecode(stored[index]));
      if (photo != null) cached.add(photo);
    } catch (_) {
      continue;
    }
    if (index > 0 && index % 100 == 0) {
      await Future<void>.delayed(Duration.zero);
    }
  }
  cachedMemoryPhotos = cached;
  return cached;
}

void cacheMemoryPhotos(List<MemoryPhoto> photos) {
  cachedMemoryPhotos = photos;
  cachedMemoryPhotosFuture = Future.value(photos);
}

Future<void> saveMemoryPhotos(List<MemoryPhoto> photos) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setStringList(
    memoryPhotosStorageKey,
    photos.map((photo) => jsonEncode(photo.toJson())).toList(),
  );
  cacheMemoryPhotos(photos);
}

Future<List<MemoryPhoto>?> syncAllMemoryPhotos(LifeDatesConfig config) async {
  final permission = await PhotoManager.requestPermissionExtend();
  if (!permission.isAuth && !permission.hasAccess) return null;

  final cached = await loadCachedMemoryPhotos();
  final manualTopics = <String, String>{};
  final manualTopicIds = <String, String>{};
  final manualCategories = <String, String>{};
  final manualCategoryIds = <String, String>{};
  final addedAtByKey = <String, DateTime>{};
  for (final photo in cached) {
    final key = photo.identityKey;
    final manualTopic = photo.manualTopic;
    final manualTopicId = photo.manualTopicId;
    final manualCategory = photo.manualCategory;
    final manualCategoryId = photo.manualCategoryId;
    if (key != null) addedAtByKey[key] = photo.addedAt;
    if (key != null && manualTopic != null) manualTopics[key] = manualTopic;
    if (key != null && manualTopicId != null) {
      manualTopicIds[key] = manualTopicId;
    }
    if (key != null && manualCategory != null) {
      manualCategories[key] = manualCategory;
    }
    if (key != null && manualCategoryId != null) {
      manualCategoryIds[key] = manualCategoryId;
    }
  }

  final count = await PhotoManager.getAssetCount(type: RequestType.image);
  final imported = <MemoryPhoto>[];
  const pageSize = 100;
  for (var page = 0; page * pageSize < count; page++) {
    final assets = await PhotoManager.getAssetListPaged(
      page: page,
      pageCount: pageSize,
      type: RequestType.image,
    );
    if (assets.isEmpty) break;
    for (final asset in assets) {
      final captureDate = dateOnly(asset.createDateTime);
      imported.add(
        MemoryPhoto(
          assetId: asset.id,
          asset: asset,
          category: config.classifyPhotoDate(captureDate),
          captureDate: captureDate,
          addedAt: addedAtByKey[asset.id] ?? DateTime.now(),
          manualTopic: manualTopics[asset.id],
          manualTopicId: manualTopicIds[asset.id],
          manualCategory: manualCategories[asset.id],
          manualCategoryId: manualCategoryIds[asset.id],
        ),
      );
    }
  }
  imported.sort((left, right) => right.captureDate.compareTo(left.captureDate));
  final keptAssetIds = {
    for (final photo in imported)
      if (photo.assetId != null) photo.assetId!,
  };
  memoryPhotoAssetFutures.removeWhere((key, _) => !keptAssetIds.contains(key));
  await saveMemoryPhotos(imported);
  return imported;
}

bool isMissingLifeSettingsTable(PostgrestException exception) {
  return exception.code == 'PGRST205' ||
      exception.code == '404' ||
      exception.message.contains('life_settings');
}

bool isMissingCustomCardsColumn(PostgrestException exception) {
  final message = exception.message.toLowerCase();
  return message.contains('custom_cards') &&
      (exception.code == 'PGRST204' ||
          exception.code == '42703' ||
          message.contains('column'));
}
