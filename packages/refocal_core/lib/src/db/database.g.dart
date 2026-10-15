// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $AssetsTable extends Assets with TableInfo<$AssetsTable, AssetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inboxPathMeta = const VerificationMeta('inboxPath');
  @override
  late final GeneratedColumn<String> inboxPath = GeneratedColumn<String>(
    'inbox_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, inboxPath, width, height, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'assets';
  @override
  VerificationContext validateIntegrity(Insertable<AssetRow> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('inbox_path')) {
      context.handle(
        _inboxPathMeta,
        inboxPath.isAcceptableOrUnknown(data['inbox_path']!, _inboxPathMeta),
      );
    } else if (isInserting) {
      context.missing(_inboxPathMeta);
    }
    if (data.containsKey('width')) {
      context.handle(_widthMeta, width.isAcceptableOrUnknown(data['width']!, _widthMeta));
    }
    if (data.containsKey('height')) {
      context.handle(_heightMeta, height.isAcceptableOrUnknown(data['height']!, _heightMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AssetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssetRow(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      inboxPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}inbox_path'],
      )!,
      width: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}width']),
      height: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}height']),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AssetsTable createAlias(String alias) {
    return $AssetsTable(attachedDatabase, alias);
  }
}

class AssetRow extends DataClass implements Insertable<AssetRow> {
  final String id;
  final String inboxPath;
  final int? width;
  final int? height;
  final int createdAt;
  const AssetRow({
    required this.id,
    required this.inboxPath,
    this.width,
    this.height,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['inbox_path'] = Variable<String>(inboxPath);
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  AssetsCompanion toCompanion(bool nullToAbsent) {
    return AssetsCompanion(
      id: Value(id),
      inboxPath: Value(inboxPath),
      width: width == null && nullToAbsent ? const Value.absent() : Value(width),
      height: height == null && nullToAbsent ? const Value.absent() : Value(height),
      createdAt: Value(createdAt),
    );
  }

  factory AssetRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssetRow(
      id: serializer.fromJson<String>(json['id']),
      inboxPath: serializer.fromJson<String>(json['inboxPath']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'inboxPath': serializer.toJson<String>(inboxPath),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  AssetRow copyWith({
    String? id,
    String? inboxPath,
    Value<int?> width = const Value.absent(),
    Value<int?> height = const Value.absent(),
    int? createdAt,
  }) => AssetRow(
    id: id ?? this.id,
    inboxPath: inboxPath ?? this.inboxPath,
    width: width.present ? width.value : this.width,
    height: height.present ? height.value : this.height,
    createdAt: createdAt ?? this.createdAt,
  );
  AssetRow copyWithCompanion(AssetsCompanion data) {
    return AssetRow(
      id: data.id.present ? data.id.value : this.id,
      inboxPath: data.inboxPath.present ? data.inboxPath.value : this.inboxPath,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssetRow(')
          ..write('id: $id, ')
          ..write('inboxPath: $inboxPath, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, inboxPath, width, height, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssetRow &&
          other.id == this.id &&
          other.inboxPath == this.inboxPath &&
          other.width == this.width &&
          other.height == this.height &&
          other.createdAt == this.createdAt);
}

class AssetsCompanion extends UpdateCompanion<AssetRow> {
  final Value<String> id;
  final Value<String> inboxPath;
  final Value<int?> width;
  final Value<int?> height;
  final Value<int> createdAt;
  final Value<int> rowid;
  const AssetsCompanion({
    this.id = const Value.absent(),
    this.inboxPath = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssetsCompanion.insert({
    required String id,
    required String inboxPath,
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       inboxPath = Value(inboxPath),
       createdAt = Value(createdAt);
  static Insertable<AssetRow> custom({
    Expression<String>? id,
    Expression<String>? inboxPath,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (inboxPath != null) 'inbox_path': inboxPath,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssetsCompanion copyWith({
    Value<String>? id,
    Value<String>? inboxPath,
    Value<int?>? width,
    Value<int?>? height,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return AssetsCompanion(
      id: id ?? this.id,
      inboxPath: inboxPath ?? this.inboxPath,
      width: width ?? this.width,
      height: height ?? this.height,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (inboxPath.present) {
      map['inbox_path'] = Variable<String>(inboxPath.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssetsCompanion(')
          ..write('id: $id, ')
          ..write('inboxPath: $inboxPath, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecipesTable extends Recipes with TableInfo<$RecipesTable, RecipeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecipesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaMeta = const VerificationMeta('schema');
  @override
  late final GeneratedColumn<int> schema = GeneratedColumn<int>(
    'schema',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, schema, json, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recipes';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecipeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('schema')) {
      context.handle(_schemaMeta, schema.isAcceptableOrUnknown(data['schema']!, _schemaMeta));
    } else if (isInserting) {
      context.missing(_schemaMeta);
    }
    if (data.containsKey('json')) {
      context.handle(_jsonMeta, json.isAcceptableOrUnknown(data['json']!, _jsonMeta));
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecipeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecipeRow(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      schema: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema'],
      )!,
      json: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}json'])!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $RecipesTable createAlias(String alias) {
    return $RecipesTable(attachedDatabase, alias);
  }
}

class RecipeRow extends DataClass implements Insertable<RecipeRow> {
  final String id;
  final int schema;
  final String json;
  final int createdAt;
  const RecipeRow({
    required this.id,
    required this.schema,
    required this.json,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['schema'] = Variable<int>(schema);
    map['json'] = Variable<String>(json);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  RecipesCompanion toCompanion(bool nullToAbsent) {
    return RecipesCompanion(
      id: Value(id),
      schema: Value(schema),
      json: Value(json),
      createdAt: Value(createdAt),
    );
  }

  factory RecipeRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecipeRow(
      id: serializer.fromJson<String>(json['id']),
      schema: serializer.fromJson<int>(json['schema']),
      json: serializer.fromJson<String>(json['json']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'schema': serializer.toJson<int>(schema),
      'json': serializer.toJson<String>(json),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  RecipeRow copyWith({String? id, int? schema, String? json, int? createdAt}) => RecipeRow(
    id: id ?? this.id,
    schema: schema ?? this.schema,
    json: json ?? this.json,
    createdAt: createdAt ?? this.createdAt,
  );
  RecipeRow copyWithCompanion(RecipesCompanion data) {
    return RecipeRow(
      id: data.id.present ? data.id.value : this.id,
      schema: data.schema.present ? data.schema.value : this.schema,
      json: data.json.present ? data.json.value : this.json,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecipeRow(')
          ..write('id: $id, ')
          ..write('schema: $schema, ')
          ..write('json: $json, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, schema, json, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecipeRow &&
          other.id == this.id &&
          other.schema == this.schema &&
          other.json == this.json &&
          other.createdAt == this.createdAt);
}

class RecipesCompanion extends UpdateCompanion<RecipeRow> {
  final Value<String> id;
  final Value<int> schema;
  final Value<String> json;
  final Value<int> createdAt;
  final Value<int> rowid;
  const RecipesCompanion({
    this.id = const Value.absent(),
    this.schema = const Value.absent(),
    this.json = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecipesCompanion.insert({
    required String id,
    required int schema,
    required String json,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       schema = Value(schema),
       json = Value(json),
       createdAt = Value(createdAt);
  static Insertable<RecipeRow> custom({
    Expression<String>? id,
    Expression<int>? schema,
    Expression<String>? json,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (schema != null) 'schema': schema,
      if (json != null) 'json': json,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecipesCompanion copyWith({
    Value<String>? id,
    Value<int>? schema,
    Value<String>? json,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return RecipesCompanion(
      id: id ?? this.id,
      schema: schema ?? this.schema,
      json: json ?? this.json,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (schema.present) {
      map['schema'] = Variable<int>(schema.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecipesCompanion(')
          ..write('id: $id, ')
          ..write('schema: $schema, ')
          ..write('json: $json, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HistoryTable extends History with TableInfo<$HistoryTable, HistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _assetIdMeta = const VerificationMeta('assetId');
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('REFERENCES assets (id)'),
  );
  static const VerificationMeta _recipeIdMeta = const VerificationMeta('recipeId');
  @override
  late final GeneratedColumn<String> recipeId = GeneratedColumn<String>(
    'recipe_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('REFERENCES recipes (id)'),
  );
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
    'job_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resultUriMeta = const VerificationMeta('resultUri');
  @override
  late final GeneratedColumn<String> resultUri = GeneratedColumn<String>(
    'result_uri',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _previewPathMeta = const VerificationMeta('previewPath');
  @override
  late final GeneratedColumn<String> previewPath = GeneratedColumn<String>(
    'preview_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelIdsMeta = const VerificationMeta('modelIds');
  @override
  late final GeneratedColumn<String> modelIds = GeneratedColumn<String>(
    'model_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _backendMeta = const VerificationMeta('backend');
  @override
  late final GeneratedColumn<String> backend = GeneratedColumn<String>(
    'backend',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta('durationMs');
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    assetId,
    recipeId,
    jobId,
    resultUri,
    previewPath,
    width,
    height,
    modelIds,
    backend,
    durationMs,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'history';
  @override
  VerificationContext validateIntegrity(
    Insertable<HistoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('asset_id')) {
      context.handle(_assetIdMeta, assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta));
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    if (data.containsKey('recipe_id')) {
      context.handle(
        _recipeIdMeta,
        recipeId.isAcceptableOrUnknown(data['recipe_id']!, _recipeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recipeIdMeta);
    }
    if (data.containsKey('job_id')) {
      context.handle(_jobIdMeta, jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta));
    } else if (isInserting) {
      context.missing(_jobIdMeta);
    }
    if (data.containsKey('result_uri')) {
      context.handle(
        _resultUriMeta,
        resultUri.isAcceptableOrUnknown(data['result_uri']!, _resultUriMeta),
      );
    } else if (isInserting) {
      context.missing(_resultUriMeta);
    }
    if (data.containsKey('preview_path')) {
      context.handle(
        _previewPathMeta,
        previewPath.isAcceptableOrUnknown(data['preview_path']!, _previewPathMeta),
      );
    } else if (isInserting) {
      context.missing(_previewPathMeta);
    }
    if (data.containsKey('width')) {
      context.handle(_widthMeta, width.isAcceptableOrUnknown(data['width']!, _widthMeta));
    } else if (isInserting) {
      context.missing(_widthMeta);
    }
    if (data.containsKey('height')) {
      context.handle(_heightMeta, height.isAcceptableOrUnknown(data['height']!, _heightMeta));
    } else if (isInserting) {
      context.missing(_heightMeta);
    }
    if (data.containsKey('model_ids')) {
      context.handle(
        _modelIdsMeta,
        modelIds.isAcceptableOrUnknown(data['model_ids']!, _modelIdsMeta),
      );
    } else if (isInserting) {
      context.missing(_modelIdsMeta);
    }
    if (data.containsKey('backend')) {
      context.handle(_backendMeta, backend.isAcceptableOrUnknown(data['backend']!, _backendMeta));
    } else if (isInserting) {
      context.missing(_backendMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HistoryRow(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      )!,
      recipeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipe_id'],
      )!,
      jobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_id'],
      )!,
      resultUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}result_uri'],
      )!,
      previewPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preview_path'],
      )!,
      width: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}width'])!,
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      )!,
      modelIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_ids'],
      )!,
      backend: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}backend'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $HistoryTable createAlias(String alias) {
    return $HistoryTable(attachedDatabase, alias);
  }
}

class HistoryRow extends DataClass implements Insertable<HistoryRow> {
  final String id;
  final String assetId;
  final String recipeId;

  /// Job directory name under AppSupport/jobs (deleted with the entry, FR-HIST-004).
  final String jobId;
  final String resultUri;
  final String previewPath;
  final int width;
  final int height;

  /// JSON list of the model ids that produced the result.
  final String modelIds;
  final String backend;
  final int? durationMs;
  final int createdAt;
  const HistoryRow({
    required this.id,
    required this.assetId,
    required this.recipeId,
    required this.jobId,
    required this.resultUri,
    required this.previewPath,
    required this.width,
    required this.height,
    required this.modelIds,
    required this.backend,
    this.durationMs,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['asset_id'] = Variable<String>(assetId);
    map['recipe_id'] = Variable<String>(recipeId);
    map['job_id'] = Variable<String>(jobId);
    map['result_uri'] = Variable<String>(resultUri);
    map['preview_path'] = Variable<String>(previewPath);
    map['width'] = Variable<int>(width);
    map['height'] = Variable<int>(height);
    map['model_ids'] = Variable<String>(modelIds);
    map['backend'] = Variable<String>(backend);
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  HistoryCompanion toCompanion(bool nullToAbsent) {
    return HistoryCompanion(
      id: Value(id),
      assetId: Value(assetId),
      recipeId: Value(recipeId),
      jobId: Value(jobId),
      resultUri: Value(resultUri),
      previewPath: Value(previewPath),
      width: Value(width),
      height: Value(height),
      modelIds: Value(modelIds),
      backend: Value(backend),
      durationMs: durationMs == null && nullToAbsent ? const Value.absent() : Value(durationMs),
      createdAt: Value(createdAt),
    );
  }

  factory HistoryRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HistoryRow(
      id: serializer.fromJson<String>(json['id']),
      assetId: serializer.fromJson<String>(json['assetId']),
      recipeId: serializer.fromJson<String>(json['recipeId']),
      jobId: serializer.fromJson<String>(json['jobId']),
      resultUri: serializer.fromJson<String>(json['resultUri']),
      previewPath: serializer.fromJson<String>(json['previewPath']),
      width: serializer.fromJson<int>(json['width']),
      height: serializer.fromJson<int>(json['height']),
      modelIds: serializer.fromJson<String>(json['modelIds']),
      backend: serializer.fromJson<String>(json['backend']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'assetId': serializer.toJson<String>(assetId),
      'recipeId': serializer.toJson<String>(recipeId),
      'jobId': serializer.toJson<String>(jobId),
      'resultUri': serializer.toJson<String>(resultUri),
      'previewPath': serializer.toJson<String>(previewPath),
      'width': serializer.toJson<int>(width),
      'height': serializer.toJson<int>(height),
      'modelIds': serializer.toJson<String>(modelIds),
      'backend': serializer.toJson<String>(backend),
      'durationMs': serializer.toJson<int?>(durationMs),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  HistoryRow copyWith({
    String? id,
    String? assetId,
    String? recipeId,
    String? jobId,
    String? resultUri,
    String? previewPath,
    int? width,
    int? height,
    String? modelIds,
    String? backend,
    Value<int?> durationMs = const Value.absent(),
    int? createdAt,
  }) => HistoryRow(
    id: id ?? this.id,
    assetId: assetId ?? this.assetId,
    recipeId: recipeId ?? this.recipeId,
    jobId: jobId ?? this.jobId,
    resultUri: resultUri ?? this.resultUri,
    previewPath: previewPath ?? this.previewPath,
    width: width ?? this.width,
    height: height ?? this.height,
    modelIds: modelIds ?? this.modelIds,
    backend: backend ?? this.backend,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    createdAt: createdAt ?? this.createdAt,
  );
  HistoryRow copyWithCompanion(HistoryCompanion data) {
    return HistoryRow(
      id: data.id.present ? data.id.value : this.id,
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      recipeId: data.recipeId.present ? data.recipeId.value : this.recipeId,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      resultUri: data.resultUri.present ? data.resultUri.value : this.resultUri,
      previewPath: data.previewPath.present ? data.previewPath.value : this.previewPath,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      modelIds: data.modelIds.present ? data.modelIds.value : this.modelIds,
      backend: data.backend.present ? data.backend.value : this.backend,
      durationMs: data.durationMs.present ? data.durationMs.value : this.durationMs,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HistoryRow(')
          ..write('id: $id, ')
          ..write('assetId: $assetId, ')
          ..write('recipeId: $recipeId, ')
          ..write('jobId: $jobId, ')
          ..write('resultUri: $resultUri, ')
          ..write('previewPath: $previewPath, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('modelIds: $modelIds, ')
          ..write('backend: $backend, ')
          ..write('durationMs: $durationMs, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    assetId,
    recipeId,
    jobId,
    resultUri,
    previewPath,
    width,
    height,
    modelIds,
    backend,
    durationMs,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryRow &&
          other.id == this.id &&
          other.assetId == this.assetId &&
          other.recipeId == this.recipeId &&
          other.jobId == this.jobId &&
          other.resultUri == this.resultUri &&
          other.previewPath == this.previewPath &&
          other.width == this.width &&
          other.height == this.height &&
          other.modelIds == this.modelIds &&
          other.backend == this.backend &&
          other.durationMs == this.durationMs &&
          other.createdAt == this.createdAt);
}

class HistoryCompanion extends UpdateCompanion<HistoryRow> {
  final Value<String> id;
  final Value<String> assetId;
  final Value<String> recipeId;
  final Value<String> jobId;
  final Value<String> resultUri;
  final Value<String> previewPath;
  final Value<int> width;
  final Value<int> height;
  final Value<String> modelIds;
  final Value<String> backend;
  final Value<int?> durationMs;
  final Value<int> createdAt;
  final Value<int> rowid;
  const HistoryCompanion({
    this.id = const Value.absent(),
    this.assetId = const Value.absent(),
    this.recipeId = const Value.absent(),
    this.jobId = const Value.absent(),
    this.resultUri = const Value.absent(),
    this.previewPath = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.modelIds = const Value.absent(),
    this.backend = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HistoryCompanion.insert({
    required String id,
    required String assetId,
    required String recipeId,
    required String jobId,
    required String resultUri,
    required String previewPath,
    required int width,
    required int height,
    required String modelIds,
    required String backend,
    this.durationMs = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       assetId = Value(assetId),
       recipeId = Value(recipeId),
       jobId = Value(jobId),
       resultUri = Value(resultUri),
       previewPath = Value(previewPath),
       width = Value(width),
       height = Value(height),
       modelIds = Value(modelIds),
       backend = Value(backend),
       createdAt = Value(createdAt);
  static Insertable<HistoryRow> custom({
    Expression<String>? id,
    Expression<String>? assetId,
    Expression<String>? recipeId,
    Expression<String>? jobId,
    Expression<String>? resultUri,
    Expression<String>? previewPath,
    Expression<int>? width,
    Expression<int>? height,
    Expression<String>? modelIds,
    Expression<String>? backend,
    Expression<int>? durationMs,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (assetId != null) 'asset_id': assetId,
      if (recipeId != null) 'recipe_id': recipeId,
      if (jobId != null) 'job_id': jobId,
      if (resultUri != null) 'result_uri': resultUri,
      if (previewPath != null) 'preview_path': previewPath,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (modelIds != null) 'model_ids': modelIds,
      if (backend != null) 'backend': backend,
      if (durationMs != null) 'duration_ms': durationMs,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HistoryCompanion copyWith({
    Value<String>? id,
    Value<String>? assetId,
    Value<String>? recipeId,
    Value<String>? jobId,
    Value<String>? resultUri,
    Value<String>? previewPath,
    Value<int>? width,
    Value<int>? height,
    Value<String>? modelIds,
    Value<String>? backend,
    Value<int?>? durationMs,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return HistoryCompanion(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      recipeId: recipeId ?? this.recipeId,
      jobId: jobId ?? this.jobId,
      resultUri: resultUri ?? this.resultUri,
      previewPath: previewPath ?? this.previewPath,
      width: width ?? this.width,
      height: height ?? this.height,
      modelIds: modelIds ?? this.modelIds,
      backend: backend ?? this.backend,
      durationMs: durationMs ?? this.durationMs,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (recipeId.present) {
      map['recipe_id'] = Variable<String>(recipeId.value);
    }
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (resultUri.present) {
      map['result_uri'] = Variable<String>(resultUri.value);
    }
    if (previewPath.present) {
      map['preview_path'] = Variable<String>(previewPath.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (modelIds.present) {
      map['model_ids'] = Variable<String>(modelIds.value);
    }
    if (backend.present) {
      map['backend'] = Variable<String>(backend.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HistoryCompanion(')
          ..write('id: $id, ')
          ..write('assetId: $assetId, ')
          ..write('recipeId: $recipeId, ')
          ..write('jobId: $jobId, ')
          ..write('resultUri: $resultUri, ')
          ..write('previewPath: $previewPath, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('modelIds: $modelIds, ')
          ..write('backend: $backend, ')
          ..write('durationMs: $durationMs, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $QueueJobsTable extends QueueJobs with TableInfo<$QueueJobsTable, QueueJobRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QueueJobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _assetIdMeta = const VerificationMeta('assetId');
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('REFERENCES assets (id)'),
  );
  static const VerificationMeta _recipeIdMeta = const VerificationMeta('recipeId');
  @override
  late final GeneratedColumn<String> recipeId = GeneratedColumn<String>(
    'recipe_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('REFERENCES recipes (id)'),
  );
  @override
  late final GeneratedColumnWithTypeConverter<QueueState, String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<QueueState>($QueueJobsTable.$converterstate);
  static const VerificationMeta _positionMeta = const VerificationMeta('position');
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
    'job_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _progressMeta = const VerificationMeta('progress');
  @override
  late final GeneratedColumn<double> progress = GeneratedColumn<double>(
    'progress',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _errorCodeMeta = const VerificationMeta('errorCode');
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    assetId,
    recipeId,
    state,
    position,
    jobId,
    progress,
    errorCode,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'queue_jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<QueueJobRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('asset_id')) {
      context.handle(_assetIdMeta, assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta));
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    if (data.containsKey('recipe_id')) {
      context.handle(
        _recipeIdMeta,
        recipeId.isAcceptableOrUnknown(data['recipe_id']!, _recipeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recipeIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('job_id')) {
      context.handle(_jobIdMeta, jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta));
    } else if (isInserting) {
      context.missing(_jobIdMeta);
    }
    if (data.containsKey('progress')) {
      context.handle(
        _progressMeta,
        progress.isAcceptableOrUnknown(data['progress']!, _progressMeta),
      );
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  QueueJobRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QueueJobRow(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      )!,
      recipeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipe_id'],
      )!,
      state: $QueueJobsTable.$converterstate.fromSql(
        attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}state'])!,
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      jobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_id'],
      )!,
      progress: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress'],
      )!,
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $QueueJobsTable createAlias(String alias) {
    return $QueueJobsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<QueueState, String, String> $converterstate =
      const EnumNameConverter<QueueState>(QueueState.values);
}

class QueueJobRow extends DataClass implements Insertable<QueueJobRow> {
  final String id;
  final String assetId;
  final String recipeId;
  final QueueState state;

  /// Processing order, ascending; gaps are allowed.
  final int position;

  /// Job directory name under AppSupport/jobs (exists once the job started).
  final String jobId;

  /// Committed bands / all bands.
  final double progress;

  /// `EnhStatus` name of a failure, or "cancelled".
  final String? errorCode;
  final int createdAt;
  final int updatedAt;
  const QueueJobRow({
    required this.id,
    required this.assetId,
    required this.recipeId,
    required this.state,
    required this.position,
    required this.jobId,
    required this.progress,
    this.errorCode,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['asset_id'] = Variable<String>(assetId);
    map['recipe_id'] = Variable<String>(recipeId);
    {
      map['state'] = Variable<String>($QueueJobsTable.$converterstate.toSql(state));
    }
    map['position'] = Variable<int>(position);
    map['job_id'] = Variable<String>(jobId);
    map['progress'] = Variable<double>(progress);
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  QueueJobsCompanion toCompanion(bool nullToAbsent) {
    return QueueJobsCompanion(
      id: Value(id),
      assetId: Value(assetId),
      recipeId: Value(recipeId),
      state: Value(state),
      position: Value(position),
      jobId: Value(jobId),
      progress: Value(progress),
      errorCode: errorCode == null && nullToAbsent ? const Value.absent() : Value(errorCode),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory QueueJobRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QueueJobRow(
      id: serializer.fromJson<String>(json['id']),
      assetId: serializer.fromJson<String>(json['assetId']),
      recipeId: serializer.fromJson<String>(json['recipeId']),
      state: $QueueJobsTable.$converterstate.fromJson(serializer.fromJson<String>(json['state'])),
      position: serializer.fromJson<int>(json['position']),
      jobId: serializer.fromJson<String>(json['jobId']),
      progress: serializer.fromJson<double>(json['progress']),
      errorCode: serializer.fromJson<String?>(json['errorCode']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'assetId': serializer.toJson<String>(assetId),
      'recipeId': serializer.toJson<String>(recipeId),
      'state': serializer.toJson<String>($QueueJobsTable.$converterstate.toJson(state)),
      'position': serializer.toJson<int>(position),
      'jobId': serializer.toJson<String>(jobId),
      'progress': serializer.toJson<double>(progress),
      'errorCode': serializer.toJson<String?>(errorCode),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  QueueJobRow copyWith({
    String? id,
    String? assetId,
    String? recipeId,
    QueueState? state,
    int? position,
    String? jobId,
    double? progress,
    Value<String?> errorCode = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => QueueJobRow(
    id: id ?? this.id,
    assetId: assetId ?? this.assetId,
    recipeId: recipeId ?? this.recipeId,
    state: state ?? this.state,
    position: position ?? this.position,
    jobId: jobId ?? this.jobId,
    progress: progress ?? this.progress,
    errorCode: errorCode.present ? errorCode.value : this.errorCode,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  QueueJobRow copyWithCompanion(QueueJobsCompanion data) {
    return QueueJobRow(
      id: data.id.present ? data.id.value : this.id,
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      recipeId: data.recipeId.present ? data.recipeId.value : this.recipeId,
      state: data.state.present ? data.state.value : this.state,
      position: data.position.present ? data.position.value : this.position,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      progress: data.progress.present ? data.progress.value : this.progress,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QueueJobRow(')
          ..write('id: $id, ')
          ..write('assetId: $assetId, ')
          ..write('recipeId: $recipeId, ')
          ..write('state: $state, ')
          ..write('position: $position, ')
          ..write('jobId: $jobId, ')
          ..write('progress: $progress, ')
          ..write('errorCode: $errorCode, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    assetId,
    recipeId,
    state,
    position,
    jobId,
    progress,
    errorCode,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QueueJobRow &&
          other.id == this.id &&
          other.assetId == this.assetId &&
          other.recipeId == this.recipeId &&
          other.state == this.state &&
          other.position == this.position &&
          other.jobId == this.jobId &&
          other.progress == this.progress &&
          other.errorCode == this.errorCode &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class QueueJobsCompanion extends UpdateCompanion<QueueJobRow> {
  final Value<String> id;
  final Value<String> assetId;
  final Value<String> recipeId;
  final Value<QueueState> state;
  final Value<int> position;
  final Value<String> jobId;
  final Value<double> progress;
  final Value<String?> errorCode;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const QueueJobsCompanion({
    this.id = const Value.absent(),
    this.assetId = const Value.absent(),
    this.recipeId = const Value.absent(),
    this.state = const Value.absent(),
    this.position = const Value.absent(),
    this.jobId = const Value.absent(),
    this.progress = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  QueueJobsCompanion.insert({
    required String id,
    required String assetId,
    required String recipeId,
    required QueueState state,
    required int position,
    required String jobId,
    this.progress = const Value.absent(),
    this.errorCode = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       assetId = Value(assetId),
       recipeId = Value(recipeId),
       state = Value(state),
       position = Value(position),
       jobId = Value(jobId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<QueueJobRow> custom({
    Expression<String>? id,
    Expression<String>? assetId,
    Expression<String>? recipeId,
    Expression<String>? state,
    Expression<int>? position,
    Expression<String>? jobId,
    Expression<double>? progress,
    Expression<String>? errorCode,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (assetId != null) 'asset_id': assetId,
      if (recipeId != null) 'recipe_id': recipeId,
      if (state != null) 'state': state,
      if (position != null) 'position': position,
      if (jobId != null) 'job_id': jobId,
      if (progress != null) 'progress': progress,
      if (errorCode != null) 'error_code': errorCode,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  QueueJobsCompanion copyWith({
    Value<String>? id,
    Value<String>? assetId,
    Value<String>? recipeId,
    Value<QueueState>? state,
    Value<int>? position,
    Value<String>? jobId,
    Value<double>? progress,
    Value<String?>? errorCode,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return QueueJobsCompanion(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      recipeId: recipeId ?? this.recipeId,
      state: state ?? this.state,
      position: position ?? this.position,
      jobId: jobId ?? this.jobId,
      progress: progress ?? this.progress,
      errorCode: errorCode ?? this.errorCode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (recipeId.present) {
      map['recipe_id'] = Variable<String>(recipeId.value);
    }
    if (state.present) {
      map['state'] = Variable<String>($QueueJobsTable.$converterstate.toSql(state.value));
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (progress.present) {
      map['progress'] = Variable<double>(progress.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QueueJobsCompanion(')
          ..write('id: $id, ')
          ..write('assetId: $assetId, ')
          ..write('recipeId: $recipeId, ')
          ..write('state: $state, ')
          ..write('position: $position, ')
          ..write('jobId: $jobId, ')
          ..write('progress: $progress, ')
          ..write('errorCode: $errorCode, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ModelPacksTable extends ModelPacks with TableInfo<$ModelPacksTable, ModelPackRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ModelPacksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta('version');
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _licenseSpdxMeta = const VerificationMeta('licenseSpdx');
  @override
  late final GeneratedColumn<String> licenseSpdx = GeneratedColumn<String>(
    'license_spdx',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _installedAtMeta = const VerificationMeta('installedAt');
  @override
  late final GeneratedColumn<int> installedAt = GeneratedColumn<int>(
    'installed_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    version,
    category,
    path,
    size,
    sha256,
    licenseSpdx,
    installedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'model_packs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ModelPackRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta, version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('path')) {
      context.handle(_pathMeta, path.isAcceptableOrUnknown(data['path']!, _pathMeta));
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('size')) {
      context.handle(_sizeMeta, size.isAcceptableOrUnknown(data['size']!, _sizeMeta));
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(_sha256Meta, sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta));
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('license_spdx')) {
      context.handle(
        _licenseSpdxMeta,
        licenseSpdx.isAcceptableOrUnknown(data['license_spdx']!, _licenseSpdxMeta),
      );
    } else if (isInserting) {
      context.missing(_licenseSpdxMeta);
    }
    if (data.containsKey('installed_at')) {
      context.handle(
        _installedAtMeta,
        installedAt.isAcceptableOrUnknown(data['installed_at']!, _installedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_installedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ModelPackRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ModelPackRow(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      path: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}path'])!,
      size: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}size'])!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      licenseSpdx: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}license_spdx'],
      )!,
      installedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}installed_at'],
      )!,
    );
  }

  @override
  $ModelPacksTable createAlias(String alias) {
    return $ModelPacksTable(attachedDatabase, alias);
  }
}

class ModelPackRow extends DataClass implements Insertable<ModelPackRow> {
  final String id;
  final String version;
  final String category;

  /// Directory relative to AppSupport.
  final String path;

  /// Bytes of the installed files.
  final int size;

  /// SHA-256 of the manifest entry's files, joined in manifest order (what was verified).
  final String sha256;
  final String licenseSpdx;
  final int installedAt;
  const ModelPackRow({
    required this.id,
    required this.version,
    required this.category,
    required this.path,
    required this.size,
    required this.sha256,
    required this.licenseSpdx,
    required this.installedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['version'] = Variable<String>(version);
    map['category'] = Variable<String>(category);
    map['path'] = Variable<String>(path);
    map['size'] = Variable<int>(size);
    map['sha256'] = Variable<String>(sha256);
    map['license_spdx'] = Variable<String>(licenseSpdx);
    map['installed_at'] = Variable<int>(installedAt);
    return map;
  }

  ModelPacksCompanion toCompanion(bool nullToAbsent) {
    return ModelPacksCompanion(
      id: Value(id),
      version: Value(version),
      category: Value(category),
      path: Value(path),
      size: Value(size),
      sha256: Value(sha256),
      licenseSpdx: Value(licenseSpdx),
      installedAt: Value(installedAt),
    );
  }

  factory ModelPackRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ModelPackRow(
      id: serializer.fromJson<String>(json['id']),
      version: serializer.fromJson<String>(json['version']),
      category: serializer.fromJson<String>(json['category']),
      path: serializer.fromJson<String>(json['path']),
      size: serializer.fromJson<int>(json['size']),
      sha256: serializer.fromJson<String>(json['sha256']),
      licenseSpdx: serializer.fromJson<String>(json['licenseSpdx']),
      installedAt: serializer.fromJson<int>(json['installedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'version': serializer.toJson<String>(version),
      'category': serializer.toJson<String>(category),
      'path': serializer.toJson<String>(path),
      'size': serializer.toJson<int>(size),
      'sha256': serializer.toJson<String>(sha256),
      'licenseSpdx': serializer.toJson<String>(licenseSpdx),
      'installedAt': serializer.toJson<int>(installedAt),
    };
  }

  ModelPackRow copyWith({
    String? id,
    String? version,
    String? category,
    String? path,
    int? size,
    String? sha256,
    String? licenseSpdx,
    int? installedAt,
  }) => ModelPackRow(
    id: id ?? this.id,
    version: version ?? this.version,
    category: category ?? this.category,
    path: path ?? this.path,
    size: size ?? this.size,
    sha256: sha256 ?? this.sha256,
    licenseSpdx: licenseSpdx ?? this.licenseSpdx,
    installedAt: installedAt ?? this.installedAt,
  );
  ModelPackRow copyWithCompanion(ModelPacksCompanion data) {
    return ModelPackRow(
      id: data.id.present ? data.id.value : this.id,
      version: data.version.present ? data.version.value : this.version,
      category: data.category.present ? data.category.value : this.category,
      path: data.path.present ? data.path.value : this.path,
      size: data.size.present ? data.size.value : this.size,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      licenseSpdx: data.licenseSpdx.present ? data.licenseSpdx.value : this.licenseSpdx,
      installedAt: data.installedAt.present ? data.installedAt.value : this.installedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ModelPackRow(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('category: $category, ')
          ..write('path: $path, ')
          ..write('size: $size, ')
          ..write('sha256: $sha256, ')
          ..write('licenseSpdx: $licenseSpdx, ')
          ..write('installedAt: $installedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, version, category, path, size, sha256, licenseSpdx, installedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ModelPackRow &&
          other.id == this.id &&
          other.version == this.version &&
          other.category == this.category &&
          other.path == this.path &&
          other.size == this.size &&
          other.sha256 == this.sha256 &&
          other.licenseSpdx == this.licenseSpdx &&
          other.installedAt == this.installedAt);
}

class ModelPacksCompanion extends UpdateCompanion<ModelPackRow> {
  final Value<String> id;
  final Value<String> version;
  final Value<String> category;
  final Value<String> path;
  final Value<int> size;
  final Value<String> sha256;
  final Value<String> licenseSpdx;
  final Value<int> installedAt;
  final Value<int> rowid;
  const ModelPacksCompanion({
    this.id = const Value.absent(),
    this.version = const Value.absent(),
    this.category = const Value.absent(),
    this.path = const Value.absent(),
    this.size = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.licenseSpdx = const Value.absent(),
    this.installedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ModelPacksCompanion.insert({
    required String id,
    required String version,
    required String category,
    required String path,
    required int size,
    required String sha256,
    required String licenseSpdx,
    required int installedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       version = Value(version),
       category = Value(category),
       path = Value(path),
       size = Value(size),
       sha256 = Value(sha256),
       licenseSpdx = Value(licenseSpdx),
       installedAt = Value(installedAt);
  static Insertable<ModelPackRow> custom({
    Expression<String>? id,
    Expression<String>? version,
    Expression<String>? category,
    Expression<String>? path,
    Expression<int>? size,
    Expression<String>? sha256,
    Expression<String>? licenseSpdx,
    Expression<int>? installedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (version != null) 'version': version,
      if (category != null) 'category': category,
      if (path != null) 'path': path,
      if (size != null) 'size': size,
      if (sha256 != null) 'sha256': sha256,
      if (licenseSpdx != null) 'license_spdx': licenseSpdx,
      if (installedAt != null) 'installed_at': installedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ModelPacksCompanion copyWith({
    Value<String>? id,
    Value<String>? version,
    Value<String>? category,
    Value<String>? path,
    Value<int>? size,
    Value<String>? sha256,
    Value<String>? licenseSpdx,
    Value<int>? installedAt,
    Value<int>? rowid,
  }) {
    return ModelPacksCompanion(
      id: id ?? this.id,
      version: version ?? this.version,
      category: category ?? this.category,
      path: path ?? this.path,
      size: size ?? this.size,
      sha256: sha256 ?? this.sha256,
      licenseSpdx: licenseSpdx ?? this.licenseSpdx,
      installedAt: installedAt ?? this.installedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (licenseSpdx.present) {
      map['license_spdx'] = Variable<String>(licenseSpdx.value);
    }
    if (installedAt.present) {
      map['installed_at'] = Variable<int>(installedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ModelPacksCompanion(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('category: $category, ')
          ..write('path: $path, ')
          ..write('size: $size, ')
          ..write('sha256: $sha256, ')
          ..write('licenseSpdx: $licenseSpdx, ')
          ..write('installedAt: $installedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConsentsTable extends Consents with TableInfo<$ConsentsTable, ConsentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConsentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _packIdMeta = const VerificationMeta('packId');
  @override
  late final GeneratedColumn<String> packId = GeneratedColumn<String>(
    'pack_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _packVersionMeta = const VerificationMeta('packVersion');
  @override
  late final GeneratedColumn<String> packVersion = GeneratedColumn<String>(
    'pack_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _licenseSha256Meta = const VerificationMeta('licenseSha256');
  @override
  late final GeneratedColumn<String> licenseSha256 = GeneratedColumn<String>(
    'license_sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _acceptedAtMeta = const VerificationMeta('acceptedAt');
  @override
  late final GeneratedColumn<int> acceptedAt = GeneratedColumn<int>(
    'accepted_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [packId, packVersion, licenseSha256, acceptedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'consents';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConsentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('pack_id')) {
      context.handle(_packIdMeta, packId.isAcceptableOrUnknown(data['pack_id']!, _packIdMeta));
    } else if (isInserting) {
      context.missing(_packIdMeta);
    }
    if (data.containsKey('pack_version')) {
      context.handle(
        _packVersionMeta,
        packVersion.isAcceptableOrUnknown(data['pack_version']!, _packVersionMeta),
      );
    } else if (isInserting) {
      context.missing(_packVersionMeta);
    }
    if (data.containsKey('license_sha256')) {
      context.handle(
        _licenseSha256Meta,
        licenseSha256.isAcceptableOrUnknown(data['license_sha256']!, _licenseSha256Meta),
      );
    } else if (isInserting) {
      context.missing(_licenseSha256Meta);
    }
    if (data.containsKey('accepted_at')) {
      context.handle(
        _acceptedAtMeta,
        acceptedAt.isAcceptableOrUnknown(data['accepted_at']!, _acceptedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_acceptedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {packId, licenseSha256};
  @override
  ConsentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConsentRow(
      packId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pack_id'],
      )!,
      packVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pack_version'],
      )!,
      licenseSha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}license_sha256'],
      )!,
      acceptedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}accepted_at'],
      )!,
    );
  }

  @override
  $ConsentsTable createAlias(String alias) {
    return $ConsentsTable(attachedDatabase, alias);
  }
}

class ConsentRow extends DataClass implements Insertable<ConsentRow> {
  final String packId;
  final String packVersion;
  final String licenseSha256;
  final int acceptedAt;
  const ConsentRow({
    required this.packId,
    required this.packVersion,
    required this.licenseSha256,
    required this.acceptedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['pack_id'] = Variable<String>(packId);
    map['pack_version'] = Variable<String>(packVersion);
    map['license_sha256'] = Variable<String>(licenseSha256);
    map['accepted_at'] = Variable<int>(acceptedAt);
    return map;
  }

  ConsentsCompanion toCompanion(bool nullToAbsent) {
    return ConsentsCompanion(
      packId: Value(packId),
      packVersion: Value(packVersion),
      licenseSha256: Value(licenseSha256),
      acceptedAt: Value(acceptedAt),
    );
  }

  factory ConsentRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConsentRow(
      packId: serializer.fromJson<String>(json['packId']),
      packVersion: serializer.fromJson<String>(json['packVersion']),
      licenseSha256: serializer.fromJson<String>(json['licenseSha256']),
      acceptedAt: serializer.fromJson<int>(json['acceptedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'packId': serializer.toJson<String>(packId),
      'packVersion': serializer.toJson<String>(packVersion),
      'licenseSha256': serializer.toJson<String>(licenseSha256),
      'acceptedAt': serializer.toJson<int>(acceptedAt),
    };
  }

  ConsentRow copyWith({
    String? packId,
    String? packVersion,
    String? licenseSha256,
    int? acceptedAt,
  }) => ConsentRow(
    packId: packId ?? this.packId,
    packVersion: packVersion ?? this.packVersion,
    licenseSha256: licenseSha256 ?? this.licenseSha256,
    acceptedAt: acceptedAt ?? this.acceptedAt,
  );
  ConsentRow copyWithCompanion(ConsentsCompanion data) {
    return ConsentRow(
      packId: data.packId.present ? data.packId.value : this.packId,
      packVersion: data.packVersion.present ? data.packVersion.value : this.packVersion,
      licenseSha256: data.licenseSha256.present ? data.licenseSha256.value : this.licenseSha256,
      acceptedAt: data.acceptedAt.present ? data.acceptedAt.value : this.acceptedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConsentRow(')
          ..write('packId: $packId, ')
          ..write('packVersion: $packVersion, ')
          ..write('licenseSha256: $licenseSha256, ')
          ..write('acceptedAt: $acceptedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(packId, packVersion, licenseSha256, acceptedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConsentRow &&
          other.packId == this.packId &&
          other.packVersion == this.packVersion &&
          other.licenseSha256 == this.licenseSha256 &&
          other.acceptedAt == this.acceptedAt);
}

class ConsentsCompanion extends UpdateCompanion<ConsentRow> {
  final Value<String> packId;
  final Value<String> packVersion;
  final Value<String> licenseSha256;
  final Value<int> acceptedAt;
  final Value<int> rowid;
  const ConsentsCompanion({
    this.packId = const Value.absent(),
    this.packVersion = const Value.absent(),
    this.licenseSha256 = const Value.absent(),
    this.acceptedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConsentsCompanion.insert({
    required String packId,
    required String packVersion,
    required String licenseSha256,
    required int acceptedAt,
    this.rowid = const Value.absent(),
  }) : packId = Value(packId),
       packVersion = Value(packVersion),
       licenseSha256 = Value(licenseSha256),
       acceptedAt = Value(acceptedAt);
  static Insertable<ConsentRow> custom({
    Expression<String>? packId,
    Expression<String>? packVersion,
    Expression<String>? licenseSha256,
    Expression<int>? acceptedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (packId != null) 'pack_id': packId,
      if (packVersion != null) 'pack_version': packVersion,
      if (licenseSha256 != null) 'license_sha256': licenseSha256,
      if (acceptedAt != null) 'accepted_at': acceptedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConsentsCompanion copyWith({
    Value<String>? packId,
    Value<String>? packVersion,
    Value<String>? licenseSha256,
    Value<int>? acceptedAt,
    Value<int>? rowid,
  }) {
    return ConsentsCompanion(
      packId: packId ?? this.packId,
      packVersion: packVersion ?? this.packVersion,
      licenseSha256: licenseSha256 ?? this.licenseSha256,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (packId.present) {
      map['pack_id'] = Variable<String>(packId.value);
    }
    if (packVersion.present) {
      map['pack_version'] = Variable<String>(packVersion.value);
    }
    if (licenseSha256.present) {
      map['license_sha256'] = Variable<String>(licenseSha256.value);
    }
    if (acceptedAt.present) {
      map['accepted_at'] = Variable<int>(acceptedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConsentsCompanion(')
          ..write('packId: $packId, ')
          ..write('packVersion: $packVersion, ')
          ..write('licenseSha256: $licenseSha256, ')
          ..write('acceptedAt: $acceptedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ManifestStateTable extends ManifestState
    with TableInfo<$ManifestStateTable, ManifestStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ManifestStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serialMeta = const VerificationMeta('serial');
  @override
  late final GeneratedColumn<int> serial = GeneratedColumn<int>(
    'serial',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta('fetchedAt');
  @override
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, serial, fetchedAt, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'manifest_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<ManifestStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('serial')) {
      context.handle(_serialMeta, serial.isAcceptableOrUnknown(data['serial']!, _serialMeta));
    } else if (isInserting) {
      context.missing(_serialMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    if (data.containsKey('json')) {
      context.handle(_jsonMeta, json.isAcceptableOrUnknown(data['json']!, _jsonMeta));
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ManifestStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ManifestStateRow(
      id: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      serial: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}serial'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      )!,
      json: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}json'])!,
    );
  }

  @override
  $ManifestStateTable createAlias(String alias) {
    return $ManifestStateTable(attachedDatabase, alias);
  }
}

class ManifestStateRow extends DataClass implements Insertable<ManifestStateRow> {
  final int id;
  final int serial;
  final int fetchedAt;
  final String json;
  const ManifestStateRow({
    required this.id,
    required this.serial,
    required this.fetchedAt,
    required this.json,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['serial'] = Variable<int>(serial);
    map['fetched_at'] = Variable<int>(fetchedAt);
    map['json'] = Variable<String>(json);
    return map;
  }

  ManifestStateCompanion toCompanion(bool nullToAbsent) {
    return ManifestStateCompanion(
      id: Value(id),
      serial: Value(serial),
      fetchedAt: Value(fetchedAt),
      json: Value(json),
    );
  }

  factory ManifestStateRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ManifestStateRow(
      id: serializer.fromJson<int>(json['id']),
      serial: serializer.fromJson<int>(json['serial']),
      fetchedAt: serializer.fromJson<int>(json['fetchedAt']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'serial': serializer.toJson<int>(serial),
      'fetchedAt': serializer.toJson<int>(fetchedAt),
      'json': serializer.toJson<String>(json),
    };
  }

  ManifestStateRow copyWith({int? id, int? serial, int? fetchedAt, String? json}) =>
      ManifestStateRow(
        id: id ?? this.id,
        serial: serial ?? this.serial,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        json: json ?? this.json,
      );
  ManifestStateRow copyWithCompanion(ManifestStateCompanion data) {
    return ManifestStateRow(
      id: data.id.present ? data.id.value : this.id,
      serial: data.serial.present ? data.serial.value : this.serial,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ManifestStateRow(')
          ..write('id: $id, ')
          ..write('serial: $serial, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, serial, fetchedAt, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ManifestStateRow &&
          other.id == this.id &&
          other.serial == this.serial &&
          other.fetchedAt == this.fetchedAt &&
          other.json == this.json);
}

class ManifestStateCompanion extends UpdateCompanion<ManifestStateRow> {
  final Value<int> id;
  final Value<int> serial;
  final Value<int> fetchedAt;
  final Value<String> json;
  const ManifestStateCompanion({
    this.id = const Value.absent(),
    this.serial = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.json = const Value.absent(),
  });
  ManifestStateCompanion.insert({
    this.id = const Value.absent(),
    required int serial,
    required int fetchedAt,
    required String json,
  }) : serial = Value(serial),
       fetchedAt = Value(fetchedAt),
       json = Value(json);
  static Insertable<ManifestStateRow> custom({
    Expression<int>? id,
    Expression<int>? serial,
    Expression<int>? fetchedAt,
    Expression<String>? json,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serial != null) 'serial': serial,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (json != null) 'json': json,
    });
  }

  ManifestStateCompanion copyWith({
    Value<int>? id,
    Value<int>? serial,
    Value<int>? fetchedAt,
    Value<String>? json,
  }) {
    return ManifestStateCompanion(
      id: id ?? this.id,
      serial: serial ?? this.serial,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      json: json ?? this.json,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (serial.present) {
      map['serial'] = Variable<int>(serial.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ManifestStateCompanion(')
          ..write('id: $id, ')
          ..write('serial: $serial, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }
}

abstract class _$RefocalDatabase extends GeneratedDatabase {
  _$RefocalDatabase(QueryExecutor e) : super(e);
  $RefocalDatabaseManager get managers => $RefocalDatabaseManager(this);
  late final $AssetsTable assets = $AssetsTable(this);
  late final $RecipesTable recipes = $RecipesTable(this);
  late final $HistoryTable history = $HistoryTable(this);
  late final $QueueJobsTable queueJobs = $QueueJobsTable(this);
  late final $ModelPacksTable modelPacks = $ModelPacksTable(this);
  late final $ConsentsTable consents = $ConsentsTable(this);
  late final $ManifestStateTable manifestState = $ManifestStateTable(this);
  late final Index historyCreatedAt = Index(
    'history_created_at',
    'CREATE INDEX history_created_at ON history (created_at)',
  );
  late final Index queueJobsPosition = Index(
    'queue_jobs_position',
    'CREATE INDEX queue_jobs_position ON queue_jobs (position)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    assets,
    recipes,
    history,
    queueJobs,
    modelPacks,
    consents,
    manifestState,
    historyCreatedAt,
    queueJobsPosition,
  ];
}

typedef $$AssetsTableCreateCompanionBuilder = AssetsCompanion Function({
  required String id,
  required String inboxPath,
  Value<int?> width,
  Value<int?> height,
  required int createdAt,
  Value<int> rowid,
});
typedef $$AssetsTableUpdateCompanionBuilder = AssetsCompanion Function({
  Value<String> id,
  Value<String> inboxPath,
  Value<int?> width,
  Value<int?> height,
  Value<int> createdAt,
  Value<int> rowid,
});

final class $$AssetsTableReferences
    extends BaseReferences<_$RefocalDatabase, $AssetsTable, AssetRow> {
  $$AssetsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$HistoryTable, List<HistoryRow>> _historyRefsTable(
    _$RefocalDatabase db,
  ) => MultiTypedResultKey.fromTable(db.history, aliasName: 'assets__id__history__asset_id');

  $$HistoryTableProcessedTableManager get historyRefs {
    final manager = $$HistoryTableTableManager(
      $_db,
      $_db.history,
    ).filter((f) => f.assetId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_historyRefsTable($_db));
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$QueueJobsTable, List<QueueJobRow>> _queueJobsRefsTable(
    _$RefocalDatabase db,
  ) => MultiTypedResultKey.fromTable(db.queueJobs, aliasName: 'assets__id__queue_jobs__asset_id');

  $$QueueJobsTableProcessedTableManager get queueJobsRefs {
    final manager = $$QueueJobsTableTableManager(
      $_db,
      $_db.queueJobs,
    ).filter((f) => f.assetId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_queueJobsRefsTable($_db));
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$AssetsTableFilterComposer extends Composer<_$RefocalDatabase, $AssetsTable> {
  $$AssetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get inboxPath =>
      $composableBuilder(column: $table.inboxPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnFilters(column));

  Expression<bool> historyRefs(Expression<bool> Function($$HistoryTableFilterComposer f) f) {
    final $$HistoryTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.history,
      getReferencedColumn: (t) => t.assetId,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$HistoryTableFilterComposer(
            $db: $db,
            $table: $db.history,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> queueJobsRefs(Expression<bool> Function($$QueueJobsTableFilterComposer f) f) {
    final $$QueueJobsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.queueJobs,
      getReferencedColumn: (t) => t.assetId,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$QueueJobsTableFilterComposer(
            $db: $db,
            $table: $db.queueJobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AssetsTableOrderingComposer extends Composer<_$RefocalDatabase, $AssetsTable> {
  $$AssetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get inboxPath =>
      $composableBuilder(column: $table.inboxPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$AssetsTableAnnotationComposer extends Composer<_$RefocalDatabase, $AssetsTable> {
  $$AssetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get inboxPath =>
      $composableBuilder(column: $table.inboxPath, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> historyRefs<T extends Object>(
    Expression<T> Function($$HistoryTableAnnotationComposer a) f,
  ) {
    final $$HistoryTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.history,
      getReferencedColumn: (t) => t.assetId,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$HistoryTableAnnotationComposer(
            $db: $db,
            $table: $db.history,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> queueJobsRefs<T extends Object>(
    Expression<T> Function($$QueueJobsTableAnnotationComposer a) f,
  ) {
    final $$QueueJobsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.queueJobs,
      getReferencedColumn: (t) => t.assetId,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$QueueJobsTableAnnotationComposer(
            $db: $db,
            $table: $db.queueJobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AssetsTableTableManager
    extends
        RootTableManager<
          _$RefocalDatabase,
          $AssetsTable,
          AssetRow,
          $$AssetsTableFilterComposer,
          $$AssetsTableOrderingComposer,
          $$AssetsTableAnnotationComposer,
          $$AssetsTableCreateCompanionBuilder,
          $$AssetsTableUpdateCompanionBuilder,
          (AssetRow, $$AssetsTableReferences),
          AssetRow,
          PrefetchHooks Function({bool historyRefs, bool queueJobsRefs})
        > {
  $$AssetsTableTableManager(_$RefocalDatabase db, $AssetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$AssetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$AssetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> inboxPath = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssetsCompanion(
                id: id,
                inboxPath: inboxPath,
                width: width,
                height: height,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String inboxPath,
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => AssetsCompanion.insert(
                id: id,
                inboxPath: inboxPath,
                width: width,
                height: height,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AssetsTable, AssetRow>(table),
                  $$AssetsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({historyRefs = false, queueJobsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (historyRefs) db.history,
                if (queueJobsRefs) db.queueJobs,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (historyRefs)
                    await $_getPrefetchedData<AssetRow, $AssetsTable, HistoryRow>(
                      currentTable: table,
                      referencedTable: $$AssetsTableReferences._historyRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$AssetsTableReferences(db, table, p0).historyRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.assetId == item.id),
                      typedResults: items,
                    ),
                  if (queueJobsRefs)
                    await $_getPrefetchedData<AssetRow, $AssetsTable, QueueJobRow>(
                      currentTable: table,
                      referencedTable: $$AssetsTableReferences._queueJobsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$AssetsTableReferences(db, table, p0).queueJobsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.assetId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$AssetsTableProcessedTableManager =
    ProcessedTableManager<
      _$RefocalDatabase,
      $AssetsTable,
      AssetRow,
      $$AssetsTableFilterComposer,
      $$AssetsTableOrderingComposer,
      $$AssetsTableAnnotationComposer,
      $$AssetsTableCreateCompanionBuilder,
      $$AssetsTableUpdateCompanionBuilder,
      (AssetRow, $$AssetsTableReferences),
      AssetRow,
      PrefetchHooks Function({bool historyRefs, bool queueJobsRefs})
    >;
typedef $$RecipesTableCreateCompanionBuilder = RecipesCompanion Function({
  required String id,
  required int schema,
  required String json,
  required int createdAt,
  Value<int> rowid,
});
typedef $$RecipesTableUpdateCompanionBuilder = RecipesCompanion Function({
  Value<String> id,
  Value<int> schema,
  Value<String> json,
  Value<int> createdAt,
  Value<int> rowid,
});

final class $$RecipesTableReferences
    extends BaseReferences<_$RefocalDatabase, $RecipesTable, RecipeRow> {
  $$RecipesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$HistoryTable, List<HistoryRow>> _historyRefsTable(
    _$RefocalDatabase db,
  ) => MultiTypedResultKey.fromTable(db.history, aliasName: 'recipes__id__history__recipe_id');

  $$HistoryTableProcessedTableManager get historyRefs {
    final manager = $$HistoryTableTableManager(
      $_db,
      $_db.history,
    ).filter((f) => f.recipeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_historyRefsTable($_db));
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$QueueJobsTable, List<QueueJobRow>> _queueJobsRefsTable(
    _$RefocalDatabase db,
  ) => MultiTypedResultKey.fromTable(db.queueJobs, aliasName: 'recipes__id__queue_jobs__recipe_id');

  $$QueueJobsTableProcessedTableManager get queueJobsRefs {
    final manager = $$QueueJobsTableTableManager(
      $_db,
      $_db.queueJobs,
    ).filter((f) => f.recipeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_queueJobsRefsTable($_db));
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$RecipesTableFilterComposer extends Composer<_$RefocalDatabase, $RecipesTable> {
  $$RecipesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get schema =>
      $composableBuilder(column: $table.schema, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnFilters(column));

  Expression<bool> historyRefs(Expression<bool> Function($$HistoryTableFilterComposer f) f) {
    final $$HistoryTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.history,
      getReferencedColumn: (t) => t.recipeId,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$HistoryTableFilterComposer(
            $db: $db,
            $table: $db.history,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> queueJobsRefs(Expression<bool> Function($$QueueJobsTableFilterComposer f) f) {
    final $$QueueJobsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.queueJobs,
      getReferencedColumn: (t) => t.recipeId,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$QueueJobsTableFilterComposer(
            $db: $db,
            $table: $db.queueJobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RecipesTableOrderingComposer extends Composer<_$RefocalDatabase, $RecipesTable> {
  $$RecipesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get schema =>
      $composableBuilder(column: $table.schema, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$RecipesTableAnnotationComposer extends Composer<_$RefocalDatabase, $RecipesTable> {
  $$RecipesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get schema =>
      $composableBuilder(column: $table.schema, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> historyRefs<T extends Object>(
    Expression<T> Function($$HistoryTableAnnotationComposer a) f,
  ) {
    final $$HistoryTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.history,
      getReferencedColumn: (t) => t.recipeId,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$HistoryTableAnnotationComposer(
            $db: $db,
            $table: $db.history,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> queueJobsRefs<T extends Object>(
    Expression<T> Function($$QueueJobsTableAnnotationComposer a) f,
  ) {
    final $$QueueJobsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.queueJobs,
      getReferencedColumn: (t) => t.recipeId,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$QueueJobsTableAnnotationComposer(
            $db: $db,
            $table: $db.queueJobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RecipesTableTableManager
    extends
        RootTableManager<
          _$RefocalDatabase,
          $RecipesTable,
          RecipeRow,
          $$RecipesTableFilterComposer,
          $$RecipesTableOrderingComposer,
          $$RecipesTableAnnotationComposer,
          $$RecipesTableCreateCompanionBuilder,
          $$RecipesTableUpdateCompanionBuilder,
          (RecipeRow, $$RecipesTableReferences),
          RecipeRow,
          PrefetchHooks Function({bool historyRefs, bool queueJobsRefs})
        > {
  $$RecipesTableTableManager(_$RefocalDatabase db, $RecipesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$RecipesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$RecipesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecipesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> schema = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecipesCompanion(
                id: id,
                schema: schema,
                json: json,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int schema,
                required String json,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => RecipesCompanion.insert(
                id: id,
                schema: schema,
                json: json,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RecipesTable, RecipeRow>(table),
                  $$RecipesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({historyRefs = false, queueJobsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (historyRefs) db.history,
                if (queueJobsRefs) db.queueJobs,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (historyRefs)
                    await $_getPrefetchedData<RecipeRow, $RecipesTable, HistoryRow>(
                      currentTable: table,
                      referencedTable: $$RecipesTableReferences._historyRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$RecipesTableReferences(db, table, p0).historyRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.recipeId == item.id),
                      typedResults: items,
                    ),
                  if (queueJobsRefs)
                    await $_getPrefetchedData<RecipeRow, $RecipesTable, QueueJobRow>(
                      currentTable: table,
                      referencedTable: $$RecipesTableReferences._queueJobsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$RecipesTableReferences(db, table, p0).queueJobsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.recipeId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$RecipesTableProcessedTableManager =
    ProcessedTableManager<
      _$RefocalDatabase,
      $RecipesTable,
      RecipeRow,
      $$RecipesTableFilterComposer,
      $$RecipesTableOrderingComposer,
      $$RecipesTableAnnotationComposer,
      $$RecipesTableCreateCompanionBuilder,
      $$RecipesTableUpdateCompanionBuilder,
      (RecipeRow, $$RecipesTableReferences),
      RecipeRow,
      PrefetchHooks Function({bool historyRefs, bool queueJobsRefs})
    >;
typedef $$HistoryTableCreateCompanionBuilder = HistoryCompanion Function({
  required String id,
  required String assetId,
  required String recipeId,
  required String jobId,
  required String resultUri,
  required String previewPath,
  required int width,
  required int height,
  required String modelIds,
  required String backend,
  Value<int?> durationMs,
  required int createdAt,
  Value<int> rowid,
});
typedef $$HistoryTableUpdateCompanionBuilder = HistoryCompanion Function({
  Value<String> id,
  Value<String> assetId,
  Value<String> recipeId,
  Value<String> jobId,
  Value<String> resultUri,
  Value<String> previewPath,
  Value<int> width,
  Value<int> height,
  Value<String> modelIds,
  Value<String> backend,
  Value<int?> durationMs,
  Value<int> createdAt,
  Value<int> rowid,
});

final class $$HistoryTableReferences
    extends BaseReferences<_$RefocalDatabase, $HistoryTable, HistoryRow> {
  $$HistoryTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AssetsTable _assetIdTable(_$RefocalDatabase db) =>
      db.assets.createAlias('history__asset_id__assets__id');

  $$AssetsTableProcessedTableManager get assetId {
    final $_column = $_itemColumn<String>('asset_id')!;

    final manager = $$AssetsTableTableManager(
      $_db,
      $_db.assets,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_assetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: [item]));
  }

  static $RecipesTable _recipeIdTable(_$RefocalDatabase db) =>
      db.recipes.createAlias('history__recipe_id__recipes__id');

  $$RecipesTableProcessedTableManager get recipeId {
    final $_column = $_itemColumn<String>('recipe_id')!;

    final manager = $$RecipesTableTableManager(
      $_db,
      $_db.recipes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_recipeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$HistoryTableFilterComposer extends Composer<_$RefocalDatabase, $HistoryTable> {
  $$HistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get resultUri =>
      $composableBuilder(column: $table.resultUri, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get previewPath =>
      $composableBuilder(column: $table.previewPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get modelIds =>
      $composableBuilder(column: $table.modelIds, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get backend =>
      $composableBuilder(column: $table.backend, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationMs =>
      $composableBuilder(column: $table.durationMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnFilters(column));

  $$AssetsTableFilterComposer get assetId {
    final $$AssetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$AssetsTableFilterComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$RecipesTableFilterComposer get recipeId {
    final $$RecipesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$RecipesTableFilterComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HistoryTableOrderingComposer extends Composer<_$RefocalDatabase, $HistoryTable> {
  $$HistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get resultUri =>
      $composableBuilder(column: $table.resultUri, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get previewPath =>
      $composableBuilder(column: $table.previewPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get modelIds =>
      $composableBuilder(column: $table.modelIds, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get backend =>
      $composableBuilder(column: $table.backend, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationMs =>
      $composableBuilder(column: $table.durationMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  $$AssetsTableOrderingComposer get assetId {
    final $$AssetsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$AssetsTableOrderingComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$RecipesTableOrderingComposer get recipeId {
    final $$RecipesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$RecipesTableOrderingComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HistoryTableAnnotationComposer extends Composer<_$RefocalDatabase, $HistoryTable> {
  $$HistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumn<String> get resultUri =>
      $composableBuilder(column: $table.resultUri, builder: (column) => column);

  GeneratedColumn<String> get previewPath =>
      $composableBuilder(column: $table.previewPath, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<String> get modelIds =>
      $composableBuilder(column: $table.modelIds, builder: (column) => column);

  GeneratedColumn<String> get backend =>
      $composableBuilder(column: $table.backend, builder: (column) => column);

  GeneratedColumn<int> get durationMs =>
      $composableBuilder(column: $table.durationMs, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$AssetsTableAnnotationComposer get assetId {
    final $$AssetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$AssetsTableAnnotationComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$RecipesTableAnnotationComposer get recipeId {
    final $$RecipesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$RecipesTableAnnotationComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HistoryTableTableManager
    extends
        RootTableManager<
          _$RefocalDatabase,
          $HistoryTable,
          HistoryRow,
          $$HistoryTableFilterComposer,
          $$HistoryTableOrderingComposer,
          $$HistoryTableAnnotationComposer,
          $$HistoryTableCreateCompanionBuilder,
          $$HistoryTableUpdateCompanionBuilder,
          (HistoryRow, $$HistoryTableReferences),
          HistoryRow,
          PrefetchHooks Function({bool assetId, bool recipeId})
        > {
  $$HistoryTableTableManager(_$RefocalDatabase db, $HistoryTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$HistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$HistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> assetId = const Value.absent(),
                Value<String> recipeId = const Value.absent(),
                Value<String> jobId = const Value.absent(),
                Value<String> resultUri = const Value.absent(),
                Value<String> previewPath = const Value.absent(),
                Value<int> width = const Value.absent(),
                Value<int> height = const Value.absent(),
                Value<String> modelIds = const Value.absent(),
                Value<String> backend = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HistoryCompanion(
                id: id,
                assetId: assetId,
                recipeId: recipeId,
                jobId: jobId,
                resultUri: resultUri,
                previewPath: previewPath,
                width: width,
                height: height,
                modelIds: modelIds,
                backend: backend,
                durationMs: durationMs,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String assetId,
                required String recipeId,
                required String jobId,
                required String resultUri,
                required String previewPath,
                required int width,
                required int height,
                required String modelIds,
                required String backend,
                Value<int?> durationMs = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => HistoryCompanion.insert(
                id: id,
                assetId: assetId,
                recipeId: recipeId,
                jobId: jobId,
                resultUri: resultUri,
                previewPath: previewPath,
                width: width,
                height: height,
                modelIds: modelIds,
                backend: backend,
                durationMs: durationMs,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$HistoryTable, HistoryRow>(table),
                  $$HistoryTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({assetId = false, recipeId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (assetId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.assetId,
                        referencedTable: $$HistoryTableReferences._assetIdTable(db),
                        referencedColumn: $$HistoryTableReferences._assetIdTable(db).id,
                      ) as T;
                    }
                    if (recipeId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.recipeId,
                        referencedTable: $$HistoryTableReferences._recipeIdTable(db),
                        referencedColumn: $$HistoryTableReferences._recipeIdTable(db).id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$HistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$RefocalDatabase,
      $HistoryTable,
      HistoryRow,
      $$HistoryTableFilterComposer,
      $$HistoryTableOrderingComposer,
      $$HistoryTableAnnotationComposer,
      $$HistoryTableCreateCompanionBuilder,
      $$HistoryTableUpdateCompanionBuilder,
      (HistoryRow, $$HistoryTableReferences),
      HistoryRow,
      PrefetchHooks Function({bool assetId, bool recipeId})
    >;
typedef $$QueueJobsTableCreateCompanionBuilder = QueueJobsCompanion Function({
  required String id,
  required String assetId,
  required String recipeId,
  required QueueState state,
  required int position,
  required String jobId,
  Value<double> progress,
  Value<String?> errorCode,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$QueueJobsTableUpdateCompanionBuilder = QueueJobsCompanion Function({
  Value<String> id,
  Value<String> assetId,
  Value<String> recipeId,
  Value<QueueState> state,
  Value<int> position,
  Value<String> jobId,
  Value<double> progress,
  Value<String?> errorCode,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

final class $$QueueJobsTableReferences
    extends BaseReferences<_$RefocalDatabase, $QueueJobsTable, QueueJobRow> {
  $$QueueJobsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AssetsTable _assetIdTable(_$RefocalDatabase db) =>
      db.assets.createAlias('queue_jobs__asset_id__assets__id');

  $$AssetsTableProcessedTableManager get assetId {
    final $_column = $_itemColumn<String>('asset_id')!;

    final manager = $$AssetsTableTableManager(
      $_db,
      $_db.assets,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_assetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: [item]));
  }

  static $RecipesTable _recipeIdTable(_$RefocalDatabase db) =>
      db.recipes.createAlias('queue_jobs__recipe_id__recipes__id');

  $$RecipesTableProcessedTableManager get recipeId {
    final $_column = $_itemColumn<String>('recipe_id')!;

    final manager = $$RecipesTableTableManager(
      $_db,
      $_db.recipes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_recipeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$QueueJobsTableFilterComposer extends Composer<_$RefocalDatabase, $QueueJobsTable> {
  $$QueueJobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<QueueState, QueueState, String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  $$AssetsTableFilterComposer get assetId {
    final $$AssetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$AssetsTableFilterComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$RecipesTableFilterComposer get recipeId {
    final $$RecipesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$RecipesTableFilterComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QueueJobsTableOrderingComposer extends Composer<_$RefocalDatabase, $QueueJobsTable> {
  $$QueueJobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  $$AssetsTableOrderingComposer get assetId {
    final $$AssetsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$AssetsTableOrderingComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$RecipesTableOrderingComposer get recipeId {
    final $$RecipesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$RecipesTableOrderingComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QueueJobsTableAnnotationComposer extends Composer<_$RefocalDatabase, $QueueJobsTable> {
  $$QueueJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<QueueState, String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumn<double> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => column);

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$AssetsTableAnnotationComposer get assetId {
    final $$AssetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$AssetsTableAnnotationComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$RecipesTableAnnotationComposer get recipeId {
    final $$RecipesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$RecipesTableAnnotationComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QueueJobsTableTableManager
    extends
        RootTableManager<
          _$RefocalDatabase,
          $QueueJobsTable,
          QueueJobRow,
          $$QueueJobsTableFilterComposer,
          $$QueueJobsTableOrderingComposer,
          $$QueueJobsTableAnnotationComposer,
          $$QueueJobsTableCreateCompanionBuilder,
          $$QueueJobsTableUpdateCompanionBuilder,
          (QueueJobRow, $$QueueJobsTableReferences),
          QueueJobRow,
          PrefetchHooks Function({bool assetId, bool recipeId})
        > {
  $$QueueJobsTableTableManager(_$RefocalDatabase db, $QueueJobsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$QueueJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$QueueJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QueueJobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> assetId = const Value.absent(),
                Value<String> recipeId = const Value.absent(),
                Value<QueueState> state = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> jobId = const Value.absent(),
                Value<double> progress = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => QueueJobsCompanion(
                id: id,
                assetId: assetId,
                recipeId: recipeId,
                state: state,
                position: position,
                jobId: jobId,
                progress: progress,
                errorCode: errorCode,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String assetId,
                required String recipeId,
                required QueueState state,
                required int position,
                required String jobId,
                Value<double> progress = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => QueueJobsCompanion.insert(
                id: id,
                assetId: assetId,
                recipeId: recipeId,
                state: state,
                position: position,
                jobId: jobId,
                progress: progress,
                errorCode: errorCode,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$QueueJobsTable, QueueJobRow>(table),
                  $$QueueJobsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({assetId = false, recipeId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (assetId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.assetId,
                        referencedTable: $$QueueJobsTableReferences._assetIdTable(db),
                        referencedColumn: $$QueueJobsTableReferences._assetIdTable(db).id,
                      ) as T;
                    }
                    if (recipeId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.recipeId,
                        referencedTable: $$QueueJobsTableReferences._recipeIdTable(db),
                        referencedColumn: $$QueueJobsTableReferences._recipeIdTable(db).id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$QueueJobsTableProcessedTableManager =
    ProcessedTableManager<
      _$RefocalDatabase,
      $QueueJobsTable,
      QueueJobRow,
      $$QueueJobsTableFilterComposer,
      $$QueueJobsTableOrderingComposer,
      $$QueueJobsTableAnnotationComposer,
      $$QueueJobsTableCreateCompanionBuilder,
      $$QueueJobsTableUpdateCompanionBuilder,
      (QueueJobRow, $$QueueJobsTableReferences),
      QueueJobRow,
      PrefetchHooks Function({bool assetId, bool recipeId})
    >;
typedef $$ModelPacksTableCreateCompanionBuilder = ModelPacksCompanion Function({
  required String id,
  required String version,
  required String category,
  required String path,
  required int size,
  required String sha256,
  required String licenseSpdx,
  required int installedAt,
  Value<int> rowid,
});
typedef $$ModelPacksTableUpdateCompanionBuilder = ModelPacksCompanion Function({
  Value<String> id,
  Value<String> version,
  Value<String> category,
  Value<String> path,
  Value<int> size,
  Value<String> sha256,
  Value<String> licenseSpdx,
  Value<int> installedAt,
  Value<int> rowid,
});

class $$ModelPacksTableFilterComposer extends Composer<_$RefocalDatabase, $ModelPacksTable> {
  $$ModelPacksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get licenseSpdx =>
      $composableBuilder(column: $table.licenseSpdx, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get installedAt =>
      $composableBuilder(column: $table.installedAt, builder: (column) => ColumnFilters(column));
}

class $$ModelPacksTableOrderingComposer extends Composer<_$RefocalDatabase, $ModelPacksTable> {
  $$ModelPacksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get licenseSpdx =>
      $composableBuilder(column: $table.licenseSpdx, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get installedAt =>
      $composableBuilder(column: $table.installedAt, builder: (column) => ColumnOrderings(column));
}

class $$ModelPacksTableAnnotationComposer extends Composer<_$RefocalDatabase, $ModelPacksTable> {
  $$ModelPacksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get licenseSpdx =>
      $composableBuilder(column: $table.licenseSpdx, builder: (column) => column);

  GeneratedColumn<int> get installedAt =>
      $composableBuilder(column: $table.installedAt, builder: (column) => column);
}

class $$ModelPacksTableTableManager
    extends
        RootTableManager<
          _$RefocalDatabase,
          $ModelPacksTable,
          ModelPackRow,
          $$ModelPacksTableFilterComposer,
          $$ModelPacksTableOrderingComposer,
          $$ModelPacksTableAnnotationComposer,
          $$ModelPacksTableCreateCompanionBuilder,
          $$ModelPacksTableUpdateCompanionBuilder,
          (ModelPackRow, BaseReferences<_$RefocalDatabase, $ModelPacksTable, ModelPackRow>),
          ModelPackRow,
          PrefetchHooks Function()
        > {
  $$ModelPacksTableTableManager(_$RefocalDatabase db, $ModelPacksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$ModelPacksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$ModelPacksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ModelPacksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<String> licenseSpdx = const Value.absent(),
                Value<int> installedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ModelPacksCompanion(
                id: id,
                version: version,
                category: category,
                path: path,
                size: size,
                sha256: sha256,
                licenseSpdx: licenseSpdx,
                installedAt: installedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String version,
                required String category,
                required String path,
                required int size,
                required String sha256,
                required String licenseSpdx,
                required int installedAt,
                Value<int> rowid = const Value.absent(),
              }) => ModelPacksCompanion.insert(
                id: id,
                version: version,
                category: category,
                path: path,
                size: size,
                sha256: sha256,
                licenseSpdx: licenseSpdx,
                installedAt: installedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ModelPacksTable, ModelPackRow>(table),
                  BaseReferences<_$RefocalDatabase, $ModelPacksTable, ModelPackRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ModelPacksTableProcessedTableManager =
    ProcessedTableManager<
      _$RefocalDatabase,
      $ModelPacksTable,
      ModelPackRow,
      $$ModelPacksTableFilterComposer,
      $$ModelPacksTableOrderingComposer,
      $$ModelPacksTableAnnotationComposer,
      $$ModelPacksTableCreateCompanionBuilder,
      $$ModelPacksTableUpdateCompanionBuilder,
      (ModelPackRow, BaseReferences<_$RefocalDatabase, $ModelPacksTable, ModelPackRow>),
      ModelPackRow,
      PrefetchHooks Function()
    >;
typedef $$ConsentsTableCreateCompanionBuilder = ConsentsCompanion Function({
  required String packId,
  required String packVersion,
  required String licenseSha256,
  required int acceptedAt,
  Value<int> rowid,
});
typedef $$ConsentsTableUpdateCompanionBuilder = ConsentsCompanion Function({
  Value<String> packId,
  Value<String> packVersion,
  Value<String> licenseSha256,
  Value<int> acceptedAt,
  Value<int> rowid,
});

class $$ConsentsTableFilterComposer extends Composer<_$RefocalDatabase, $ConsentsTable> {
  $$ConsentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get packId =>
      $composableBuilder(column: $table.packId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get packVersion =>
      $composableBuilder(column: $table.packVersion, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get licenseSha256 =>
      $composableBuilder(column: $table.licenseSha256, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get acceptedAt =>
      $composableBuilder(column: $table.acceptedAt, builder: (column) => ColumnFilters(column));
}

class $$ConsentsTableOrderingComposer extends Composer<_$RefocalDatabase, $ConsentsTable> {
  $$ConsentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get packId =>
      $composableBuilder(column: $table.packId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get packVersion =>
      $composableBuilder(column: $table.packVersion, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get licenseSha256 => $composableBuilder(
    column: $table.licenseSha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get acceptedAt =>
      $composableBuilder(column: $table.acceptedAt, builder: (column) => ColumnOrderings(column));
}

class $$ConsentsTableAnnotationComposer extends Composer<_$RefocalDatabase, $ConsentsTable> {
  $$ConsentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get packId =>
      $composableBuilder(column: $table.packId, builder: (column) => column);

  GeneratedColumn<String> get packVersion =>
      $composableBuilder(column: $table.packVersion, builder: (column) => column);

  GeneratedColumn<String> get licenseSha256 =>
      $composableBuilder(column: $table.licenseSha256, builder: (column) => column);

  GeneratedColumn<int> get acceptedAt =>
      $composableBuilder(column: $table.acceptedAt, builder: (column) => column);
}

class $$ConsentsTableTableManager
    extends
        RootTableManager<
          _$RefocalDatabase,
          $ConsentsTable,
          ConsentRow,
          $$ConsentsTableFilterComposer,
          $$ConsentsTableOrderingComposer,
          $$ConsentsTableAnnotationComposer,
          $$ConsentsTableCreateCompanionBuilder,
          $$ConsentsTableUpdateCompanionBuilder,
          (ConsentRow, BaseReferences<_$RefocalDatabase, $ConsentsTable, ConsentRow>),
          ConsentRow,
          PrefetchHooks Function()
        > {
  $$ConsentsTableTableManager(_$RefocalDatabase db, $ConsentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$ConsentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$ConsentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConsentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> packId = const Value.absent(),
                Value<String> packVersion = const Value.absent(),
                Value<String> licenseSha256 = const Value.absent(),
                Value<int> acceptedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConsentsCompanion(
                packId: packId,
                packVersion: packVersion,
                licenseSha256: licenseSha256,
                acceptedAt: acceptedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String packId,
                required String packVersion,
                required String licenseSha256,
                required int acceptedAt,
                Value<int> rowid = const Value.absent(),
              }) => ConsentsCompanion.insert(
                packId: packId,
                packVersion: packVersion,
                licenseSha256: licenseSha256,
                acceptedAt: acceptedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ConsentsTable, ConsentRow>(table),
                  BaseReferences<_$RefocalDatabase, $ConsentsTable, ConsentRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ConsentsTableProcessedTableManager =
    ProcessedTableManager<
      _$RefocalDatabase,
      $ConsentsTable,
      ConsentRow,
      $$ConsentsTableFilterComposer,
      $$ConsentsTableOrderingComposer,
      $$ConsentsTableAnnotationComposer,
      $$ConsentsTableCreateCompanionBuilder,
      $$ConsentsTableUpdateCompanionBuilder,
      (ConsentRow, BaseReferences<_$RefocalDatabase, $ConsentsTable, ConsentRow>),
      ConsentRow,
      PrefetchHooks Function()
    >;
typedef $$ManifestStateTableCreateCompanionBuilder = ManifestStateCompanion Function({
  Value<int> id,
  required int serial,
  required int fetchedAt,
  required String json,
});
typedef $$ManifestStateTableUpdateCompanionBuilder = ManifestStateCompanion Function({
  Value<int> id,
  Value<int> serial,
  Value<int> fetchedAt,
  Value<String> json,
});

class $$ManifestStateTableFilterComposer extends Composer<_$RefocalDatabase, $ManifestStateTable> {
  $$ManifestStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get serial =>
      $composableBuilder(column: $table.serial, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => ColumnFilters(column));
}

class $$ManifestStateTableOrderingComposer
    extends Composer<_$RefocalDatabase, $ManifestStateTable> {
  $$ManifestStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get serial =>
      $composableBuilder(column: $table.serial, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => ColumnOrderings(column));
}

class $$ManifestStateTableAnnotationComposer
    extends Composer<_$RefocalDatabase, $ManifestStateTable> {
  $$ManifestStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id => $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get serial =>
      $composableBuilder(column: $table.serial, builder: (column) => column);

  GeneratedColumn<int> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);
}

class $$ManifestStateTableTableManager
    extends
        RootTableManager<
          _$RefocalDatabase,
          $ManifestStateTable,
          ManifestStateRow,
          $$ManifestStateTableFilterComposer,
          $$ManifestStateTableOrderingComposer,
          $$ManifestStateTableAnnotationComposer,
          $$ManifestStateTableCreateCompanionBuilder,
          $$ManifestStateTableUpdateCompanionBuilder,
          (
            ManifestStateRow,
            BaseReferences<_$RefocalDatabase, $ManifestStateTable, ManifestStateRow>,
          ),
          ManifestStateRow,
          PrefetchHooks Function()
        > {
  $$ManifestStateTableTableManager(_$RefocalDatabase db, $ManifestStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$ManifestStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ManifestStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ManifestStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> serial = const Value.absent(),
            Value<int> fetchedAt = const Value.absent(),
            Value<String> json = const Value.absent(),
          }) => ManifestStateCompanion(id: id, serial: serial, fetchedAt: fetchedAt, json: json),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int serial,
                required int fetchedAt,
                required String json,
              }) => ManifestStateCompanion.insert(
                id: id,
                serial: serial,
                fetchedAt: fetchedAt,
                json: json,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ManifestStateTable, ManifestStateRow>(table),
                  BaseReferences<_$RefocalDatabase, $ManifestStateTable, ManifestStateRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ManifestStateTableProcessedTableManager =
    ProcessedTableManager<
      _$RefocalDatabase,
      $ManifestStateTable,
      ManifestStateRow,
      $$ManifestStateTableFilterComposer,
      $$ManifestStateTableOrderingComposer,
      $$ManifestStateTableAnnotationComposer,
      $$ManifestStateTableCreateCompanionBuilder,
      $$ManifestStateTableUpdateCompanionBuilder,
      (ManifestStateRow, BaseReferences<_$RefocalDatabase, $ManifestStateTable, ManifestStateRow>),
      ManifestStateRow,
      PrefetchHooks Function()
    >;

class $RefocalDatabaseManager {
  final _$RefocalDatabase _db;
  $RefocalDatabaseManager(this._db);
  $$AssetsTableTableManager get assets => $$AssetsTableTableManager(_db, _db.assets);
  $$RecipesTableTableManager get recipes => $$RecipesTableTableManager(_db, _db.recipes);
  $$HistoryTableTableManager get history => $$HistoryTableTableManager(_db, _db.history);
  $$QueueJobsTableTableManager get queueJobs => $$QueueJobsTableTableManager(_db, _db.queueJobs);
  $$ModelPacksTableTableManager get modelPacks =>
      $$ModelPacksTableTableManager(_db, _db.modelPacks);
  $$ConsentsTableTableManager get consents => $$ConsentsTableTableManager(_db, _db.consents);
  $$ManifestStateTableTableManager get manifestState =>
      $$ManifestStateTableTableManager(_db, _db.manifestState);
}
