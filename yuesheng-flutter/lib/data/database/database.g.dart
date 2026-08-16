// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ManuscriptsTable extends Manuscripts
    with TableInfo<$ManuscriptsTable, Manuscript> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ManuscriptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _genreMeta = const VerificationMeta('genre');
  @override
  late final GeneratedColumn<String> genre = GeneratedColumn<String>(
    'genre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('中文'),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    check: () => status.isIn(const ['active', 'archived']),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
    'tags',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    description,
    genre,
    language,
    status,
    tags,
    sortOrder,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'manuscripts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Manuscript> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('genre')) {
      context.handle(
        _genreMeta,
        genre.isAcceptableOrUnknown(data['genre']!, _genreMeta),
      );
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('tags')) {
      context.handle(
        _tagsMeta,
        tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Manuscript map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Manuscript(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      genre: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genre'],
      )!,
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      tags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
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
  $ManuscriptsTable createAlias(String alias) {
    return $ManuscriptsTable(attachedDatabase, alias);
  }
}

class Manuscript extends DataClass implements Insertable<Manuscript> {
  final String id;
  final String title;
  final String description;
  final String genre;
  final String language;
  final String status;
  final String tags;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;
  const Manuscript({
    required this.id,
    required this.title,
    required this.description,
    required this.genre,
    required this.language,
    required this.status,
    required this.tags,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['description'] = Variable<String>(description);
    map['genre'] = Variable<String>(genre);
    map['language'] = Variable<String>(language);
    map['status'] = Variable<String>(status);
    map['tags'] = Variable<String>(tags);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  ManuscriptsCompanion toCompanion(bool nullToAbsent) {
    return ManuscriptsCompanion(
      id: Value(id),
      title: Value(title),
      description: Value(description),
      genre: Value(genre),
      language: Value(language),
      status: Value(status),
      tags: Value(tags),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Manuscript.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Manuscript(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String>(json['description']),
      genre: serializer.fromJson<String>(json['genre']),
      language: serializer.fromJson<String>(json['language']),
      status: serializer.fromJson<String>(json['status']),
      tags: serializer.fromJson<String>(json['tags']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String>(description),
      'genre': serializer.toJson<String>(genre),
      'language': serializer.toJson<String>(language),
      'status': serializer.toJson<String>(status),
      'tags': serializer.toJson<String>(tags),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  Manuscript copyWith({
    String? id,
    String? title,
    String? description,
    String? genre,
    String? language,
    String? status,
    String? tags,
    int? sortOrder,
    int? createdAt,
    int? updatedAt,
  }) => Manuscript(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description ?? this.description,
    genre: genre ?? this.genre,
    language: language ?? this.language,
    status: status ?? this.status,
    tags: tags ?? this.tags,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Manuscript copyWithCompanion(ManuscriptsCompanion data) {
    return Manuscript(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      genre: data.genre.present ? data.genre.value : this.genre,
      language: data.language.present ? data.language.value : this.language,
      status: data.status.present ? data.status.value : this.status,
      tags: data.tags.present ? data.tags.value : this.tags,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Manuscript(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('genre: $genre, ')
          ..write('language: $language, ')
          ..write('status: $status, ')
          ..write('tags: $tags, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    description,
    genre,
    language,
    status,
    tags,
    sortOrder,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Manuscript &&
          other.id == this.id &&
          other.title == this.title &&
          other.description == this.description &&
          other.genre == this.genre &&
          other.language == this.language &&
          other.status == this.status &&
          other.tags == this.tags &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ManuscriptsCompanion extends UpdateCompanion<Manuscript> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> description;
  final Value<String> genre;
  final Value<String> language;
  final Value<String> status;
  final Value<String> tags;
  final Value<int> sortOrder;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const ManuscriptsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.genre = const Value.absent(),
    this.language = const Value.absent(),
    this.status = const Value.absent(),
    this.tags = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ManuscriptsCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.genre = const Value.absent(),
    this.language = const Value.absent(),
    this.status = const Value.absent(),
    this.tags = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<Manuscript> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? genre,
    Expression<String>? language,
    Expression<String>? status,
    Expression<String>? tags,
    Expression<int>? sortOrder,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (genre != null) 'genre': genre,
      if (language != null) 'language': language,
      if (status != null) 'status': status,
      if (tags != null) 'tags': tags,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ManuscriptsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? description,
    Value<String>? genre,
    Value<String>? language,
    Value<String>? status,
    Value<String>? tags,
    Value<int>? sortOrder,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return ManuscriptsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      genre: genre ?? this.genre,
      language: language ?? this.language,
      status: status ?? this.status,
      tags: tags ?? this.tags,
      sortOrder: sortOrder ?? this.sortOrder,
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
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (genre.present) {
      map['genre'] = Variable<String>(genre.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
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
    return (StringBuffer('ManuscriptsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('genre: $genre, ')
          ..write('language: $language, ')
          ..write('status: $status, ')
          ..write('tags: $tags, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VolumesTable extends Volumes with TableInfo<$VolumesTable, Volume> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VolumesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _manuscriptIdMeta = const VerificationMeta(
    'manuscriptId',
  );
  @override
  late final GeneratedColumn<String> manuscriptId = GeneratedColumn<String>(
    'manuscript_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES manuscripts (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    manuscriptId,
    title,
    sortOrder,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'volumes';
  @override
  VerificationContext validateIntegrity(
    Insertable<Volume> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('manuscript_id')) {
      context.handle(
        _manuscriptIdMeta,
        manuscriptId.isAcceptableOrUnknown(
          data['manuscript_id']!,
          _manuscriptIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_manuscriptIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Volume map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Volume(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      manuscriptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manuscript_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
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
  $VolumesTable createAlias(String alias) {
    return $VolumesTable(attachedDatabase, alias);
  }
}

class Volume extends DataClass implements Insertable<Volume> {
  final String id;
  final String manuscriptId;
  final String title;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;
  const Volume({
    required this.id,
    required this.manuscriptId,
    required this.title,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['manuscript_id'] = Variable<String>(manuscriptId);
    map['title'] = Variable<String>(title);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  VolumesCompanion toCompanion(bool nullToAbsent) {
    return VolumesCompanion(
      id: Value(id),
      manuscriptId: Value(manuscriptId),
      title: Value(title),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Volume.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Volume(
      id: serializer.fromJson<String>(json['id']),
      manuscriptId: serializer.fromJson<String>(json['manuscriptId']),
      title: serializer.fromJson<String>(json['title']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'manuscriptId': serializer.toJson<String>(manuscriptId),
      'title': serializer.toJson<String>(title),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  Volume copyWith({
    String? id,
    String? manuscriptId,
    String? title,
    int? sortOrder,
    int? createdAt,
    int? updatedAt,
  }) => Volume(
    id: id ?? this.id,
    manuscriptId: manuscriptId ?? this.manuscriptId,
    title: title ?? this.title,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Volume copyWithCompanion(VolumesCompanion data) {
    return Volume(
      id: data.id.present ? data.id.value : this.id,
      manuscriptId: data.manuscriptId.present
          ? data.manuscriptId.value
          : this.manuscriptId,
      title: data.title.present ? data.title.value : this.title,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Volume(')
          ..write('id: $id, ')
          ..write('manuscriptId: $manuscriptId, ')
          ..write('title: $title, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, manuscriptId, title, sortOrder, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Volume &&
          other.id == this.id &&
          other.manuscriptId == this.manuscriptId &&
          other.title == this.title &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class VolumesCompanion extends UpdateCompanion<Volume> {
  final Value<String> id;
  final Value<String> manuscriptId;
  final Value<String> title;
  final Value<int> sortOrder;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const VolumesCompanion({
    this.id = const Value.absent(),
    this.manuscriptId = const Value.absent(),
    this.title = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VolumesCompanion.insert({
    required String id,
    required String manuscriptId,
    this.title = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       manuscriptId = Value(manuscriptId);
  static Insertable<Volume> custom({
    Expression<String>? id,
    Expression<String>? manuscriptId,
    Expression<String>? title,
    Expression<int>? sortOrder,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (manuscriptId != null) 'manuscript_id': manuscriptId,
      if (title != null) 'title': title,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VolumesCompanion copyWith({
    Value<String>? id,
    Value<String>? manuscriptId,
    Value<String>? title,
    Value<int>? sortOrder,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return VolumesCompanion(
      id: id ?? this.id,
      manuscriptId: manuscriptId ?? this.manuscriptId,
      title: title ?? this.title,
      sortOrder: sortOrder ?? this.sortOrder,
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
    if (manuscriptId.present) {
      map['manuscript_id'] = Variable<String>(manuscriptId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
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
    return (StringBuffer('VolumesCompanion(')
          ..write('id: $id, ')
          ..write('manuscriptId: $manuscriptId, ')
          ..write('title: $title, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChaptersTable extends Chapters with TableInfo<$ChaptersTable, Chapter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChaptersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _manuscriptIdMeta = const VerificationMeta(
    'manuscriptId',
  );
  @override
  late final GeneratedColumn<String> manuscriptId = GeneratedColumn<String>(
    'manuscript_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES manuscripts (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _volumeIdMeta = const VerificationMeta(
    'volumeId',
  );
  @override
  late final GeneratedColumn<String> volumeId = GeneratedColumn<String>(
    'volume_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES volumes (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _previousContentMeta = const VerificationMeta(
    'previousContent',
  );
  @override
  late final GeneratedColumn<String> previousContent = GeneratedColumn<String>(
    'previous_content',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _wordCountMeta = const VerificationMeta(
    'wordCount',
  );
  @override
  late final GeneratedColumn<int> wordCount = GeneratedColumn<int>(
    'word_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    check: () =>
        status.isIn(const ['draft', 'revising', 'complete', 'archived']),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('draft'),
  );
  static const VerificationMeta _lastDiagnosedAtMeta = const VerificationMeta(
    'lastDiagnosedAt',
  );
  @override
  late final GeneratedColumn<int> lastDiagnosedAt = GeneratedColumn<int>(
    'last_diagnosed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    manuscriptId,
    volumeId,
    title,
    content,
    previousContent,
    wordCount,
    sortOrder,
    status,
    lastDiagnosedAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chapters';
  @override
  VerificationContext validateIntegrity(
    Insertable<Chapter> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('manuscript_id')) {
      context.handle(
        _manuscriptIdMeta,
        manuscriptId.isAcceptableOrUnknown(
          data['manuscript_id']!,
          _manuscriptIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_manuscriptIdMeta);
    }
    if (data.containsKey('volume_id')) {
      context.handle(
        _volumeIdMeta,
        volumeId.isAcceptableOrUnknown(data['volume_id']!, _volumeIdMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('previous_content')) {
      context.handle(
        _previousContentMeta,
        previousContent.isAcceptableOrUnknown(
          data['previous_content']!,
          _previousContentMeta,
        ),
      );
    }
    if (data.containsKey('word_count')) {
      context.handle(
        _wordCountMeta,
        wordCount.isAcceptableOrUnknown(data['word_count']!, _wordCountMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('last_diagnosed_at')) {
      context.handle(
        _lastDiagnosedAtMeta,
        lastDiagnosedAt.isAcceptableOrUnknown(
          data['last_diagnosed_at']!,
          _lastDiagnosedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Chapter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Chapter(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      manuscriptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manuscript_id'],
      )!,
      volumeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}volume_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      previousContent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}previous_content'],
      ),
      wordCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}word_count'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      lastDiagnosedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_diagnosed_at'],
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
  $ChaptersTable createAlias(String alias) {
    return $ChaptersTable(attachedDatabase, alias);
  }
}

class Chapter extends DataClass implements Insertable<Chapter> {
  final String id;
  final String manuscriptId;
  final String? volumeId;
  final String title;
  final String content;
  final String? previousContent;
  final int wordCount;
  final int sortOrder;
  final String status;
  final int? lastDiagnosedAt;
  final int createdAt;
  final int updatedAt;
  const Chapter({
    required this.id,
    required this.manuscriptId,
    this.volumeId,
    required this.title,
    required this.content,
    this.previousContent,
    required this.wordCount,
    required this.sortOrder,
    required this.status,
    this.lastDiagnosedAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['manuscript_id'] = Variable<String>(manuscriptId);
    if (!nullToAbsent || volumeId != null) {
      map['volume_id'] = Variable<String>(volumeId);
    }
    map['title'] = Variable<String>(title);
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || previousContent != null) {
      map['previous_content'] = Variable<String>(previousContent);
    }
    map['word_count'] = Variable<int>(wordCount);
    map['sort_order'] = Variable<int>(sortOrder);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || lastDiagnosedAt != null) {
      map['last_diagnosed_at'] = Variable<int>(lastDiagnosedAt);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  ChaptersCompanion toCompanion(bool nullToAbsent) {
    return ChaptersCompanion(
      id: Value(id),
      manuscriptId: Value(manuscriptId),
      volumeId: volumeId == null && nullToAbsent
          ? const Value.absent()
          : Value(volumeId),
      title: Value(title),
      content: Value(content),
      previousContent: previousContent == null && nullToAbsent
          ? const Value.absent()
          : Value(previousContent),
      wordCount: Value(wordCount),
      sortOrder: Value(sortOrder),
      status: Value(status),
      lastDiagnosedAt: lastDiagnosedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastDiagnosedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Chapter.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Chapter(
      id: serializer.fromJson<String>(json['id']),
      manuscriptId: serializer.fromJson<String>(json['manuscriptId']),
      volumeId: serializer.fromJson<String?>(json['volumeId']),
      title: serializer.fromJson<String>(json['title']),
      content: serializer.fromJson<String>(json['content']),
      previousContent: serializer.fromJson<String?>(json['previousContent']),
      wordCount: serializer.fromJson<int>(json['wordCount']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      status: serializer.fromJson<String>(json['status']),
      lastDiagnosedAt: serializer.fromJson<int?>(json['lastDiagnosedAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'manuscriptId': serializer.toJson<String>(manuscriptId),
      'volumeId': serializer.toJson<String?>(volumeId),
      'title': serializer.toJson<String>(title),
      'content': serializer.toJson<String>(content),
      'previousContent': serializer.toJson<String?>(previousContent),
      'wordCount': serializer.toJson<int>(wordCount),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'status': serializer.toJson<String>(status),
      'lastDiagnosedAt': serializer.toJson<int?>(lastDiagnosedAt),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  Chapter copyWith({
    String? id,
    String? manuscriptId,
    Value<String?> volumeId = const Value.absent(),
    String? title,
    String? content,
    Value<String?> previousContent = const Value.absent(),
    int? wordCount,
    int? sortOrder,
    String? status,
    Value<int?> lastDiagnosedAt = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => Chapter(
    id: id ?? this.id,
    manuscriptId: manuscriptId ?? this.manuscriptId,
    volumeId: volumeId.present ? volumeId.value : this.volumeId,
    title: title ?? this.title,
    content: content ?? this.content,
    previousContent: previousContent.present
        ? previousContent.value
        : this.previousContent,
    wordCount: wordCount ?? this.wordCount,
    sortOrder: sortOrder ?? this.sortOrder,
    status: status ?? this.status,
    lastDiagnosedAt: lastDiagnosedAt.present
        ? lastDiagnosedAt.value
        : this.lastDiagnosedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Chapter copyWithCompanion(ChaptersCompanion data) {
    return Chapter(
      id: data.id.present ? data.id.value : this.id,
      manuscriptId: data.manuscriptId.present
          ? data.manuscriptId.value
          : this.manuscriptId,
      volumeId: data.volumeId.present ? data.volumeId.value : this.volumeId,
      title: data.title.present ? data.title.value : this.title,
      content: data.content.present ? data.content.value : this.content,
      previousContent: data.previousContent.present
          ? data.previousContent.value
          : this.previousContent,
      wordCount: data.wordCount.present ? data.wordCount.value : this.wordCount,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      status: data.status.present ? data.status.value : this.status,
      lastDiagnosedAt: data.lastDiagnosedAt.present
          ? data.lastDiagnosedAt.value
          : this.lastDiagnosedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Chapter(')
          ..write('id: $id, ')
          ..write('manuscriptId: $manuscriptId, ')
          ..write('volumeId: $volumeId, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('previousContent: $previousContent, ')
          ..write('wordCount: $wordCount, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('status: $status, ')
          ..write('lastDiagnosedAt: $lastDiagnosedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    manuscriptId,
    volumeId,
    title,
    content,
    previousContent,
    wordCount,
    sortOrder,
    status,
    lastDiagnosedAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Chapter &&
          other.id == this.id &&
          other.manuscriptId == this.manuscriptId &&
          other.volumeId == this.volumeId &&
          other.title == this.title &&
          other.content == this.content &&
          other.previousContent == this.previousContent &&
          other.wordCount == this.wordCount &&
          other.sortOrder == this.sortOrder &&
          other.status == this.status &&
          other.lastDiagnosedAt == this.lastDiagnosedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ChaptersCompanion extends UpdateCompanion<Chapter> {
  final Value<String> id;
  final Value<String> manuscriptId;
  final Value<String?> volumeId;
  final Value<String> title;
  final Value<String> content;
  final Value<String?> previousContent;
  final Value<int> wordCount;
  final Value<int> sortOrder;
  final Value<String> status;
  final Value<int?> lastDiagnosedAt;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const ChaptersCompanion({
    this.id = const Value.absent(),
    this.manuscriptId = const Value.absent(),
    this.volumeId = const Value.absent(),
    this.title = const Value.absent(),
    this.content = const Value.absent(),
    this.previousContent = const Value.absent(),
    this.wordCount = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.status = const Value.absent(),
    this.lastDiagnosedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChaptersCompanion.insert({
    required String id,
    required String manuscriptId,
    this.volumeId = const Value.absent(),
    this.title = const Value.absent(),
    this.content = const Value.absent(),
    this.previousContent = const Value.absent(),
    this.wordCount = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.status = const Value.absent(),
    this.lastDiagnosedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       manuscriptId = Value(manuscriptId);
  static Insertable<Chapter> custom({
    Expression<String>? id,
    Expression<String>? manuscriptId,
    Expression<String>? volumeId,
    Expression<String>? title,
    Expression<String>? content,
    Expression<String>? previousContent,
    Expression<int>? wordCount,
    Expression<int>? sortOrder,
    Expression<String>? status,
    Expression<int>? lastDiagnosedAt,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (manuscriptId != null) 'manuscript_id': manuscriptId,
      if (volumeId != null) 'volume_id': volumeId,
      if (title != null) 'title': title,
      if (content != null) 'content': content,
      if (previousContent != null) 'previous_content': previousContent,
      if (wordCount != null) 'word_count': wordCount,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (status != null) 'status': status,
      if (lastDiagnosedAt != null) 'last_diagnosed_at': lastDiagnosedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChaptersCompanion copyWith({
    Value<String>? id,
    Value<String>? manuscriptId,
    Value<String?>? volumeId,
    Value<String>? title,
    Value<String>? content,
    Value<String?>? previousContent,
    Value<int>? wordCount,
    Value<int>? sortOrder,
    Value<String>? status,
    Value<int?>? lastDiagnosedAt,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return ChaptersCompanion(
      id: id ?? this.id,
      manuscriptId: manuscriptId ?? this.manuscriptId,
      volumeId: volumeId ?? this.volumeId,
      title: title ?? this.title,
      content: content ?? this.content,
      previousContent: previousContent ?? this.previousContent,
      wordCount: wordCount ?? this.wordCount,
      sortOrder: sortOrder ?? this.sortOrder,
      status: status ?? this.status,
      lastDiagnosedAt: lastDiagnosedAt ?? this.lastDiagnosedAt,
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
    if (manuscriptId.present) {
      map['manuscript_id'] = Variable<String>(manuscriptId.value);
    }
    if (volumeId.present) {
      map['volume_id'] = Variable<String>(volumeId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (previousContent.present) {
      map['previous_content'] = Variable<String>(previousContent.value);
    }
    if (wordCount.present) {
      map['word_count'] = Variable<int>(wordCount.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (lastDiagnosedAt.present) {
      map['last_diagnosed_at'] = Variable<int>(lastDiagnosedAt.value);
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
    return (StringBuffer('ChaptersCompanion(')
          ..write('id: $id, ')
          ..write('manuscriptId: $manuscriptId, ')
          ..write('volumeId: $volumeId, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('previousContent: $previousContent, ')
          ..write('wordCount: $wordCount, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('status: $status, ')
          ..write('lastDiagnosedAt: $lastDiagnosedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionsTable extends Sessions
    with TableInfo<$SessionsTable, SessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('新建会话'),
  );
  static const VerificationMeta _previewMeta = const VerificationMeta(
    'preview',
  );
  @override
  late final GeneratedColumn<String> preview = GeneratedColumn<String>(
    'preview',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _manuscriptIdMeta = const VerificationMeta(
    'manuscriptId',
  );
  @override
  late final GeneratedColumn<String> manuscriptId = GeneratedColumn<String>(
    'manuscript_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES manuscripts (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _chapterIdMeta = const VerificationMeta(
    'chapterId',
  );
  @override
  late final GeneratedColumn<String> chapterId = GeneratedColumn<String>(
    'chapter_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES chapters (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _diagnosisSummaryMeta = const VerificationMeta(
    'diagnosisSummary',
  );
  @override
  late final GeneratedColumn<String> diagnosisSummary = GeneratedColumn<String>(
    'diagnosis_summary',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    preview,
    manuscriptId,
    chapterId,
    diagnosisSummary,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('preview')) {
      context.handle(
        _previewMeta,
        preview.isAcceptableOrUnknown(data['preview']!, _previewMeta),
      );
    }
    if (data.containsKey('manuscript_id')) {
      context.handle(
        _manuscriptIdMeta,
        manuscriptId.isAcceptableOrUnknown(
          data['manuscript_id']!,
          _manuscriptIdMeta,
        ),
      );
    }
    if (data.containsKey('chapter_id')) {
      context.handle(
        _chapterIdMeta,
        chapterId.isAcceptableOrUnknown(data['chapter_id']!, _chapterIdMeta),
      );
    }
    if (data.containsKey('diagnosis_summary')) {
      context.handle(
        _diagnosisSummaryMeta,
        diagnosisSummary.isAcceptableOrUnknown(
          data['diagnosis_summary']!,
          _diagnosisSummaryMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      preview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preview'],
      )!,
      manuscriptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manuscript_id'],
      ),
      chapterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_id'],
      ),
      diagnosisSummary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}diagnosis_summary'],
      )!,
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
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }
}

class SessionRow extends DataClass implements Insertable<SessionRow> {
  final String id;
  final String title;
  final String preview;
  final String? manuscriptId;
  final String? chapterId;
  final String diagnosisSummary;
  final int createdAt;
  final int updatedAt;
  const SessionRow({
    required this.id,
    required this.title,
    required this.preview,
    this.manuscriptId,
    this.chapterId,
    required this.diagnosisSummary,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['preview'] = Variable<String>(preview);
    if (!nullToAbsent || manuscriptId != null) {
      map['manuscript_id'] = Variable<String>(manuscriptId);
    }
    if (!nullToAbsent || chapterId != null) {
      map['chapter_id'] = Variable<String>(chapterId);
    }
    map['diagnosis_summary'] = Variable<String>(diagnosisSummary);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      id: Value(id),
      title: Value(title),
      preview: Value(preview),
      manuscriptId: manuscriptId == null && nullToAbsent
          ? const Value.absent()
          : Value(manuscriptId),
      chapterId: chapterId == null && nullToAbsent
          ? const Value.absent()
          : Value(chapterId),
      diagnosisSummary: Value(diagnosisSummary),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      preview: serializer.fromJson<String>(json['preview']),
      manuscriptId: serializer.fromJson<String?>(json['manuscriptId']),
      chapterId: serializer.fromJson<String?>(json['chapterId']),
      diagnosisSummary: serializer.fromJson<String>(json['diagnosisSummary']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'preview': serializer.toJson<String>(preview),
      'manuscriptId': serializer.toJson<String?>(manuscriptId),
      'chapterId': serializer.toJson<String?>(chapterId),
      'diagnosisSummary': serializer.toJson<String>(diagnosisSummary),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  SessionRow copyWith({
    String? id,
    String? title,
    String? preview,
    Value<String?> manuscriptId = const Value.absent(),
    Value<String?> chapterId = const Value.absent(),
    String? diagnosisSummary,
    int? createdAt,
    int? updatedAt,
  }) => SessionRow(
    id: id ?? this.id,
    title: title ?? this.title,
    preview: preview ?? this.preview,
    manuscriptId: manuscriptId.present ? manuscriptId.value : this.manuscriptId,
    chapterId: chapterId.present ? chapterId.value : this.chapterId,
    diagnosisSummary: diagnosisSummary ?? this.diagnosisSummary,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SessionRow copyWithCompanion(SessionsCompanion data) {
    return SessionRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      preview: data.preview.present ? data.preview.value : this.preview,
      manuscriptId: data.manuscriptId.present
          ? data.manuscriptId.value
          : this.manuscriptId,
      chapterId: data.chapterId.present ? data.chapterId.value : this.chapterId,
      diagnosisSummary: data.diagnosisSummary.present
          ? data.diagnosisSummary.value
          : this.diagnosisSummary,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('preview: $preview, ')
          ..write('manuscriptId: $manuscriptId, ')
          ..write('chapterId: $chapterId, ')
          ..write('diagnosisSummary: $diagnosisSummary, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    preview,
    manuscriptId,
    chapterId,
    diagnosisSummary,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.preview == this.preview &&
          other.manuscriptId == this.manuscriptId &&
          other.chapterId == this.chapterId &&
          other.diagnosisSummary == this.diagnosisSummary &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SessionsCompanion extends UpdateCompanion<SessionRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> preview;
  final Value<String?> manuscriptId;
  final Value<String?> chapterId;
  final Value<String> diagnosisSummary;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const SessionsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.preview = const Value.absent(),
    this.manuscriptId = const Value.absent(),
    this.chapterId = const Value.absent(),
    this.diagnosisSummary = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    this.preview = const Value.absent(),
    this.manuscriptId = const Value.absent(),
    this.chapterId = const Value.absent(),
    this.diagnosisSummary = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<SessionRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? preview,
    Expression<String>? manuscriptId,
    Expression<String>? chapterId,
    Expression<String>? diagnosisSummary,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (preview != null) 'preview': preview,
      if (manuscriptId != null) 'manuscript_id': manuscriptId,
      if (chapterId != null) 'chapter_id': chapterId,
      if (diagnosisSummary != null) 'diagnosis_summary': diagnosisSummary,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? preview,
    Value<String?>? manuscriptId,
    Value<String?>? chapterId,
    Value<String>? diagnosisSummary,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return SessionsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      preview: preview ?? this.preview,
      manuscriptId: manuscriptId ?? this.manuscriptId,
      chapterId: chapterId ?? this.chapterId,
      diagnosisSummary: diagnosisSummary ?? this.diagnosisSummary,
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
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (preview.present) {
      map['preview'] = Variable<String>(preview.value);
    }
    if (manuscriptId.present) {
      map['manuscript_id'] = Variable<String>(manuscriptId.value);
    }
    if (chapterId.present) {
      map['chapter_id'] = Variable<String>(chapterId.value);
    }
    if (diagnosisSummary.present) {
      map['diagnosis_summary'] = Variable<String>(diagnosisSummary.value);
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
    return (StringBuffer('SessionsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('preview: $preview, ')
          ..write('manuscriptId: $manuscriptId, ')
          ..write('chapterId: $chapterId, ')
          ..write('diagnosisSummary: $diagnosisSummary, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    check: () => role.isIn(const ['user', 'assistant', 'system']),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  static const VerificationMeta _messageTypeMeta = const VerificationMeta(
    'messageType',
  );
  @override
  late final GeneratedColumn<String> messageType = GeneratedColumn<String>(
    'message_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('chat'),
  );
  static const VerificationMeta _referencesJsonMeta = const VerificationMeta(
    'referencesJson',
  );
  @override
  late final GeneratedColumn<String> referencesJson = GeneratedColumn<String>(
    'references_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    role,
    content,
    timestamp,
    messageType,
    referencesJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Message> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    }
    if (data.containsKey('message_type')) {
      context.handle(
        _messageTypeMeta,
        messageType.isAcceptableOrUnknown(
          data['message_type']!,
          _messageTypeMeta,
        ),
      );
    }
    if (data.containsKey('references_json')) {
      context.handle(
        _referencesJsonMeta,
        referencesJson.isAcceptableOrUnknown(
          data['references_json']!,
          _referencesJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp'],
      )!,
      messageType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_type'],
      )!,
      referencesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}references_json'],
      ),
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  final String id;
  final String sessionId;
  final String role;
  final String content;
  final int timestamp;
  final String messageType;
  final String? referencesJson;
  const Message({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.timestamp,
    required this.messageType,
    this.referencesJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['role'] = Variable<String>(role);
    map['content'] = Variable<String>(content);
    map['timestamp'] = Variable<int>(timestamp);
    map['message_type'] = Variable<String>(messageType);
    if (!nullToAbsent || referencesJson != null) {
      map['references_json'] = Variable<String>(referencesJson);
    }
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      role: Value(role),
      content: Value(content),
      timestamp: Value(timestamp),
      messageType: Value(messageType),
      referencesJson: referencesJson == null && nullToAbsent
          ? const Value.absent()
          : Value(referencesJson),
    );
  }

  factory Message.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      role: serializer.fromJson<String>(json['role']),
      content: serializer.fromJson<String>(json['content']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
      messageType: serializer.fromJson<String>(json['messageType']),
      referencesJson: serializer.fromJson<String?>(json['referencesJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'role': serializer.toJson<String>(role),
      'content': serializer.toJson<String>(content),
      'timestamp': serializer.toJson<int>(timestamp),
      'messageType': serializer.toJson<String>(messageType),
      'referencesJson': serializer.toJson<String?>(referencesJson),
    };
  }

  Message copyWith({
    String? id,
    String? sessionId,
    String? role,
    String? content,
    int? timestamp,
    String? messageType,
    Value<String?> referencesJson = const Value.absent(),
  }) => Message(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    role: role ?? this.role,
    content: content ?? this.content,
    timestamp: timestamp ?? this.timestamp,
    messageType: messageType ?? this.messageType,
    referencesJson: referencesJson.present
        ? referencesJson.value
        : this.referencesJson,
  );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      messageType: data.messageType.present
          ? data.messageType.value
          : this.messageType,
      referencesJson: data.referencesJson.present
          ? data.referencesJson.value
          : this.referencesJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('timestamp: $timestamp, ')
          ..write('messageType: $messageType, ')
          ..write('referencesJson: $referencesJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    role,
    content,
    timestamp,
    messageType,
    referencesJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.role == this.role &&
          other.content == this.content &&
          other.timestamp == this.timestamp &&
          other.messageType == this.messageType &&
          other.referencesJson == this.referencesJson);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> role;
  final Value<String> content;
  final Value<int> timestamp;
  final Value<String> messageType;
  final Value<String?> referencesJson;
  final Value<int> rowid;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.messageType = const Value.absent(),
    this.referencesJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String id,
    required String sessionId,
    required String role,
    required String content,
    this.timestamp = const Value.absent(),
    this.messageType = const Value.absent(),
    this.referencesJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       role = Value(role),
       content = Value(content);
  static Insertable<Message> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? role,
    Expression<String>? content,
    Expression<int>? timestamp,
    Expression<String>? messageType,
    Expression<String>? referencesJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (timestamp != null) 'timestamp': timestamp,
      if (messageType != null) 'message_type': messageType,
      if (referencesJson != null) 'references_json': referencesJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? role,
    Value<String>? content,
    Value<int>? timestamp,
    Value<String>? messageType,
    Value<String?>? referencesJson,
    Value<int>? rowid,
  }) {
    return MessagesCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      messageType: messageType ?? this.messageType,
      referencesJson: referencesJson ?? this.referencesJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
    }
    if (messageType.present) {
      map['message_type'] = Variable<String>(messageType.value);
    }
    if (referencesJson.present) {
      map['references_json'] = Variable<String>(referencesJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('timestamp: $timestamp, ')
          ..write('messageType: $messageType, ')
          ..write('referencesJson: $referencesJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DiagnosisResultsTable extends DiagnosisResults
    with TableInfo<$DiagnosisResultsTable, DiagnosisRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DiagnosisResultsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syndromesMeta = const VerificationMeta(
    'syndromes',
  );
  @override
  late final GeneratedColumn<String> syndromes = GeneratedColumn<String>(
    'syndromes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _suggestedActionsMeta = const VerificationMeta(
    'suggestedActions',
  );
  @override
  late final GeneratedColumn<String> suggestedActions = GeneratedColumn<String>(
    'suggested_actions',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _rootCauseAnalysisMeta = const VerificationMeta(
    'rootCauseAnalysis',
  );
  @override
  late final GeneratedColumn<String> rootCauseAnalysis =
      GeneratedColumn<String>(
        'root_cause_analysis',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _nextFocusMeta = const VerificationMeta(
    'nextFocus',
  );
  @override
  late final GeneratedColumn<String> nextFocus = GeneratedColumn<String>(
    'next_focus',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _feedbackSummaryMeta = const VerificationMeta(
    'feedbackSummary',
  );
  @override
  late final GeneratedColumn<String> feedbackSummary = GeneratedColumn<String>(
    'feedback_summary',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<double> confidence = GeneratedColumn<double>(
    'confidence',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _teachingProgressMeta = const VerificationMeta(
    'teachingProgress',
  );
  @override
  late final GeneratedColumn<String> teachingProgress = GeneratedColumn<String>(
    'teaching_progress',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _targetRefTypeMeta = const VerificationMeta(
    'targetRefType',
  );
  @override
  late final GeneratedColumn<String> targetRefType = GeneratedColumn<String>(
    'target_ref_type',
    aliasedName,
    true,
    check: () =>
        targetRefType.isNull() |
        targetRefType.isIn(const ['manuscript', 'chapter']),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _targetRefIdMeta = const VerificationMeta(
    'targetRefId',
  );
  @override
  late final GeneratedColumn<String> targetRefId = GeneratedColumn<String>(
    'target_ref_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  static const VerificationMeta _currentTeachingFocusIdMeta =
      const VerificationMeta('currentTeachingFocusId');
  @override
  late final GeneratedColumn<String> currentTeachingFocusId =
      GeneratedColumn<String>(
        'current_teaching_focus_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _focusReasonMeta = const VerificationMeta(
    'focusReason',
  );
  @override
  late final GeneratedColumn<String> focusReason = GeneratedColumn<String>(
    'focus_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    messageId,
    syndromes,
    suggestedActions,
    rootCauseAnalysis,
    nextFocus,
    feedbackSummary,
    confidence,
    teachingProgress,
    targetRefType,
    targetRefId,
    timestamp,
    createdAt,
    currentTeachingFocusId,
    focusReason,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'diagnosis_results';
  @override
  VerificationContext validateIntegrity(
    Insertable<DiagnosisRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('syndromes')) {
      context.handle(
        _syndromesMeta,
        syndromes.isAcceptableOrUnknown(data['syndromes']!, _syndromesMeta),
      );
    }
    if (data.containsKey('suggested_actions')) {
      context.handle(
        _suggestedActionsMeta,
        suggestedActions.isAcceptableOrUnknown(
          data['suggested_actions']!,
          _suggestedActionsMeta,
        ),
      );
    }
    if (data.containsKey('root_cause_analysis')) {
      context.handle(
        _rootCauseAnalysisMeta,
        rootCauseAnalysis.isAcceptableOrUnknown(
          data['root_cause_analysis']!,
          _rootCauseAnalysisMeta,
        ),
      );
    }
    if (data.containsKey('next_focus')) {
      context.handle(
        _nextFocusMeta,
        nextFocus.isAcceptableOrUnknown(data['next_focus']!, _nextFocusMeta),
      );
    }
    if (data.containsKey('feedback_summary')) {
      context.handle(
        _feedbackSummaryMeta,
        feedbackSummary.isAcceptableOrUnknown(
          data['feedback_summary']!,
          _feedbackSummaryMeta,
        ),
      );
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    }
    if (data.containsKey('teaching_progress')) {
      context.handle(
        _teachingProgressMeta,
        teachingProgress.isAcceptableOrUnknown(
          data['teaching_progress']!,
          _teachingProgressMeta,
        ),
      );
    }
    if (data.containsKey('target_ref_type')) {
      context.handle(
        _targetRefTypeMeta,
        targetRefType.isAcceptableOrUnknown(
          data['target_ref_type']!,
          _targetRefTypeMeta,
        ),
      );
    }
    if (data.containsKey('target_ref_id')) {
      context.handle(
        _targetRefIdMeta,
        targetRefId.isAcceptableOrUnknown(
          data['target_ref_id']!,
          _targetRefIdMeta,
        ),
      );
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('current_teaching_focus_id')) {
      context.handle(
        _currentTeachingFocusIdMeta,
        currentTeachingFocusId.isAcceptableOrUnknown(
          data['current_teaching_focus_id']!,
          _currentTeachingFocusIdMeta,
        ),
      );
    }
    if (data.containsKey('focus_reason')) {
      context.handle(
        _focusReasonMeta,
        focusReason.isAcceptableOrUnknown(
          data['focus_reason']!,
          _focusReasonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {sessionId, messageId},
  ];
  @override
  DiagnosisRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DiagnosisRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      syndromes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}syndromes'],
      )!,
      suggestedActions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}suggested_actions'],
      )!,
      rootCauseAnalysis: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}root_cause_analysis'],
      ),
      nextFocus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}next_focus'],
      ),
      feedbackSummary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}feedback_summary'],
      ),
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}confidence'],
      )!,
      teachingProgress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}teaching_progress'],
      ),
      targetRefType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_ref_type'],
      ),
      targetRefId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_ref_id'],
      ),
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      currentTeachingFocusId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_teaching_focus_id'],
      ),
      focusReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}focus_reason'],
      ),
    );
  }

  @override
  $DiagnosisResultsTable createAlias(String alias) {
    return $DiagnosisResultsTable(attachedDatabase, alias);
  }
}

class DiagnosisRow extends DataClass implements Insertable<DiagnosisRow> {
  final String id;
  final String sessionId;
  final String messageId;
  final String syndromes;
  final String suggestedActions;
  final String? rootCauseAnalysis;
  final String? nextFocus;
  final String? feedbackSummary;
  final double confidence;
  final String? teachingProgress;
  final String? targetRefType;
  final String? targetRefId;
  final int timestamp;
  final int createdAt;
  final String? currentTeachingFocusId;
  final String? focusReason;
  const DiagnosisRow({
    required this.id,
    required this.sessionId,
    required this.messageId,
    required this.syndromes,
    required this.suggestedActions,
    this.rootCauseAnalysis,
    this.nextFocus,
    this.feedbackSummary,
    required this.confidence,
    this.teachingProgress,
    this.targetRefType,
    this.targetRefId,
    required this.timestamp,
    required this.createdAt,
    this.currentTeachingFocusId,
    this.focusReason,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['message_id'] = Variable<String>(messageId);
    map['syndromes'] = Variable<String>(syndromes);
    map['suggested_actions'] = Variable<String>(suggestedActions);
    if (!nullToAbsent || rootCauseAnalysis != null) {
      map['root_cause_analysis'] = Variable<String>(rootCauseAnalysis);
    }
    if (!nullToAbsent || nextFocus != null) {
      map['next_focus'] = Variable<String>(nextFocus);
    }
    if (!nullToAbsent || feedbackSummary != null) {
      map['feedback_summary'] = Variable<String>(feedbackSummary);
    }
    map['confidence'] = Variable<double>(confidence);
    if (!nullToAbsent || teachingProgress != null) {
      map['teaching_progress'] = Variable<String>(teachingProgress);
    }
    if (!nullToAbsent || targetRefType != null) {
      map['target_ref_type'] = Variable<String>(targetRefType);
    }
    if (!nullToAbsent || targetRefId != null) {
      map['target_ref_id'] = Variable<String>(targetRefId);
    }
    map['timestamp'] = Variable<int>(timestamp);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || currentTeachingFocusId != null) {
      map['current_teaching_focus_id'] = Variable<String>(
        currentTeachingFocusId,
      );
    }
    if (!nullToAbsent || focusReason != null) {
      map['focus_reason'] = Variable<String>(focusReason);
    }
    return map;
  }

  DiagnosisResultsCompanion toCompanion(bool nullToAbsent) {
    return DiagnosisResultsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      messageId: Value(messageId),
      syndromes: Value(syndromes),
      suggestedActions: Value(suggestedActions),
      rootCauseAnalysis: rootCauseAnalysis == null && nullToAbsent
          ? const Value.absent()
          : Value(rootCauseAnalysis),
      nextFocus: nextFocus == null && nullToAbsent
          ? const Value.absent()
          : Value(nextFocus),
      feedbackSummary: feedbackSummary == null && nullToAbsent
          ? const Value.absent()
          : Value(feedbackSummary),
      confidence: Value(confidence),
      teachingProgress: teachingProgress == null && nullToAbsent
          ? const Value.absent()
          : Value(teachingProgress),
      targetRefType: targetRefType == null && nullToAbsent
          ? const Value.absent()
          : Value(targetRefType),
      targetRefId: targetRefId == null && nullToAbsent
          ? const Value.absent()
          : Value(targetRefId),
      timestamp: Value(timestamp),
      createdAt: Value(createdAt),
      currentTeachingFocusId: currentTeachingFocusId == null && nullToAbsent
          ? const Value.absent()
          : Value(currentTeachingFocusId),
      focusReason: focusReason == null && nullToAbsent
          ? const Value.absent()
          : Value(focusReason),
    );
  }

  factory DiagnosisRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DiagnosisRow(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      messageId: serializer.fromJson<String>(json['messageId']),
      syndromes: serializer.fromJson<String>(json['syndromes']),
      suggestedActions: serializer.fromJson<String>(json['suggestedActions']),
      rootCauseAnalysis: serializer.fromJson<String?>(
        json['rootCauseAnalysis'],
      ),
      nextFocus: serializer.fromJson<String?>(json['nextFocus']),
      feedbackSummary: serializer.fromJson<String?>(json['feedbackSummary']),
      confidence: serializer.fromJson<double>(json['confidence']),
      teachingProgress: serializer.fromJson<String?>(json['teachingProgress']),
      targetRefType: serializer.fromJson<String?>(json['targetRefType']),
      targetRefId: serializer.fromJson<String?>(json['targetRefId']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      currentTeachingFocusId: serializer.fromJson<String?>(
        json['currentTeachingFocusId'],
      ),
      focusReason: serializer.fromJson<String?>(json['focusReason']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'messageId': serializer.toJson<String>(messageId),
      'syndromes': serializer.toJson<String>(syndromes),
      'suggestedActions': serializer.toJson<String>(suggestedActions),
      'rootCauseAnalysis': serializer.toJson<String?>(rootCauseAnalysis),
      'nextFocus': serializer.toJson<String?>(nextFocus),
      'feedbackSummary': serializer.toJson<String?>(feedbackSummary),
      'confidence': serializer.toJson<double>(confidence),
      'teachingProgress': serializer.toJson<String?>(teachingProgress),
      'targetRefType': serializer.toJson<String?>(targetRefType),
      'targetRefId': serializer.toJson<String?>(targetRefId),
      'timestamp': serializer.toJson<int>(timestamp),
      'createdAt': serializer.toJson<int>(createdAt),
      'currentTeachingFocusId': serializer.toJson<String?>(
        currentTeachingFocusId,
      ),
      'focusReason': serializer.toJson<String?>(focusReason),
    };
  }

  DiagnosisRow copyWith({
    String? id,
    String? sessionId,
    String? messageId,
    String? syndromes,
    String? suggestedActions,
    Value<String?> rootCauseAnalysis = const Value.absent(),
    Value<String?> nextFocus = const Value.absent(),
    Value<String?> feedbackSummary = const Value.absent(),
    double? confidence,
    Value<String?> teachingProgress = const Value.absent(),
    Value<String?> targetRefType = const Value.absent(),
    Value<String?> targetRefId = const Value.absent(),
    int? timestamp,
    int? createdAt,
    Value<String?> currentTeachingFocusId = const Value.absent(),
    Value<String?> focusReason = const Value.absent(),
  }) => DiagnosisRow(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    messageId: messageId ?? this.messageId,
    syndromes: syndromes ?? this.syndromes,
    suggestedActions: suggestedActions ?? this.suggestedActions,
    rootCauseAnalysis: rootCauseAnalysis.present
        ? rootCauseAnalysis.value
        : this.rootCauseAnalysis,
    nextFocus: nextFocus.present ? nextFocus.value : this.nextFocus,
    feedbackSummary: feedbackSummary.present
        ? feedbackSummary.value
        : this.feedbackSummary,
    confidence: confidence ?? this.confidence,
    teachingProgress: teachingProgress.present
        ? teachingProgress.value
        : this.teachingProgress,
    targetRefType: targetRefType.present
        ? targetRefType.value
        : this.targetRefType,
    targetRefId: targetRefId.present ? targetRefId.value : this.targetRefId,
    timestamp: timestamp ?? this.timestamp,
    createdAt: createdAt ?? this.createdAt,
    currentTeachingFocusId: currentTeachingFocusId.present
        ? currentTeachingFocusId.value
        : this.currentTeachingFocusId,
    focusReason: focusReason.present ? focusReason.value : this.focusReason,
  );
  DiagnosisRow copyWithCompanion(DiagnosisResultsCompanion data) {
    return DiagnosisRow(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      syndromes: data.syndromes.present ? data.syndromes.value : this.syndromes,
      suggestedActions: data.suggestedActions.present
          ? data.suggestedActions.value
          : this.suggestedActions,
      rootCauseAnalysis: data.rootCauseAnalysis.present
          ? data.rootCauseAnalysis.value
          : this.rootCauseAnalysis,
      nextFocus: data.nextFocus.present ? data.nextFocus.value : this.nextFocus,
      feedbackSummary: data.feedbackSummary.present
          ? data.feedbackSummary.value
          : this.feedbackSummary,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
      teachingProgress: data.teachingProgress.present
          ? data.teachingProgress.value
          : this.teachingProgress,
      targetRefType: data.targetRefType.present
          ? data.targetRefType.value
          : this.targetRefType,
      targetRefId: data.targetRefId.present
          ? data.targetRefId.value
          : this.targetRefId,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      currentTeachingFocusId: data.currentTeachingFocusId.present
          ? data.currentTeachingFocusId.value
          : this.currentTeachingFocusId,
      focusReason: data.focusReason.present
          ? data.focusReason.value
          : this.focusReason,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DiagnosisRow(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('messageId: $messageId, ')
          ..write('syndromes: $syndromes, ')
          ..write('suggestedActions: $suggestedActions, ')
          ..write('rootCauseAnalysis: $rootCauseAnalysis, ')
          ..write('nextFocus: $nextFocus, ')
          ..write('feedbackSummary: $feedbackSummary, ')
          ..write('confidence: $confidence, ')
          ..write('teachingProgress: $teachingProgress, ')
          ..write('targetRefType: $targetRefType, ')
          ..write('targetRefId: $targetRefId, ')
          ..write('timestamp: $timestamp, ')
          ..write('createdAt: $createdAt, ')
          ..write('currentTeachingFocusId: $currentTeachingFocusId, ')
          ..write('focusReason: $focusReason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    messageId,
    syndromes,
    suggestedActions,
    rootCauseAnalysis,
    nextFocus,
    feedbackSummary,
    confidence,
    teachingProgress,
    targetRefType,
    targetRefId,
    timestamp,
    createdAt,
    currentTeachingFocusId,
    focusReason,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiagnosisRow &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.messageId == this.messageId &&
          other.syndromes == this.syndromes &&
          other.suggestedActions == this.suggestedActions &&
          other.rootCauseAnalysis == this.rootCauseAnalysis &&
          other.nextFocus == this.nextFocus &&
          other.feedbackSummary == this.feedbackSummary &&
          other.confidence == this.confidence &&
          other.teachingProgress == this.teachingProgress &&
          other.targetRefType == this.targetRefType &&
          other.targetRefId == this.targetRefId &&
          other.timestamp == this.timestamp &&
          other.createdAt == this.createdAt &&
          other.currentTeachingFocusId == this.currentTeachingFocusId &&
          other.focusReason == this.focusReason);
}

class DiagnosisResultsCompanion extends UpdateCompanion<DiagnosisRow> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> messageId;
  final Value<String> syndromes;
  final Value<String> suggestedActions;
  final Value<String?> rootCauseAnalysis;
  final Value<String?> nextFocus;
  final Value<String?> feedbackSummary;
  final Value<double> confidence;
  final Value<String?> teachingProgress;
  final Value<String?> targetRefType;
  final Value<String?> targetRefId;
  final Value<int> timestamp;
  final Value<int> createdAt;
  final Value<String?> currentTeachingFocusId;
  final Value<String?> focusReason;
  final Value<int> rowid;
  const DiagnosisResultsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.syndromes = const Value.absent(),
    this.suggestedActions = const Value.absent(),
    this.rootCauseAnalysis = const Value.absent(),
    this.nextFocus = const Value.absent(),
    this.feedbackSummary = const Value.absent(),
    this.confidence = const Value.absent(),
    this.teachingProgress = const Value.absent(),
    this.targetRefType = const Value.absent(),
    this.targetRefId = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.currentTeachingFocusId = const Value.absent(),
    this.focusReason = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DiagnosisResultsCompanion.insert({
    required String id,
    required String sessionId,
    required String messageId,
    this.syndromes = const Value.absent(),
    this.suggestedActions = const Value.absent(),
    this.rootCauseAnalysis = const Value.absent(),
    this.nextFocus = const Value.absent(),
    this.feedbackSummary = const Value.absent(),
    this.confidence = const Value.absent(),
    this.teachingProgress = const Value.absent(),
    this.targetRefType = const Value.absent(),
    this.targetRefId = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.currentTeachingFocusId = const Value.absent(),
    this.focusReason = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       messageId = Value(messageId);
  static Insertable<DiagnosisRow> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? messageId,
    Expression<String>? syndromes,
    Expression<String>? suggestedActions,
    Expression<String>? rootCauseAnalysis,
    Expression<String>? nextFocus,
    Expression<String>? feedbackSummary,
    Expression<double>? confidence,
    Expression<String>? teachingProgress,
    Expression<String>? targetRefType,
    Expression<String>? targetRefId,
    Expression<int>? timestamp,
    Expression<int>? createdAt,
    Expression<String>? currentTeachingFocusId,
    Expression<String>? focusReason,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (messageId != null) 'message_id': messageId,
      if (syndromes != null) 'syndromes': syndromes,
      if (suggestedActions != null) 'suggested_actions': suggestedActions,
      if (rootCauseAnalysis != null) 'root_cause_analysis': rootCauseAnalysis,
      if (nextFocus != null) 'next_focus': nextFocus,
      if (feedbackSummary != null) 'feedback_summary': feedbackSummary,
      if (confidence != null) 'confidence': confidence,
      if (teachingProgress != null) 'teaching_progress': teachingProgress,
      if (targetRefType != null) 'target_ref_type': targetRefType,
      if (targetRefId != null) 'target_ref_id': targetRefId,
      if (timestamp != null) 'timestamp': timestamp,
      if (createdAt != null) 'created_at': createdAt,
      if (currentTeachingFocusId != null)
        'current_teaching_focus_id': currentTeachingFocusId,
      if (focusReason != null) 'focus_reason': focusReason,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DiagnosisResultsCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? messageId,
    Value<String>? syndromes,
    Value<String>? suggestedActions,
    Value<String?>? rootCauseAnalysis,
    Value<String?>? nextFocus,
    Value<String?>? feedbackSummary,
    Value<double>? confidence,
    Value<String?>? teachingProgress,
    Value<String?>? targetRefType,
    Value<String?>? targetRefId,
    Value<int>? timestamp,
    Value<int>? createdAt,
    Value<String?>? currentTeachingFocusId,
    Value<String?>? focusReason,
    Value<int>? rowid,
  }) {
    return DiagnosisResultsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      messageId: messageId ?? this.messageId,
      syndromes: syndromes ?? this.syndromes,
      suggestedActions: suggestedActions ?? this.suggestedActions,
      rootCauseAnalysis: rootCauseAnalysis ?? this.rootCauseAnalysis,
      nextFocus: nextFocus ?? this.nextFocus,
      feedbackSummary: feedbackSummary ?? this.feedbackSummary,
      confidence: confidence ?? this.confidence,
      teachingProgress: teachingProgress ?? this.teachingProgress,
      targetRefType: targetRefType ?? this.targetRefType,
      targetRefId: targetRefId ?? this.targetRefId,
      timestamp: timestamp ?? this.timestamp,
      createdAt: createdAt ?? this.createdAt,
      currentTeachingFocusId:
          currentTeachingFocusId ?? this.currentTeachingFocusId,
      focusReason: focusReason ?? this.focusReason,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (syndromes.present) {
      map['syndromes'] = Variable<String>(syndromes.value);
    }
    if (suggestedActions.present) {
      map['suggested_actions'] = Variable<String>(suggestedActions.value);
    }
    if (rootCauseAnalysis.present) {
      map['root_cause_analysis'] = Variable<String>(rootCauseAnalysis.value);
    }
    if (nextFocus.present) {
      map['next_focus'] = Variable<String>(nextFocus.value);
    }
    if (feedbackSummary.present) {
      map['feedback_summary'] = Variable<String>(feedbackSummary.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<double>(confidence.value);
    }
    if (teachingProgress.present) {
      map['teaching_progress'] = Variable<String>(teachingProgress.value);
    }
    if (targetRefType.present) {
      map['target_ref_type'] = Variable<String>(targetRefType.value);
    }
    if (targetRefId.present) {
      map['target_ref_id'] = Variable<String>(targetRefId.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (currentTeachingFocusId.present) {
      map['current_teaching_focus_id'] = Variable<String>(
        currentTeachingFocusId.value,
      );
    }
    if (focusReason.present) {
      map['focus_reason'] = Variable<String>(focusReason.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DiagnosisResultsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('messageId: $messageId, ')
          ..write('syndromes: $syndromes, ')
          ..write('suggestedActions: $suggestedActions, ')
          ..write('rootCauseAnalysis: $rootCauseAnalysis, ')
          ..write('nextFocus: $nextFocus, ')
          ..write('feedbackSummary: $feedbackSummary, ')
          ..write('confidence: $confidence, ')
          ..write('teachingProgress: $teachingProgress, ')
          ..write('targetRefType: $targetRefType, ')
          ..write('targetRefId: $targetRefId, ')
          ..write('timestamp: $timestamp, ')
          ..write('createdAt: $createdAt, ')
          ..write('currentTeachingFocusId: $currentTeachingFocusId, ')
          ..write('focusReason: $focusReason, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TeachingStateTable extends TeachingState
    with TableInfo<$TeachingStateTable, TeachingStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TeachingStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'UNIQUE REFERENCES sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _currentPhaseMeta = const VerificationMeta(
    'currentPhase',
  );
  @override
  late final GeneratedColumn<String> currentPhase = GeneratedColumn<String>(
    'current_phase',
    aliasedName,
    false,
    check: () => currentPhase.isIn(const [
      'P0_ENGAGE',
      'P1_WORLD',
      'P2_PRACTICE_LOOP',
      'P3_TRAINING',
      'P4_REVIEW',
    ]),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('P0_ENGAGE'),
  );
  static const VerificationMeta _currentSubphaseMeta = const VerificationMeta(
    'currentSubphase',
  );
  @override
  late final GeneratedColumn<String> currentSubphase = GeneratedColumn<String>(
    'current_subphase',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attitudeLevelMeta = const VerificationMeta(
    'attitudeLevel',
  );
  @override
  late final GeneratedColumn<String> attitudeLevel = GeneratedColumn<String>(
    'attitude_level',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _beginnerLevelMeta = const VerificationMeta(
    'beginnerLevel',
  );
  @override
  late final GeneratedColumn<String> beginnerLevel = GeneratedColumn<String>(
    'beginner_level',
    aliasedName,
    true,
    check: () =>
        beginnerLevel.isNull() |
        beginnerLevel.isIn(const [
          'N0_ENGAGE',
          'N1_ELEMENTS',
          'N2_SCENE',
          'N3_DIAGNOSE',
          'N4_INDEPENDENT',
        ]),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    currentPhase,
    currentSubphase,
    attitudeLevel,
    beginnerLevel,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'teaching_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<TeachingStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('current_phase')) {
      context.handle(
        _currentPhaseMeta,
        currentPhase.isAcceptableOrUnknown(
          data['current_phase']!,
          _currentPhaseMeta,
        ),
      );
    }
    if (data.containsKey('current_subphase')) {
      context.handle(
        _currentSubphaseMeta,
        currentSubphase.isAcceptableOrUnknown(
          data['current_subphase']!,
          _currentSubphaseMeta,
        ),
      );
    }
    if (data.containsKey('attitude_level')) {
      context.handle(
        _attitudeLevelMeta,
        attitudeLevel.isAcceptableOrUnknown(
          data['attitude_level']!,
          _attitudeLevelMeta,
        ),
      );
    }
    if (data.containsKey('beginner_level')) {
      context.handle(
        _beginnerLevelMeta,
        beginnerLevel.isAcceptableOrUnknown(
          data['beginner_level']!,
          _beginnerLevelMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TeachingStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TeachingStateRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      currentPhase: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_phase'],
      )!,
      currentSubphase: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_subphase'],
      ),
      attitudeLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attitude_level'],
      ),
      beginnerLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}beginner_level'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $TeachingStateTable createAlias(String alias) {
    return $TeachingStateTable(attachedDatabase, alias);
  }
}

class TeachingStateRow extends DataClass
    implements Insertable<TeachingStateRow> {
  final String id;
  final String sessionId;
  final String currentPhase;
  final String? currentSubphase;
  final String? attitudeLevel;
  final String? beginnerLevel;
  final int updatedAt;
  const TeachingStateRow({
    required this.id,
    required this.sessionId,
    required this.currentPhase,
    this.currentSubphase,
    this.attitudeLevel,
    this.beginnerLevel,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['current_phase'] = Variable<String>(currentPhase);
    if (!nullToAbsent || currentSubphase != null) {
      map['current_subphase'] = Variable<String>(currentSubphase);
    }
    if (!nullToAbsent || attitudeLevel != null) {
      map['attitude_level'] = Variable<String>(attitudeLevel);
    }
    if (!nullToAbsent || beginnerLevel != null) {
      map['beginner_level'] = Variable<String>(beginnerLevel);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  TeachingStateCompanion toCompanion(bool nullToAbsent) {
    return TeachingStateCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      currentPhase: Value(currentPhase),
      currentSubphase: currentSubphase == null && nullToAbsent
          ? const Value.absent()
          : Value(currentSubphase),
      attitudeLevel: attitudeLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(attitudeLevel),
      beginnerLevel: beginnerLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(beginnerLevel),
      updatedAt: Value(updatedAt),
    );
  }

  factory TeachingStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TeachingStateRow(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      currentPhase: serializer.fromJson<String>(json['currentPhase']),
      currentSubphase: serializer.fromJson<String?>(json['currentSubphase']),
      attitudeLevel: serializer.fromJson<String?>(json['attitudeLevel']),
      beginnerLevel: serializer.fromJson<String?>(json['beginnerLevel']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'currentPhase': serializer.toJson<String>(currentPhase),
      'currentSubphase': serializer.toJson<String?>(currentSubphase),
      'attitudeLevel': serializer.toJson<String?>(attitudeLevel),
      'beginnerLevel': serializer.toJson<String?>(beginnerLevel),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  TeachingStateRow copyWith({
    String? id,
    String? sessionId,
    String? currentPhase,
    Value<String?> currentSubphase = const Value.absent(),
    Value<String?> attitudeLevel = const Value.absent(),
    Value<String?> beginnerLevel = const Value.absent(),
    int? updatedAt,
  }) => TeachingStateRow(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    currentPhase: currentPhase ?? this.currentPhase,
    currentSubphase: currentSubphase.present
        ? currentSubphase.value
        : this.currentSubphase,
    attitudeLevel: attitudeLevel.present
        ? attitudeLevel.value
        : this.attitudeLevel,
    beginnerLevel: beginnerLevel.present
        ? beginnerLevel.value
        : this.beginnerLevel,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  TeachingStateRow copyWithCompanion(TeachingStateCompanion data) {
    return TeachingStateRow(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      currentPhase: data.currentPhase.present
          ? data.currentPhase.value
          : this.currentPhase,
      currentSubphase: data.currentSubphase.present
          ? data.currentSubphase.value
          : this.currentSubphase,
      attitudeLevel: data.attitudeLevel.present
          ? data.attitudeLevel.value
          : this.attitudeLevel,
      beginnerLevel: data.beginnerLevel.present
          ? data.beginnerLevel.value
          : this.beginnerLevel,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TeachingStateRow(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('currentPhase: $currentPhase, ')
          ..write('currentSubphase: $currentSubphase, ')
          ..write('attitudeLevel: $attitudeLevel, ')
          ..write('beginnerLevel: $beginnerLevel, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    currentPhase,
    currentSubphase,
    attitudeLevel,
    beginnerLevel,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TeachingStateRow &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.currentPhase == this.currentPhase &&
          other.currentSubphase == this.currentSubphase &&
          other.attitudeLevel == this.attitudeLevel &&
          other.beginnerLevel == this.beginnerLevel &&
          other.updatedAt == this.updatedAt);
}

class TeachingStateCompanion extends UpdateCompanion<TeachingStateRow> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> currentPhase;
  final Value<String?> currentSubphase;
  final Value<String?> attitudeLevel;
  final Value<String?> beginnerLevel;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const TeachingStateCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.currentPhase = const Value.absent(),
    this.currentSubphase = const Value.absent(),
    this.attitudeLevel = const Value.absent(),
    this.beginnerLevel = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TeachingStateCompanion.insert({
    required String id,
    required String sessionId,
    this.currentPhase = const Value.absent(),
    this.currentSubphase = const Value.absent(),
    this.attitudeLevel = const Value.absent(),
    this.beginnerLevel = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId);
  static Insertable<TeachingStateRow> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? currentPhase,
    Expression<String>? currentSubphase,
    Expression<String>? attitudeLevel,
    Expression<String>? beginnerLevel,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (currentPhase != null) 'current_phase': currentPhase,
      if (currentSubphase != null) 'current_subphase': currentSubphase,
      if (attitudeLevel != null) 'attitude_level': attitudeLevel,
      if (beginnerLevel != null) 'beginner_level': beginnerLevel,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TeachingStateCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? currentPhase,
    Value<String?>? currentSubphase,
    Value<String?>? attitudeLevel,
    Value<String?>? beginnerLevel,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return TeachingStateCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      currentPhase: currentPhase ?? this.currentPhase,
      currentSubphase: currentSubphase ?? this.currentSubphase,
      attitudeLevel: attitudeLevel ?? this.attitudeLevel,
      beginnerLevel: beginnerLevel ?? this.beginnerLevel,
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
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (currentPhase.present) {
      map['current_phase'] = Variable<String>(currentPhase.value);
    }
    if (currentSubphase.present) {
      map['current_subphase'] = Variable<String>(currentSubphase.value);
    }
    if (attitudeLevel.present) {
      map['attitude_level'] = Variable<String>(attitudeLevel.value);
    }
    if (beginnerLevel.present) {
      map['beginner_level'] = Variable<String>(beginnerLevel.value);
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
    return (StringBuffer('TeachingStateCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('currentPhase: $currentPhase, ')
          ..write('currentSubphase: $currentSubphase, ')
          ..write('attitudeLevel: $attitudeLevel, ')
          ..write('beginnerLevel: $beginnerLevel, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActiveProblemsTable extends ActiveProblems
    with TableInfo<$ActiveProblemsTable, ActiveProblem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActiveProblemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _syndromeIdMeta = const VerificationMeta(
    'syndromeId',
  );
  @override
  late final GeneratedColumn<String> syndromeId = GeneratedColumn<String>(
    'syndrome_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syndromeNameMeta = const VerificationMeta(
    'syndromeName',
  );
  @override
  late final GeneratedColumn<String> syndromeName = GeneratedColumn<String>(
    'syndrome_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _severityMeta = const VerificationMeta(
    'severity',
  );
  @override
  late final GeneratedColumn<String> severity = GeneratedColumn<String>(
    'severity',
    aliasedName,
    false,
    check: () => severity.isIn(const ['L1', 'L2', 'L3']),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('L2'),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    check: () => status.isIn(const ['active', 'resolved']),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _confirmationStatusMeta =
      const VerificationMeta('confirmationStatus');
  @override
  late final GeneratedColumn<String> confirmationStatus =
      GeneratedColumn<String>(
        'confirmation_status',
        aliasedName,
        false,
        check: () => confirmationStatus.isIn(const [
          'suspected',
          'confirmed',
          'rejected',
          'ignored',
        ]),
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('suspected'),
      );
  static const VerificationMeta _teachingStateMeta = const VerificationMeta(
    'teachingState',
  );
  @override
  late final GeneratedColumn<String> teachingState = GeneratedColumn<String>(
    'teaching_state',
    aliasedName,
    true,
    check: () => teachingState.isIn(const [
      'identified',
      'in_progress',
      'consolidating',
      'mastered',
    ]),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _confirmedAtMeta = const VerificationMeta(
    'confirmedAt',
  );
  @override
  late final GeneratedColumn<int> confirmedAt = GeneratedColumn<int>(
    'confirmed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  static const VerificationMeta _resolvedAtMeta = const VerificationMeta(
    'resolvedAt',
  );
  @override
  late final GeneratedColumn<int> resolvedAt = GeneratedColumn<int>(
    'resolved_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    syndromeId,
    syndromeName,
    severity,
    status,
    confirmationStatus,
    teachingState,
    confirmedAt,
    createdAt,
    resolvedAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'active_problem';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActiveProblem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('syndrome_id')) {
      context.handle(
        _syndromeIdMeta,
        syndromeId.isAcceptableOrUnknown(data['syndrome_id']!, _syndromeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_syndromeIdMeta);
    }
    if (data.containsKey('syndrome_name')) {
      context.handle(
        _syndromeNameMeta,
        syndromeName.isAcceptableOrUnknown(
          data['syndrome_name']!,
          _syndromeNameMeta,
        ),
      );
    }
    if (data.containsKey('severity')) {
      context.handle(
        _severityMeta,
        severity.isAcceptableOrUnknown(data['severity']!, _severityMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('confirmation_status')) {
      context.handle(
        _confirmationStatusMeta,
        confirmationStatus.isAcceptableOrUnknown(
          data['confirmation_status']!,
          _confirmationStatusMeta,
        ),
      );
    }
    if (data.containsKey('teaching_state')) {
      context.handle(
        _teachingStateMeta,
        teachingState.isAcceptableOrUnknown(
          data['teaching_state']!,
          _teachingStateMeta,
        ),
      );
    }
    if (data.containsKey('confirmed_at')) {
      context.handle(
        _confirmedAtMeta,
        confirmedAt.isAcceptableOrUnknown(
          data['confirmed_at']!,
          _confirmedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('resolved_at')) {
      context.handle(
        _resolvedAtMeta,
        resolvedAt.isAcceptableOrUnknown(data['resolved_at']!, _resolvedAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {sessionId, syndromeId},
  ];
  @override
  ActiveProblem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActiveProblem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      syndromeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}syndrome_id'],
      )!,
      syndromeName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}syndrome_name'],
      )!,
      severity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}severity'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      confirmationStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}confirmation_status'],
      )!,
      teachingState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}teaching_state'],
      ),
      confirmedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}confirmed_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      resolvedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}resolved_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $ActiveProblemsTable createAlias(String alias) {
    return $ActiveProblemsTable(attachedDatabase, alias);
  }
}

class ActiveProblem extends DataClass implements Insertable<ActiveProblem> {
  final String id;
  final String sessionId;
  final String syndromeId;
  final String syndromeName;
  final String severity;
  final String status;
  final String confirmationStatus;
  final String? teachingState;
  final int? confirmedAt;
  final int createdAt;
  final int? resolvedAt;
  final int? updatedAt;
  const ActiveProblem({
    required this.id,
    required this.sessionId,
    required this.syndromeId,
    required this.syndromeName,
    required this.severity,
    required this.status,
    required this.confirmationStatus,
    this.teachingState,
    this.confirmedAt,
    required this.createdAt,
    this.resolvedAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['syndrome_id'] = Variable<String>(syndromeId);
    map['syndrome_name'] = Variable<String>(syndromeName);
    map['severity'] = Variable<String>(severity);
    map['status'] = Variable<String>(status);
    map['confirmation_status'] = Variable<String>(confirmationStatus);
    if (!nullToAbsent || teachingState != null) {
      map['teaching_state'] = Variable<String>(teachingState);
    }
    if (!nullToAbsent || confirmedAt != null) {
      map['confirmed_at'] = Variable<int>(confirmedAt);
    }
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || resolvedAt != null) {
      map['resolved_at'] = Variable<int>(resolvedAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<int>(updatedAt);
    }
    return map;
  }

  ActiveProblemsCompanion toCompanion(bool nullToAbsent) {
    return ActiveProblemsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      syndromeId: Value(syndromeId),
      syndromeName: Value(syndromeName),
      severity: Value(severity),
      status: Value(status),
      confirmationStatus: Value(confirmationStatus),
      teachingState: teachingState == null && nullToAbsent
          ? const Value.absent()
          : Value(teachingState),
      confirmedAt: confirmedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(confirmedAt),
      createdAt: Value(createdAt),
      resolvedAt: resolvedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory ActiveProblem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActiveProblem(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      syndromeId: serializer.fromJson<String>(json['syndromeId']),
      syndromeName: serializer.fromJson<String>(json['syndromeName']),
      severity: serializer.fromJson<String>(json['severity']),
      status: serializer.fromJson<String>(json['status']),
      confirmationStatus: serializer.fromJson<String>(
        json['confirmationStatus'],
      ),
      teachingState: serializer.fromJson<String?>(json['teachingState']),
      confirmedAt: serializer.fromJson<int?>(json['confirmedAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      resolvedAt: serializer.fromJson<int?>(json['resolvedAt']),
      updatedAt: serializer.fromJson<int?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'syndromeId': serializer.toJson<String>(syndromeId),
      'syndromeName': serializer.toJson<String>(syndromeName),
      'severity': serializer.toJson<String>(severity),
      'status': serializer.toJson<String>(status),
      'confirmationStatus': serializer.toJson<String>(confirmationStatus),
      'teachingState': serializer.toJson<String?>(teachingState),
      'confirmedAt': serializer.toJson<int?>(confirmedAt),
      'createdAt': serializer.toJson<int>(createdAt),
      'resolvedAt': serializer.toJson<int?>(resolvedAt),
      'updatedAt': serializer.toJson<int?>(updatedAt),
    };
  }

  ActiveProblem copyWith({
    String? id,
    String? sessionId,
    String? syndromeId,
    String? syndromeName,
    String? severity,
    String? status,
    String? confirmationStatus,
    Value<String?> teachingState = const Value.absent(),
    Value<int?> confirmedAt = const Value.absent(),
    int? createdAt,
    Value<int?> resolvedAt = const Value.absent(),
    Value<int?> updatedAt = const Value.absent(),
  }) => ActiveProblem(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    syndromeId: syndromeId ?? this.syndromeId,
    syndromeName: syndromeName ?? this.syndromeName,
    severity: severity ?? this.severity,
    status: status ?? this.status,
    confirmationStatus: confirmationStatus ?? this.confirmationStatus,
    teachingState: teachingState.present
        ? teachingState.value
        : this.teachingState,
    confirmedAt: confirmedAt.present ? confirmedAt.value : this.confirmedAt,
    createdAt: createdAt ?? this.createdAt,
    resolvedAt: resolvedAt.present ? resolvedAt.value : this.resolvedAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  ActiveProblem copyWithCompanion(ActiveProblemsCompanion data) {
    return ActiveProblem(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      syndromeId: data.syndromeId.present
          ? data.syndromeId.value
          : this.syndromeId,
      syndromeName: data.syndromeName.present
          ? data.syndromeName.value
          : this.syndromeName,
      severity: data.severity.present ? data.severity.value : this.severity,
      status: data.status.present ? data.status.value : this.status,
      confirmationStatus: data.confirmationStatus.present
          ? data.confirmationStatus.value
          : this.confirmationStatus,
      teachingState: data.teachingState.present
          ? data.teachingState.value
          : this.teachingState,
      confirmedAt: data.confirmedAt.present
          ? data.confirmedAt.value
          : this.confirmedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      resolvedAt: data.resolvedAt.present
          ? data.resolvedAt.value
          : this.resolvedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActiveProblem(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('syndromeId: $syndromeId, ')
          ..write('syndromeName: $syndromeName, ')
          ..write('severity: $severity, ')
          ..write('status: $status, ')
          ..write('confirmationStatus: $confirmationStatus, ')
          ..write('teachingState: $teachingState, ')
          ..write('confirmedAt: $confirmedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    syndromeId,
    syndromeName,
    severity,
    status,
    confirmationStatus,
    teachingState,
    confirmedAt,
    createdAt,
    resolvedAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActiveProblem &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.syndromeId == this.syndromeId &&
          other.syndromeName == this.syndromeName &&
          other.severity == this.severity &&
          other.status == this.status &&
          other.confirmationStatus == this.confirmationStatus &&
          other.teachingState == this.teachingState &&
          other.confirmedAt == this.confirmedAt &&
          other.createdAt == this.createdAt &&
          other.resolvedAt == this.resolvedAt &&
          other.updatedAt == this.updatedAt);
}

class ActiveProblemsCompanion extends UpdateCompanion<ActiveProblem> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> syndromeId;
  final Value<String> syndromeName;
  final Value<String> severity;
  final Value<String> status;
  final Value<String> confirmationStatus;
  final Value<String?> teachingState;
  final Value<int?> confirmedAt;
  final Value<int> createdAt;
  final Value<int?> resolvedAt;
  final Value<int?> updatedAt;
  final Value<int> rowid;
  const ActiveProblemsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.syndromeId = const Value.absent(),
    this.syndromeName = const Value.absent(),
    this.severity = const Value.absent(),
    this.status = const Value.absent(),
    this.confirmationStatus = const Value.absent(),
    this.teachingState = const Value.absent(),
    this.confirmedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActiveProblemsCompanion.insert({
    required String id,
    required String sessionId,
    required String syndromeId,
    this.syndromeName = const Value.absent(),
    this.severity = const Value.absent(),
    this.status = const Value.absent(),
    this.confirmationStatus = const Value.absent(),
    this.teachingState = const Value.absent(),
    this.confirmedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       syndromeId = Value(syndromeId);
  static Insertable<ActiveProblem> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? syndromeId,
    Expression<String>? syndromeName,
    Expression<String>? severity,
    Expression<String>? status,
    Expression<String>? confirmationStatus,
    Expression<String>? teachingState,
    Expression<int>? confirmedAt,
    Expression<int>? createdAt,
    Expression<int>? resolvedAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (syndromeId != null) 'syndrome_id': syndromeId,
      if (syndromeName != null) 'syndrome_name': syndromeName,
      if (severity != null) 'severity': severity,
      if (status != null) 'status': status,
      if (confirmationStatus != null) 'confirmation_status': confirmationStatus,
      if (teachingState != null) 'teaching_state': teachingState,
      if (confirmedAt != null) 'confirmed_at': confirmedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (resolvedAt != null) 'resolved_at': resolvedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActiveProblemsCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? syndromeId,
    Value<String>? syndromeName,
    Value<String>? severity,
    Value<String>? status,
    Value<String>? confirmationStatus,
    Value<String?>? teachingState,
    Value<int?>? confirmedAt,
    Value<int>? createdAt,
    Value<int?>? resolvedAt,
    Value<int?>? updatedAt,
    Value<int>? rowid,
  }) {
    return ActiveProblemsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      syndromeId: syndromeId ?? this.syndromeId,
      syndromeName: syndromeName ?? this.syndromeName,
      severity: severity ?? this.severity,
      status: status ?? this.status,
      confirmationStatus: confirmationStatus ?? this.confirmationStatus,
      teachingState: teachingState ?? this.teachingState,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      createdAt: createdAt ?? this.createdAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
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
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (syndromeId.present) {
      map['syndrome_id'] = Variable<String>(syndromeId.value);
    }
    if (syndromeName.present) {
      map['syndrome_name'] = Variable<String>(syndromeName.value);
    }
    if (severity.present) {
      map['severity'] = Variable<String>(severity.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (confirmationStatus.present) {
      map['confirmation_status'] = Variable<String>(confirmationStatus.value);
    }
    if (teachingState.present) {
      map['teaching_state'] = Variable<String>(teachingState.value);
    }
    if (confirmedAt.present) {
      map['confirmed_at'] = Variable<int>(confirmedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (resolvedAt.present) {
      map['resolved_at'] = Variable<int>(resolvedAt.value);
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
    return (StringBuffer('ActiveProblemsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('syndromeId: $syndromeId, ')
          ..write('syndromeName: $syndromeName, ')
          ..write('severity: $severity, ')
          ..write('status: $status, ')
          ..write('confirmationStatus: $confirmationStatus, ')
          ..write('teachingState: $teachingState, ')
          ..write('confirmedAt: $confirmedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StudentModelsTable extends StudentModels
    with TableInfo<$StudentModelsTable, StudentModelRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StudentModelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _attitudePreferenceMeta =
      const VerificationMeta('attitudePreference');
  @override
  late final GeneratedColumn<String> attitudePreference =
      GeneratedColumn<String>(
        'attitude_preference',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _teachingHistoryMeta = const VerificationMeta(
    'teachingHistory',
  );
  @override
  late final GeneratedColumn<String> teachingHistory = GeneratedColumn<String>(
    'teaching_history',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _onboardingDataMeta = const VerificationMeta(
    'onboardingData',
  );
  @override
  late final GeneratedColumn<String> onboardingData = GeneratedColumn<String>(
    'onboarding_data',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _styleProfileMeta = const VerificationMeta(
    'styleProfile',
  );
  @override
  late final GeneratedColumn<String> styleProfile = GeneratedColumn<String>(
    'style_profile',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _styleFingerprintMeta = const VerificationMeta(
    'styleFingerprint',
  );
  @override
  late final GeneratedColumn<String> styleFingerprint = GeneratedColumn<String>(
    'style_fingerprint',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    attitudePreference,
    teachingHistory,
    onboardingData,
    styleProfile,
    styleFingerprint,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'student_model';
  @override
  VerificationContext validateIntegrity(
    Insertable<StudentModelRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('attitude_preference')) {
      context.handle(
        _attitudePreferenceMeta,
        attitudePreference.isAcceptableOrUnknown(
          data['attitude_preference']!,
          _attitudePreferenceMeta,
        ),
      );
    }
    if (data.containsKey('teaching_history')) {
      context.handle(
        _teachingHistoryMeta,
        teachingHistory.isAcceptableOrUnknown(
          data['teaching_history']!,
          _teachingHistoryMeta,
        ),
      );
    }
    if (data.containsKey('onboarding_data')) {
      context.handle(
        _onboardingDataMeta,
        onboardingData.isAcceptableOrUnknown(
          data['onboarding_data']!,
          _onboardingDataMeta,
        ),
      );
    }
    if (data.containsKey('style_profile')) {
      context.handle(
        _styleProfileMeta,
        styleProfile.isAcceptableOrUnknown(
          data['style_profile']!,
          _styleProfileMeta,
        ),
      );
    }
    if (data.containsKey('style_fingerprint')) {
      context.handle(
        _styleFingerprintMeta,
        styleFingerprint.isAcceptableOrUnknown(
          data['style_fingerprint']!,
          _styleFingerprintMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StudentModelRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StudentModelRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      attitudePreference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attitude_preference'],
      ),
      teachingHistory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}teaching_history'],
      )!,
      onboardingData: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}onboarding_data'],
      ),
      styleProfile: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}style_profile'],
      ),
      styleFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}style_fingerprint'],
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
  $StudentModelsTable createAlias(String alias) {
    return $StudentModelsTable(attachedDatabase, alias);
  }
}

class StudentModelRow extends DataClass implements Insertable<StudentModelRow> {
  final String id;
  final String sessionId;
  final String? attitudePreference;
  final String teachingHistory;
  final String? onboardingData;
  final String? styleProfile;
  final String? styleFingerprint;
  final int createdAt;
  final int updatedAt;
  const StudentModelRow({
    required this.id,
    required this.sessionId,
    this.attitudePreference,
    required this.teachingHistory,
    this.onboardingData,
    this.styleProfile,
    this.styleFingerprint,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    if (!nullToAbsent || attitudePreference != null) {
      map['attitude_preference'] = Variable<String>(attitudePreference);
    }
    map['teaching_history'] = Variable<String>(teachingHistory);
    if (!nullToAbsent || onboardingData != null) {
      map['onboarding_data'] = Variable<String>(onboardingData);
    }
    if (!nullToAbsent || styleProfile != null) {
      map['style_profile'] = Variable<String>(styleProfile);
    }
    if (!nullToAbsent || styleFingerprint != null) {
      map['style_fingerprint'] = Variable<String>(styleFingerprint);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  StudentModelsCompanion toCompanion(bool nullToAbsent) {
    return StudentModelsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      attitudePreference: attitudePreference == null && nullToAbsent
          ? const Value.absent()
          : Value(attitudePreference),
      teachingHistory: Value(teachingHistory),
      onboardingData: onboardingData == null && nullToAbsent
          ? const Value.absent()
          : Value(onboardingData),
      styleProfile: styleProfile == null && nullToAbsent
          ? const Value.absent()
          : Value(styleProfile),
      styleFingerprint: styleFingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(styleFingerprint),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory StudentModelRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StudentModelRow(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      attitudePreference: serializer.fromJson<String?>(
        json['attitudePreference'],
      ),
      teachingHistory: serializer.fromJson<String>(json['teachingHistory']),
      onboardingData: serializer.fromJson<String?>(json['onboardingData']),
      styleProfile: serializer.fromJson<String?>(json['styleProfile']),
      styleFingerprint: serializer.fromJson<String?>(json['styleFingerprint']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'attitudePreference': serializer.toJson<String?>(attitudePreference),
      'teachingHistory': serializer.toJson<String>(teachingHistory),
      'onboardingData': serializer.toJson<String?>(onboardingData),
      'styleProfile': serializer.toJson<String?>(styleProfile),
      'styleFingerprint': serializer.toJson<String?>(styleFingerprint),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  StudentModelRow copyWith({
    String? id,
    String? sessionId,
    Value<String?> attitudePreference = const Value.absent(),
    String? teachingHistory,
    Value<String?> onboardingData = const Value.absent(),
    Value<String?> styleProfile = const Value.absent(),
    Value<String?> styleFingerprint = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => StudentModelRow(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    attitudePreference: attitudePreference.present
        ? attitudePreference.value
        : this.attitudePreference,
    teachingHistory: teachingHistory ?? this.teachingHistory,
    onboardingData: onboardingData.present
        ? onboardingData.value
        : this.onboardingData,
    styleProfile: styleProfile.present ? styleProfile.value : this.styleProfile,
    styleFingerprint: styleFingerprint.present
        ? styleFingerprint.value
        : this.styleFingerprint,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  StudentModelRow copyWithCompanion(StudentModelsCompanion data) {
    return StudentModelRow(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      attitudePreference: data.attitudePreference.present
          ? data.attitudePreference.value
          : this.attitudePreference,
      teachingHistory: data.teachingHistory.present
          ? data.teachingHistory.value
          : this.teachingHistory,
      onboardingData: data.onboardingData.present
          ? data.onboardingData.value
          : this.onboardingData,
      styleProfile: data.styleProfile.present
          ? data.styleProfile.value
          : this.styleProfile,
      styleFingerprint: data.styleFingerprint.present
          ? data.styleFingerprint.value
          : this.styleFingerprint,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StudentModelRow(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('attitudePreference: $attitudePreference, ')
          ..write('teachingHistory: $teachingHistory, ')
          ..write('onboardingData: $onboardingData, ')
          ..write('styleProfile: $styleProfile, ')
          ..write('styleFingerprint: $styleFingerprint, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    attitudePreference,
    teachingHistory,
    onboardingData,
    styleProfile,
    styleFingerprint,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StudentModelRow &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.attitudePreference == this.attitudePreference &&
          other.teachingHistory == this.teachingHistory &&
          other.onboardingData == this.onboardingData &&
          other.styleProfile == this.styleProfile &&
          other.styleFingerprint == this.styleFingerprint &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class StudentModelsCompanion extends UpdateCompanion<StudentModelRow> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String?> attitudePreference;
  final Value<String> teachingHistory;
  final Value<String?> onboardingData;
  final Value<String?> styleProfile;
  final Value<String?> styleFingerprint;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const StudentModelsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.attitudePreference = const Value.absent(),
    this.teachingHistory = const Value.absent(),
    this.onboardingData = const Value.absent(),
    this.styleProfile = const Value.absent(),
    this.styleFingerprint = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StudentModelsCompanion.insert({
    required String id,
    required String sessionId,
    this.attitudePreference = const Value.absent(),
    this.teachingHistory = const Value.absent(),
    this.onboardingData = const Value.absent(),
    this.styleProfile = const Value.absent(),
    this.styleFingerprint = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId);
  static Insertable<StudentModelRow> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? attitudePreference,
    Expression<String>? teachingHistory,
    Expression<String>? onboardingData,
    Expression<String>? styleProfile,
    Expression<String>? styleFingerprint,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (attitudePreference != null) 'attitude_preference': attitudePreference,
      if (teachingHistory != null) 'teaching_history': teachingHistory,
      if (onboardingData != null) 'onboarding_data': onboardingData,
      if (styleProfile != null) 'style_profile': styleProfile,
      if (styleFingerprint != null) 'style_fingerprint': styleFingerprint,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StudentModelsCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String?>? attitudePreference,
    Value<String>? teachingHistory,
    Value<String?>? onboardingData,
    Value<String?>? styleProfile,
    Value<String?>? styleFingerprint,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return StudentModelsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      attitudePreference: attitudePreference ?? this.attitudePreference,
      teachingHistory: teachingHistory ?? this.teachingHistory,
      onboardingData: onboardingData ?? this.onboardingData,
      styleProfile: styleProfile ?? this.styleProfile,
      styleFingerprint: styleFingerprint ?? this.styleFingerprint,
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
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (attitudePreference.present) {
      map['attitude_preference'] = Variable<String>(attitudePreference.value);
    }
    if (teachingHistory.present) {
      map['teaching_history'] = Variable<String>(teachingHistory.value);
    }
    if (onboardingData.present) {
      map['onboarding_data'] = Variable<String>(onboardingData.value);
    }
    if (styleProfile.present) {
      map['style_profile'] = Variable<String>(styleProfile.value);
    }
    if (styleFingerprint.present) {
      map['style_fingerprint'] = Variable<String>(styleFingerprint.value);
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
    return (StringBuffer('StudentModelsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('attitudePreference: $attitudePreference, ')
          ..write('teachingHistory: $teachingHistory, ')
          ..write('onboardingData: $onboardingData, ')
          ..write('styleProfile: $styleProfile, ')
          ..write('styleFingerprint: $styleFingerprint, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionReferencesTable extends SessionReferences
    with TableInfo<$SessionReferencesTable, SessionReference> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionReferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _refTypeMeta = const VerificationMeta(
    'refType',
  );
  @override
  late final GeneratedColumn<String> refType = GeneratedColumn<String>(
    'ref_type',
    aliasedName,
    false,
    check: () => refType.isIn(const ['manuscript', 'chapter', 'file']),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refIdMeta = const VerificationMeta('refId');
  @override
  late final GeneratedColumn<String> refId = GeneratedColumn<String>(
    'ref_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isPrimaryMeta = const VerificationMeta(
    'isPrimary',
  );
  @override
  late final GeneratedColumn<int> isPrimary = GeneratedColumn<int>(
    'is_primary',
    aliasedName,
    false,
    check: () => isPrimary.isIn(const [0, 1]),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _excerptRangeMeta = const VerificationMeta(
    'excerptRange',
  );
  @override
  late final GeneratedColumn<String> excerptRange = GeneratedColumn<String>(
    'excerpt_range',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    refType,
    refId,
    isPrimary,
    excerptRange,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'session_reference';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionReference> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('ref_type')) {
      context.handle(
        _refTypeMeta,
        refType.isAcceptableOrUnknown(data['ref_type']!, _refTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_refTypeMeta);
    }
    if (data.containsKey('ref_id')) {
      context.handle(
        _refIdMeta,
        refId.isAcceptableOrUnknown(data['ref_id']!, _refIdMeta),
      );
    } else if (isInserting) {
      context.missing(_refIdMeta);
    }
    if (data.containsKey('is_primary')) {
      context.handle(
        _isPrimaryMeta,
        isPrimary.isAcceptableOrUnknown(data['is_primary']!, _isPrimaryMeta),
      );
    }
    if (data.containsKey('excerpt_range')) {
      context.handle(
        _excerptRangeMeta,
        excerptRange.isAcceptableOrUnknown(
          data['excerpt_range']!,
          _excerptRangeMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {sessionId, refType, refId},
  ];
  @override
  SessionReference map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionReference(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      refType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_type'],
      )!,
      refId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_id'],
      )!,
      isPrimary: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}is_primary'],
      )!,
      excerptRange: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}excerpt_range'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SessionReferencesTable createAlias(String alias) {
    return $SessionReferencesTable(attachedDatabase, alias);
  }
}

class SessionReference extends DataClass
    implements Insertable<SessionReference> {
  final String id;
  final String sessionId;
  final String refType;
  final String refId;
  final int isPrimary;
  final String? excerptRange;
  final int createdAt;
  const SessionReference({
    required this.id,
    required this.sessionId,
    required this.refType,
    required this.refId,
    required this.isPrimary,
    this.excerptRange,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['ref_type'] = Variable<String>(refType);
    map['ref_id'] = Variable<String>(refId);
    map['is_primary'] = Variable<int>(isPrimary);
    if (!nullToAbsent || excerptRange != null) {
      map['excerpt_range'] = Variable<String>(excerptRange);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  SessionReferencesCompanion toCompanion(bool nullToAbsent) {
    return SessionReferencesCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      refType: Value(refType),
      refId: Value(refId),
      isPrimary: Value(isPrimary),
      excerptRange: excerptRange == null && nullToAbsent
          ? const Value.absent()
          : Value(excerptRange),
      createdAt: Value(createdAt),
    );
  }

  factory SessionReference.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionReference(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      refType: serializer.fromJson<String>(json['refType']),
      refId: serializer.fromJson<String>(json['refId']),
      isPrimary: serializer.fromJson<int>(json['isPrimary']),
      excerptRange: serializer.fromJson<String?>(json['excerptRange']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'refType': serializer.toJson<String>(refType),
      'refId': serializer.toJson<String>(refId),
      'isPrimary': serializer.toJson<int>(isPrimary),
      'excerptRange': serializer.toJson<String?>(excerptRange),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  SessionReference copyWith({
    String? id,
    String? sessionId,
    String? refType,
    String? refId,
    int? isPrimary,
    Value<String?> excerptRange = const Value.absent(),
    int? createdAt,
  }) => SessionReference(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    refType: refType ?? this.refType,
    refId: refId ?? this.refId,
    isPrimary: isPrimary ?? this.isPrimary,
    excerptRange: excerptRange.present ? excerptRange.value : this.excerptRange,
    createdAt: createdAt ?? this.createdAt,
  );
  SessionReference copyWithCompanion(SessionReferencesCompanion data) {
    return SessionReference(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      refType: data.refType.present ? data.refType.value : this.refType,
      refId: data.refId.present ? data.refId.value : this.refId,
      isPrimary: data.isPrimary.present ? data.isPrimary.value : this.isPrimary,
      excerptRange: data.excerptRange.present
          ? data.excerptRange.value
          : this.excerptRange,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionReference(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('refType: $refType, ')
          ..write('refId: $refId, ')
          ..write('isPrimary: $isPrimary, ')
          ..write('excerptRange: $excerptRange, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    refType,
    refId,
    isPrimary,
    excerptRange,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionReference &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.refType == this.refType &&
          other.refId == this.refId &&
          other.isPrimary == this.isPrimary &&
          other.excerptRange == this.excerptRange &&
          other.createdAt == this.createdAt);
}

class SessionReferencesCompanion extends UpdateCompanion<SessionReference> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> refType;
  final Value<String> refId;
  final Value<int> isPrimary;
  final Value<String?> excerptRange;
  final Value<int> createdAt;
  final Value<int> rowid;
  const SessionReferencesCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.refType = const Value.absent(),
    this.refId = const Value.absent(),
    this.isPrimary = const Value.absent(),
    this.excerptRange = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionReferencesCompanion.insert({
    required String id,
    required String sessionId,
    required String refType,
    required String refId,
    this.isPrimary = const Value.absent(),
    this.excerptRange = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       refType = Value(refType),
       refId = Value(refId);
  static Insertable<SessionReference> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? refType,
    Expression<String>? refId,
    Expression<int>? isPrimary,
    Expression<String>? excerptRange,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (refType != null) 'ref_type': refType,
      if (refId != null) 'ref_id': refId,
      if (isPrimary != null) 'is_primary': isPrimary,
      if (excerptRange != null) 'excerpt_range': excerptRange,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionReferencesCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? refType,
    Value<String>? refId,
    Value<int>? isPrimary,
    Value<String?>? excerptRange,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return SessionReferencesCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      refType: refType ?? this.refType,
      refId: refId ?? this.refId,
      isPrimary: isPrimary ?? this.isPrimary,
      excerptRange: excerptRange ?? this.excerptRange,
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
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (refType.present) {
      map['ref_type'] = Variable<String>(refType.value);
    }
    if (refId.present) {
      map['ref_id'] = Variable<String>(refId.value);
    }
    if (isPrimary.present) {
      map['is_primary'] = Variable<int>(isPrimary.value);
    }
    if (excerptRange.present) {
      map['excerpt_range'] = Variable<String>(excerptRange.value);
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
    return (StringBuffer('SessionReferencesCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('refType: $refType, ')
          ..write('refId: $refId, ')
          ..write('isPrimary: $isPrimary, ')
          ..write('excerptRange: $excerptRange, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppStatesTable extends AppStates
    with TableInfo<$AppStatesTable, AppStateEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppStateEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppStateEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppStateEntry(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AppStatesTable createAlias(String alias) {
    return $AppStatesTable(attachedDatabase, alias);
  }
}

class AppStateEntry extends DataClass implements Insertable<AppStateEntry> {
  final String key;
  final String value;
  final int updatedAt;
  const AppStateEntry({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  AppStatesCompanion toCompanion(bool nullToAbsent) {
    return AppStatesCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppStateEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppStateEntry(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  AppStateEntry copyWith({String? key, String? value, int? updatedAt}) =>
      AppStateEntry(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  AppStateEntry copyWithCompanion(AppStatesCompanion data) {
    return AppStateEntry(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppStateEntry(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppStateEntry &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class AppStatesCompanion extends UpdateCompanion<AppStateEntry> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const AppStatesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppStatesCompanion.insert({
    required String key,
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key);
  static Insertable<AppStateEntry> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppStatesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return AppStatesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
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
    return (StringBuffer('AppStatesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ErrorLogsTable extends ErrorLogs
    with TableInfo<$ErrorLogsTable, ErrorLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ErrorLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<String> level = GeneratedColumn<String>(
    'level',
    aliasedName,
    false,
    check: () => level.isIn(const ['debug', 'info', 'warn', 'error', 'fatal']),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('error'),
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    check: () => category.isIn(const [
      'general',
      'api',
      'database',
      'render',
      'network',
      'skill',
      'validation',
    ]),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('general'),
  );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stackMeta = const VerificationMeta('stack');
  @override
  late final GeneratedColumn<String> stack = GeneratedColumn<String>(
    'stack',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contextMeta = const VerificationMeta(
    'context',
  );
  @override
  late final GeneratedColumn<String> context = GeneratedColumn<String>(
    'context',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deviceInfoMeta = const VerificationMeta(
    'deviceInfo',
  );
  @override
  late final GeneratedColumn<String> deviceInfo = GeneratedColumn<String>(
    'device_info',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    level,
    category,
    message,
    stack,
    context,
    deviceInfo,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'error_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ErrorLog> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('level')) {
      context.handle(
        _levelMeta,
        level.isAcceptableOrUnknown(data['level']!, _levelMeta),
      );
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    } else if (isInserting) {
      context.missing(_messageMeta);
    }
    if (data.containsKey('stack')) {
      context.handle(
        _stackMeta,
        stack.isAcceptableOrUnknown(data['stack']!, _stackMeta),
      );
    }
    if (data.containsKey('context')) {
      context.handle(
        _contextMeta,
        this.context.isAcceptableOrUnknown(data['context']!, _contextMeta),
      );
    }
    if (data.containsKey('device_info')) {
      context.handle(
        _deviceInfoMeta,
        deviceInfo.isAcceptableOrUnknown(data['device_info']!, _deviceInfoMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ErrorLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ErrorLog(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      level: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}level'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      )!,
      stack: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stack'],
      ),
      context: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}context'],
      ),
      deviceInfo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_info'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ErrorLogsTable createAlias(String alias) {
    return $ErrorLogsTable(attachedDatabase, alias);
  }
}

class ErrorLog extends DataClass implements Insertable<ErrorLog> {
  final String id;
  final String level;
  final String category;
  final String message;
  final String? stack;
  final String? context;
  final String? deviceInfo;
  final int createdAt;
  const ErrorLog({
    required this.id,
    required this.level,
    required this.category,
    required this.message,
    this.stack,
    this.context,
    this.deviceInfo,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['level'] = Variable<String>(level);
    map['category'] = Variable<String>(category);
    map['message'] = Variable<String>(message);
    if (!nullToAbsent || stack != null) {
      map['stack'] = Variable<String>(stack);
    }
    if (!nullToAbsent || context != null) {
      map['context'] = Variable<String>(context);
    }
    if (!nullToAbsent || deviceInfo != null) {
      map['device_info'] = Variable<String>(deviceInfo);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ErrorLogsCompanion toCompanion(bool nullToAbsent) {
    return ErrorLogsCompanion(
      id: Value(id),
      level: Value(level),
      category: Value(category),
      message: Value(message),
      stack: stack == null && nullToAbsent
          ? const Value.absent()
          : Value(stack),
      context: context == null && nullToAbsent
          ? const Value.absent()
          : Value(context),
      deviceInfo: deviceInfo == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceInfo),
      createdAt: Value(createdAt),
    );
  }

  factory ErrorLog.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ErrorLog(
      id: serializer.fromJson<String>(json['id']),
      level: serializer.fromJson<String>(json['level']),
      category: serializer.fromJson<String>(json['category']),
      message: serializer.fromJson<String>(json['message']),
      stack: serializer.fromJson<String?>(json['stack']),
      context: serializer.fromJson<String?>(json['context']),
      deviceInfo: serializer.fromJson<String?>(json['deviceInfo']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'level': serializer.toJson<String>(level),
      'category': serializer.toJson<String>(category),
      'message': serializer.toJson<String>(message),
      'stack': serializer.toJson<String?>(stack),
      'context': serializer.toJson<String?>(context),
      'deviceInfo': serializer.toJson<String?>(deviceInfo),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  ErrorLog copyWith({
    String? id,
    String? level,
    String? category,
    String? message,
    Value<String?> stack = const Value.absent(),
    Value<String?> context = const Value.absent(),
    Value<String?> deviceInfo = const Value.absent(),
    int? createdAt,
  }) => ErrorLog(
    id: id ?? this.id,
    level: level ?? this.level,
    category: category ?? this.category,
    message: message ?? this.message,
    stack: stack.present ? stack.value : this.stack,
    context: context.present ? context.value : this.context,
    deviceInfo: deviceInfo.present ? deviceInfo.value : this.deviceInfo,
    createdAt: createdAt ?? this.createdAt,
  );
  ErrorLog copyWithCompanion(ErrorLogsCompanion data) {
    return ErrorLog(
      id: data.id.present ? data.id.value : this.id,
      level: data.level.present ? data.level.value : this.level,
      category: data.category.present ? data.category.value : this.category,
      message: data.message.present ? data.message.value : this.message,
      stack: data.stack.present ? data.stack.value : this.stack,
      context: data.context.present ? data.context.value : this.context,
      deviceInfo: data.deviceInfo.present
          ? data.deviceInfo.value
          : this.deviceInfo,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ErrorLog(')
          ..write('id: $id, ')
          ..write('level: $level, ')
          ..write('category: $category, ')
          ..write('message: $message, ')
          ..write('stack: $stack, ')
          ..write('context: $context, ')
          ..write('deviceInfo: $deviceInfo, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    level,
    category,
    message,
    stack,
    context,
    deviceInfo,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ErrorLog &&
          other.id == this.id &&
          other.level == this.level &&
          other.category == this.category &&
          other.message == this.message &&
          other.stack == this.stack &&
          other.context == this.context &&
          other.deviceInfo == this.deviceInfo &&
          other.createdAt == this.createdAt);
}

class ErrorLogsCompanion extends UpdateCompanion<ErrorLog> {
  final Value<String> id;
  final Value<String> level;
  final Value<String> category;
  final Value<String> message;
  final Value<String?> stack;
  final Value<String?> context;
  final Value<String?> deviceInfo;
  final Value<int> createdAt;
  final Value<int> rowid;
  const ErrorLogsCompanion({
    this.id = const Value.absent(),
    this.level = const Value.absent(),
    this.category = const Value.absent(),
    this.message = const Value.absent(),
    this.stack = const Value.absent(),
    this.context = const Value.absent(),
    this.deviceInfo = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ErrorLogsCompanion.insert({
    required String id,
    this.level = const Value.absent(),
    this.category = const Value.absent(),
    required String message,
    this.stack = const Value.absent(),
    this.context = const Value.absent(),
    this.deviceInfo = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       message = Value(message);
  static Insertable<ErrorLog> custom({
    Expression<String>? id,
    Expression<String>? level,
    Expression<String>? category,
    Expression<String>? message,
    Expression<String>? stack,
    Expression<String>? context,
    Expression<String>? deviceInfo,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (level != null) 'level': level,
      if (category != null) 'category': category,
      if (message != null) 'message': message,
      if (stack != null) 'stack': stack,
      if (context != null) 'context': context,
      if (deviceInfo != null) 'device_info': deviceInfo,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ErrorLogsCompanion copyWith({
    Value<String>? id,
    Value<String>? level,
    Value<String>? category,
    Value<String>? message,
    Value<String?>? stack,
    Value<String?>? context,
    Value<String?>? deviceInfo,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return ErrorLogsCompanion(
      id: id ?? this.id,
      level: level ?? this.level,
      category: category ?? this.category,
      message: message ?? this.message,
      stack: stack ?? this.stack,
      context: context ?? this.context,
      deviceInfo: deviceInfo ?? this.deviceInfo,
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
    if (level.present) {
      map['level'] = Variable<String>(level.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (stack.present) {
      map['stack'] = Variable<String>(stack.value);
    }
    if (context.present) {
      map['context'] = Variable<String>(context.value);
    }
    if (deviceInfo.present) {
      map['device_info'] = Variable<String>(deviceInfo.value);
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
    return (StringBuffer('ErrorLogsCompanion(')
          ..write('id: $id, ')
          ..write('level: $level, ')
          ..write('category: $category, ')
          ..write('message: $message, ')
          ..write('stack: $stack, ')
          ..write('context: $context, ')
          ..write('deviceInfo: $deviceInfo, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AttachedFilesTable extends AttachedFiles
    with TableInfo<$AttachedFilesTable, AttachedFile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AttachedFilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES manuscripts (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _fileRoleMeta = const VerificationMeta(
    'fileRole',
  );
  @override
  late final GeneratedColumn<String> fileRole = GeneratedColumn<String>(
    'file_role',
    aliasedName,
    false,
    check: () => fileRole.isIn(const ['outline', 'material', 'general']),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('general'),
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('text/plain'),
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _byteSizeMeta = const VerificationMeta(
    'byteSize',
  );
  @override
  late final GeneratedColumn<int> byteSize = GeneratedColumn<int>(
    'byte_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    fileName,
    fileRole,
    mimeType,
    content,
    byteSize,
    sortOrder,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'attached_files';
  @override
  VerificationContext validateIntegrity(
    Insertable<AttachedFile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    }
    if (data.containsKey('file_role')) {
      context.handle(
        _fileRoleMeta,
        fileRole.isAcceptableOrUnknown(data['file_role']!, _fileRoleMeta),
      );
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('byte_size')) {
      context.handle(
        _byteSizeMeta,
        byteSize.isAcceptableOrUnknown(data['byte_size']!, _byteSizeMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AttachedFile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AttachedFile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      fileRole: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_role'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      byteSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_size'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
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
  $AttachedFilesTable createAlias(String alias) {
    return $AttachedFilesTable(attachedDatabase, alias);
  }
}

class AttachedFile extends DataClass implements Insertable<AttachedFile> {
  final String id;
  final String bookId;
  final String fileName;
  final String fileRole;
  final String mimeType;
  final String content;
  final int byteSize;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;
  const AttachedFile({
    required this.id,
    required this.bookId,
    required this.fileName,
    required this.fileRole,
    required this.mimeType,
    required this.content,
    required this.byteSize,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['book_id'] = Variable<String>(bookId);
    map['file_name'] = Variable<String>(fileName);
    map['file_role'] = Variable<String>(fileRole);
    map['mime_type'] = Variable<String>(mimeType);
    map['content'] = Variable<String>(content);
    map['byte_size'] = Variable<int>(byteSize);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  AttachedFilesCompanion toCompanion(bool nullToAbsent) {
    return AttachedFilesCompanion(
      id: Value(id),
      bookId: Value(bookId),
      fileName: Value(fileName),
      fileRole: Value(fileRole),
      mimeType: Value(mimeType),
      content: Value(content),
      byteSize: Value(byteSize),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AttachedFile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AttachedFile(
      id: serializer.fromJson<String>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      fileName: serializer.fromJson<String>(json['fileName']),
      fileRole: serializer.fromJson<String>(json['fileRole']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      content: serializer.fromJson<String>(json['content']),
      byteSize: serializer.fromJson<int>(json['byteSize']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bookId': serializer.toJson<String>(bookId),
      'fileName': serializer.toJson<String>(fileName),
      'fileRole': serializer.toJson<String>(fileRole),
      'mimeType': serializer.toJson<String>(mimeType),
      'content': serializer.toJson<String>(content),
      'byteSize': serializer.toJson<int>(byteSize),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  AttachedFile copyWith({
    String? id,
    String? bookId,
    String? fileName,
    String? fileRole,
    String? mimeType,
    String? content,
    int? byteSize,
    int? sortOrder,
    int? createdAt,
    int? updatedAt,
  }) => AttachedFile(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    fileName: fileName ?? this.fileName,
    fileRole: fileRole ?? this.fileRole,
    mimeType: mimeType ?? this.mimeType,
    content: content ?? this.content,
    byteSize: byteSize ?? this.byteSize,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AttachedFile copyWithCompanion(AttachedFilesCompanion data) {
    return AttachedFile(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      fileRole: data.fileRole.present ? data.fileRole.value : this.fileRole,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      content: data.content.present ? data.content.value : this.content,
      byteSize: data.byteSize.present ? data.byteSize.value : this.byteSize,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AttachedFile(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('fileName: $fileName, ')
          ..write('fileRole: $fileRole, ')
          ..write('mimeType: $mimeType, ')
          ..write('content: $content, ')
          ..write('byteSize: $byteSize, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    fileName,
    fileRole,
    mimeType,
    content,
    byteSize,
    sortOrder,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AttachedFile &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.fileName == this.fileName &&
          other.fileRole == this.fileRole &&
          other.mimeType == this.mimeType &&
          other.content == this.content &&
          other.byteSize == this.byteSize &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AttachedFilesCompanion extends UpdateCompanion<AttachedFile> {
  final Value<String> id;
  final Value<String> bookId;
  final Value<String> fileName;
  final Value<String> fileRole;
  final Value<String> mimeType;
  final Value<String> content;
  final Value<int> byteSize;
  final Value<int> sortOrder;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const AttachedFilesCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.fileName = const Value.absent(),
    this.fileRole = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.content = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AttachedFilesCompanion.insert({
    required String id,
    required String bookId,
    this.fileName = const Value.absent(),
    this.fileRole = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.content = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       bookId = Value(bookId);
  static Insertable<AttachedFile> custom({
    Expression<String>? id,
    Expression<String>? bookId,
    Expression<String>? fileName,
    Expression<String>? fileRole,
    Expression<String>? mimeType,
    Expression<String>? content,
    Expression<int>? byteSize,
    Expression<int>? sortOrder,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (fileName != null) 'file_name': fileName,
      if (fileRole != null) 'file_role': fileRole,
      if (mimeType != null) 'mime_type': mimeType,
      if (content != null) 'content': content,
      if (byteSize != null) 'byte_size': byteSize,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AttachedFilesCompanion copyWith({
    Value<String>? id,
    Value<String>? bookId,
    Value<String>? fileName,
    Value<String>? fileRole,
    Value<String>? mimeType,
    Value<String>? content,
    Value<int>? byteSize,
    Value<int>? sortOrder,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return AttachedFilesCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      fileName: fileName ?? this.fileName,
      fileRole: fileRole ?? this.fileRole,
      mimeType: mimeType ?? this.mimeType,
      content: content ?? this.content,
      byteSize: byteSize ?? this.byteSize,
      sortOrder: sortOrder ?? this.sortOrder,
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
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (fileRole.present) {
      map['file_role'] = Variable<String>(fileRole.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (byteSize.present) {
      map['byte_size'] = Variable<int>(byteSize.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
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
    return (StringBuffer('AttachedFilesCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('fileName: $fileName, ')
          ..write('fileRole: $fileRole, ')
          ..write('mimeType: $mimeType, ')
          ..write('content: $content, ')
          ..write('byteSize: $byteSize, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TeacherSuggestionsTable extends TeacherSuggestions
    with TableInfo<$TeacherSuggestionsTable, TeacherSuggestionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TeacherSuggestionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES messages (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    check: () => source.isIn(const ['editor', 'diagnosis']),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _teachingDecisionMeta = const VerificationMeta(
    'teachingDecision',
  );
  @override
  late final GeneratedColumn<String> teachingDecision = GeneratedColumn<String>(
    'teaching_decision',
    aliasedName,
    false,
    check: () => teachingDecision.isIn(const ['guide', 'train']),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetSyndromeIdMeta = const VerificationMeta(
    'targetSyndromeId',
  );
  @override
  late final GeneratedColumn<String> targetSyndromeId = GeneratedColumn<String>(
    'target_syndrome_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _targetDimensionMeta = const VerificationMeta(
    'targetDimension',
  );
  @override
  late final GeneratedColumn<String> targetDimension = GeneratedColumn<String>(
    'target_dimension',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _taskTypeMeta = const VerificationMeta(
    'taskType',
  );
  @override
  late final GeneratedColumn<String> taskType = GeneratedColumn<String>(
    'task_type',
    aliasedName,
    false,
    check: () =>
        taskType.isIn(const ['rewrite', 'analyze', 'compare', 'generate']),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskDescriptionMeta = const VerificationMeta(
    'taskDescription',
  );
  @override
  late final GeneratedColumn<String> taskDescription = GeneratedColumn<String>(
    'task_description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _difficultyMeta = const VerificationMeta(
    'difficulty',
  );
  @override
  late final GeneratedColumn<String> difficulty = GeneratedColumn<String>(
    'difficulty',
    aliasedName,
    false,
    check: () => difficulty.isIn(const ['easy', 'medium', 'hard']),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _evaluationCriteriaMeta =
      const VerificationMeta('evaluationCriteria');
  @override
  late final GeneratedColumn<String> evaluationCriteria =
      GeneratedColumn<String>(
        'evaluation_criteria',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    check: () => status.isIn(const ['active', 'resolved']),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  static const VerificationMeta _resolvedAtMeta = const VerificationMeta(
    'resolvedAt',
  );
  @override
  late final GeneratedColumn<int> resolvedAt = GeneratedColumn<int>(
    'resolved_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _adoptedAtMeta = const VerificationMeta(
    'adoptedAt',
  );
  @override
  late final GeneratedColumn<int> adoptedAt = GeneratedColumn<int>(
    'adopted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dismissedAtMeta = const VerificationMeta(
    'dismissedAt',
  );
  @override
  late final GeneratedColumn<int> dismissedAt = GeneratedColumn<int>(
    'dismissed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    messageId,
    source,
    teachingDecision,
    targetSyndromeId,
    targetDimension,
    taskType,
    taskDescription,
    difficulty,
    evaluationCriteria,
    status,
    createdAt,
    resolvedAt,
    adoptedAt,
    dismissedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'teacher_suggestion';
  @override
  VerificationContext validateIntegrity(
    Insertable<TeacherSuggestionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('teaching_decision')) {
      context.handle(
        _teachingDecisionMeta,
        teachingDecision.isAcceptableOrUnknown(
          data['teaching_decision']!,
          _teachingDecisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_teachingDecisionMeta);
    }
    if (data.containsKey('target_syndrome_id')) {
      context.handle(
        _targetSyndromeIdMeta,
        targetSyndromeId.isAcceptableOrUnknown(
          data['target_syndrome_id']!,
          _targetSyndromeIdMeta,
        ),
      );
    }
    if (data.containsKey('target_dimension')) {
      context.handle(
        _targetDimensionMeta,
        targetDimension.isAcceptableOrUnknown(
          data['target_dimension']!,
          _targetDimensionMeta,
        ),
      );
    }
    if (data.containsKey('task_type')) {
      context.handle(
        _taskTypeMeta,
        taskType.isAcceptableOrUnknown(data['task_type']!, _taskTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_taskTypeMeta);
    }
    if (data.containsKey('task_description')) {
      context.handle(
        _taskDescriptionMeta,
        taskDescription.isAcceptableOrUnknown(
          data['task_description']!,
          _taskDescriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_taskDescriptionMeta);
    }
    if (data.containsKey('difficulty')) {
      context.handle(
        _difficultyMeta,
        difficulty.isAcceptableOrUnknown(data['difficulty']!, _difficultyMeta),
      );
    } else if (isInserting) {
      context.missing(_difficultyMeta);
    }
    if (data.containsKey('evaluation_criteria')) {
      context.handle(
        _evaluationCriteriaMeta,
        evaluationCriteria.isAcceptableOrUnknown(
          data['evaluation_criteria']!,
          _evaluationCriteriaMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('resolved_at')) {
      context.handle(
        _resolvedAtMeta,
        resolvedAt.isAcceptableOrUnknown(data['resolved_at']!, _resolvedAtMeta),
      );
    }
    if (data.containsKey('adopted_at')) {
      context.handle(
        _adoptedAtMeta,
        adoptedAt.isAcceptableOrUnknown(data['adopted_at']!, _adoptedAtMeta),
      );
    }
    if (data.containsKey('dismissed_at')) {
      context.handle(
        _dismissedAtMeta,
        dismissedAt.isAcceptableOrUnknown(
          data['dismissed_at']!,
          _dismissedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TeacherSuggestionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TeacherSuggestionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      teachingDecision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}teaching_decision'],
      )!,
      targetSyndromeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_syndrome_id'],
      ),
      targetDimension: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_dimension'],
      ),
      taskType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_type'],
      )!,
      taskDescription: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_description'],
      )!,
      difficulty: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}difficulty'],
      )!,
      evaluationCriteria: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}evaluation_criteria'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      resolvedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}resolved_at'],
      ),
      adoptedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}adopted_at'],
      ),
      dismissedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dismissed_at'],
      ),
    );
  }

  @override
  $TeacherSuggestionsTable createAlias(String alias) {
    return $TeacherSuggestionsTable(attachedDatabase, alias);
  }
}

class TeacherSuggestionRow extends DataClass
    implements Insertable<TeacherSuggestionRow> {
  final String id;
  final String sessionId;
  final String messageId;
  final String source;
  final String teachingDecision;
  final String? targetSyndromeId;
  final String? targetDimension;
  final String taskType;
  final String taskDescription;
  final String difficulty;
  final String evaluationCriteria;
  final String status;
  final int createdAt;
  final int? resolvedAt;

  /// 批次62：用户采纳时间（「开始练习」时写入；null = 未采纳）
  final int? adoptedAt;

  /// 批次62：用户跳过时间（「跳过此建议」时写入；null = 未跳过）
  final int? dismissedAt;
  const TeacherSuggestionRow({
    required this.id,
    required this.sessionId,
    required this.messageId,
    required this.source,
    required this.teachingDecision,
    this.targetSyndromeId,
    this.targetDimension,
    required this.taskType,
    required this.taskDescription,
    required this.difficulty,
    required this.evaluationCriteria,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
    this.adoptedAt,
    this.dismissedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['message_id'] = Variable<String>(messageId);
    map['source'] = Variable<String>(source);
    map['teaching_decision'] = Variable<String>(teachingDecision);
    if (!nullToAbsent || targetSyndromeId != null) {
      map['target_syndrome_id'] = Variable<String>(targetSyndromeId);
    }
    if (!nullToAbsent || targetDimension != null) {
      map['target_dimension'] = Variable<String>(targetDimension);
    }
    map['task_type'] = Variable<String>(taskType);
    map['task_description'] = Variable<String>(taskDescription);
    map['difficulty'] = Variable<String>(difficulty);
    map['evaluation_criteria'] = Variable<String>(evaluationCriteria);
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || resolvedAt != null) {
      map['resolved_at'] = Variable<int>(resolvedAt);
    }
    if (!nullToAbsent || adoptedAt != null) {
      map['adopted_at'] = Variable<int>(adoptedAt);
    }
    if (!nullToAbsent || dismissedAt != null) {
      map['dismissed_at'] = Variable<int>(dismissedAt);
    }
    return map;
  }

  TeacherSuggestionsCompanion toCompanion(bool nullToAbsent) {
    return TeacherSuggestionsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      messageId: Value(messageId),
      source: Value(source),
      teachingDecision: Value(teachingDecision),
      targetSyndromeId: targetSyndromeId == null && nullToAbsent
          ? const Value.absent()
          : Value(targetSyndromeId),
      targetDimension: targetDimension == null && nullToAbsent
          ? const Value.absent()
          : Value(targetDimension),
      taskType: Value(taskType),
      taskDescription: Value(taskDescription),
      difficulty: Value(difficulty),
      evaluationCriteria: Value(evaluationCriteria),
      status: Value(status),
      createdAt: Value(createdAt),
      resolvedAt: resolvedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedAt),
      adoptedAt: adoptedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(adoptedAt),
      dismissedAt: dismissedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(dismissedAt),
    );
  }

  factory TeacherSuggestionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TeacherSuggestionRow(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      messageId: serializer.fromJson<String>(json['messageId']),
      source: serializer.fromJson<String>(json['source']),
      teachingDecision: serializer.fromJson<String>(json['teachingDecision']),
      targetSyndromeId: serializer.fromJson<String?>(json['targetSyndromeId']),
      targetDimension: serializer.fromJson<String?>(json['targetDimension']),
      taskType: serializer.fromJson<String>(json['taskType']),
      taskDescription: serializer.fromJson<String>(json['taskDescription']),
      difficulty: serializer.fromJson<String>(json['difficulty']),
      evaluationCriteria: serializer.fromJson<String>(
        json['evaluationCriteria'],
      ),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      resolvedAt: serializer.fromJson<int?>(json['resolvedAt']),
      adoptedAt: serializer.fromJson<int?>(json['adoptedAt']),
      dismissedAt: serializer.fromJson<int?>(json['dismissedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'messageId': serializer.toJson<String>(messageId),
      'source': serializer.toJson<String>(source),
      'teachingDecision': serializer.toJson<String>(teachingDecision),
      'targetSyndromeId': serializer.toJson<String?>(targetSyndromeId),
      'targetDimension': serializer.toJson<String?>(targetDimension),
      'taskType': serializer.toJson<String>(taskType),
      'taskDescription': serializer.toJson<String>(taskDescription),
      'difficulty': serializer.toJson<String>(difficulty),
      'evaluationCriteria': serializer.toJson<String>(evaluationCriteria),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<int>(createdAt),
      'resolvedAt': serializer.toJson<int?>(resolvedAt),
      'adoptedAt': serializer.toJson<int?>(adoptedAt),
      'dismissedAt': serializer.toJson<int?>(dismissedAt),
    };
  }

  TeacherSuggestionRow copyWith({
    String? id,
    String? sessionId,
    String? messageId,
    String? source,
    String? teachingDecision,
    Value<String?> targetSyndromeId = const Value.absent(),
    Value<String?> targetDimension = const Value.absent(),
    String? taskType,
    String? taskDescription,
    String? difficulty,
    String? evaluationCriteria,
    String? status,
    int? createdAt,
    Value<int?> resolvedAt = const Value.absent(),
    Value<int?> adoptedAt = const Value.absent(),
    Value<int?> dismissedAt = const Value.absent(),
  }) => TeacherSuggestionRow(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    messageId: messageId ?? this.messageId,
    source: source ?? this.source,
    teachingDecision: teachingDecision ?? this.teachingDecision,
    targetSyndromeId: targetSyndromeId.present
        ? targetSyndromeId.value
        : this.targetSyndromeId,
    targetDimension: targetDimension.present
        ? targetDimension.value
        : this.targetDimension,
    taskType: taskType ?? this.taskType,
    taskDescription: taskDescription ?? this.taskDescription,
    difficulty: difficulty ?? this.difficulty,
    evaluationCriteria: evaluationCriteria ?? this.evaluationCriteria,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    resolvedAt: resolvedAt.present ? resolvedAt.value : this.resolvedAt,
    adoptedAt: adoptedAt.present ? adoptedAt.value : this.adoptedAt,
    dismissedAt: dismissedAt.present ? dismissedAt.value : this.dismissedAt,
  );
  TeacherSuggestionRow copyWithCompanion(TeacherSuggestionsCompanion data) {
    return TeacherSuggestionRow(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      source: data.source.present ? data.source.value : this.source,
      teachingDecision: data.teachingDecision.present
          ? data.teachingDecision.value
          : this.teachingDecision,
      targetSyndromeId: data.targetSyndromeId.present
          ? data.targetSyndromeId.value
          : this.targetSyndromeId,
      targetDimension: data.targetDimension.present
          ? data.targetDimension.value
          : this.targetDimension,
      taskType: data.taskType.present ? data.taskType.value : this.taskType,
      taskDescription: data.taskDescription.present
          ? data.taskDescription.value
          : this.taskDescription,
      difficulty: data.difficulty.present
          ? data.difficulty.value
          : this.difficulty,
      evaluationCriteria: data.evaluationCriteria.present
          ? data.evaluationCriteria.value
          : this.evaluationCriteria,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      resolvedAt: data.resolvedAt.present
          ? data.resolvedAt.value
          : this.resolvedAt,
      adoptedAt: data.adoptedAt.present ? data.adoptedAt.value : this.adoptedAt,
      dismissedAt: data.dismissedAt.present
          ? data.dismissedAt.value
          : this.dismissedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TeacherSuggestionRow(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('messageId: $messageId, ')
          ..write('source: $source, ')
          ..write('teachingDecision: $teachingDecision, ')
          ..write('targetSyndromeId: $targetSyndromeId, ')
          ..write('targetDimension: $targetDimension, ')
          ..write('taskType: $taskType, ')
          ..write('taskDescription: $taskDescription, ')
          ..write('difficulty: $difficulty, ')
          ..write('evaluationCriteria: $evaluationCriteria, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('adoptedAt: $adoptedAt, ')
          ..write('dismissedAt: $dismissedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    messageId,
    source,
    teachingDecision,
    targetSyndromeId,
    targetDimension,
    taskType,
    taskDescription,
    difficulty,
    evaluationCriteria,
    status,
    createdAt,
    resolvedAt,
    adoptedAt,
    dismissedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TeacherSuggestionRow &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.messageId == this.messageId &&
          other.source == this.source &&
          other.teachingDecision == this.teachingDecision &&
          other.targetSyndromeId == this.targetSyndromeId &&
          other.targetDimension == this.targetDimension &&
          other.taskType == this.taskType &&
          other.taskDescription == this.taskDescription &&
          other.difficulty == this.difficulty &&
          other.evaluationCriteria == this.evaluationCriteria &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.resolvedAt == this.resolvedAt &&
          other.adoptedAt == this.adoptedAt &&
          other.dismissedAt == this.dismissedAt);
}

class TeacherSuggestionsCompanion
    extends UpdateCompanion<TeacherSuggestionRow> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> messageId;
  final Value<String> source;
  final Value<String> teachingDecision;
  final Value<String?> targetSyndromeId;
  final Value<String?> targetDimension;
  final Value<String> taskType;
  final Value<String> taskDescription;
  final Value<String> difficulty;
  final Value<String> evaluationCriteria;
  final Value<String> status;
  final Value<int> createdAt;
  final Value<int?> resolvedAt;
  final Value<int?> adoptedAt;
  final Value<int?> dismissedAt;
  final Value<int> rowid;
  const TeacherSuggestionsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.source = const Value.absent(),
    this.teachingDecision = const Value.absent(),
    this.targetSyndromeId = const Value.absent(),
    this.targetDimension = const Value.absent(),
    this.taskType = const Value.absent(),
    this.taskDescription = const Value.absent(),
    this.difficulty = const Value.absent(),
    this.evaluationCriteria = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.adoptedAt = const Value.absent(),
    this.dismissedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TeacherSuggestionsCompanion.insert({
    required String id,
    required String sessionId,
    required String messageId,
    required String source,
    required String teachingDecision,
    this.targetSyndromeId = const Value.absent(),
    this.targetDimension = const Value.absent(),
    required String taskType,
    required String taskDescription,
    required String difficulty,
    this.evaluationCriteria = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.adoptedAt = const Value.absent(),
    this.dismissedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       messageId = Value(messageId),
       source = Value(source),
       teachingDecision = Value(teachingDecision),
       taskType = Value(taskType),
       taskDescription = Value(taskDescription),
       difficulty = Value(difficulty);
  static Insertable<TeacherSuggestionRow> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? messageId,
    Expression<String>? source,
    Expression<String>? teachingDecision,
    Expression<String>? targetSyndromeId,
    Expression<String>? targetDimension,
    Expression<String>? taskType,
    Expression<String>? taskDescription,
    Expression<String>? difficulty,
    Expression<String>? evaluationCriteria,
    Expression<String>? status,
    Expression<int>? createdAt,
    Expression<int>? resolvedAt,
    Expression<int>? adoptedAt,
    Expression<int>? dismissedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (messageId != null) 'message_id': messageId,
      if (source != null) 'source': source,
      if (teachingDecision != null) 'teaching_decision': teachingDecision,
      if (targetSyndromeId != null) 'target_syndrome_id': targetSyndromeId,
      if (targetDimension != null) 'target_dimension': targetDimension,
      if (taskType != null) 'task_type': taskType,
      if (taskDescription != null) 'task_description': taskDescription,
      if (difficulty != null) 'difficulty': difficulty,
      if (evaluationCriteria != null) 'evaluation_criteria': evaluationCriteria,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (resolvedAt != null) 'resolved_at': resolvedAt,
      if (adoptedAt != null) 'adopted_at': adoptedAt,
      if (dismissedAt != null) 'dismissed_at': dismissedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TeacherSuggestionsCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? messageId,
    Value<String>? source,
    Value<String>? teachingDecision,
    Value<String?>? targetSyndromeId,
    Value<String?>? targetDimension,
    Value<String>? taskType,
    Value<String>? taskDescription,
    Value<String>? difficulty,
    Value<String>? evaluationCriteria,
    Value<String>? status,
    Value<int>? createdAt,
    Value<int?>? resolvedAt,
    Value<int?>? adoptedAt,
    Value<int?>? dismissedAt,
    Value<int>? rowid,
  }) {
    return TeacherSuggestionsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      messageId: messageId ?? this.messageId,
      source: source ?? this.source,
      teachingDecision: teachingDecision ?? this.teachingDecision,
      targetSyndromeId: targetSyndromeId ?? this.targetSyndromeId,
      targetDimension: targetDimension ?? this.targetDimension,
      taskType: taskType ?? this.taskType,
      taskDescription: taskDescription ?? this.taskDescription,
      difficulty: difficulty ?? this.difficulty,
      evaluationCriteria: evaluationCriteria ?? this.evaluationCriteria,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      adoptedAt: adoptedAt ?? this.adoptedAt,
      dismissedAt: dismissedAt ?? this.dismissedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (teachingDecision.present) {
      map['teaching_decision'] = Variable<String>(teachingDecision.value);
    }
    if (targetSyndromeId.present) {
      map['target_syndrome_id'] = Variable<String>(targetSyndromeId.value);
    }
    if (targetDimension.present) {
      map['target_dimension'] = Variable<String>(targetDimension.value);
    }
    if (taskType.present) {
      map['task_type'] = Variable<String>(taskType.value);
    }
    if (taskDescription.present) {
      map['task_description'] = Variable<String>(taskDescription.value);
    }
    if (difficulty.present) {
      map['difficulty'] = Variable<String>(difficulty.value);
    }
    if (evaluationCriteria.present) {
      map['evaluation_criteria'] = Variable<String>(evaluationCriteria.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (resolvedAt.present) {
      map['resolved_at'] = Variable<int>(resolvedAt.value);
    }
    if (adoptedAt.present) {
      map['adopted_at'] = Variable<int>(adoptedAt.value);
    }
    if (dismissedAt.present) {
      map['dismissed_at'] = Variable<int>(dismissedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TeacherSuggestionsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('messageId: $messageId, ')
          ..write('source: $source, ')
          ..write('teachingDecision: $teachingDecision, ')
          ..write('targetSyndromeId: $targetSyndromeId, ')
          ..write('targetDimension: $targetDimension, ')
          ..write('taskType: $taskType, ')
          ..write('taskDescription: $taskDescription, ')
          ..write('difficulty: $difficulty, ')
          ..write('evaluationCriteria: $evaluationCriteria, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('adoptedAt: $adoptedAt, ')
          ..write('dismissedAt: $dismissedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EditorObservationsTable extends EditorObservations
    with TableInfo<$EditorObservationsTable, EditorObservationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EditorObservationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES messages (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _possibleIntentMeta = const VerificationMeta(
    'possibleIntent',
  );
  @override
  late final GeneratedColumn<String> possibleIntent = GeneratedColumn<String>(
    'possible_intent',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _intentConfidenceMeta = const VerificationMeta(
    'intentConfidence',
  );
  @override
  late final GeneratedColumn<String> intentConfidence = GeneratedColumn<String>(
    'intent_confidence',
    aliasedName,
    false,
    check: () => intentConfidence.isIn(const ['low', 'moderate', 'high']),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _observationsMeta = const VerificationMeta(
    'observations',
  );
  @override
  late final GeneratedColumn<String> observations = GeneratedColumn<String>(
    'observations',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _overallImpressionMeta = const VerificationMeta(
    'overallImpression',
  );
  @override
  late final GeneratedColumn<String> overallImpression =
      GeneratedColumn<String>(
        'overall_impression',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _strengthsMeta = const VerificationMeta(
    'strengths',
  );
  @override
  late final GeneratedColumn<String> strengths = GeneratedColumn<String>(
    'strengths',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _teacherTriggeredMeta = const VerificationMeta(
    'teacherTriggered',
  );
  @override
  late final GeneratedColumn<int> teacherTriggered = GeneratedColumn<int>(
    'teacher_triggered',
    aliasedName,
    false,
    check: () => teacherTriggered.isIn(const [0, 1]),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pronouncedCountMeta = const VerificationMeta(
    'pronouncedCount',
  );
  @override
  late final GeneratedColumn<int> pronouncedCount = GeneratedColumn<int>(
    'pronounced_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _againstCountMeta = const VerificationMeta(
    'againstCount',
  );
  @override
  late final GeneratedColumn<int> againstCount = GeneratedColumn<int>(
    'against_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _targetRefTypeMeta = const VerificationMeta(
    'targetRefType',
  );
  @override
  late final GeneratedColumn<String> targetRefType = GeneratedColumn<String>(
    'target_ref_type',
    aliasedName,
    true,
    check: () =>
        targetRefType.isNull() |
        targetRefType.isIn(const ['manuscript', 'chapter']),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _targetRefIdMeta = const VerificationMeta(
    'targetRefId',
  );
  @override
  late final GeneratedColumn<String> targetRefId = GeneratedColumn<String>(
    'target_ref_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    messageId,
    possibleIntent,
    intentConfidence,
    observations,
    overallImpression,
    strengths,
    teacherTriggered,
    pronouncedCount,
    againstCount,
    targetRefType,
    targetRefId,
    timestamp,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'editor_observation';
  @override
  VerificationContext validateIntegrity(
    Insertable<EditorObservationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('possible_intent')) {
      context.handle(
        _possibleIntentMeta,
        possibleIntent.isAcceptableOrUnknown(
          data['possible_intent']!,
          _possibleIntentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_possibleIntentMeta);
    }
    if (data.containsKey('intent_confidence')) {
      context.handle(
        _intentConfidenceMeta,
        intentConfidence.isAcceptableOrUnknown(
          data['intent_confidence']!,
          _intentConfidenceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_intentConfidenceMeta);
    }
    if (data.containsKey('observations')) {
      context.handle(
        _observationsMeta,
        observations.isAcceptableOrUnknown(
          data['observations']!,
          _observationsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_observationsMeta);
    }
    if (data.containsKey('overall_impression')) {
      context.handle(
        _overallImpressionMeta,
        overallImpression.isAcceptableOrUnknown(
          data['overall_impression']!,
          _overallImpressionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_overallImpressionMeta);
    }
    if (data.containsKey('strengths')) {
      context.handle(
        _strengthsMeta,
        strengths.isAcceptableOrUnknown(data['strengths']!, _strengthsMeta),
      );
    }
    if (data.containsKey('teacher_triggered')) {
      context.handle(
        _teacherTriggeredMeta,
        teacherTriggered.isAcceptableOrUnknown(
          data['teacher_triggered']!,
          _teacherTriggeredMeta,
        ),
      );
    }
    if (data.containsKey('pronounced_count')) {
      context.handle(
        _pronouncedCountMeta,
        pronouncedCount.isAcceptableOrUnknown(
          data['pronounced_count']!,
          _pronouncedCountMeta,
        ),
      );
    }
    if (data.containsKey('against_count')) {
      context.handle(
        _againstCountMeta,
        againstCount.isAcceptableOrUnknown(
          data['against_count']!,
          _againstCountMeta,
        ),
      );
    }
    if (data.containsKey('target_ref_type')) {
      context.handle(
        _targetRefTypeMeta,
        targetRefType.isAcceptableOrUnknown(
          data['target_ref_type']!,
          _targetRefTypeMeta,
        ),
      );
    }
    if (data.containsKey('target_ref_id')) {
      context.handle(
        _targetRefIdMeta,
        targetRefId.isAcceptableOrUnknown(
          data['target_ref_id']!,
          _targetRefIdMeta,
        ),
      );
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {sessionId, messageId},
  ];
  @override
  EditorObservationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EditorObservationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      possibleIntent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}possible_intent'],
      )!,
      intentConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intent_confidence'],
      )!,
      observations: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}observations'],
      )!,
      overallImpression: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}overall_impression'],
      )!,
      strengths: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}strengths'],
      )!,
      teacherTriggered: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}teacher_triggered'],
      )!,
      pronouncedCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pronounced_count'],
      )!,
      againstCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}against_count'],
      )!,
      targetRefType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_ref_type'],
      ),
      targetRefId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_ref_id'],
      ),
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $EditorObservationsTable createAlias(String alias) {
    return $EditorObservationsTable(attachedDatabase, alias);
  }
}

class EditorObservationRow extends DataClass
    implements Insertable<EditorObservationRow> {
  final String id;
  final String sessionId;
  final String messageId;
  final String possibleIntent;
  final String intentConfidence;
  final String observations;
  final String overallImpression;
  final String strengths;
  final int teacherTriggered;
  final int pronouncedCount;
  final int againstCount;
  final String? targetRefType;
  final String? targetRefId;
  final int timestamp;
  final int createdAt;
  const EditorObservationRow({
    required this.id,
    required this.sessionId,
    required this.messageId,
    required this.possibleIntent,
    required this.intentConfidence,
    required this.observations,
    required this.overallImpression,
    required this.strengths,
    required this.teacherTriggered,
    required this.pronouncedCount,
    required this.againstCount,
    this.targetRefType,
    this.targetRefId,
    required this.timestamp,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['message_id'] = Variable<String>(messageId);
    map['possible_intent'] = Variable<String>(possibleIntent);
    map['intent_confidence'] = Variable<String>(intentConfidence);
    map['observations'] = Variable<String>(observations);
    map['overall_impression'] = Variable<String>(overallImpression);
    map['strengths'] = Variable<String>(strengths);
    map['teacher_triggered'] = Variable<int>(teacherTriggered);
    map['pronounced_count'] = Variable<int>(pronouncedCount);
    map['against_count'] = Variable<int>(againstCount);
    if (!nullToAbsent || targetRefType != null) {
      map['target_ref_type'] = Variable<String>(targetRefType);
    }
    if (!nullToAbsent || targetRefId != null) {
      map['target_ref_id'] = Variable<String>(targetRefId);
    }
    map['timestamp'] = Variable<int>(timestamp);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  EditorObservationsCompanion toCompanion(bool nullToAbsent) {
    return EditorObservationsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      messageId: Value(messageId),
      possibleIntent: Value(possibleIntent),
      intentConfidence: Value(intentConfidence),
      observations: Value(observations),
      overallImpression: Value(overallImpression),
      strengths: Value(strengths),
      teacherTriggered: Value(teacherTriggered),
      pronouncedCount: Value(pronouncedCount),
      againstCount: Value(againstCount),
      targetRefType: targetRefType == null && nullToAbsent
          ? const Value.absent()
          : Value(targetRefType),
      targetRefId: targetRefId == null && nullToAbsent
          ? const Value.absent()
          : Value(targetRefId),
      timestamp: Value(timestamp),
      createdAt: Value(createdAt),
    );
  }

  factory EditorObservationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EditorObservationRow(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      messageId: serializer.fromJson<String>(json['messageId']),
      possibleIntent: serializer.fromJson<String>(json['possibleIntent']),
      intentConfidence: serializer.fromJson<String>(json['intentConfidence']),
      observations: serializer.fromJson<String>(json['observations']),
      overallImpression: serializer.fromJson<String>(json['overallImpression']),
      strengths: serializer.fromJson<String>(json['strengths']),
      teacherTriggered: serializer.fromJson<int>(json['teacherTriggered']),
      pronouncedCount: serializer.fromJson<int>(json['pronouncedCount']),
      againstCount: serializer.fromJson<int>(json['againstCount']),
      targetRefType: serializer.fromJson<String?>(json['targetRefType']),
      targetRefId: serializer.fromJson<String?>(json['targetRefId']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'messageId': serializer.toJson<String>(messageId),
      'possibleIntent': serializer.toJson<String>(possibleIntent),
      'intentConfidence': serializer.toJson<String>(intentConfidence),
      'observations': serializer.toJson<String>(observations),
      'overallImpression': serializer.toJson<String>(overallImpression),
      'strengths': serializer.toJson<String>(strengths),
      'teacherTriggered': serializer.toJson<int>(teacherTriggered),
      'pronouncedCount': serializer.toJson<int>(pronouncedCount),
      'againstCount': serializer.toJson<int>(againstCount),
      'targetRefType': serializer.toJson<String?>(targetRefType),
      'targetRefId': serializer.toJson<String?>(targetRefId),
      'timestamp': serializer.toJson<int>(timestamp),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  EditorObservationRow copyWith({
    String? id,
    String? sessionId,
    String? messageId,
    String? possibleIntent,
    String? intentConfidence,
    String? observations,
    String? overallImpression,
    String? strengths,
    int? teacherTriggered,
    int? pronouncedCount,
    int? againstCount,
    Value<String?> targetRefType = const Value.absent(),
    Value<String?> targetRefId = const Value.absent(),
    int? timestamp,
    int? createdAt,
  }) => EditorObservationRow(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    messageId: messageId ?? this.messageId,
    possibleIntent: possibleIntent ?? this.possibleIntent,
    intentConfidence: intentConfidence ?? this.intentConfidence,
    observations: observations ?? this.observations,
    overallImpression: overallImpression ?? this.overallImpression,
    strengths: strengths ?? this.strengths,
    teacherTriggered: teacherTriggered ?? this.teacherTriggered,
    pronouncedCount: pronouncedCount ?? this.pronouncedCount,
    againstCount: againstCount ?? this.againstCount,
    targetRefType: targetRefType.present
        ? targetRefType.value
        : this.targetRefType,
    targetRefId: targetRefId.present ? targetRefId.value : this.targetRefId,
    timestamp: timestamp ?? this.timestamp,
    createdAt: createdAt ?? this.createdAt,
  );
  EditorObservationRow copyWithCompanion(EditorObservationsCompanion data) {
    return EditorObservationRow(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      possibleIntent: data.possibleIntent.present
          ? data.possibleIntent.value
          : this.possibleIntent,
      intentConfidence: data.intentConfidence.present
          ? data.intentConfidence.value
          : this.intentConfidence,
      observations: data.observations.present
          ? data.observations.value
          : this.observations,
      overallImpression: data.overallImpression.present
          ? data.overallImpression.value
          : this.overallImpression,
      strengths: data.strengths.present ? data.strengths.value : this.strengths,
      teacherTriggered: data.teacherTriggered.present
          ? data.teacherTriggered.value
          : this.teacherTriggered,
      pronouncedCount: data.pronouncedCount.present
          ? data.pronouncedCount.value
          : this.pronouncedCount,
      againstCount: data.againstCount.present
          ? data.againstCount.value
          : this.againstCount,
      targetRefType: data.targetRefType.present
          ? data.targetRefType.value
          : this.targetRefType,
      targetRefId: data.targetRefId.present
          ? data.targetRefId.value
          : this.targetRefId,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EditorObservationRow(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('messageId: $messageId, ')
          ..write('possibleIntent: $possibleIntent, ')
          ..write('intentConfidence: $intentConfidence, ')
          ..write('observations: $observations, ')
          ..write('overallImpression: $overallImpression, ')
          ..write('strengths: $strengths, ')
          ..write('teacherTriggered: $teacherTriggered, ')
          ..write('pronouncedCount: $pronouncedCount, ')
          ..write('againstCount: $againstCount, ')
          ..write('targetRefType: $targetRefType, ')
          ..write('targetRefId: $targetRefId, ')
          ..write('timestamp: $timestamp, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    messageId,
    possibleIntent,
    intentConfidence,
    observations,
    overallImpression,
    strengths,
    teacherTriggered,
    pronouncedCount,
    againstCount,
    targetRefType,
    targetRefId,
    timestamp,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EditorObservationRow &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.messageId == this.messageId &&
          other.possibleIntent == this.possibleIntent &&
          other.intentConfidence == this.intentConfidence &&
          other.observations == this.observations &&
          other.overallImpression == this.overallImpression &&
          other.strengths == this.strengths &&
          other.teacherTriggered == this.teacherTriggered &&
          other.pronouncedCount == this.pronouncedCount &&
          other.againstCount == this.againstCount &&
          other.targetRefType == this.targetRefType &&
          other.targetRefId == this.targetRefId &&
          other.timestamp == this.timestamp &&
          other.createdAt == this.createdAt);
}

class EditorObservationsCompanion
    extends UpdateCompanion<EditorObservationRow> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> messageId;
  final Value<String> possibleIntent;
  final Value<String> intentConfidence;
  final Value<String> observations;
  final Value<String> overallImpression;
  final Value<String> strengths;
  final Value<int> teacherTriggered;
  final Value<int> pronouncedCount;
  final Value<int> againstCount;
  final Value<String?> targetRefType;
  final Value<String?> targetRefId;
  final Value<int> timestamp;
  final Value<int> createdAt;
  final Value<int> rowid;
  const EditorObservationsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.possibleIntent = const Value.absent(),
    this.intentConfidence = const Value.absent(),
    this.observations = const Value.absent(),
    this.overallImpression = const Value.absent(),
    this.strengths = const Value.absent(),
    this.teacherTriggered = const Value.absent(),
    this.pronouncedCount = const Value.absent(),
    this.againstCount = const Value.absent(),
    this.targetRefType = const Value.absent(),
    this.targetRefId = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EditorObservationsCompanion.insert({
    required String id,
    required String sessionId,
    required String messageId,
    required String possibleIntent,
    required String intentConfidence,
    required String observations,
    required String overallImpression,
    this.strengths = const Value.absent(),
    this.teacherTriggered = const Value.absent(),
    this.pronouncedCount = const Value.absent(),
    this.againstCount = const Value.absent(),
    this.targetRefType = const Value.absent(),
    this.targetRefId = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       messageId = Value(messageId),
       possibleIntent = Value(possibleIntent),
       intentConfidence = Value(intentConfidence),
       observations = Value(observations),
       overallImpression = Value(overallImpression);
  static Insertable<EditorObservationRow> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? messageId,
    Expression<String>? possibleIntent,
    Expression<String>? intentConfidence,
    Expression<String>? observations,
    Expression<String>? overallImpression,
    Expression<String>? strengths,
    Expression<int>? teacherTriggered,
    Expression<int>? pronouncedCount,
    Expression<int>? againstCount,
    Expression<String>? targetRefType,
    Expression<String>? targetRefId,
    Expression<int>? timestamp,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (messageId != null) 'message_id': messageId,
      if (possibleIntent != null) 'possible_intent': possibleIntent,
      if (intentConfidence != null) 'intent_confidence': intentConfidence,
      if (observations != null) 'observations': observations,
      if (overallImpression != null) 'overall_impression': overallImpression,
      if (strengths != null) 'strengths': strengths,
      if (teacherTriggered != null) 'teacher_triggered': teacherTriggered,
      if (pronouncedCount != null) 'pronounced_count': pronouncedCount,
      if (againstCount != null) 'against_count': againstCount,
      if (targetRefType != null) 'target_ref_type': targetRefType,
      if (targetRefId != null) 'target_ref_id': targetRefId,
      if (timestamp != null) 'timestamp': timestamp,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EditorObservationsCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? messageId,
    Value<String>? possibleIntent,
    Value<String>? intentConfidence,
    Value<String>? observations,
    Value<String>? overallImpression,
    Value<String>? strengths,
    Value<int>? teacherTriggered,
    Value<int>? pronouncedCount,
    Value<int>? againstCount,
    Value<String?>? targetRefType,
    Value<String?>? targetRefId,
    Value<int>? timestamp,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return EditorObservationsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      messageId: messageId ?? this.messageId,
      possibleIntent: possibleIntent ?? this.possibleIntent,
      intentConfidence: intentConfidence ?? this.intentConfidence,
      observations: observations ?? this.observations,
      overallImpression: overallImpression ?? this.overallImpression,
      strengths: strengths ?? this.strengths,
      teacherTriggered: teacherTriggered ?? this.teacherTriggered,
      pronouncedCount: pronouncedCount ?? this.pronouncedCount,
      againstCount: againstCount ?? this.againstCount,
      targetRefType: targetRefType ?? this.targetRefType,
      targetRefId: targetRefId ?? this.targetRefId,
      timestamp: timestamp ?? this.timestamp,
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
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (possibleIntent.present) {
      map['possible_intent'] = Variable<String>(possibleIntent.value);
    }
    if (intentConfidence.present) {
      map['intent_confidence'] = Variable<String>(intentConfidence.value);
    }
    if (observations.present) {
      map['observations'] = Variable<String>(observations.value);
    }
    if (overallImpression.present) {
      map['overall_impression'] = Variable<String>(overallImpression.value);
    }
    if (strengths.present) {
      map['strengths'] = Variable<String>(strengths.value);
    }
    if (teacherTriggered.present) {
      map['teacher_triggered'] = Variable<int>(teacherTriggered.value);
    }
    if (pronouncedCount.present) {
      map['pronounced_count'] = Variable<int>(pronouncedCount.value);
    }
    if (againstCount.present) {
      map['against_count'] = Variable<int>(againstCount.value);
    }
    if (targetRefType.present) {
      map['target_ref_type'] = Variable<String>(targetRefType.value);
    }
    if (targetRefId.present) {
      map['target_ref_id'] = Variable<String>(targetRefId.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
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
    return (StringBuffer('EditorObservationsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('messageId: $messageId, ')
          ..write('possibleIntent: $possibleIntent, ')
          ..write('intentConfidence: $intentConfidence, ')
          ..write('observations: $observations, ')
          ..write('overallImpression: $overallImpression, ')
          ..write('strengths: $strengths, ')
          ..write('teacherTriggered: $teacherTriggered, ')
          ..write('pronouncedCount: $pronouncedCount, ')
          ..write('againstCount: $againstCount, ')
          ..write('targetRefType: $targetRefType, ')
          ..write('targetRefId: $targetRefId, ')
          ..write('timestamp: $timestamp, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CharacterFactsTable extends CharacterFacts
    with TableInfo<$CharacterFactsTable, CharacterFact> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CharacterFactsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _manuscriptIdMeta = const VerificationMeta(
    'manuscriptId',
  );
  @override
  late final GeneratedColumn<String> manuscriptId = GeneratedColumn<String>(
    'manuscript_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES manuscripts (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstSeenChapterMeta = const VerificationMeta(
    'firstSeenChapter',
  );
  @override
  late final GeneratedColumn<int> firstSeenChapter = GeneratedColumn<int>(
    'first_seen_chapter',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _firstSeenAtMeta = const VerificationMeta(
    'firstSeenAt',
  );
  @override
  late final GeneratedColumn<int> firstSeenAt = GeneratedColumn<int>(
    'first_seen_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _assertionsMeta = const VerificationMeta(
    'assertions',
  );
  @override
  late final GeneratedColumn<String> assertions = GeneratedColumn<String>(
    'assertions',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    manuscriptId,
    name,
    firstSeenChapter,
    firstSeenAt,
    assertions,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'character_fact';
  @override
  VerificationContext validateIntegrity(
    Insertable<CharacterFact> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('manuscript_id')) {
      context.handle(
        _manuscriptIdMeta,
        manuscriptId.isAcceptableOrUnknown(
          data['manuscript_id']!,
          _manuscriptIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_manuscriptIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('first_seen_chapter')) {
      context.handle(
        _firstSeenChapterMeta,
        firstSeenChapter.isAcceptableOrUnknown(
          data['first_seen_chapter']!,
          _firstSeenChapterMeta,
        ),
      );
    }
    if (data.containsKey('first_seen_at')) {
      context.handle(
        _firstSeenAtMeta,
        firstSeenAt.isAcceptableOrUnknown(
          data['first_seen_at']!,
          _firstSeenAtMeta,
        ),
      );
    }
    if (data.containsKey('assertions')) {
      context.handle(
        _assertionsMeta,
        assertions.isAcceptableOrUnknown(data['assertions']!, _assertionsMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {manuscriptId, name},
  ];
  @override
  CharacterFact map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CharacterFact(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      manuscriptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manuscript_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      firstSeenChapter: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_seen_chapter'],
      ),
      firstSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_seen_at'],
      ),
      assertions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assertions'],
      )!,
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
  $CharacterFactsTable createAlias(String alias) {
    return $CharacterFactsTable(attachedDatabase, alias);
  }
}

class CharacterFact extends DataClass implements Insertable<CharacterFact> {
  final String id;
  final String manuscriptId;
  final String name;
  final int? firstSeenChapter;
  final int? firstSeenAt;
  final String assertions;
  final int createdAt;
  final int updatedAt;
  const CharacterFact({
    required this.id,
    required this.manuscriptId,
    required this.name,
    this.firstSeenChapter,
    this.firstSeenAt,
    required this.assertions,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['manuscript_id'] = Variable<String>(manuscriptId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || firstSeenChapter != null) {
      map['first_seen_chapter'] = Variable<int>(firstSeenChapter);
    }
    if (!nullToAbsent || firstSeenAt != null) {
      map['first_seen_at'] = Variable<int>(firstSeenAt);
    }
    map['assertions'] = Variable<String>(assertions);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  CharacterFactsCompanion toCompanion(bool nullToAbsent) {
    return CharacterFactsCompanion(
      id: Value(id),
      manuscriptId: Value(manuscriptId),
      name: Value(name),
      firstSeenChapter: firstSeenChapter == null && nullToAbsent
          ? const Value.absent()
          : Value(firstSeenChapter),
      firstSeenAt: firstSeenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(firstSeenAt),
      assertions: Value(assertions),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CharacterFact.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CharacterFact(
      id: serializer.fromJson<String>(json['id']),
      manuscriptId: serializer.fromJson<String>(json['manuscriptId']),
      name: serializer.fromJson<String>(json['name']),
      firstSeenChapter: serializer.fromJson<int?>(json['firstSeenChapter']),
      firstSeenAt: serializer.fromJson<int?>(json['firstSeenAt']),
      assertions: serializer.fromJson<String>(json['assertions']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'manuscriptId': serializer.toJson<String>(manuscriptId),
      'name': serializer.toJson<String>(name),
      'firstSeenChapter': serializer.toJson<int?>(firstSeenChapter),
      'firstSeenAt': serializer.toJson<int?>(firstSeenAt),
      'assertions': serializer.toJson<String>(assertions),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  CharacterFact copyWith({
    String? id,
    String? manuscriptId,
    String? name,
    Value<int?> firstSeenChapter = const Value.absent(),
    Value<int?> firstSeenAt = const Value.absent(),
    String? assertions,
    int? createdAt,
    int? updatedAt,
  }) => CharacterFact(
    id: id ?? this.id,
    manuscriptId: manuscriptId ?? this.manuscriptId,
    name: name ?? this.name,
    firstSeenChapter: firstSeenChapter.present
        ? firstSeenChapter.value
        : this.firstSeenChapter,
    firstSeenAt: firstSeenAt.present ? firstSeenAt.value : this.firstSeenAt,
    assertions: assertions ?? this.assertions,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CharacterFact copyWithCompanion(CharacterFactsCompanion data) {
    return CharacterFact(
      id: data.id.present ? data.id.value : this.id,
      manuscriptId: data.manuscriptId.present
          ? data.manuscriptId.value
          : this.manuscriptId,
      name: data.name.present ? data.name.value : this.name,
      firstSeenChapter: data.firstSeenChapter.present
          ? data.firstSeenChapter.value
          : this.firstSeenChapter,
      firstSeenAt: data.firstSeenAt.present
          ? data.firstSeenAt.value
          : this.firstSeenAt,
      assertions: data.assertions.present
          ? data.assertions.value
          : this.assertions,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CharacterFact(')
          ..write('id: $id, ')
          ..write('manuscriptId: $manuscriptId, ')
          ..write('name: $name, ')
          ..write('firstSeenChapter: $firstSeenChapter, ')
          ..write('firstSeenAt: $firstSeenAt, ')
          ..write('assertions: $assertions, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    manuscriptId,
    name,
    firstSeenChapter,
    firstSeenAt,
    assertions,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CharacterFact &&
          other.id == this.id &&
          other.manuscriptId == this.manuscriptId &&
          other.name == this.name &&
          other.firstSeenChapter == this.firstSeenChapter &&
          other.firstSeenAt == this.firstSeenAt &&
          other.assertions == this.assertions &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CharacterFactsCompanion extends UpdateCompanion<CharacterFact> {
  final Value<String> id;
  final Value<String> manuscriptId;
  final Value<String> name;
  final Value<int?> firstSeenChapter;
  final Value<int?> firstSeenAt;
  final Value<String> assertions;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const CharacterFactsCompanion({
    this.id = const Value.absent(),
    this.manuscriptId = const Value.absent(),
    this.name = const Value.absent(),
    this.firstSeenChapter = const Value.absent(),
    this.firstSeenAt = const Value.absent(),
    this.assertions = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CharacterFactsCompanion.insert({
    required String id,
    required String manuscriptId,
    required String name,
    this.firstSeenChapter = const Value.absent(),
    this.firstSeenAt = const Value.absent(),
    this.assertions = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       manuscriptId = Value(manuscriptId),
       name = Value(name);
  static Insertable<CharacterFact> custom({
    Expression<String>? id,
    Expression<String>? manuscriptId,
    Expression<String>? name,
    Expression<int>? firstSeenChapter,
    Expression<int>? firstSeenAt,
    Expression<String>? assertions,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (manuscriptId != null) 'manuscript_id': manuscriptId,
      if (name != null) 'name': name,
      if (firstSeenChapter != null) 'first_seen_chapter': firstSeenChapter,
      if (firstSeenAt != null) 'first_seen_at': firstSeenAt,
      if (assertions != null) 'assertions': assertions,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CharacterFactsCompanion copyWith({
    Value<String>? id,
    Value<String>? manuscriptId,
    Value<String>? name,
    Value<int?>? firstSeenChapter,
    Value<int?>? firstSeenAt,
    Value<String>? assertions,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return CharacterFactsCompanion(
      id: id ?? this.id,
      manuscriptId: manuscriptId ?? this.manuscriptId,
      name: name ?? this.name,
      firstSeenChapter: firstSeenChapter ?? this.firstSeenChapter,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      assertions: assertions ?? this.assertions,
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
    if (manuscriptId.present) {
      map['manuscript_id'] = Variable<String>(manuscriptId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (firstSeenChapter.present) {
      map['first_seen_chapter'] = Variable<int>(firstSeenChapter.value);
    }
    if (firstSeenAt.present) {
      map['first_seen_at'] = Variable<int>(firstSeenAt.value);
    }
    if (assertions.present) {
      map['assertions'] = Variable<String>(assertions.value);
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
    return (StringBuffer('CharacterFactsCompanion(')
          ..write('id: $id, ')
          ..write('manuscriptId: $manuscriptId, ')
          ..write('name: $name, ')
          ..write('firstSeenChapter: $firstSeenChapter, ')
          ..write('firstSeenAt: $firstSeenAt, ')
          ..write('assertions: $assertions, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EventFactsTable extends EventFacts
    with TableInfo<$EventFactsTable, EventFact> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventFactsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _manuscriptIdMeta = const VerificationMeta(
    'manuscriptId',
  );
  @override
  late final GeneratedColumn<String> manuscriptId = GeneratedColumn<String>(
    'manuscript_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES manuscripts (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterMeta = const VerificationMeta(
    'chapter',
  );
  @override
  late final GeneratedColumn<int> chapter = GeneratedColumn<int>(
    'chapter',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _eventTypeMeta = const VerificationMeta(
    'eventType',
  );
  @override
  late final GeneratedColumn<String> eventType = GeneratedColumn<String>(
    'event_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _causeEventIdMeta = const VerificationMeta(
    'causeEventId',
  );
  @override
  late final GeneratedColumn<String> causeEventId = GeneratedColumn<String>(
    'cause_event_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _effectEventIdMeta = const VerificationMeta(
    'effectEventId',
  );
  @override
  late final GeneratedColumn<String> effectEventId = GeneratedColumn<String>(
    'effect_event_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _participantsMeta = const VerificationMeta(
    'participants',
  );
  @override
  late final GeneratedColumn<String> participants = GeneratedColumn<String>(
    'participants',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    manuscriptId,
    name,
    chapter,
    eventType,
    causeEventId,
    effectEventId,
    participants,
    description,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'event_fact';
  @override
  VerificationContext validateIntegrity(
    Insertable<EventFact> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('manuscript_id')) {
      context.handle(
        _manuscriptIdMeta,
        manuscriptId.isAcceptableOrUnknown(
          data['manuscript_id']!,
          _manuscriptIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_manuscriptIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('chapter')) {
      context.handle(
        _chapterMeta,
        chapter.isAcceptableOrUnknown(data['chapter']!, _chapterMeta),
      );
    }
    if (data.containsKey('event_type')) {
      context.handle(
        _eventTypeMeta,
        eventType.isAcceptableOrUnknown(data['event_type']!, _eventTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_eventTypeMeta);
    }
    if (data.containsKey('cause_event_id')) {
      context.handle(
        _causeEventIdMeta,
        causeEventId.isAcceptableOrUnknown(
          data['cause_event_id']!,
          _causeEventIdMeta,
        ),
      );
    }
    if (data.containsKey('effect_event_id')) {
      context.handle(
        _effectEventIdMeta,
        effectEventId.isAcceptableOrUnknown(
          data['effect_event_id']!,
          _effectEventIdMeta,
        ),
      );
    }
    if (data.containsKey('participants')) {
      context.handle(
        _participantsMeta,
        participants.isAcceptableOrUnknown(
          data['participants']!,
          _participantsMeta,
        ),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {manuscriptId, name},
  ];
  @override
  EventFact map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EventFact(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      manuscriptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manuscript_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      chapter: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter'],
      ),
      eventType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_type'],
      )!,
      causeEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cause_event_id'],
      ),
      effectEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}effect_event_id'],
      ),
      participants: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}participants'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
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
  $EventFactsTable createAlias(String alias) {
    return $EventFactsTable(attachedDatabase, alias);
  }
}

class EventFact extends DataClass implements Insertable<EventFact> {
  final String id;
  final String manuscriptId;
  final String name;
  final int? chapter;
  final String eventType;
  final String? causeEventId;
  final String? effectEventId;
  final String participants;
  final String description;
  final int createdAt;
  final int updatedAt;
  const EventFact({
    required this.id,
    required this.manuscriptId,
    required this.name,
    this.chapter,
    required this.eventType,
    this.causeEventId,
    this.effectEventId,
    required this.participants,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['manuscript_id'] = Variable<String>(manuscriptId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || chapter != null) {
      map['chapter'] = Variable<int>(chapter);
    }
    map['event_type'] = Variable<String>(eventType);
    if (!nullToAbsent || causeEventId != null) {
      map['cause_event_id'] = Variable<String>(causeEventId);
    }
    if (!nullToAbsent || effectEventId != null) {
      map['effect_event_id'] = Variable<String>(effectEventId);
    }
    map['participants'] = Variable<String>(participants);
    map['description'] = Variable<String>(description);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  EventFactsCompanion toCompanion(bool nullToAbsent) {
    return EventFactsCompanion(
      id: Value(id),
      manuscriptId: Value(manuscriptId),
      name: Value(name),
      chapter: chapter == null && nullToAbsent
          ? const Value.absent()
          : Value(chapter),
      eventType: Value(eventType),
      causeEventId: causeEventId == null && nullToAbsent
          ? const Value.absent()
          : Value(causeEventId),
      effectEventId: effectEventId == null && nullToAbsent
          ? const Value.absent()
          : Value(effectEventId),
      participants: Value(participants),
      description: Value(description),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory EventFact.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EventFact(
      id: serializer.fromJson<String>(json['id']),
      manuscriptId: serializer.fromJson<String>(json['manuscriptId']),
      name: serializer.fromJson<String>(json['name']),
      chapter: serializer.fromJson<int?>(json['chapter']),
      eventType: serializer.fromJson<String>(json['eventType']),
      causeEventId: serializer.fromJson<String?>(json['causeEventId']),
      effectEventId: serializer.fromJson<String?>(json['effectEventId']),
      participants: serializer.fromJson<String>(json['participants']),
      description: serializer.fromJson<String>(json['description']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'manuscriptId': serializer.toJson<String>(manuscriptId),
      'name': serializer.toJson<String>(name),
      'chapter': serializer.toJson<int?>(chapter),
      'eventType': serializer.toJson<String>(eventType),
      'causeEventId': serializer.toJson<String?>(causeEventId),
      'effectEventId': serializer.toJson<String?>(effectEventId),
      'participants': serializer.toJson<String>(participants),
      'description': serializer.toJson<String>(description),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  EventFact copyWith({
    String? id,
    String? manuscriptId,
    String? name,
    Value<int?> chapter = const Value.absent(),
    String? eventType,
    Value<String?> causeEventId = const Value.absent(),
    Value<String?> effectEventId = const Value.absent(),
    String? participants,
    String? description,
    int? createdAt,
    int? updatedAt,
  }) => EventFact(
    id: id ?? this.id,
    manuscriptId: manuscriptId ?? this.manuscriptId,
    name: name ?? this.name,
    chapter: chapter.present ? chapter.value : this.chapter,
    eventType: eventType ?? this.eventType,
    causeEventId: causeEventId.present ? causeEventId.value : this.causeEventId,
    effectEventId: effectEventId.present
        ? effectEventId.value
        : this.effectEventId,
    participants: participants ?? this.participants,
    description: description ?? this.description,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  EventFact copyWithCompanion(EventFactsCompanion data) {
    return EventFact(
      id: data.id.present ? data.id.value : this.id,
      manuscriptId: data.manuscriptId.present
          ? data.manuscriptId.value
          : this.manuscriptId,
      name: data.name.present ? data.name.value : this.name,
      chapter: data.chapter.present ? data.chapter.value : this.chapter,
      eventType: data.eventType.present ? data.eventType.value : this.eventType,
      causeEventId: data.causeEventId.present
          ? data.causeEventId.value
          : this.causeEventId,
      effectEventId: data.effectEventId.present
          ? data.effectEventId.value
          : this.effectEventId,
      participants: data.participants.present
          ? data.participants.value
          : this.participants,
      description: data.description.present
          ? data.description.value
          : this.description,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EventFact(')
          ..write('id: $id, ')
          ..write('manuscriptId: $manuscriptId, ')
          ..write('name: $name, ')
          ..write('chapter: $chapter, ')
          ..write('eventType: $eventType, ')
          ..write('causeEventId: $causeEventId, ')
          ..write('effectEventId: $effectEventId, ')
          ..write('participants: $participants, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    manuscriptId,
    name,
    chapter,
    eventType,
    causeEventId,
    effectEventId,
    participants,
    description,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EventFact &&
          other.id == this.id &&
          other.manuscriptId == this.manuscriptId &&
          other.name == this.name &&
          other.chapter == this.chapter &&
          other.eventType == this.eventType &&
          other.causeEventId == this.causeEventId &&
          other.effectEventId == this.effectEventId &&
          other.participants == this.participants &&
          other.description == this.description &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class EventFactsCompanion extends UpdateCompanion<EventFact> {
  final Value<String> id;
  final Value<String> manuscriptId;
  final Value<String> name;
  final Value<int?> chapter;
  final Value<String> eventType;
  final Value<String?> causeEventId;
  final Value<String?> effectEventId;
  final Value<String> participants;
  final Value<String> description;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const EventFactsCompanion({
    this.id = const Value.absent(),
    this.manuscriptId = const Value.absent(),
    this.name = const Value.absent(),
    this.chapter = const Value.absent(),
    this.eventType = const Value.absent(),
    this.causeEventId = const Value.absent(),
    this.effectEventId = const Value.absent(),
    this.participants = const Value.absent(),
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EventFactsCompanion.insert({
    required String id,
    required String manuscriptId,
    required String name,
    this.chapter = const Value.absent(),
    required String eventType,
    this.causeEventId = const Value.absent(),
    this.effectEventId = const Value.absent(),
    this.participants = const Value.absent(),
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       manuscriptId = Value(manuscriptId),
       name = Value(name),
       eventType = Value(eventType);
  static Insertable<EventFact> custom({
    Expression<String>? id,
    Expression<String>? manuscriptId,
    Expression<String>? name,
    Expression<int>? chapter,
    Expression<String>? eventType,
    Expression<String>? causeEventId,
    Expression<String>? effectEventId,
    Expression<String>? participants,
    Expression<String>? description,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (manuscriptId != null) 'manuscript_id': manuscriptId,
      if (name != null) 'name': name,
      if (chapter != null) 'chapter': chapter,
      if (eventType != null) 'event_type': eventType,
      if (causeEventId != null) 'cause_event_id': causeEventId,
      if (effectEventId != null) 'effect_event_id': effectEventId,
      if (participants != null) 'participants': participants,
      if (description != null) 'description': description,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EventFactsCompanion copyWith({
    Value<String>? id,
    Value<String>? manuscriptId,
    Value<String>? name,
    Value<int?>? chapter,
    Value<String>? eventType,
    Value<String?>? causeEventId,
    Value<String?>? effectEventId,
    Value<String>? participants,
    Value<String>? description,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return EventFactsCompanion(
      id: id ?? this.id,
      manuscriptId: manuscriptId ?? this.manuscriptId,
      name: name ?? this.name,
      chapter: chapter ?? this.chapter,
      eventType: eventType ?? this.eventType,
      causeEventId: causeEventId ?? this.causeEventId,
      effectEventId: effectEventId ?? this.effectEventId,
      participants: participants ?? this.participants,
      description: description ?? this.description,
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
    if (manuscriptId.present) {
      map['manuscript_id'] = Variable<String>(manuscriptId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (chapter.present) {
      map['chapter'] = Variable<int>(chapter.value);
    }
    if (eventType.present) {
      map['event_type'] = Variable<String>(eventType.value);
    }
    if (causeEventId.present) {
      map['cause_event_id'] = Variable<String>(causeEventId.value);
    }
    if (effectEventId.present) {
      map['effect_event_id'] = Variable<String>(effectEventId.value);
    }
    if (participants.present) {
      map['participants'] = Variable<String>(participants.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
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
    return (StringBuffer('EventFactsCompanion(')
          ..write('id: $id, ')
          ..write('manuscriptId: $manuscriptId, ')
          ..write('name: $name, ')
          ..write('chapter: $chapter, ')
          ..write('eventType: $eventType, ')
          ..write('causeEventId: $causeEventId, ')
          ..write('effectEventId: $effectEventId, ')
          ..write('participants: $participants, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SubplotFactsTable extends SubplotFacts
    with TableInfo<$SubplotFactsTable, SubplotFact> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SubplotFactsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _manuscriptIdMeta = const VerificationMeta(
    'manuscriptId',
  );
  @override
  late final GeneratedColumn<String> manuscriptId = GeneratedColumn<String>(
    'manuscript_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES manuscripts (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _introducedChapterMeta = const VerificationMeta(
    'introducedChapter',
  );
  @override
  late final GeneratedColumn<int> introducedChapter = GeneratedColumn<int>(
    'introduced_chapter',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resolvedChapterMeta = const VerificationMeta(
    'resolvedChapter',
  );
  @override
  late final GeneratedColumn<int> resolvedChapter = GeneratedColumn<int>(
    'resolved_chapter',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resolvedAtMeta = const VerificationMeta(
    'resolvedAt',
  );
  @override
  late final GeneratedColumn<int> resolvedAt = GeneratedColumn<int>(
    'resolved_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    manuscriptId,
    name,
    introducedChapter,
    resolvedChapter,
    resolvedAt,
    description,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'subplot_fact';
  @override
  VerificationContext validateIntegrity(
    Insertable<SubplotFact> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('manuscript_id')) {
      context.handle(
        _manuscriptIdMeta,
        manuscriptId.isAcceptableOrUnknown(
          data['manuscript_id']!,
          _manuscriptIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_manuscriptIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('introduced_chapter')) {
      context.handle(
        _introducedChapterMeta,
        introducedChapter.isAcceptableOrUnknown(
          data['introduced_chapter']!,
          _introducedChapterMeta,
        ),
      );
    }
    if (data.containsKey('resolved_chapter')) {
      context.handle(
        _resolvedChapterMeta,
        resolvedChapter.isAcceptableOrUnknown(
          data['resolved_chapter']!,
          _resolvedChapterMeta,
        ),
      );
    }
    if (data.containsKey('resolved_at')) {
      context.handle(
        _resolvedAtMeta,
        resolvedAt.isAcceptableOrUnknown(data['resolved_at']!, _resolvedAtMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {manuscriptId, name},
  ];
  @override
  SubplotFact map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SubplotFact(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      manuscriptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manuscript_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      introducedChapter: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}introduced_chapter'],
      ),
      resolvedChapter: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}resolved_chapter'],
      ),
      resolvedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}resolved_at'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
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
  $SubplotFactsTable createAlias(String alias) {
    return $SubplotFactsTable(attachedDatabase, alias);
  }
}

class SubplotFact extends DataClass implements Insertable<SubplotFact> {
  final String id;
  final String manuscriptId;
  final String name;
  final int? introducedChapter;
  final int? resolvedChapter;
  final int? resolvedAt;
  final String description;
  final int createdAt;
  final int updatedAt;
  const SubplotFact({
    required this.id,
    required this.manuscriptId,
    required this.name,
    this.introducedChapter,
    this.resolvedChapter,
    this.resolvedAt,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['manuscript_id'] = Variable<String>(manuscriptId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || introducedChapter != null) {
      map['introduced_chapter'] = Variable<int>(introducedChapter);
    }
    if (!nullToAbsent || resolvedChapter != null) {
      map['resolved_chapter'] = Variable<int>(resolvedChapter);
    }
    if (!nullToAbsent || resolvedAt != null) {
      map['resolved_at'] = Variable<int>(resolvedAt);
    }
    map['description'] = Variable<String>(description);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  SubplotFactsCompanion toCompanion(bool nullToAbsent) {
    return SubplotFactsCompanion(
      id: Value(id),
      manuscriptId: Value(manuscriptId),
      name: Value(name),
      introducedChapter: introducedChapter == null && nullToAbsent
          ? const Value.absent()
          : Value(introducedChapter),
      resolvedChapter: resolvedChapter == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedChapter),
      resolvedAt: resolvedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedAt),
      description: Value(description),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SubplotFact.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SubplotFact(
      id: serializer.fromJson<String>(json['id']),
      manuscriptId: serializer.fromJson<String>(json['manuscriptId']),
      name: serializer.fromJson<String>(json['name']),
      introducedChapter: serializer.fromJson<int?>(json['introducedChapter']),
      resolvedChapter: serializer.fromJson<int?>(json['resolvedChapter']),
      resolvedAt: serializer.fromJson<int?>(json['resolvedAt']),
      description: serializer.fromJson<String>(json['description']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'manuscriptId': serializer.toJson<String>(manuscriptId),
      'name': serializer.toJson<String>(name),
      'introducedChapter': serializer.toJson<int?>(introducedChapter),
      'resolvedChapter': serializer.toJson<int?>(resolvedChapter),
      'resolvedAt': serializer.toJson<int?>(resolvedAt),
      'description': serializer.toJson<String>(description),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  SubplotFact copyWith({
    String? id,
    String? manuscriptId,
    String? name,
    Value<int?> introducedChapter = const Value.absent(),
    Value<int?> resolvedChapter = const Value.absent(),
    Value<int?> resolvedAt = const Value.absent(),
    String? description,
    int? createdAt,
    int? updatedAt,
  }) => SubplotFact(
    id: id ?? this.id,
    manuscriptId: manuscriptId ?? this.manuscriptId,
    name: name ?? this.name,
    introducedChapter: introducedChapter.present
        ? introducedChapter.value
        : this.introducedChapter,
    resolvedChapter: resolvedChapter.present
        ? resolvedChapter.value
        : this.resolvedChapter,
    resolvedAt: resolvedAt.present ? resolvedAt.value : this.resolvedAt,
    description: description ?? this.description,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SubplotFact copyWithCompanion(SubplotFactsCompanion data) {
    return SubplotFact(
      id: data.id.present ? data.id.value : this.id,
      manuscriptId: data.manuscriptId.present
          ? data.manuscriptId.value
          : this.manuscriptId,
      name: data.name.present ? data.name.value : this.name,
      introducedChapter: data.introducedChapter.present
          ? data.introducedChapter.value
          : this.introducedChapter,
      resolvedChapter: data.resolvedChapter.present
          ? data.resolvedChapter.value
          : this.resolvedChapter,
      resolvedAt: data.resolvedAt.present
          ? data.resolvedAt.value
          : this.resolvedAt,
      description: data.description.present
          ? data.description.value
          : this.description,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SubplotFact(')
          ..write('id: $id, ')
          ..write('manuscriptId: $manuscriptId, ')
          ..write('name: $name, ')
          ..write('introducedChapter: $introducedChapter, ')
          ..write('resolvedChapter: $resolvedChapter, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    manuscriptId,
    name,
    introducedChapter,
    resolvedChapter,
    resolvedAt,
    description,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SubplotFact &&
          other.id == this.id &&
          other.manuscriptId == this.manuscriptId &&
          other.name == this.name &&
          other.introducedChapter == this.introducedChapter &&
          other.resolvedChapter == this.resolvedChapter &&
          other.resolvedAt == this.resolvedAt &&
          other.description == this.description &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SubplotFactsCompanion extends UpdateCompanion<SubplotFact> {
  final Value<String> id;
  final Value<String> manuscriptId;
  final Value<String> name;
  final Value<int?> introducedChapter;
  final Value<int?> resolvedChapter;
  final Value<int?> resolvedAt;
  final Value<String> description;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const SubplotFactsCompanion({
    this.id = const Value.absent(),
    this.manuscriptId = const Value.absent(),
    this.name = const Value.absent(),
    this.introducedChapter = const Value.absent(),
    this.resolvedChapter = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SubplotFactsCompanion.insert({
    required String id,
    required String manuscriptId,
    required String name,
    this.introducedChapter = const Value.absent(),
    this.resolvedChapter = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       manuscriptId = Value(manuscriptId),
       name = Value(name);
  static Insertable<SubplotFact> custom({
    Expression<String>? id,
    Expression<String>? manuscriptId,
    Expression<String>? name,
    Expression<int>? introducedChapter,
    Expression<int>? resolvedChapter,
    Expression<int>? resolvedAt,
    Expression<String>? description,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (manuscriptId != null) 'manuscript_id': manuscriptId,
      if (name != null) 'name': name,
      if (introducedChapter != null) 'introduced_chapter': introducedChapter,
      if (resolvedChapter != null) 'resolved_chapter': resolvedChapter,
      if (resolvedAt != null) 'resolved_at': resolvedAt,
      if (description != null) 'description': description,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SubplotFactsCompanion copyWith({
    Value<String>? id,
    Value<String>? manuscriptId,
    Value<String>? name,
    Value<int?>? introducedChapter,
    Value<int?>? resolvedChapter,
    Value<int?>? resolvedAt,
    Value<String>? description,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return SubplotFactsCompanion(
      id: id ?? this.id,
      manuscriptId: manuscriptId ?? this.manuscriptId,
      name: name ?? this.name,
      introducedChapter: introducedChapter ?? this.introducedChapter,
      resolvedChapter: resolvedChapter ?? this.resolvedChapter,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      description: description ?? this.description,
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
    if (manuscriptId.present) {
      map['manuscript_id'] = Variable<String>(manuscriptId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (introducedChapter.present) {
      map['introduced_chapter'] = Variable<int>(introducedChapter.value);
    }
    if (resolvedChapter.present) {
      map['resolved_chapter'] = Variable<int>(resolvedChapter.value);
    }
    if (resolvedAt.present) {
      map['resolved_at'] = Variable<int>(resolvedAt.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
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
    return (StringBuffer('SubplotFactsCompanion(')
          ..write('id: $id, ')
          ..write('manuscriptId: $manuscriptId, ')
          ..write('name: $name, ')
          ..write('introducedChapter: $introducedChapter, ')
          ..write('resolvedChapter: $resolvedChapter, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutlineEntitiesTable extends OutlineEntities
    with TableInfo<$OutlineEntitiesTable, OutlineEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutlineEntitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _manuscriptIdMeta = const VerificationMeta(
    'manuscriptId',
  );
  @override
  late final GeneratedColumn<String> manuscriptId = GeneratedColumn<String>(
    'manuscript_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES manuscripts (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityKeyMeta = const VerificationMeta(
    'entityKey',
  );
  @override
  late final GeneratedColumn<String> entityKey = GeneratedColumn<String>(
    'entity_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aliasesMeta = const VerificationMeta(
    'aliases',
  );
  @override
  late final GeneratedColumn<String> aliases = GeneratedColumn<String>(
    'aliases',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    manuscriptId,
    entityType,
    entityKey,
    aliases,
    status,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outline_entity';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutlineEntity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('manuscript_id')) {
      context.handle(
        _manuscriptIdMeta,
        manuscriptId.isAcceptableOrUnknown(
          data['manuscript_id']!,
          _manuscriptIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_manuscriptIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_key')) {
      context.handle(
        _entityKeyMeta,
        entityKey.isAcceptableOrUnknown(data['entity_key']!, _entityKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_entityKeyMeta);
    }
    if (data.containsKey('aliases')) {
      context.handle(
        _aliasesMeta,
        aliases.isAcceptableOrUnknown(data['aliases']!, _aliasesMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {manuscriptId, entityKey},
  ];
  @override
  OutlineEntity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutlineEntity(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      manuscriptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manuscript_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_key'],
      )!,
      aliases: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aliases'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
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
  $OutlineEntitiesTable createAlias(String alias) {
    return $OutlineEntitiesTable(attachedDatabase, alias);
  }
}

class OutlineEntity extends DataClass implements Insertable<OutlineEntity> {
  final String id;
  final String manuscriptId;
  final String entityType;
  final String entityKey;
  final String aliases;
  final String status;
  final int createdAt;
  final int updatedAt;
  const OutlineEntity({
    required this.id,
    required this.manuscriptId,
    required this.entityType,
    required this.entityKey,
    required this.aliases,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['manuscript_id'] = Variable<String>(manuscriptId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_key'] = Variable<String>(entityKey);
    map['aliases'] = Variable<String>(aliases);
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  OutlineEntitiesCompanion toCompanion(bool nullToAbsent) {
    return OutlineEntitiesCompanion(
      id: Value(id),
      manuscriptId: Value(manuscriptId),
      entityType: Value(entityType),
      entityKey: Value(entityKey),
      aliases: Value(aliases),
      status: Value(status),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory OutlineEntity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutlineEntity(
      id: serializer.fromJson<String>(json['id']),
      manuscriptId: serializer.fromJson<String>(json['manuscriptId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityKey: serializer.fromJson<String>(json['entityKey']),
      aliases: serializer.fromJson<String>(json['aliases']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'manuscriptId': serializer.toJson<String>(manuscriptId),
      'entityType': serializer.toJson<String>(entityType),
      'entityKey': serializer.toJson<String>(entityKey),
      'aliases': serializer.toJson<String>(aliases),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  OutlineEntity copyWith({
    String? id,
    String? manuscriptId,
    String? entityType,
    String? entityKey,
    String? aliases,
    String? status,
    int? createdAt,
    int? updatedAt,
  }) => OutlineEntity(
    id: id ?? this.id,
    manuscriptId: manuscriptId ?? this.manuscriptId,
    entityType: entityType ?? this.entityType,
    entityKey: entityKey ?? this.entityKey,
    aliases: aliases ?? this.aliases,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  OutlineEntity copyWithCompanion(OutlineEntitiesCompanion data) {
    return OutlineEntity(
      id: data.id.present ? data.id.value : this.id,
      manuscriptId: data.manuscriptId.present
          ? data.manuscriptId.value
          : this.manuscriptId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityKey: data.entityKey.present ? data.entityKey.value : this.entityKey,
      aliases: data.aliases.present ? data.aliases.value : this.aliases,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutlineEntity(')
          ..write('id: $id, ')
          ..write('manuscriptId: $manuscriptId, ')
          ..write('entityType: $entityType, ')
          ..write('entityKey: $entityKey, ')
          ..write('aliases: $aliases, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    manuscriptId,
    entityType,
    entityKey,
    aliases,
    status,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutlineEntity &&
          other.id == this.id &&
          other.manuscriptId == this.manuscriptId &&
          other.entityType == this.entityType &&
          other.entityKey == this.entityKey &&
          other.aliases == this.aliases &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class OutlineEntitiesCompanion extends UpdateCompanion<OutlineEntity> {
  final Value<String> id;
  final Value<String> manuscriptId;
  final Value<String> entityType;
  final Value<String> entityKey;
  final Value<String> aliases;
  final Value<String> status;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const OutlineEntitiesCompanion({
    this.id = const Value.absent(),
    this.manuscriptId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityKey = const Value.absent(),
    this.aliases = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutlineEntitiesCompanion.insert({
    required String id,
    required String manuscriptId,
    required String entityType,
    required String entityKey,
    this.aliases = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       manuscriptId = Value(manuscriptId),
       entityType = Value(entityType),
       entityKey = Value(entityKey);
  static Insertable<OutlineEntity> custom({
    Expression<String>? id,
    Expression<String>? manuscriptId,
    Expression<String>? entityType,
    Expression<String>? entityKey,
    Expression<String>? aliases,
    Expression<String>? status,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (manuscriptId != null) 'manuscript_id': manuscriptId,
      if (entityType != null) 'entity_type': entityType,
      if (entityKey != null) 'entity_key': entityKey,
      if (aliases != null) 'aliases': aliases,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutlineEntitiesCompanion copyWith({
    Value<String>? id,
    Value<String>? manuscriptId,
    Value<String>? entityType,
    Value<String>? entityKey,
    Value<String>? aliases,
    Value<String>? status,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return OutlineEntitiesCompanion(
      id: id ?? this.id,
      manuscriptId: manuscriptId ?? this.manuscriptId,
      entityType: entityType ?? this.entityType,
      entityKey: entityKey ?? this.entityKey,
      aliases: aliases ?? this.aliases,
      status: status ?? this.status,
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
    if (manuscriptId.present) {
      map['manuscript_id'] = Variable<String>(manuscriptId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityKey.present) {
      map['entity_key'] = Variable<String>(entityKey.value);
    }
    if (aliases.present) {
      map['aliases'] = Variable<String>(aliases.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
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
    return (StringBuffer('OutlineEntitiesCompanion(')
          ..write('id: $id, ')
          ..write('manuscriptId: $manuscriptId, ')
          ..write('entityType: $entityType, ')
          ..write('entityKey: $entityKey, ')
          ..write('aliases: $aliases, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutlineImpressionsTable extends OutlineImpressions
    with TableInfo<$OutlineImpressionsTable, OutlineImpression> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutlineImpressionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES outline_entity (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _impressionMeta = const VerificationMeta(
    'impression',
  );
  @override
  late final GeneratedColumn<String> impression = GeneratedColumn<String>(
    'impression',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceChapterIdMeta = const VerificationMeta(
    'sourceChapterId',
  );
  @override
  late final GeneratedColumn<String> sourceChapterId = GeneratedColumn<String>(
    'source_chapter_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceChapterNoMeta = const VerificationMeta(
    'sourceChapterNo',
  );
  @override
  late final GeneratedColumn<int> sourceChapterNo = GeneratedColumn<int>(
    'source_chapter_no',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _conflictWithMeta = const VerificationMeta(
    'conflictWith',
  );
  @override
  late final GeneratedColumn<String> conflictWith = GeneratedColumn<String>(
    'conflict_with',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression<int>('unixepoch()'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entityId,
    impression,
    sourceChapterId,
    sourceChapterNo,
    version,
    conflictWith,
    status,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outline_impression';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutlineImpression> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('impression')) {
      context.handle(
        _impressionMeta,
        impression.isAcceptableOrUnknown(data['impression']!, _impressionMeta),
      );
    } else if (isInserting) {
      context.missing(_impressionMeta);
    }
    if (data.containsKey('source_chapter_id')) {
      context.handle(
        _sourceChapterIdMeta,
        sourceChapterId.isAcceptableOrUnknown(
          data['source_chapter_id']!,
          _sourceChapterIdMeta,
        ),
      );
    }
    if (data.containsKey('source_chapter_no')) {
      context.handle(
        _sourceChapterNoMeta,
        sourceChapterNo.isAcceptableOrUnknown(
          data['source_chapter_no']!,
          _sourceChapterNoMeta,
        ),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('conflict_with')) {
      context.handle(
        _conflictWithMeta,
        conflictWith.isAcceptableOrUnknown(
          data['conflict_with']!,
          _conflictWithMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {entityId, impression},
  ];
  @override
  OutlineImpression map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutlineImpression(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      impression: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}impression'],
      )!,
      sourceChapterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_chapter_id'],
      ),
      sourceChapterNo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_chapter_no'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      conflictWith: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conflict_with'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $OutlineImpressionsTable createAlias(String alias) {
    return $OutlineImpressionsTable(attachedDatabase, alias);
  }
}

class OutlineImpression extends DataClass
    implements Insertable<OutlineImpression> {
  final String id;
  final String entityId;
  final String impression;
  final String? sourceChapterId;
  final int? sourceChapterNo;
  final int version;
  final String? conflictWith;
  final String status;
  final int createdAt;
  const OutlineImpression({
    required this.id,
    required this.entityId,
    required this.impression,
    this.sourceChapterId,
    this.sourceChapterNo,
    required this.version,
    this.conflictWith,
    required this.status,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entity_id'] = Variable<String>(entityId);
    map['impression'] = Variable<String>(impression);
    if (!nullToAbsent || sourceChapterId != null) {
      map['source_chapter_id'] = Variable<String>(sourceChapterId);
    }
    if (!nullToAbsent || sourceChapterNo != null) {
      map['source_chapter_no'] = Variable<int>(sourceChapterNo);
    }
    map['version'] = Variable<int>(version);
    if (!nullToAbsent || conflictWith != null) {
      map['conflict_with'] = Variable<String>(conflictWith);
    }
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  OutlineImpressionsCompanion toCompanion(bool nullToAbsent) {
    return OutlineImpressionsCompanion(
      id: Value(id),
      entityId: Value(entityId),
      impression: Value(impression),
      sourceChapterId: sourceChapterId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceChapterId),
      sourceChapterNo: sourceChapterNo == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceChapterNo),
      version: Value(version),
      conflictWith: conflictWith == null && nullToAbsent
          ? const Value.absent()
          : Value(conflictWith),
      status: Value(status),
      createdAt: Value(createdAt),
    );
  }

  factory OutlineImpression.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutlineImpression(
      id: serializer.fromJson<String>(json['id']),
      entityId: serializer.fromJson<String>(json['entityId']),
      impression: serializer.fromJson<String>(json['impression']),
      sourceChapterId: serializer.fromJson<String?>(json['sourceChapterId']),
      sourceChapterNo: serializer.fromJson<int?>(json['sourceChapterNo']),
      version: serializer.fromJson<int>(json['version']),
      conflictWith: serializer.fromJson<String?>(json['conflictWith']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entityId': serializer.toJson<String>(entityId),
      'impression': serializer.toJson<String>(impression),
      'sourceChapterId': serializer.toJson<String?>(sourceChapterId),
      'sourceChapterNo': serializer.toJson<int?>(sourceChapterNo),
      'version': serializer.toJson<int>(version),
      'conflictWith': serializer.toJson<String?>(conflictWith),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  OutlineImpression copyWith({
    String? id,
    String? entityId,
    String? impression,
    Value<String?> sourceChapterId = const Value.absent(),
    Value<int?> sourceChapterNo = const Value.absent(),
    int? version,
    Value<String?> conflictWith = const Value.absent(),
    String? status,
    int? createdAt,
  }) => OutlineImpression(
    id: id ?? this.id,
    entityId: entityId ?? this.entityId,
    impression: impression ?? this.impression,
    sourceChapterId: sourceChapterId.present
        ? sourceChapterId.value
        : this.sourceChapterId,
    sourceChapterNo: sourceChapterNo.present
        ? sourceChapterNo.value
        : this.sourceChapterNo,
    version: version ?? this.version,
    conflictWith: conflictWith.present ? conflictWith.value : this.conflictWith,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
  );
  OutlineImpression copyWithCompanion(OutlineImpressionsCompanion data) {
    return OutlineImpression(
      id: data.id.present ? data.id.value : this.id,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      impression: data.impression.present
          ? data.impression.value
          : this.impression,
      sourceChapterId: data.sourceChapterId.present
          ? data.sourceChapterId.value
          : this.sourceChapterId,
      sourceChapterNo: data.sourceChapterNo.present
          ? data.sourceChapterNo.value
          : this.sourceChapterNo,
      version: data.version.present ? data.version.value : this.version,
      conflictWith: data.conflictWith.present
          ? data.conflictWith.value
          : this.conflictWith,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutlineImpression(')
          ..write('id: $id, ')
          ..write('entityId: $entityId, ')
          ..write('impression: $impression, ')
          ..write('sourceChapterId: $sourceChapterId, ')
          ..write('sourceChapterNo: $sourceChapterNo, ')
          ..write('version: $version, ')
          ..write('conflictWith: $conflictWith, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entityId,
    impression,
    sourceChapterId,
    sourceChapterNo,
    version,
    conflictWith,
    status,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutlineImpression &&
          other.id == this.id &&
          other.entityId == this.entityId &&
          other.impression == this.impression &&
          other.sourceChapterId == this.sourceChapterId &&
          other.sourceChapterNo == this.sourceChapterNo &&
          other.version == this.version &&
          other.conflictWith == this.conflictWith &&
          other.status == this.status &&
          other.createdAt == this.createdAt);
}

class OutlineImpressionsCompanion extends UpdateCompanion<OutlineImpression> {
  final Value<String> id;
  final Value<String> entityId;
  final Value<String> impression;
  final Value<String?> sourceChapterId;
  final Value<int?> sourceChapterNo;
  final Value<int> version;
  final Value<String?> conflictWith;
  final Value<String> status;
  final Value<int> createdAt;
  final Value<int> rowid;
  const OutlineImpressionsCompanion({
    this.id = const Value.absent(),
    this.entityId = const Value.absent(),
    this.impression = const Value.absent(),
    this.sourceChapterId = const Value.absent(),
    this.sourceChapterNo = const Value.absent(),
    this.version = const Value.absent(),
    this.conflictWith = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutlineImpressionsCompanion.insert({
    required String id,
    required String entityId,
    required String impression,
    this.sourceChapterId = const Value.absent(),
    this.sourceChapterNo = const Value.absent(),
    this.version = const Value.absent(),
    this.conflictWith = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       entityId = Value(entityId),
       impression = Value(impression);
  static Insertable<OutlineImpression> custom({
    Expression<String>? id,
    Expression<String>? entityId,
    Expression<String>? impression,
    Expression<String>? sourceChapterId,
    Expression<int>? sourceChapterNo,
    Expression<int>? version,
    Expression<String>? conflictWith,
    Expression<String>? status,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityId != null) 'entity_id': entityId,
      if (impression != null) 'impression': impression,
      if (sourceChapterId != null) 'source_chapter_id': sourceChapterId,
      if (sourceChapterNo != null) 'source_chapter_no': sourceChapterNo,
      if (version != null) 'version': version,
      if (conflictWith != null) 'conflict_with': conflictWith,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutlineImpressionsCompanion copyWith({
    Value<String>? id,
    Value<String>? entityId,
    Value<String>? impression,
    Value<String?>? sourceChapterId,
    Value<int?>? sourceChapterNo,
    Value<int>? version,
    Value<String?>? conflictWith,
    Value<String>? status,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return OutlineImpressionsCompanion(
      id: id ?? this.id,
      entityId: entityId ?? this.entityId,
      impression: impression ?? this.impression,
      sourceChapterId: sourceChapterId ?? this.sourceChapterId,
      sourceChapterNo: sourceChapterNo ?? this.sourceChapterNo,
      version: version ?? this.version,
      conflictWith: conflictWith ?? this.conflictWith,
      status: status ?? this.status,
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
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (impression.present) {
      map['impression'] = Variable<String>(impression.value);
    }
    if (sourceChapterId.present) {
      map['source_chapter_id'] = Variable<String>(sourceChapterId.value);
    }
    if (sourceChapterNo.present) {
      map['source_chapter_no'] = Variable<int>(sourceChapterNo.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (conflictWith.present) {
      map['conflict_with'] = Variable<String>(conflictWith.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
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
    return (StringBuffer('OutlineImpressionsCompanion(')
          ..write('id: $id, ')
          ..write('entityId: $entityId, ')
          ..write('impression: $impression, ')
          ..write('sourceChapterId: $sourceChapterId, ')
          ..write('sourceChapterNo: $sourceChapterNo, ')
          ..write('version: $version, ')
          ..write('conflictWith: $conflictWith, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ManuscriptsTable manuscripts = $ManuscriptsTable(this);
  late final $VolumesTable volumes = $VolumesTable(this);
  late final $ChaptersTable chapters = $ChaptersTable(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $DiagnosisResultsTable diagnosisResults = $DiagnosisResultsTable(
    this,
  );
  late final $TeachingStateTable teachingState = $TeachingStateTable(this);
  late final $ActiveProblemsTable activeProblems = $ActiveProblemsTable(this);
  late final $StudentModelsTable studentModels = $StudentModelsTable(this);
  late final $SessionReferencesTable sessionReferences =
      $SessionReferencesTable(this);
  late final $AppStatesTable appStates = $AppStatesTable(this);
  late final $ErrorLogsTable errorLogs = $ErrorLogsTable(this);
  late final $AttachedFilesTable attachedFiles = $AttachedFilesTable(this);
  late final $TeacherSuggestionsTable teacherSuggestions =
      $TeacherSuggestionsTable(this);
  late final $EditorObservationsTable editorObservations =
      $EditorObservationsTable(this);
  late final $CharacterFactsTable characterFacts = $CharacterFactsTable(this);
  late final $EventFactsTable eventFacts = $EventFactsTable(this);
  late final $SubplotFactsTable subplotFacts = $SubplotFactsTable(this);
  late final $OutlineEntitiesTable outlineEntities = $OutlineEntitiesTable(
    this,
  );
  late final $OutlineImpressionsTable outlineImpressions =
      $OutlineImpressionsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    manuscripts,
    volumes,
    chapters,
    sessions,
    messages,
    diagnosisResults,
    teachingState,
    activeProblems,
    studentModels,
    sessionReferences,
    appStates,
    errorLogs,
    attachedFiles,
    teacherSuggestions,
    editorObservations,
    characterFacts,
    eventFacts,
    subplotFacts,
    outlineEntities,
    outlineImpressions,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'manuscripts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('volumes', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'manuscripts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('chapters', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'volumes',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('chapters', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'manuscripts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('sessions', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'chapters',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('sessions', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('messages', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('diagnosis_results', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('teaching_state', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('active_problem', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('student_model', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('session_reference', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'manuscripts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('attached_files', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('teacher_suggestion', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('teacher_suggestion', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('editor_observation', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('editor_observation', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'manuscripts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('character_fact', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'manuscripts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('event_fact', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'manuscripts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('subplot_fact', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'manuscripts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('outline_entity', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'outline_entity',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('outline_impression', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$ManuscriptsTableCreateCompanionBuilder =
    ManuscriptsCompanion Function({
      required String id,
      Value<String> title,
      Value<String> description,
      Value<String> genre,
      Value<String> language,
      Value<String> status,
      Value<String> tags,
      Value<int> sortOrder,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });
typedef $$ManuscriptsTableUpdateCompanionBuilder =
    ManuscriptsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> description,
      Value<String> genre,
      Value<String> language,
      Value<String> status,
      Value<String> tags,
      Value<int> sortOrder,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $$ManuscriptsTableReferences
    extends BaseReferences<_$AppDatabase, $ManuscriptsTable, Manuscript> {
  $$ManuscriptsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$VolumesTable, List<Volume>> _volumesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.volumes,
    aliasName: $_aliasNameGenerator(db.manuscripts.id, db.volumes.manuscriptId),
  );

  $$VolumesTableProcessedTableManager get volumesRefs {
    final manager = $$VolumesTableTableManager(
      $_db,
      $_db.volumes,
    ).filter((f) => f.manuscriptId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_volumesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ChaptersTable, List<Chapter>> _chaptersRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.chapters,
    aliasName: $_aliasNameGenerator(
      db.manuscripts.id,
      db.chapters.manuscriptId,
    ),
  );

  $$ChaptersTableProcessedTableManager get chaptersRefs {
    final manager = $$ChaptersTableTableManager(
      $_db,
      $_db.chapters,
    ).filter((f) => f.manuscriptId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_chaptersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SessionsTable, List<SessionRow>>
  _sessionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.sessions,
    aliasName: $_aliasNameGenerator(
      db.manuscripts.id,
      db.sessions.manuscriptId,
    ),
  );

  $$SessionsTableProcessedTableManager get sessionsRefs {
    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.manuscriptId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_sessionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$AttachedFilesTable, List<AttachedFile>>
  _attachedFilesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.attachedFiles,
    aliasName: $_aliasNameGenerator(db.manuscripts.id, db.attachedFiles.bookId),
  );

  $$AttachedFilesTableProcessedTableManager get attachedFilesRefs {
    final manager = $$AttachedFilesTableTableManager(
      $_db,
      $_db.attachedFiles,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_attachedFilesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CharacterFactsTable, List<CharacterFact>>
  _characterFactsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.characterFacts,
    aliasName: $_aliasNameGenerator(
      db.manuscripts.id,
      db.characterFacts.manuscriptId,
    ),
  );

  $$CharacterFactsTableProcessedTableManager get characterFactsRefs {
    final manager = $$CharacterFactsTableTableManager(
      $_db,
      $_db.characterFacts,
    ).filter((f) => f.manuscriptId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_characterFactsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$EventFactsTable, List<EventFact>>
  _eventFactsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.eventFacts,
    aliasName: $_aliasNameGenerator(
      db.manuscripts.id,
      db.eventFacts.manuscriptId,
    ),
  );

  $$EventFactsTableProcessedTableManager get eventFactsRefs {
    final manager = $$EventFactsTableTableManager(
      $_db,
      $_db.eventFacts,
    ).filter((f) => f.manuscriptId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_eventFactsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SubplotFactsTable, List<SubplotFact>>
  _subplotFactsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.subplotFacts,
    aliasName: $_aliasNameGenerator(
      db.manuscripts.id,
      db.subplotFacts.manuscriptId,
    ),
  );

  $$SubplotFactsTableProcessedTableManager get subplotFactsRefs {
    final manager = $$SubplotFactsTableTableManager(
      $_db,
      $_db.subplotFacts,
    ).filter((f) => f.manuscriptId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_subplotFactsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$OutlineEntitiesTable, List<OutlineEntity>>
  _outlineEntitiesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.outlineEntities,
    aliasName: $_aliasNameGenerator(
      db.manuscripts.id,
      db.outlineEntities.manuscriptId,
    ),
  );

  $$OutlineEntitiesTableProcessedTableManager get outlineEntitiesRefs {
    final manager = $$OutlineEntitiesTableTableManager(
      $_db,
      $_db.outlineEntities,
    ).filter((f) => f.manuscriptId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _outlineEntitiesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ManuscriptsTableFilterComposer
    extends Composer<_$AppDatabase, $ManuscriptsTable> {
  $$ManuscriptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> volumesRefs(
    Expression<bool> Function($$VolumesTableFilterComposer f) f,
  ) {
    final $$VolumesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.volumes,
      getReferencedColumn: (t) => t.manuscriptId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VolumesTableFilterComposer(
            $db: $db,
            $table: $db.volumes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> chaptersRefs(
    Expression<bool> Function($$ChaptersTableFilterComposer f) f,
  ) {
    final $$ChaptersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chapters,
      getReferencedColumn: (t) => t.manuscriptId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChaptersTableFilterComposer(
            $db: $db,
            $table: $db.chapters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> sessionsRefs(
    Expression<bool> Function($$SessionsTableFilterComposer f) f,
  ) {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.manuscriptId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> attachedFilesRefs(
    Expression<bool> Function($$AttachedFilesTableFilterComposer f) f,
  ) {
    final $$AttachedFilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.attachedFiles,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AttachedFilesTableFilterComposer(
            $db: $db,
            $table: $db.attachedFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> characterFactsRefs(
    Expression<bool> Function($$CharacterFactsTableFilterComposer f) f,
  ) {
    final $$CharacterFactsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.characterFacts,
      getReferencedColumn: (t) => t.manuscriptId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharacterFactsTableFilterComposer(
            $db: $db,
            $table: $db.characterFacts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> eventFactsRefs(
    Expression<bool> Function($$EventFactsTableFilterComposer f) f,
  ) {
    final $$EventFactsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.eventFacts,
      getReferencedColumn: (t) => t.manuscriptId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventFactsTableFilterComposer(
            $db: $db,
            $table: $db.eventFacts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> subplotFactsRefs(
    Expression<bool> Function($$SubplotFactsTableFilterComposer f) f,
  ) {
    final $$SubplotFactsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.subplotFacts,
      getReferencedColumn: (t) => t.manuscriptId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubplotFactsTableFilterComposer(
            $db: $db,
            $table: $db.subplotFacts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> outlineEntitiesRefs(
    Expression<bool> Function($$OutlineEntitiesTableFilterComposer f) f,
  ) {
    final $$OutlineEntitiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.outlineEntities,
      getReferencedColumn: (t) => t.manuscriptId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutlineEntitiesTableFilterComposer(
            $db: $db,
            $table: $db.outlineEntities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ManuscriptsTableOrderingComposer
    extends Composer<_$AppDatabase, $ManuscriptsTable> {
  $$ManuscriptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ManuscriptsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ManuscriptsTable> {
  $$ManuscriptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get genre =>
      $composableBuilder(column: $table.genre, builder: (column) => column);

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> volumesRefs<T extends Object>(
    Expression<T> Function($$VolumesTableAnnotationComposer a) f,
  ) {
    final $$VolumesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.volumes,
      getReferencedColumn: (t) => t.manuscriptId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VolumesTableAnnotationComposer(
            $db: $db,
            $table: $db.volumes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> chaptersRefs<T extends Object>(
    Expression<T> Function($$ChaptersTableAnnotationComposer a) f,
  ) {
    final $$ChaptersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chapters,
      getReferencedColumn: (t) => t.manuscriptId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChaptersTableAnnotationComposer(
            $db: $db,
            $table: $db.chapters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> sessionsRefs<T extends Object>(
    Expression<T> Function($$SessionsTableAnnotationComposer a) f,
  ) {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.manuscriptId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> attachedFilesRefs<T extends Object>(
    Expression<T> Function($$AttachedFilesTableAnnotationComposer a) f,
  ) {
    final $$AttachedFilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.attachedFiles,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AttachedFilesTableAnnotationComposer(
            $db: $db,
            $table: $db.attachedFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> characterFactsRefs<T extends Object>(
    Expression<T> Function($$CharacterFactsTableAnnotationComposer a) f,
  ) {
    final $$CharacterFactsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.characterFacts,
      getReferencedColumn: (t) => t.manuscriptId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharacterFactsTableAnnotationComposer(
            $db: $db,
            $table: $db.characterFacts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> eventFactsRefs<T extends Object>(
    Expression<T> Function($$EventFactsTableAnnotationComposer a) f,
  ) {
    final $$EventFactsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.eventFacts,
      getReferencedColumn: (t) => t.manuscriptId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventFactsTableAnnotationComposer(
            $db: $db,
            $table: $db.eventFacts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> subplotFactsRefs<T extends Object>(
    Expression<T> Function($$SubplotFactsTableAnnotationComposer a) f,
  ) {
    final $$SubplotFactsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.subplotFacts,
      getReferencedColumn: (t) => t.manuscriptId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SubplotFactsTableAnnotationComposer(
            $db: $db,
            $table: $db.subplotFacts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> outlineEntitiesRefs<T extends Object>(
    Expression<T> Function($$OutlineEntitiesTableAnnotationComposer a) f,
  ) {
    final $$OutlineEntitiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.outlineEntities,
      getReferencedColumn: (t) => t.manuscriptId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutlineEntitiesTableAnnotationComposer(
            $db: $db,
            $table: $db.outlineEntities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ManuscriptsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ManuscriptsTable,
          Manuscript,
          $$ManuscriptsTableFilterComposer,
          $$ManuscriptsTableOrderingComposer,
          $$ManuscriptsTableAnnotationComposer,
          $$ManuscriptsTableCreateCompanionBuilder,
          $$ManuscriptsTableUpdateCompanionBuilder,
          (Manuscript, $$ManuscriptsTableReferences),
          Manuscript,
          PrefetchHooks Function({
            bool volumesRefs,
            bool chaptersRefs,
            bool sessionsRefs,
            bool attachedFilesRefs,
            bool characterFactsRefs,
            bool eventFactsRefs,
            bool subplotFactsRefs,
            bool outlineEntitiesRefs,
          })
        > {
  $$ManuscriptsTableTableManager(_$AppDatabase db, $ManuscriptsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ManuscriptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ManuscriptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ManuscriptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> genre = const Value.absent(),
                Value<String> language = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> tags = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ManuscriptsCompanion(
                id: id,
                title: title,
                description: description,
                genre: genre,
                language: language,
                status: status,
                tags: tags,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> title = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> genre = const Value.absent(),
                Value<String> language = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> tags = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ManuscriptsCompanion.insert(
                id: id,
                title: title,
                description: description,
                genre: genre,
                language: language,
                status: status,
                tags: tags,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ManuscriptsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                volumesRefs = false,
                chaptersRefs = false,
                sessionsRefs = false,
                attachedFilesRefs = false,
                characterFactsRefs = false,
                eventFactsRefs = false,
                subplotFactsRefs = false,
                outlineEntitiesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (volumesRefs) db.volumes,
                    if (chaptersRefs) db.chapters,
                    if (sessionsRefs) db.sessions,
                    if (attachedFilesRefs) db.attachedFiles,
                    if (characterFactsRefs) db.characterFacts,
                    if (eventFactsRefs) db.eventFacts,
                    if (subplotFactsRefs) db.subplotFacts,
                    if (outlineEntitiesRefs) db.outlineEntities,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (volumesRefs)
                        await $_getPrefetchedData<
                          Manuscript,
                          $ManuscriptsTable,
                          Volume
                        >(
                          currentTable: table,
                          referencedTable: $$ManuscriptsTableReferences
                              ._volumesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ManuscriptsTableReferences(
                                db,
                                table,
                                p0,
                              ).volumesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.manuscriptId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (chaptersRefs)
                        await $_getPrefetchedData<
                          Manuscript,
                          $ManuscriptsTable,
                          Chapter
                        >(
                          currentTable: table,
                          referencedTable: $$ManuscriptsTableReferences
                              ._chaptersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ManuscriptsTableReferences(
                                db,
                                table,
                                p0,
                              ).chaptersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.manuscriptId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (sessionsRefs)
                        await $_getPrefetchedData<
                          Manuscript,
                          $ManuscriptsTable,
                          SessionRow
                        >(
                          currentTable: table,
                          referencedTable: $$ManuscriptsTableReferences
                              ._sessionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ManuscriptsTableReferences(
                                db,
                                table,
                                p0,
                              ).sessionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.manuscriptId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (attachedFilesRefs)
                        await $_getPrefetchedData<
                          Manuscript,
                          $ManuscriptsTable,
                          AttachedFile
                        >(
                          currentTable: table,
                          referencedTable: $$ManuscriptsTableReferences
                              ._attachedFilesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ManuscriptsTableReferences(
                                db,
                                table,
                                p0,
                              ).attachedFilesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (characterFactsRefs)
                        await $_getPrefetchedData<
                          Manuscript,
                          $ManuscriptsTable,
                          CharacterFact
                        >(
                          currentTable: table,
                          referencedTable: $$ManuscriptsTableReferences
                              ._characterFactsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ManuscriptsTableReferences(
                                db,
                                table,
                                p0,
                              ).characterFactsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.manuscriptId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (eventFactsRefs)
                        await $_getPrefetchedData<
                          Manuscript,
                          $ManuscriptsTable,
                          EventFact
                        >(
                          currentTable: table,
                          referencedTable: $$ManuscriptsTableReferences
                              ._eventFactsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ManuscriptsTableReferences(
                                db,
                                table,
                                p0,
                              ).eventFactsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.manuscriptId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (subplotFactsRefs)
                        await $_getPrefetchedData<
                          Manuscript,
                          $ManuscriptsTable,
                          SubplotFact
                        >(
                          currentTable: table,
                          referencedTable: $$ManuscriptsTableReferences
                              ._subplotFactsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ManuscriptsTableReferences(
                                db,
                                table,
                                p0,
                              ).subplotFactsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.manuscriptId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (outlineEntitiesRefs)
                        await $_getPrefetchedData<
                          Manuscript,
                          $ManuscriptsTable,
                          OutlineEntity
                        >(
                          currentTable: table,
                          referencedTable: $$ManuscriptsTableReferences
                              ._outlineEntitiesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ManuscriptsTableReferences(
                                db,
                                table,
                                p0,
                              ).outlineEntitiesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.manuscriptId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ManuscriptsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ManuscriptsTable,
      Manuscript,
      $$ManuscriptsTableFilterComposer,
      $$ManuscriptsTableOrderingComposer,
      $$ManuscriptsTableAnnotationComposer,
      $$ManuscriptsTableCreateCompanionBuilder,
      $$ManuscriptsTableUpdateCompanionBuilder,
      (Manuscript, $$ManuscriptsTableReferences),
      Manuscript,
      PrefetchHooks Function({
        bool volumesRefs,
        bool chaptersRefs,
        bool sessionsRefs,
        bool attachedFilesRefs,
        bool characterFactsRefs,
        bool eventFactsRefs,
        bool subplotFactsRefs,
        bool outlineEntitiesRefs,
      })
    >;
typedef $$VolumesTableCreateCompanionBuilder =
    VolumesCompanion Function({
      required String id,
      required String manuscriptId,
      Value<String> title,
      Value<int> sortOrder,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });
typedef $$VolumesTableUpdateCompanionBuilder =
    VolumesCompanion Function({
      Value<String> id,
      Value<String> manuscriptId,
      Value<String> title,
      Value<int> sortOrder,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $$VolumesTableReferences
    extends BaseReferences<_$AppDatabase, $VolumesTable, Volume> {
  $$VolumesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ManuscriptsTable _manuscriptIdTable(_$AppDatabase db) =>
      db.manuscripts.createAlias(
        $_aliasNameGenerator(db.volumes.manuscriptId, db.manuscripts.id),
      );

  $$ManuscriptsTableProcessedTableManager get manuscriptId {
    final $_column = $_itemColumn<String>('manuscript_id')!;

    final manager = $$ManuscriptsTableTableManager(
      $_db,
      $_db.manuscripts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_manuscriptIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ChaptersTable, List<Chapter>> _chaptersRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.chapters,
    aliasName: $_aliasNameGenerator(db.volumes.id, db.chapters.volumeId),
  );

  $$ChaptersTableProcessedTableManager get chaptersRefs {
    final manager = $$ChaptersTableTableManager(
      $_db,
      $_db.chapters,
    ).filter((f) => f.volumeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_chaptersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$VolumesTableFilterComposer
    extends Composer<_$AppDatabase, $VolumesTable> {
  $$VolumesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ManuscriptsTableFilterComposer get manuscriptId {
    final $$ManuscriptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableFilterComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> chaptersRefs(
    Expression<bool> Function($$ChaptersTableFilterComposer f) f,
  ) {
    final $$ChaptersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chapters,
      getReferencedColumn: (t) => t.volumeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChaptersTableFilterComposer(
            $db: $db,
            $table: $db.chapters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$VolumesTableOrderingComposer
    extends Composer<_$AppDatabase, $VolumesTable> {
  $$VolumesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ManuscriptsTableOrderingComposer get manuscriptId {
    final $$ManuscriptsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableOrderingComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$VolumesTableAnnotationComposer
    extends Composer<_$AppDatabase, $VolumesTable> {
  $$VolumesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ManuscriptsTableAnnotationComposer get manuscriptId {
    final $$ManuscriptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableAnnotationComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> chaptersRefs<T extends Object>(
    Expression<T> Function($$ChaptersTableAnnotationComposer a) f,
  ) {
    final $$ChaptersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chapters,
      getReferencedColumn: (t) => t.volumeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChaptersTableAnnotationComposer(
            $db: $db,
            $table: $db.chapters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$VolumesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VolumesTable,
          Volume,
          $$VolumesTableFilterComposer,
          $$VolumesTableOrderingComposer,
          $$VolumesTableAnnotationComposer,
          $$VolumesTableCreateCompanionBuilder,
          $$VolumesTableUpdateCompanionBuilder,
          (Volume, $$VolumesTableReferences),
          Volume,
          PrefetchHooks Function({bool manuscriptId, bool chaptersRefs})
        > {
  $$VolumesTableTableManager(_$AppDatabase db, $VolumesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VolumesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VolumesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VolumesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> manuscriptId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VolumesCompanion(
                id: id,
                manuscriptId: manuscriptId,
                title: title,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String manuscriptId,
                Value<String> title = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VolumesCompanion.insert(
                id: id,
                manuscriptId: manuscriptId,
                title: title,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$VolumesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({manuscriptId = false, chaptersRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [if (chaptersRefs) db.chapters],
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
                        if (manuscriptId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.manuscriptId,
                                    referencedTable: $$VolumesTableReferences
                                        ._manuscriptIdTable(db),
                                    referencedColumn: $$VolumesTableReferences
                                        ._manuscriptIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (chaptersRefs)
                        await $_getPrefetchedData<
                          Volume,
                          $VolumesTable,
                          Chapter
                        >(
                          currentTable: table,
                          referencedTable: $$VolumesTableReferences
                              ._chaptersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$VolumesTableReferences(
                                db,
                                table,
                                p0,
                              ).chaptersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.volumeId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$VolumesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VolumesTable,
      Volume,
      $$VolumesTableFilterComposer,
      $$VolumesTableOrderingComposer,
      $$VolumesTableAnnotationComposer,
      $$VolumesTableCreateCompanionBuilder,
      $$VolumesTableUpdateCompanionBuilder,
      (Volume, $$VolumesTableReferences),
      Volume,
      PrefetchHooks Function({bool manuscriptId, bool chaptersRefs})
    >;
typedef $$ChaptersTableCreateCompanionBuilder =
    ChaptersCompanion Function({
      required String id,
      required String manuscriptId,
      Value<String?> volumeId,
      Value<String> title,
      Value<String> content,
      Value<String?> previousContent,
      Value<int> wordCount,
      Value<int> sortOrder,
      Value<String> status,
      Value<int?> lastDiagnosedAt,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });
typedef $$ChaptersTableUpdateCompanionBuilder =
    ChaptersCompanion Function({
      Value<String> id,
      Value<String> manuscriptId,
      Value<String?> volumeId,
      Value<String> title,
      Value<String> content,
      Value<String?> previousContent,
      Value<int> wordCount,
      Value<int> sortOrder,
      Value<String> status,
      Value<int?> lastDiagnosedAt,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $$ChaptersTableReferences
    extends BaseReferences<_$AppDatabase, $ChaptersTable, Chapter> {
  $$ChaptersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ManuscriptsTable _manuscriptIdTable(_$AppDatabase db) =>
      db.manuscripts.createAlias(
        $_aliasNameGenerator(db.chapters.manuscriptId, db.manuscripts.id),
      );

  $$ManuscriptsTableProcessedTableManager get manuscriptId {
    final $_column = $_itemColumn<String>('manuscript_id')!;

    final manager = $$ManuscriptsTableTableManager(
      $_db,
      $_db.manuscripts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_manuscriptIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $VolumesTable _volumeIdTable(_$AppDatabase db) => db.volumes
      .createAlias($_aliasNameGenerator(db.chapters.volumeId, db.volumes.id));

  $$VolumesTableProcessedTableManager? get volumeId {
    final $_column = $_itemColumn<String>('volume_id');
    if ($_column == null) return null;
    final manager = $$VolumesTableTableManager(
      $_db,
      $_db.volumes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_volumeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$SessionsTable, List<SessionRow>>
  _sessionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.sessions,
    aliasName: $_aliasNameGenerator(db.chapters.id, db.sessions.chapterId),
  );

  $$SessionsTableProcessedTableManager get sessionsRefs {
    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.chapterId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_sessionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ChaptersTableFilterComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get previousContent => $composableBuilder(
    column: $table.previousContent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wordCount => $composableBuilder(
    column: $table.wordCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastDiagnosedAt => $composableBuilder(
    column: $table.lastDiagnosedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ManuscriptsTableFilterComposer get manuscriptId {
    final $$ManuscriptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableFilterComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$VolumesTableFilterComposer get volumeId {
    final $$VolumesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.volumeId,
      referencedTable: $db.volumes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VolumesTableFilterComposer(
            $db: $db,
            $table: $db.volumes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> sessionsRefs(
    Expression<bool> Function($$SessionsTableFilterComposer f) f,
  ) {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.chapterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChaptersTableOrderingComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get previousContent => $composableBuilder(
    column: $table.previousContent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wordCount => $composableBuilder(
    column: $table.wordCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastDiagnosedAt => $composableBuilder(
    column: $table.lastDiagnosedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ManuscriptsTableOrderingComposer get manuscriptId {
    final $$ManuscriptsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableOrderingComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$VolumesTableOrderingComposer get volumeId {
    final $$VolumesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.volumeId,
      referencedTable: $db.volumes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VolumesTableOrderingComposer(
            $db: $db,
            $table: $db.volumes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChaptersTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get previousContent => $composableBuilder(
    column: $table.previousContent,
    builder: (column) => column,
  );

  GeneratedColumn<int> get wordCount =>
      $composableBuilder(column: $table.wordCount, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get lastDiagnosedAt => $composableBuilder(
    column: $table.lastDiagnosedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ManuscriptsTableAnnotationComposer get manuscriptId {
    final $$ManuscriptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableAnnotationComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$VolumesTableAnnotationComposer get volumeId {
    final $$VolumesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.volumeId,
      referencedTable: $db.volumes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VolumesTableAnnotationComposer(
            $db: $db,
            $table: $db.volumes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> sessionsRefs<T extends Object>(
    Expression<T> Function($$SessionsTableAnnotationComposer a) f,
  ) {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.chapterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChaptersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChaptersTable,
          Chapter,
          $$ChaptersTableFilterComposer,
          $$ChaptersTableOrderingComposer,
          $$ChaptersTableAnnotationComposer,
          $$ChaptersTableCreateCompanionBuilder,
          $$ChaptersTableUpdateCompanionBuilder,
          (Chapter, $$ChaptersTableReferences),
          Chapter,
          PrefetchHooks Function({
            bool manuscriptId,
            bool volumeId,
            bool sessionsRefs,
          })
        > {
  $$ChaptersTableTableManager(_$AppDatabase db, $ChaptersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChaptersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChaptersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChaptersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> manuscriptId = const Value.absent(),
                Value<String?> volumeId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String?> previousContent = const Value.absent(),
                Value<int> wordCount = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> lastDiagnosedAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChaptersCompanion(
                id: id,
                manuscriptId: manuscriptId,
                volumeId: volumeId,
                title: title,
                content: content,
                previousContent: previousContent,
                wordCount: wordCount,
                sortOrder: sortOrder,
                status: status,
                lastDiagnosedAt: lastDiagnosedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String manuscriptId,
                Value<String?> volumeId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String?> previousContent = const Value.absent(),
                Value<int> wordCount = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> lastDiagnosedAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChaptersCompanion.insert(
                id: id,
                manuscriptId: manuscriptId,
                volumeId: volumeId,
                title: title,
                content: content,
                previousContent: previousContent,
                wordCount: wordCount,
                sortOrder: sortOrder,
                status: status,
                lastDiagnosedAt: lastDiagnosedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ChaptersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({manuscriptId = false, volumeId = false, sessionsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [if (sessionsRefs) db.sessions],
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
                        if (manuscriptId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.manuscriptId,
                                    referencedTable: $$ChaptersTableReferences
                                        ._manuscriptIdTable(db),
                                    referencedColumn: $$ChaptersTableReferences
                                        ._manuscriptIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (volumeId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.volumeId,
                                    referencedTable: $$ChaptersTableReferences
                                        ._volumeIdTable(db),
                                    referencedColumn: $$ChaptersTableReferences
                                        ._volumeIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (sessionsRefs)
                        await $_getPrefetchedData<
                          Chapter,
                          $ChaptersTable,
                          SessionRow
                        >(
                          currentTable: table,
                          referencedTable: $$ChaptersTableReferences
                              ._sessionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ChaptersTableReferences(
                                db,
                                table,
                                p0,
                              ).sessionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.chapterId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ChaptersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChaptersTable,
      Chapter,
      $$ChaptersTableFilterComposer,
      $$ChaptersTableOrderingComposer,
      $$ChaptersTableAnnotationComposer,
      $$ChaptersTableCreateCompanionBuilder,
      $$ChaptersTableUpdateCompanionBuilder,
      (Chapter, $$ChaptersTableReferences),
      Chapter,
      PrefetchHooks Function({
        bool manuscriptId,
        bool volumeId,
        bool sessionsRefs,
      })
    >;
typedef $$SessionsTableCreateCompanionBuilder =
    SessionsCompanion Function({
      required String id,
      Value<String> title,
      Value<String> preview,
      Value<String?> manuscriptId,
      Value<String?> chapterId,
      Value<String> diagnosisSummary,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });
typedef $$SessionsTableUpdateCompanionBuilder =
    SessionsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> preview,
      Value<String?> manuscriptId,
      Value<String?> chapterId,
      Value<String> diagnosisSummary,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $$SessionsTableReferences
    extends BaseReferences<_$AppDatabase, $SessionsTable, SessionRow> {
  $$SessionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ManuscriptsTable _manuscriptIdTable(_$AppDatabase db) =>
      db.manuscripts.createAlias(
        $_aliasNameGenerator(db.sessions.manuscriptId, db.manuscripts.id),
      );

  $$ManuscriptsTableProcessedTableManager? get manuscriptId {
    final $_column = $_itemColumn<String>('manuscript_id');
    if ($_column == null) return null;
    final manager = $$ManuscriptsTableTableManager(
      $_db,
      $_db.manuscripts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_manuscriptIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ChaptersTable _chapterIdTable(_$AppDatabase db) => db.chapters
      .createAlias($_aliasNameGenerator(db.sessions.chapterId, db.chapters.id));

  $$ChaptersTableProcessedTableManager? get chapterId {
    final $_column = $_itemColumn<String>('chapter_id');
    if ($_column == null) return null;
    final manager = $$ChaptersTableTableManager(
      $_db,
      $_db.chapters,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_chapterIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$MessagesTable, List<Message>> _messagesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.messages,
    aliasName: $_aliasNameGenerator(db.sessions.id, db.messages.sessionId),
  );

  $$MessagesTableProcessedTableManager get messagesRefs {
    final manager = $$MessagesTableTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_messagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DiagnosisResultsTable, List<DiagnosisRow>>
  _diagnosisResultsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.diagnosisResults,
    aliasName: $_aliasNameGenerator(
      db.sessions.id,
      db.diagnosisResults.sessionId,
    ),
  );

  $$DiagnosisResultsTableProcessedTableManager get diagnosisResultsRefs {
    final manager = $$DiagnosisResultsTableTableManager(
      $_db,
      $_db.diagnosisResults,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _diagnosisResultsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TeachingStateTable, List<TeachingStateRow>>
  _teachingStateRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.teachingState,
    aliasName: $_aliasNameGenerator(db.sessions.id, db.teachingState.sessionId),
  );

  $$TeachingStateTableProcessedTableManager get teachingStateRefs {
    final manager = $$TeachingStateTableTableManager(
      $_db,
      $_db.teachingState,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_teachingStateRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ActiveProblemsTable, List<ActiveProblem>>
  _activeProblemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.activeProblems,
    aliasName: $_aliasNameGenerator(
      db.sessions.id,
      db.activeProblems.sessionId,
    ),
  );

  $$ActiveProblemsTableProcessedTableManager get activeProblemsRefs {
    final manager = $$ActiveProblemsTableTableManager(
      $_db,
      $_db.activeProblems,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_activeProblemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$StudentModelsTable, List<StudentModelRow>>
  _studentModelsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.studentModels,
    aliasName: $_aliasNameGenerator(db.sessions.id, db.studentModels.sessionId),
  );

  $$StudentModelsTableProcessedTableManager get studentModelsRefs {
    final manager = $$StudentModelsTableTableManager(
      $_db,
      $_db.studentModels,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_studentModelsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SessionReferencesTable, List<SessionReference>>
  _sessionReferencesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.sessionReferences,
        aliasName: $_aliasNameGenerator(
          db.sessions.id,
          db.sessionReferences.sessionId,
        ),
      );

  $$SessionReferencesTableProcessedTableManager get sessionReferencesRefs {
    final manager = $$SessionReferencesTableTableManager(
      $_db,
      $_db.sessionReferences,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _sessionReferencesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $TeacherSuggestionsTable,
    List<TeacherSuggestionRow>
  >
  _teacherSuggestionsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.teacherSuggestions,
        aliasName: $_aliasNameGenerator(
          db.sessions.id,
          db.teacherSuggestions.sessionId,
        ),
      );

  $$TeacherSuggestionsTableProcessedTableManager get teacherSuggestionsRefs {
    final manager = $$TeacherSuggestionsTableTableManager(
      $_db,
      $_db.teacherSuggestions,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _teacherSuggestionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $EditorObservationsTable,
    List<EditorObservationRow>
  >
  _editorObservationsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.editorObservations,
        aliasName: $_aliasNameGenerator(
          db.sessions.id,
          db.editorObservations.sessionId,
        ),
      );

  $$EditorObservationsTableProcessedTableManager get editorObservationsRefs {
    final manager = $$EditorObservationsTableTableManager(
      $_db,
      $_db.editorObservations,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _editorObservationsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SessionsTableFilterComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get preview => $composableBuilder(
    column: $table.preview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get diagnosisSummary => $composableBuilder(
    column: $table.diagnosisSummary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ManuscriptsTableFilterComposer get manuscriptId {
    final $$ManuscriptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableFilterComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ChaptersTableFilterComposer get chapterId {
    final $$ChaptersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chapterId,
      referencedTable: $db.chapters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChaptersTableFilterComposer(
            $db: $db,
            $table: $db.chapters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> messagesRefs(
    Expression<bool> Function($$MessagesTableFilterComposer f) f,
  ) {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> diagnosisResultsRefs(
    Expression<bool> Function($$DiagnosisResultsTableFilterComposer f) f,
  ) {
    final $$DiagnosisResultsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diagnosisResults,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiagnosisResultsTableFilterComposer(
            $db: $db,
            $table: $db.diagnosisResults,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> teachingStateRefs(
    Expression<bool> Function($$TeachingStateTableFilterComposer f) f,
  ) {
    final $$TeachingStateTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.teachingState,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TeachingStateTableFilterComposer(
            $db: $db,
            $table: $db.teachingState,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> activeProblemsRefs(
    Expression<bool> Function($$ActiveProblemsTableFilterComposer f) f,
  ) {
    final $$ActiveProblemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.activeProblems,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActiveProblemsTableFilterComposer(
            $db: $db,
            $table: $db.activeProblems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> studentModelsRefs(
    Expression<bool> Function($$StudentModelsTableFilterComposer f) f,
  ) {
    final $$StudentModelsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.studentModels,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StudentModelsTableFilterComposer(
            $db: $db,
            $table: $db.studentModels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> sessionReferencesRefs(
    Expression<bool> Function($$SessionReferencesTableFilterComposer f) f,
  ) {
    final $$SessionReferencesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessionReferences,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionReferencesTableFilterComposer(
            $db: $db,
            $table: $db.sessionReferences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> teacherSuggestionsRefs(
    Expression<bool> Function($$TeacherSuggestionsTableFilterComposer f) f,
  ) {
    final $$TeacherSuggestionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.teacherSuggestions,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TeacherSuggestionsTableFilterComposer(
            $db: $db,
            $table: $db.teacherSuggestions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> editorObservationsRefs(
    Expression<bool> Function($$EditorObservationsTableFilterComposer f) f,
  ) {
    final $$EditorObservationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.editorObservations,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EditorObservationsTableFilterComposer(
            $db: $db,
            $table: $db.editorObservations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get preview => $composableBuilder(
    column: $table.preview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get diagnosisSummary => $composableBuilder(
    column: $table.diagnosisSummary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ManuscriptsTableOrderingComposer get manuscriptId {
    final $$ManuscriptsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableOrderingComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ChaptersTableOrderingComposer get chapterId {
    final $$ChaptersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chapterId,
      referencedTable: $db.chapters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChaptersTableOrderingComposer(
            $db: $db,
            $table: $db.chapters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get preview =>
      $composableBuilder(column: $table.preview, builder: (column) => column);

  GeneratedColumn<String> get diagnosisSummary => $composableBuilder(
    column: $table.diagnosisSummary,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ManuscriptsTableAnnotationComposer get manuscriptId {
    final $$ManuscriptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableAnnotationComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ChaptersTableAnnotationComposer get chapterId {
    final $$ChaptersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chapterId,
      referencedTable: $db.chapters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChaptersTableAnnotationComposer(
            $db: $db,
            $table: $db.chapters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> messagesRefs<T extends Object>(
    Expression<T> Function($$MessagesTableAnnotationComposer a) f,
  ) {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> diagnosisResultsRefs<T extends Object>(
    Expression<T> Function($$DiagnosisResultsTableAnnotationComposer a) f,
  ) {
    final $$DiagnosisResultsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diagnosisResults,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiagnosisResultsTableAnnotationComposer(
            $db: $db,
            $table: $db.diagnosisResults,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> teachingStateRefs<T extends Object>(
    Expression<T> Function($$TeachingStateTableAnnotationComposer a) f,
  ) {
    final $$TeachingStateTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.teachingState,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TeachingStateTableAnnotationComposer(
            $db: $db,
            $table: $db.teachingState,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> activeProblemsRefs<T extends Object>(
    Expression<T> Function($$ActiveProblemsTableAnnotationComposer a) f,
  ) {
    final $$ActiveProblemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.activeProblems,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActiveProblemsTableAnnotationComposer(
            $db: $db,
            $table: $db.activeProblems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> studentModelsRefs<T extends Object>(
    Expression<T> Function($$StudentModelsTableAnnotationComposer a) f,
  ) {
    final $$StudentModelsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.studentModels,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StudentModelsTableAnnotationComposer(
            $db: $db,
            $table: $db.studentModels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> sessionReferencesRefs<T extends Object>(
    Expression<T> Function($$SessionReferencesTableAnnotationComposer a) f,
  ) {
    final $$SessionReferencesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.sessionReferences,
          getReferencedColumn: (t) => t.sessionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SessionReferencesTableAnnotationComposer(
                $db: $db,
                $table: $db.sessionReferences,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> teacherSuggestionsRefs<T extends Object>(
    Expression<T> Function($$TeacherSuggestionsTableAnnotationComposer a) f,
  ) {
    final $$TeacherSuggestionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.teacherSuggestions,
          getReferencedColumn: (t) => t.sessionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$TeacherSuggestionsTableAnnotationComposer(
                $db: $db,
                $table: $db.teacherSuggestions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> editorObservationsRefs<T extends Object>(
    Expression<T> Function($$EditorObservationsTableAnnotationComposer a) f,
  ) {
    final $$EditorObservationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.editorObservations,
          getReferencedColumn: (t) => t.sessionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$EditorObservationsTableAnnotationComposer(
                $db: $db,
                $table: $db.editorObservations,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$SessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionsTable,
          SessionRow,
          $$SessionsTableFilterComposer,
          $$SessionsTableOrderingComposer,
          $$SessionsTableAnnotationComposer,
          $$SessionsTableCreateCompanionBuilder,
          $$SessionsTableUpdateCompanionBuilder,
          (SessionRow, $$SessionsTableReferences),
          SessionRow,
          PrefetchHooks Function({
            bool manuscriptId,
            bool chapterId,
            bool messagesRefs,
            bool diagnosisResultsRefs,
            bool teachingStateRefs,
            bool activeProblemsRefs,
            bool studentModelsRefs,
            bool sessionReferencesRefs,
            bool teacherSuggestionsRefs,
            bool editorObservationsRefs,
          })
        > {
  $$SessionsTableTableManager(_$AppDatabase db, $SessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> preview = const Value.absent(),
                Value<String?> manuscriptId = const Value.absent(),
                Value<String?> chapterId = const Value.absent(),
                Value<String> diagnosisSummary = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion(
                id: id,
                title: title,
                preview: preview,
                manuscriptId: manuscriptId,
                chapterId: chapterId,
                diagnosisSummary: diagnosisSummary,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> title = const Value.absent(),
                Value<String> preview = const Value.absent(),
                Value<String?> manuscriptId = const Value.absent(),
                Value<String?> chapterId = const Value.absent(),
                Value<String> diagnosisSummary = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion.insert(
                id: id,
                title: title,
                preview: preview,
                manuscriptId: manuscriptId,
                chapterId: chapterId,
                diagnosisSummary: diagnosisSummary,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                manuscriptId = false,
                chapterId = false,
                messagesRefs = false,
                diagnosisResultsRefs = false,
                teachingStateRefs = false,
                activeProblemsRefs = false,
                studentModelsRefs = false,
                sessionReferencesRefs = false,
                teacherSuggestionsRefs = false,
                editorObservationsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (messagesRefs) db.messages,
                    if (diagnosisResultsRefs) db.diagnosisResults,
                    if (teachingStateRefs) db.teachingState,
                    if (activeProblemsRefs) db.activeProblems,
                    if (studentModelsRefs) db.studentModels,
                    if (sessionReferencesRefs) db.sessionReferences,
                    if (teacherSuggestionsRefs) db.teacherSuggestions,
                    if (editorObservationsRefs) db.editorObservations,
                  ],
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
                        if (manuscriptId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.manuscriptId,
                                    referencedTable: $$SessionsTableReferences
                                        ._manuscriptIdTable(db),
                                    referencedColumn: $$SessionsTableReferences
                                        ._manuscriptIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (chapterId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.chapterId,
                                    referencedTable: $$SessionsTableReferences
                                        ._chapterIdTable(db),
                                    referencedColumn: $$SessionsTableReferences
                                        ._chapterIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (messagesRefs)
                        await $_getPrefetchedData<
                          SessionRow,
                          $SessionsTable,
                          Message
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._messagesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).messagesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (diagnosisResultsRefs)
                        await $_getPrefetchedData<
                          SessionRow,
                          $SessionsTable,
                          DiagnosisRow
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._diagnosisResultsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).diagnosisResultsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (teachingStateRefs)
                        await $_getPrefetchedData<
                          SessionRow,
                          $SessionsTable,
                          TeachingStateRow
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._teachingStateRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).teachingStateRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (activeProblemsRefs)
                        await $_getPrefetchedData<
                          SessionRow,
                          $SessionsTable,
                          ActiveProblem
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._activeProblemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).activeProblemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (studentModelsRefs)
                        await $_getPrefetchedData<
                          SessionRow,
                          $SessionsTable,
                          StudentModelRow
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._studentModelsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).studentModelsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (sessionReferencesRefs)
                        await $_getPrefetchedData<
                          SessionRow,
                          $SessionsTable,
                          SessionReference
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._sessionReferencesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).sessionReferencesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (teacherSuggestionsRefs)
                        await $_getPrefetchedData<
                          SessionRow,
                          $SessionsTable,
                          TeacherSuggestionRow
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._teacherSuggestionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).teacherSuggestionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (editorObservationsRefs)
                        await $_getPrefetchedData<
                          SessionRow,
                          $SessionsTable,
                          EditorObservationRow
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._editorObservationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).editorObservationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionsTable,
      SessionRow,
      $$SessionsTableFilterComposer,
      $$SessionsTableOrderingComposer,
      $$SessionsTableAnnotationComposer,
      $$SessionsTableCreateCompanionBuilder,
      $$SessionsTableUpdateCompanionBuilder,
      (SessionRow, $$SessionsTableReferences),
      SessionRow,
      PrefetchHooks Function({
        bool manuscriptId,
        bool chapterId,
        bool messagesRefs,
        bool diagnosisResultsRefs,
        bool teachingStateRefs,
        bool activeProblemsRefs,
        bool studentModelsRefs,
        bool sessionReferencesRefs,
        bool teacherSuggestionsRefs,
        bool editorObservationsRefs,
      })
    >;
typedef $$MessagesTableCreateCompanionBuilder =
    MessagesCompanion Function({
      required String id,
      required String sessionId,
      required String role,
      required String content,
      Value<int> timestamp,
      Value<String> messageType,
      Value<String?> referencesJson,
      Value<int> rowid,
    });
typedef $$MessagesTableUpdateCompanionBuilder =
    MessagesCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<String> role,
      Value<String> content,
      Value<int> timestamp,
      Value<String> messageType,
      Value<String?> referencesJson,
      Value<int> rowid,
    });

final class $$MessagesTableReferences
    extends BaseReferences<_$AppDatabase, $MessagesTable, Message> {
  $$MessagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SessionsTable _sessionIdTable(_$AppDatabase db) => db.sessions
      .createAlias($_aliasNameGenerator(db.messages.sessionId, db.sessions.id));

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $TeacherSuggestionsTable,
    List<TeacherSuggestionRow>
  >
  _teacherSuggestionsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.teacherSuggestions,
        aliasName: $_aliasNameGenerator(
          db.messages.id,
          db.teacherSuggestions.messageId,
        ),
      );

  $$TeacherSuggestionsTableProcessedTableManager get teacherSuggestionsRefs {
    final manager = $$TeacherSuggestionsTableTableManager(
      $_db,
      $_db.teacherSuggestions,
    ).filter((f) => f.messageId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _teacherSuggestionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $EditorObservationsTable,
    List<EditorObservationRow>
  >
  _editorObservationsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.editorObservations,
        aliasName: $_aliasNameGenerator(
          db.messages.id,
          db.editorObservations.messageId,
        ),
      );

  $$EditorObservationsTableProcessedTableManager get editorObservationsRefs {
    final manager = $$EditorObservationsTableTableManager(
      $_db,
      $_db.editorObservations,
    ).filter((f) => f.messageId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _editorObservationsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageType => $composableBuilder(
    column: $table.messageType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get referencesJson => $composableBuilder(
    column: $table.referencesJson,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> teacherSuggestionsRefs(
    Expression<bool> Function($$TeacherSuggestionsTableFilterComposer f) f,
  ) {
    final $$TeacherSuggestionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.teacherSuggestions,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TeacherSuggestionsTableFilterComposer(
            $db: $db,
            $table: $db.teacherSuggestions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> editorObservationsRefs(
    Expression<bool> Function($$EditorObservationsTableFilterComposer f) f,
  ) {
    final $$EditorObservationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.editorObservations,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EditorObservationsTableFilterComposer(
            $db: $db,
            $table: $db.editorObservations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageType => $composableBuilder(
    column: $table.messageType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get referencesJson => $composableBuilder(
    column: $table.referencesJson,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get messageType => $composableBuilder(
    column: $table.messageType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get referencesJson => $composableBuilder(
    column: $table.referencesJson,
    builder: (column) => column,
  );

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> teacherSuggestionsRefs<T extends Object>(
    Expression<T> Function($$TeacherSuggestionsTableAnnotationComposer a) f,
  ) {
    final $$TeacherSuggestionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.teacherSuggestions,
          getReferencedColumn: (t) => t.messageId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$TeacherSuggestionsTableAnnotationComposer(
                $db: $db,
                $table: $db.teacherSuggestions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> editorObservationsRefs<T extends Object>(
    Expression<T> Function($$EditorObservationsTableAnnotationComposer a) f,
  ) {
    final $$EditorObservationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.editorObservations,
          getReferencedColumn: (t) => t.messageId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$EditorObservationsTableAnnotationComposer(
                $db: $db,
                $table: $db.editorObservations,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MessagesTable,
          Message,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (Message, $$MessagesTableReferences),
          Message,
          PrefetchHooks Function({
            bool sessionId,
            bool teacherSuggestionsRefs,
            bool editorObservationsRefs,
          })
        > {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<int> timestamp = const Value.absent(),
                Value<String> messageType = const Value.absent(),
                Value<String?> referencesJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion(
                id: id,
                sessionId: sessionId,
                role: role,
                content: content,
                timestamp: timestamp,
                messageType: messageType,
                referencesJson: referencesJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                required String role,
                required String content,
                Value<int> timestamp = const Value.absent(),
                Value<String> messageType = const Value.absent(),
                Value<String?> referencesJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion.insert(
                id: id,
                sessionId: sessionId,
                role: role,
                content: content,
                timestamp: timestamp,
                messageType: messageType,
                referencesJson: referencesJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MessagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                sessionId = false,
                teacherSuggestionsRefs = false,
                editorObservationsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (teacherSuggestionsRefs) db.teacherSuggestions,
                    if (editorObservationsRefs) db.editorObservations,
                  ],
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
                        if (sessionId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.sessionId,
                                    referencedTable: $$MessagesTableReferences
                                        ._sessionIdTable(db),
                                    referencedColumn: $$MessagesTableReferences
                                        ._sessionIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (teacherSuggestionsRefs)
                        await $_getPrefetchedData<
                          Message,
                          $MessagesTable,
                          TeacherSuggestionRow
                        >(
                          currentTable: table,
                          referencedTable: $$MessagesTableReferences
                              ._teacherSuggestionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MessagesTableReferences(
                                db,
                                table,
                                p0,
                              ).teacherSuggestionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.messageId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (editorObservationsRefs)
                        await $_getPrefetchedData<
                          Message,
                          $MessagesTable,
                          EditorObservationRow
                        >(
                          currentTable: table,
                          referencedTable: $$MessagesTableReferences
                              ._editorObservationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MessagesTableReferences(
                                db,
                                table,
                                p0,
                              ).editorObservationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.messageId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MessagesTable,
      Message,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (Message, $$MessagesTableReferences),
      Message,
      PrefetchHooks Function({
        bool sessionId,
        bool teacherSuggestionsRefs,
        bool editorObservationsRefs,
      })
    >;
typedef $$DiagnosisResultsTableCreateCompanionBuilder =
    DiagnosisResultsCompanion Function({
      required String id,
      required String sessionId,
      required String messageId,
      Value<String> syndromes,
      Value<String> suggestedActions,
      Value<String?> rootCauseAnalysis,
      Value<String?> nextFocus,
      Value<String?> feedbackSummary,
      Value<double> confidence,
      Value<String?> teachingProgress,
      Value<String?> targetRefType,
      Value<String?> targetRefId,
      Value<int> timestamp,
      Value<int> createdAt,
      Value<String?> currentTeachingFocusId,
      Value<String?> focusReason,
      Value<int> rowid,
    });
typedef $$DiagnosisResultsTableUpdateCompanionBuilder =
    DiagnosisResultsCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<String> messageId,
      Value<String> syndromes,
      Value<String> suggestedActions,
      Value<String?> rootCauseAnalysis,
      Value<String?> nextFocus,
      Value<String?> feedbackSummary,
      Value<double> confidence,
      Value<String?> teachingProgress,
      Value<String?> targetRefType,
      Value<String?> targetRefId,
      Value<int> timestamp,
      Value<int> createdAt,
      Value<String?> currentTeachingFocusId,
      Value<String?> focusReason,
      Value<int> rowid,
    });

final class $$DiagnosisResultsTableReferences
    extends
        BaseReferences<_$AppDatabase, $DiagnosisResultsTable, DiagnosisRow> {
  $$DiagnosisResultsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias(
        $_aliasNameGenerator(db.diagnosisResults.sessionId, db.sessions.id),
      );

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DiagnosisResultsTableFilterComposer
    extends Composer<_$AppDatabase, $DiagnosisResultsTable> {
  $$DiagnosisResultsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syndromes => $composableBuilder(
    column: $table.syndromes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get suggestedActions => $composableBuilder(
    column: $table.suggestedActions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rootCauseAnalysis => $composableBuilder(
    column: $table.rootCauseAnalysis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nextFocus => $composableBuilder(
    column: $table.nextFocus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get feedbackSummary => $composableBuilder(
    column: $table.feedbackSummary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get teachingProgress => $composableBuilder(
    column: $table.teachingProgress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetRefType => $composableBuilder(
    column: $table.targetRefType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetRefId => $composableBuilder(
    column: $table.targetRefId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentTeachingFocusId => $composableBuilder(
    column: $table.currentTeachingFocusId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get focusReason => $composableBuilder(
    column: $table.focusReason,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiagnosisResultsTableOrderingComposer
    extends Composer<_$AppDatabase, $DiagnosisResultsTable> {
  $$DiagnosisResultsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syndromes => $composableBuilder(
    column: $table.syndromes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get suggestedActions => $composableBuilder(
    column: $table.suggestedActions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rootCauseAnalysis => $composableBuilder(
    column: $table.rootCauseAnalysis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nextFocus => $composableBuilder(
    column: $table.nextFocus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get feedbackSummary => $composableBuilder(
    column: $table.feedbackSummary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get teachingProgress => $composableBuilder(
    column: $table.teachingProgress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetRefType => $composableBuilder(
    column: $table.targetRefType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetRefId => $composableBuilder(
    column: $table.targetRefId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentTeachingFocusId => $composableBuilder(
    column: $table.currentTeachingFocusId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get focusReason => $composableBuilder(
    column: $table.focusReason,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiagnosisResultsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DiagnosisResultsTable> {
  $$DiagnosisResultsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get syndromes =>
      $composableBuilder(column: $table.syndromes, builder: (column) => column);

  GeneratedColumn<String> get suggestedActions => $composableBuilder(
    column: $table.suggestedActions,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rootCauseAnalysis => $composableBuilder(
    column: $table.rootCauseAnalysis,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nextFocus =>
      $composableBuilder(column: $table.nextFocus, builder: (column) => column);

  GeneratedColumn<String> get feedbackSummary => $composableBuilder(
    column: $table.feedbackSummary,
    builder: (column) => column,
  );

  GeneratedColumn<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get teachingProgress => $composableBuilder(
    column: $table.teachingProgress,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetRefType => $composableBuilder(
    column: $table.targetRefType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetRefId => $composableBuilder(
    column: $table.targetRefId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get currentTeachingFocusId => $composableBuilder(
    column: $table.currentTeachingFocusId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get focusReason => $composableBuilder(
    column: $table.focusReason,
    builder: (column) => column,
  );

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiagnosisResultsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DiagnosisResultsTable,
          DiagnosisRow,
          $$DiagnosisResultsTableFilterComposer,
          $$DiagnosisResultsTableOrderingComposer,
          $$DiagnosisResultsTableAnnotationComposer,
          $$DiagnosisResultsTableCreateCompanionBuilder,
          $$DiagnosisResultsTableUpdateCompanionBuilder,
          (DiagnosisRow, $$DiagnosisResultsTableReferences),
          DiagnosisRow,
          PrefetchHooks Function({bool sessionId})
        > {
  $$DiagnosisResultsTableTableManager(
    _$AppDatabase db,
    $DiagnosisResultsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DiagnosisResultsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DiagnosisResultsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DiagnosisResultsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<String> syndromes = const Value.absent(),
                Value<String> suggestedActions = const Value.absent(),
                Value<String?> rootCauseAnalysis = const Value.absent(),
                Value<String?> nextFocus = const Value.absent(),
                Value<String?> feedbackSummary = const Value.absent(),
                Value<double> confidence = const Value.absent(),
                Value<String?> teachingProgress = const Value.absent(),
                Value<String?> targetRefType = const Value.absent(),
                Value<String?> targetRefId = const Value.absent(),
                Value<int> timestamp = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<String?> currentTeachingFocusId = const Value.absent(),
                Value<String?> focusReason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiagnosisResultsCompanion(
                id: id,
                sessionId: sessionId,
                messageId: messageId,
                syndromes: syndromes,
                suggestedActions: suggestedActions,
                rootCauseAnalysis: rootCauseAnalysis,
                nextFocus: nextFocus,
                feedbackSummary: feedbackSummary,
                confidence: confidence,
                teachingProgress: teachingProgress,
                targetRefType: targetRefType,
                targetRefId: targetRefId,
                timestamp: timestamp,
                createdAt: createdAt,
                currentTeachingFocusId: currentTeachingFocusId,
                focusReason: focusReason,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                required String messageId,
                Value<String> syndromes = const Value.absent(),
                Value<String> suggestedActions = const Value.absent(),
                Value<String?> rootCauseAnalysis = const Value.absent(),
                Value<String?> nextFocus = const Value.absent(),
                Value<String?> feedbackSummary = const Value.absent(),
                Value<double> confidence = const Value.absent(),
                Value<String?> teachingProgress = const Value.absent(),
                Value<String?> targetRefType = const Value.absent(),
                Value<String?> targetRefId = const Value.absent(),
                Value<int> timestamp = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<String?> currentTeachingFocusId = const Value.absent(),
                Value<String?> focusReason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiagnosisResultsCompanion.insert(
                id: id,
                sessionId: sessionId,
                messageId: messageId,
                syndromes: syndromes,
                suggestedActions: suggestedActions,
                rootCauseAnalysis: rootCauseAnalysis,
                nextFocus: nextFocus,
                feedbackSummary: feedbackSummary,
                confidence: confidence,
                teachingProgress: teachingProgress,
                targetRefType: targetRefType,
                targetRefId: targetRefId,
                timestamp: timestamp,
                createdAt: createdAt,
                currentTeachingFocusId: currentTeachingFocusId,
                focusReason: focusReason,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DiagnosisResultsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
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
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable:
                                    $$DiagnosisResultsTableReferences
                                        ._sessionIdTable(db),
                                referencedColumn:
                                    $$DiagnosisResultsTableReferences
                                        ._sessionIdTable(db)
                                        .id,
                              )
                              as T;
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

typedef $$DiagnosisResultsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DiagnosisResultsTable,
      DiagnosisRow,
      $$DiagnosisResultsTableFilterComposer,
      $$DiagnosisResultsTableOrderingComposer,
      $$DiagnosisResultsTableAnnotationComposer,
      $$DiagnosisResultsTableCreateCompanionBuilder,
      $$DiagnosisResultsTableUpdateCompanionBuilder,
      (DiagnosisRow, $$DiagnosisResultsTableReferences),
      DiagnosisRow,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$TeachingStateTableCreateCompanionBuilder =
    TeachingStateCompanion Function({
      required String id,
      required String sessionId,
      Value<String> currentPhase,
      Value<String?> currentSubphase,
      Value<String?> attitudeLevel,
      Value<String?> beginnerLevel,
      Value<int> updatedAt,
      Value<int> rowid,
    });
typedef $$TeachingStateTableUpdateCompanionBuilder =
    TeachingStateCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<String> currentPhase,
      Value<String?> currentSubphase,
      Value<String?> attitudeLevel,
      Value<String?> beginnerLevel,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $$TeachingStateTableReferences
    extends
        BaseReferences<_$AppDatabase, $TeachingStateTable, TeachingStateRow> {
  $$TeachingStateTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias(
        $_aliasNameGenerator(db.teachingState.sessionId, db.sessions.id),
      );

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TeachingStateTableFilterComposer
    extends Composer<_$AppDatabase, $TeachingStateTable> {
  $$TeachingStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentPhase => $composableBuilder(
    column: $table.currentPhase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentSubphase => $composableBuilder(
    column: $table.currentSubphase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attitudeLevel => $composableBuilder(
    column: $table.attitudeLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get beginnerLevel => $composableBuilder(
    column: $table.beginnerLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TeachingStateTableOrderingComposer
    extends Composer<_$AppDatabase, $TeachingStateTable> {
  $$TeachingStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentPhase => $composableBuilder(
    column: $table.currentPhase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentSubphase => $composableBuilder(
    column: $table.currentSubphase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attitudeLevel => $composableBuilder(
    column: $table.attitudeLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get beginnerLevel => $composableBuilder(
    column: $table.beginnerLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TeachingStateTableAnnotationComposer
    extends Composer<_$AppDatabase, $TeachingStateTable> {
  $$TeachingStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get currentPhase => $composableBuilder(
    column: $table.currentPhase,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currentSubphase => $composableBuilder(
    column: $table.currentSubphase,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attitudeLevel => $composableBuilder(
    column: $table.attitudeLevel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get beginnerLevel => $composableBuilder(
    column: $table.beginnerLevel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TeachingStateTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TeachingStateTable,
          TeachingStateRow,
          $$TeachingStateTableFilterComposer,
          $$TeachingStateTableOrderingComposer,
          $$TeachingStateTableAnnotationComposer,
          $$TeachingStateTableCreateCompanionBuilder,
          $$TeachingStateTableUpdateCompanionBuilder,
          (TeachingStateRow, $$TeachingStateTableReferences),
          TeachingStateRow,
          PrefetchHooks Function({bool sessionId})
        > {
  $$TeachingStateTableTableManager(_$AppDatabase db, $TeachingStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TeachingStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TeachingStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TeachingStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> currentPhase = const Value.absent(),
                Value<String?> currentSubphase = const Value.absent(),
                Value<String?> attitudeLevel = const Value.absent(),
                Value<String?> beginnerLevel = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TeachingStateCompanion(
                id: id,
                sessionId: sessionId,
                currentPhase: currentPhase,
                currentSubphase: currentSubphase,
                attitudeLevel: attitudeLevel,
                beginnerLevel: beginnerLevel,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                Value<String> currentPhase = const Value.absent(),
                Value<String?> currentSubphase = const Value.absent(),
                Value<String?> attitudeLevel = const Value.absent(),
                Value<String?> beginnerLevel = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TeachingStateCompanion.insert(
                id: id,
                sessionId: sessionId,
                currentPhase: currentPhase,
                currentSubphase: currentSubphase,
                attitudeLevel: attitudeLevel,
                beginnerLevel: beginnerLevel,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TeachingStateTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
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
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable: $$TeachingStateTableReferences
                                    ._sessionIdTable(db),
                                referencedColumn: $$TeachingStateTableReferences
                                    ._sessionIdTable(db)
                                    .id,
                              )
                              as T;
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

typedef $$TeachingStateTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TeachingStateTable,
      TeachingStateRow,
      $$TeachingStateTableFilterComposer,
      $$TeachingStateTableOrderingComposer,
      $$TeachingStateTableAnnotationComposer,
      $$TeachingStateTableCreateCompanionBuilder,
      $$TeachingStateTableUpdateCompanionBuilder,
      (TeachingStateRow, $$TeachingStateTableReferences),
      TeachingStateRow,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$ActiveProblemsTableCreateCompanionBuilder =
    ActiveProblemsCompanion Function({
      required String id,
      required String sessionId,
      required String syndromeId,
      Value<String> syndromeName,
      Value<String> severity,
      Value<String> status,
      Value<String> confirmationStatus,
      Value<String?> teachingState,
      Value<int?> confirmedAt,
      Value<int> createdAt,
      Value<int?> resolvedAt,
      Value<int?> updatedAt,
      Value<int> rowid,
    });
typedef $$ActiveProblemsTableUpdateCompanionBuilder =
    ActiveProblemsCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<String> syndromeId,
      Value<String> syndromeName,
      Value<String> severity,
      Value<String> status,
      Value<String> confirmationStatus,
      Value<String?> teachingState,
      Value<int?> confirmedAt,
      Value<int> createdAt,
      Value<int?> resolvedAt,
      Value<int?> updatedAt,
      Value<int> rowid,
    });

final class $$ActiveProblemsTableReferences
    extends BaseReferences<_$AppDatabase, $ActiveProblemsTable, ActiveProblem> {
  $$ActiveProblemsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias(
        $_aliasNameGenerator(db.activeProblems.sessionId, db.sessions.id),
      );

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ActiveProblemsTableFilterComposer
    extends Composer<_$AppDatabase, $ActiveProblemsTable> {
  $$ActiveProblemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syndromeId => $composableBuilder(
    column: $table.syndromeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syndromeName => $composableBuilder(
    column: $table.syndromeName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get severity => $composableBuilder(
    column: $table.severity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get confirmationStatus => $composableBuilder(
    column: $table.confirmationStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get teachingState => $composableBuilder(
    column: $table.teachingState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get confirmedAt => $composableBuilder(
    column: $table.confirmedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActiveProblemsTableOrderingComposer
    extends Composer<_$AppDatabase, $ActiveProblemsTable> {
  $$ActiveProblemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syndromeId => $composableBuilder(
    column: $table.syndromeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syndromeName => $composableBuilder(
    column: $table.syndromeName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get severity => $composableBuilder(
    column: $table.severity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get confirmationStatus => $composableBuilder(
    column: $table.confirmationStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get teachingState => $composableBuilder(
    column: $table.teachingState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get confirmedAt => $composableBuilder(
    column: $table.confirmedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActiveProblemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ActiveProblemsTable> {
  $$ActiveProblemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get syndromeId => $composableBuilder(
    column: $table.syndromeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syndromeName => $composableBuilder(
    column: $table.syndromeName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get severity =>
      $composableBuilder(column: $table.severity, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get confirmationStatus => $composableBuilder(
    column: $table.confirmationStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get teachingState => $composableBuilder(
    column: $table.teachingState,
    builder: (column) => column,
  );

  GeneratedColumn<int> get confirmedAt => $composableBuilder(
    column: $table.confirmedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActiveProblemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ActiveProblemsTable,
          ActiveProblem,
          $$ActiveProblemsTableFilterComposer,
          $$ActiveProblemsTableOrderingComposer,
          $$ActiveProblemsTableAnnotationComposer,
          $$ActiveProblemsTableCreateCompanionBuilder,
          $$ActiveProblemsTableUpdateCompanionBuilder,
          (ActiveProblem, $$ActiveProblemsTableReferences),
          ActiveProblem,
          PrefetchHooks Function({bool sessionId})
        > {
  $$ActiveProblemsTableTableManager(
    _$AppDatabase db,
    $ActiveProblemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActiveProblemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActiveProblemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActiveProblemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> syndromeId = const Value.absent(),
                Value<String> syndromeName = const Value.absent(),
                Value<String> severity = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> confirmationStatus = const Value.absent(),
                Value<String?> teachingState = const Value.absent(),
                Value<int?> confirmedAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> resolvedAt = const Value.absent(),
                Value<int?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActiveProblemsCompanion(
                id: id,
                sessionId: sessionId,
                syndromeId: syndromeId,
                syndromeName: syndromeName,
                severity: severity,
                status: status,
                confirmationStatus: confirmationStatus,
                teachingState: teachingState,
                confirmedAt: confirmedAt,
                createdAt: createdAt,
                resolvedAt: resolvedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                required String syndromeId,
                Value<String> syndromeName = const Value.absent(),
                Value<String> severity = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> confirmationStatus = const Value.absent(),
                Value<String?> teachingState = const Value.absent(),
                Value<int?> confirmedAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> resolvedAt = const Value.absent(),
                Value<int?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActiveProblemsCompanion.insert(
                id: id,
                sessionId: sessionId,
                syndromeId: syndromeId,
                syndromeName: syndromeName,
                severity: severity,
                status: status,
                confirmationStatus: confirmationStatus,
                teachingState: teachingState,
                confirmedAt: confirmedAt,
                createdAt: createdAt,
                resolvedAt: resolvedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ActiveProblemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
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
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable: $$ActiveProblemsTableReferences
                                    ._sessionIdTable(db),
                                referencedColumn:
                                    $$ActiveProblemsTableReferences
                                        ._sessionIdTable(db)
                                        .id,
                              )
                              as T;
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

typedef $$ActiveProblemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ActiveProblemsTable,
      ActiveProblem,
      $$ActiveProblemsTableFilterComposer,
      $$ActiveProblemsTableOrderingComposer,
      $$ActiveProblemsTableAnnotationComposer,
      $$ActiveProblemsTableCreateCompanionBuilder,
      $$ActiveProblemsTableUpdateCompanionBuilder,
      (ActiveProblem, $$ActiveProblemsTableReferences),
      ActiveProblem,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$StudentModelsTableCreateCompanionBuilder =
    StudentModelsCompanion Function({
      required String id,
      required String sessionId,
      Value<String?> attitudePreference,
      Value<String> teachingHistory,
      Value<String?> onboardingData,
      Value<String?> styleProfile,
      Value<String?> styleFingerprint,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });
typedef $$StudentModelsTableUpdateCompanionBuilder =
    StudentModelsCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<String?> attitudePreference,
      Value<String> teachingHistory,
      Value<String?> onboardingData,
      Value<String?> styleProfile,
      Value<String?> styleFingerprint,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $$StudentModelsTableReferences
    extends
        BaseReferences<_$AppDatabase, $StudentModelsTable, StudentModelRow> {
  $$StudentModelsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias(
        $_aliasNameGenerator(db.studentModels.sessionId, db.sessions.id),
      );

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$StudentModelsTableFilterComposer
    extends Composer<_$AppDatabase, $StudentModelsTable> {
  $$StudentModelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attitudePreference => $composableBuilder(
    column: $table.attitudePreference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get teachingHistory => $composableBuilder(
    column: $table.teachingHistory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get onboardingData => $composableBuilder(
    column: $table.onboardingData,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get styleProfile => $composableBuilder(
    column: $table.styleProfile,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get styleFingerprint => $composableBuilder(
    column: $table.styleFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StudentModelsTableOrderingComposer
    extends Composer<_$AppDatabase, $StudentModelsTable> {
  $$StudentModelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attitudePreference => $composableBuilder(
    column: $table.attitudePreference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get teachingHistory => $composableBuilder(
    column: $table.teachingHistory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get onboardingData => $composableBuilder(
    column: $table.onboardingData,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get styleProfile => $composableBuilder(
    column: $table.styleProfile,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get styleFingerprint => $composableBuilder(
    column: $table.styleFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StudentModelsTableAnnotationComposer
    extends Composer<_$AppDatabase, $StudentModelsTable> {
  $$StudentModelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get attitudePreference => $composableBuilder(
    column: $table.attitudePreference,
    builder: (column) => column,
  );

  GeneratedColumn<String> get teachingHistory => $composableBuilder(
    column: $table.teachingHistory,
    builder: (column) => column,
  );

  GeneratedColumn<String> get onboardingData => $composableBuilder(
    column: $table.onboardingData,
    builder: (column) => column,
  );

  GeneratedColumn<String> get styleProfile => $composableBuilder(
    column: $table.styleProfile,
    builder: (column) => column,
  );

  GeneratedColumn<String> get styleFingerprint => $composableBuilder(
    column: $table.styleFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StudentModelsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StudentModelsTable,
          StudentModelRow,
          $$StudentModelsTableFilterComposer,
          $$StudentModelsTableOrderingComposer,
          $$StudentModelsTableAnnotationComposer,
          $$StudentModelsTableCreateCompanionBuilder,
          $$StudentModelsTableUpdateCompanionBuilder,
          (StudentModelRow, $$StudentModelsTableReferences),
          StudentModelRow,
          PrefetchHooks Function({bool sessionId})
        > {
  $$StudentModelsTableTableManager(_$AppDatabase db, $StudentModelsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StudentModelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StudentModelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StudentModelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String?> attitudePreference = const Value.absent(),
                Value<String> teachingHistory = const Value.absent(),
                Value<String?> onboardingData = const Value.absent(),
                Value<String?> styleProfile = const Value.absent(),
                Value<String?> styleFingerprint = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StudentModelsCompanion(
                id: id,
                sessionId: sessionId,
                attitudePreference: attitudePreference,
                teachingHistory: teachingHistory,
                onboardingData: onboardingData,
                styleProfile: styleProfile,
                styleFingerprint: styleFingerprint,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                Value<String?> attitudePreference = const Value.absent(),
                Value<String> teachingHistory = const Value.absent(),
                Value<String?> onboardingData = const Value.absent(),
                Value<String?> styleProfile = const Value.absent(),
                Value<String?> styleFingerprint = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StudentModelsCompanion.insert(
                id: id,
                sessionId: sessionId,
                attitudePreference: attitudePreference,
                teachingHistory: teachingHistory,
                onboardingData: onboardingData,
                styleProfile: styleProfile,
                styleFingerprint: styleFingerprint,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$StudentModelsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
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
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable: $$StudentModelsTableReferences
                                    ._sessionIdTable(db),
                                referencedColumn: $$StudentModelsTableReferences
                                    ._sessionIdTable(db)
                                    .id,
                              )
                              as T;
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

typedef $$StudentModelsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StudentModelsTable,
      StudentModelRow,
      $$StudentModelsTableFilterComposer,
      $$StudentModelsTableOrderingComposer,
      $$StudentModelsTableAnnotationComposer,
      $$StudentModelsTableCreateCompanionBuilder,
      $$StudentModelsTableUpdateCompanionBuilder,
      (StudentModelRow, $$StudentModelsTableReferences),
      StudentModelRow,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$SessionReferencesTableCreateCompanionBuilder =
    SessionReferencesCompanion Function({
      required String id,
      required String sessionId,
      required String refType,
      required String refId,
      Value<int> isPrimary,
      Value<String?> excerptRange,
      Value<int> createdAt,
      Value<int> rowid,
    });
typedef $$SessionReferencesTableUpdateCompanionBuilder =
    SessionReferencesCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<String> refType,
      Value<String> refId,
      Value<int> isPrimary,
      Value<String?> excerptRange,
      Value<int> createdAt,
      Value<int> rowid,
    });

final class $$SessionReferencesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $SessionReferencesTable,
          SessionReference
        > {
  $$SessionReferencesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias(
        $_aliasNameGenerator(db.sessionReferences.sessionId, db.sessions.id),
      );

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SessionReferencesTableFilterComposer
    extends Composer<_$AppDatabase, $SessionReferencesTable> {
  $$SessionReferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refType => $composableBuilder(
    column: $table.refType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get isPrimary => $composableBuilder(
    column: $table.isPrimary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get excerptRange => $composableBuilder(
    column: $table.excerptRange,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionReferencesTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionReferencesTable> {
  $$SessionReferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refType => $composableBuilder(
    column: $table.refType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get isPrimary => $composableBuilder(
    column: $table.isPrimary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get excerptRange => $composableBuilder(
    column: $table.excerptRange,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionReferencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionReferencesTable> {
  $$SessionReferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get refType =>
      $composableBuilder(column: $table.refType, builder: (column) => column);

  GeneratedColumn<String> get refId =>
      $composableBuilder(column: $table.refId, builder: (column) => column);

  GeneratedColumn<int> get isPrimary =>
      $composableBuilder(column: $table.isPrimary, builder: (column) => column);

  GeneratedColumn<String> get excerptRange => $composableBuilder(
    column: $table.excerptRange,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionReferencesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionReferencesTable,
          SessionReference,
          $$SessionReferencesTableFilterComposer,
          $$SessionReferencesTableOrderingComposer,
          $$SessionReferencesTableAnnotationComposer,
          $$SessionReferencesTableCreateCompanionBuilder,
          $$SessionReferencesTableUpdateCompanionBuilder,
          (SessionReference, $$SessionReferencesTableReferences),
          SessionReference,
          PrefetchHooks Function({bool sessionId})
        > {
  $$SessionReferencesTableTableManager(
    _$AppDatabase db,
    $SessionReferencesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionReferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionReferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionReferencesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> refType = const Value.absent(),
                Value<String> refId = const Value.absent(),
                Value<int> isPrimary = const Value.absent(),
                Value<String?> excerptRange = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionReferencesCompanion(
                id: id,
                sessionId: sessionId,
                refType: refType,
                refId: refId,
                isPrimary: isPrimary,
                excerptRange: excerptRange,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                required String refType,
                required String refId,
                Value<int> isPrimary = const Value.absent(),
                Value<String?> excerptRange = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionReferencesCompanion.insert(
                id: id,
                sessionId: sessionId,
                refType: refType,
                refId: refId,
                isPrimary: isPrimary,
                excerptRange: excerptRange,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SessionReferencesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
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
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable:
                                    $$SessionReferencesTableReferences
                                        ._sessionIdTable(db),
                                referencedColumn:
                                    $$SessionReferencesTableReferences
                                        ._sessionIdTable(db)
                                        .id,
                              )
                              as T;
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

typedef $$SessionReferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionReferencesTable,
      SessionReference,
      $$SessionReferencesTableFilterComposer,
      $$SessionReferencesTableOrderingComposer,
      $$SessionReferencesTableAnnotationComposer,
      $$SessionReferencesTableCreateCompanionBuilder,
      $$SessionReferencesTableUpdateCompanionBuilder,
      (SessionReference, $$SessionReferencesTableReferences),
      SessionReference,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$AppStatesTableCreateCompanionBuilder =
    AppStatesCompanion Function({
      required String key,
      Value<String> value,
      Value<int> updatedAt,
      Value<int> rowid,
    });
typedef $$AppStatesTableUpdateCompanionBuilder =
    AppStatesCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$AppStatesTableFilterComposer
    extends Composer<_$AppDatabase, $AppStatesTable> {
  $$AppStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $AppStatesTable> {
  $$AppStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppStatesTable> {
  $$AppStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppStatesTable,
          AppStateEntry,
          $$AppStatesTableFilterComposer,
          $$AppStatesTableOrderingComposer,
          $$AppStatesTableAnnotationComposer,
          $$AppStatesTableCreateCompanionBuilder,
          $$AppStatesTableUpdateCompanionBuilder,
          (
            AppStateEntry,
            BaseReferences<_$AppDatabase, $AppStatesTable, AppStateEntry>,
          ),
          AppStateEntry,
          PrefetchHooks Function()
        > {
  $$AppStatesTableTableManager(_$AppDatabase db, $AppStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppStatesCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                Value<String> value = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppStatesCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppStatesTable,
      AppStateEntry,
      $$AppStatesTableFilterComposer,
      $$AppStatesTableOrderingComposer,
      $$AppStatesTableAnnotationComposer,
      $$AppStatesTableCreateCompanionBuilder,
      $$AppStatesTableUpdateCompanionBuilder,
      (
        AppStateEntry,
        BaseReferences<_$AppDatabase, $AppStatesTable, AppStateEntry>,
      ),
      AppStateEntry,
      PrefetchHooks Function()
    >;
typedef $$ErrorLogsTableCreateCompanionBuilder =
    ErrorLogsCompanion Function({
      required String id,
      Value<String> level,
      Value<String> category,
      required String message,
      Value<String?> stack,
      Value<String?> context,
      Value<String?> deviceInfo,
      Value<int> createdAt,
      Value<int> rowid,
    });
typedef $$ErrorLogsTableUpdateCompanionBuilder =
    ErrorLogsCompanion Function({
      Value<String> id,
      Value<String> level,
      Value<String> category,
      Value<String> message,
      Value<String?> stack,
      Value<String?> context,
      Value<String?> deviceInfo,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $$ErrorLogsTableFilterComposer
    extends Composer<_$AppDatabase, $ErrorLogsTable> {
  $$ErrorLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stack => $composableBuilder(
    column: $table.stack,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get context => $composableBuilder(
    column: $table.context,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceInfo => $composableBuilder(
    column: $table.deviceInfo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ErrorLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $ErrorLogsTable> {
  $$ErrorLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stack => $composableBuilder(
    column: $table.stack,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get context => $composableBuilder(
    column: $table.context,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceInfo => $composableBuilder(
    column: $table.deviceInfo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ErrorLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ErrorLogsTable> {
  $$ErrorLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<String> get stack =>
      $composableBuilder(column: $table.stack, builder: (column) => column);

  GeneratedColumn<String> get context =>
      $composableBuilder(column: $table.context, builder: (column) => column);

  GeneratedColumn<String> get deviceInfo => $composableBuilder(
    column: $table.deviceInfo,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ErrorLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ErrorLogsTable,
          ErrorLog,
          $$ErrorLogsTableFilterComposer,
          $$ErrorLogsTableOrderingComposer,
          $$ErrorLogsTableAnnotationComposer,
          $$ErrorLogsTableCreateCompanionBuilder,
          $$ErrorLogsTableUpdateCompanionBuilder,
          (ErrorLog, BaseReferences<_$AppDatabase, $ErrorLogsTable, ErrorLog>),
          ErrorLog,
          PrefetchHooks Function()
        > {
  $$ErrorLogsTableTableManager(_$AppDatabase db, $ErrorLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ErrorLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ErrorLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ErrorLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> level = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> message = const Value.absent(),
                Value<String?> stack = const Value.absent(),
                Value<String?> context = const Value.absent(),
                Value<String?> deviceInfo = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ErrorLogsCompanion(
                id: id,
                level: level,
                category: category,
                message: message,
                stack: stack,
                context: context,
                deviceInfo: deviceInfo,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> level = const Value.absent(),
                Value<String> category = const Value.absent(),
                required String message,
                Value<String?> stack = const Value.absent(),
                Value<String?> context = const Value.absent(),
                Value<String?> deviceInfo = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ErrorLogsCompanion.insert(
                id: id,
                level: level,
                category: category,
                message: message,
                stack: stack,
                context: context,
                deviceInfo: deviceInfo,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ErrorLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ErrorLogsTable,
      ErrorLog,
      $$ErrorLogsTableFilterComposer,
      $$ErrorLogsTableOrderingComposer,
      $$ErrorLogsTableAnnotationComposer,
      $$ErrorLogsTableCreateCompanionBuilder,
      $$ErrorLogsTableUpdateCompanionBuilder,
      (ErrorLog, BaseReferences<_$AppDatabase, $ErrorLogsTable, ErrorLog>),
      ErrorLog,
      PrefetchHooks Function()
    >;
typedef $$AttachedFilesTableCreateCompanionBuilder =
    AttachedFilesCompanion Function({
      required String id,
      required String bookId,
      Value<String> fileName,
      Value<String> fileRole,
      Value<String> mimeType,
      Value<String> content,
      Value<int> byteSize,
      Value<int> sortOrder,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });
typedef $$AttachedFilesTableUpdateCompanionBuilder =
    AttachedFilesCompanion Function({
      Value<String> id,
      Value<String> bookId,
      Value<String> fileName,
      Value<String> fileRole,
      Value<String> mimeType,
      Value<String> content,
      Value<int> byteSize,
      Value<int> sortOrder,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $$AttachedFilesTableReferences
    extends BaseReferences<_$AppDatabase, $AttachedFilesTable, AttachedFile> {
  $$AttachedFilesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ManuscriptsTable _bookIdTable(_$AppDatabase db) =>
      db.manuscripts.createAlias(
        $_aliasNameGenerator(db.attachedFiles.bookId, db.manuscripts.id),
      );

  $$ManuscriptsTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$ManuscriptsTableTableManager(
      $_db,
      $_db.manuscripts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AttachedFilesTableFilterComposer
    extends Composer<_$AppDatabase, $AttachedFilesTable> {
  $$AttachedFilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileRole => $composableBuilder(
    column: $table.fileRole,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ManuscriptsTableFilterComposer get bookId {
    final $$ManuscriptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableFilterComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AttachedFilesTableOrderingComposer
    extends Composer<_$AppDatabase, $AttachedFilesTable> {
  $$AttachedFilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileRole => $composableBuilder(
    column: $table.fileRole,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ManuscriptsTableOrderingComposer get bookId {
    final $$ManuscriptsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableOrderingComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AttachedFilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AttachedFilesTable> {
  $$AttachedFilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get fileRole =>
      $composableBuilder(column: $table.fileRole, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get byteSize =>
      $composableBuilder(column: $table.byteSize, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ManuscriptsTableAnnotationComposer get bookId {
    final $$ManuscriptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableAnnotationComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AttachedFilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AttachedFilesTable,
          AttachedFile,
          $$AttachedFilesTableFilterComposer,
          $$AttachedFilesTableOrderingComposer,
          $$AttachedFilesTableAnnotationComposer,
          $$AttachedFilesTableCreateCompanionBuilder,
          $$AttachedFilesTableUpdateCompanionBuilder,
          (AttachedFile, $$AttachedFilesTableReferences),
          AttachedFile,
          PrefetchHooks Function({bool bookId})
        > {
  $$AttachedFilesTableTableManager(_$AppDatabase db, $AttachedFilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AttachedFilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AttachedFilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AttachedFilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String> fileRole = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<int> byteSize = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AttachedFilesCompanion(
                id: id,
                bookId: bookId,
                fileName: fileName,
                fileRole: fileRole,
                mimeType: mimeType,
                content: content,
                byteSize: byteSize,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String bookId,
                Value<String> fileName = const Value.absent(),
                Value<String> fileRole = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<int> byteSize = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AttachedFilesCompanion.insert(
                id: id,
                bookId: bookId,
                fileName: fileName,
                fileRole: fileRole,
                mimeType: mimeType,
                content: content,
                byteSize: byteSize,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$AttachedFilesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
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
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable: $$AttachedFilesTableReferences
                                    ._bookIdTable(db),
                                referencedColumn: $$AttachedFilesTableReferences
                                    ._bookIdTable(db)
                                    .id,
                              )
                              as T;
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

typedef $$AttachedFilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AttachedFilesTable,
      AttachedFile,
      $$AttachedFilesTableFilterComposer,
      $$AttachedFilesTableOrderingComposer,
      $$AttachedFilesTableAnnotationComposer,
      $$AttachedFilesTableCreateCompanionBuilder,
      $$AttachedFilesTableUpdateCompanionBuilder,
      (AttachedFile, $$AttachedFilesTableReferences),
      AttachedFile,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$TeacherSuggestionsTableCreateCompanionBuilder =
    TeacherSuggestionsCompanion Function({
      required String id,
      required String sessionId,
      required String messageId,
      required String source,
      required String teachingDecision,
      Value<String?> targetSyndromeId,
      Value<String?> targetDimension,
      required String taskType,
      required String taskDescription,
      required String difficulty,
      Value<String> evaluationCriteria,
      Value<String> status,
      Value<int> createdAt,
      Value<int?> resolvedAt,
      Value<int?> adoptedAt,
      Value<int?> dismissedAt,
      Value<int> rowid,
    });
typedef $$TeacherSuggestionsTableUpdateCompanionBuilder =
    TeacherSuggestionsCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<String> messageId,
      Value<String> source,
      Value<String> teachingDecision,
      Value<String?> targetSyndromeId,
      Value<String?> targetDimension,
      Value<String> taskType,
      Value<String> taskDescription,
      Value<String> difficulty,
      Value<String> evaluationCriteria,
      Value<String> status,
      Value<int> createdAt,
      Value<int?> resolvedAt,
      Value<int?> adoptedAt,
      Value<int?> dismissedAt,
      Value<int> rowid,
    });

final class $$TeacherSuggestionsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $TeacherSuggestionsTable,
          TeacherSuggestionRow
        > {
  $$TeacherSuggestionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias(
        $_aliasNameGenerator(db.teacherSuggestions.sessionId, db.sessions.id),
      );

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $MessagesTable _messageIdTable(_$AppDatabase db) =>
      db.messages.createAlias(
        $_aliasNameGenerator(db.teacherSuggestions.messageId, db.messages.id),
      );

  $$MessagesTableProcessedTableManager get messageId {
    final $_column = $_itemColumn<String>('message_id')!;

    final manager = $$MessagesTableTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_messageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TeacherSuggestionsTableFilterComposer
    extends Composer<_$AppDatabase, $TeacherSuggestionsTable> {
  $$TeacherSuggestionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get teachingDecision => $composableBuilder(
    column: $table.teachingDecision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetSyndromeId => $composableBuilder(
    column: $table.targetSyndromeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetDimension => $composableBuilder(
    column: $table.targetDimension,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taskType => $composableBuilder(
    column: $table.taskType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taskDescription => $composableBuilder(
    column: $table.taskDescription,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get evaluationCriteria => $composableBuilder(
    column: $table.evaluationCriteria,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get adoptedAt => $composableBuilder(
    column: $table.adoptedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dismissedAt => $composableBuilder(
    column: $table.dismissedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MessagesTableFilterComposer get messageId {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TeacherSuggestionsTableOrderingComposer
    extends Composer<_$AppDatabase, $TeacherSuggestionsTable> {
  $$TeacherSuggestionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get teachingDecision => $composableBuilder(
    column: $table.teachingDecision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetSyndromeId => $composableBuilder(
    column: $table.targetSyndromeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetDimension => $composableBuilder(
    column: $table.targetDimension,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskType => $composableBuilder(
    column: $table.taskType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskDescription => $composableBuilder(
    column: $table.taskDescription,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get evaluationCriteria => $composableBuilder(
    column: $table.evaluationCriteria,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get adoptedAt => $composableBuilder(
    column: $table.adoptedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dismissedAt => $composableBuilder(
    column: $table.dismissedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MessagesTableOrderingComposer get messageId {
    final $$MessagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableOrderingComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TeacherSuggestionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TeacherSuggestionsTable> {
  $$TeacherSuggestionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get teachingDecision => $composableBuilder(
    column: $table.teachingDecision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetSyndromeId => $composableBuilder(
    column: $table.targetSyndromeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetDimension => $composableBuilder(
    column: $table.targetDimension,
    builder: (column) => column,
  );

  GeneratedColumn<String> get taskType =>
      $composableBuilder(column: $table.taskType, builder: (column) => column);

  GeneratedColumn<String> get taskDescription => $composableBuilder(
    column: $table.taskDescription,
    builder: (column) => column,
  );

  GeneratedColumn<String> get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => column,
  );

  GeneratedColumn<String> get evaluationCriteria => $composableBuilder(
    column: $table.evaluationCriteria,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get adoptedAt =>
      $composableBuilder(column: $table.adoptedAt, builder: (column) => column);

  GeneratedColumn<int> get dismissedAt => $composableBuilder(
    column: $table.dismissedAt,
    builder: (column) => column,
  );

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MessagesTableAnnotationComposer get messageId {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TeacherSuggestionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TeacherSuggestionsTable,
          TeacherSuggestionRow,
          $$TeacherSuggestionsTableFilterComposer,
          $$TeacherSuggestionsTableOrderingComposer,
          $$TeacherSuggestionsTableAnnotationComposer,
          $$TeacherSuggestionsTableCreateCompanionBuilder,
          $$TeacherSuggestionsTableUpdateCompanionBuilder,
          (TeacherSuggestionRow, $$TeacherSuggestionsTableReferences),
          TeacherSuggestionRow,
          PrefetchHooks Function({bool sessionId, bool messageId})
        > {
  $$TeacherSuggestionsTableTableManager(
    _$AppDatabase db,
    $TeacherSuggestionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TeacherSuggestionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TeacherSuggestionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TeacherSuggestionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> teachingDecision = const Value.absent(),
                Value<String?> targetSyndromeId = const Value.absent(),
                Value<String?> targetDimension = const Value.absent(),
                Value<String> taskType = const Value.absent(),
                Value<String> taskDescription = const Value.absent(),
                Value<String> difficulty = const Value.absent(),
                Value<String> evaluationCriteria = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> resolvedAt = const Value.absent(),
                Value<int?> adoptedAt = const Value.absent(),
                Value<int?> dismissedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TeacherSuggestionsCompanion(
                id: id,
                sessionId: sessionId,
                messageId: messageId,
                source: source,
                teachingDecision: teachingDecision,
                targetSyndromeId: targetSyndromeId,
                targetDimension: targetDimension,
                taskType: taskType,
                taskDescription: taskDescription,
                difficulty: difficulty,
                evaluationCriteria: evaluationCriteria,
                status: status,
                createdAt: createdAt,
                resolvedAt: resolvedAt,
                adoptedAt: adoptedAt,
                dismissedAt: dismissedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                required String messageId,
                required String source,
                required String teachingDecision,
                Value<String?> targetSyndromeId = const Value.absent(),
                Value<String?> targetDimension = const Value.absent(),
                required String taskType,
                required String taskDescription,
                required String difficulty,
                Value<String> evaluationCriteria = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> resolvedAt = const Value.absent(),
                Value<int?> adoptedAt = const Value.absent(),
                Value<int?> dismissedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TeacherSuggestionsCompanion.insert(
                id: id,
                sessionId: sessionId,
                messageId: messageId,
                source: source,
                teachingDecision: teachingDecision,
                targetSyndromeId: targetSyndromeId,
                targetDimension: targetDimension,
                taskType: taskType,
                taskDescription: taskDescription,
                difficulty: difficulty,
                evaluationCriteria: evaluationCriteria,
                status: status,
                createdAt: createdAt,
                resolvedAt: resolvedAt,
                adoptedAt: adoptedAt,
                dismissedAt: dismissedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TeacherSuggestionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false, messageId = false}) {
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
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable:
                                    $$TeacherSuggestionsTableReferences
                                        ._sessionIdTable(db),
                                referencedColumn:
                                    $$TeacherSuggestionsTableReferences
                                        ._sessionIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (messageId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.messageId,
                                referencedTable:
                                    $$TeacherSuggestionsTableReferences
                                        ._messageIdTable(db),
                                referencedColumn:
                                    $$TeacherSuggestionsTableReferences
                                        ._messageIdTable(db)
                                        .id,
                              )
                              as T;
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

typedef $$TeacherSuggestionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TeacherSuggestionsTable,
      TeacherSuggestionRow,
      $$TeacherSuggestionsTableFilterComposer,
      $$TeacherSuggestionsTableOrderingComposer,
      $$TeacherSuggestionsTableAnnotationComposer,
      $$TeacherSuggestionsTableCreateCompanionBuilder,
      $$TeacherSuggestionsTableUpdateCompanionBuilder,
      (TeacherSuggestionRow, $$TeacherSuggestionsTableReferences),
      TeacherSuggestionRow,
      PrefetchHooks Function({bool sessionId, bool messageId})
    >;
typedef $$EditorObservationsTableCreateCompanionBuilder =
    EditorObservationsCompanion Function({
      required String id,
      required String sessionId,
      required String messageId,
      required String possibleIntent,
      required String intentConfidence,
      required String observations,
      required String overallImpression,
      Value<String> strengths,
      Value<int> teacherTriggered,
      Value<int> pronouncedCount,
      Value<int> againstCount,
      Value<String?> targetRefType,
      Value<String?> targetRefId,
      Value<int> timestamp,
      Value<int> createdAt,
      Value<int> rowid,
    });
typedef $$EditorObservationsTableUpdateCompanionBuilder =
    EditorObservationsCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<String> messageId,
      Value<String> possibleIntent,
      Value<String> intentConfidence,
      Value<String> observations,
      Value<String> overallImpression,
      Value<String> strengths,
      Value<int> teacherTriggered,
      Value<int> pronouncedCount,
      Value<int> againstCount,
      Value<String?> targetRefType,
      Value<String?> targetRefId,
      Value<int> timestamp,
      Value<int> createdAt,
      Value<int> rowid,
    });

final class $$EditorObservationsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $EditorObservationsTable,
          EditorObservationRow
        > {
  $$EditorObservationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias(
        $_aliasNameGenerator(db.editorObservations.sessionId, db.sessions.id),
      );

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $MessagesTable _messageIdTable(_$AppDatabase db) =>
      db.messages.createAlias(
        $_aliasNameGenerator(db.editorObservations.messageId, db.messages.id),
      );

  $$MessagesTableProcessedTableManager get messageId {
    final $_column = $_itemColumn<String>('message_id')!;

    final manager = $$MessagesTableTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_messageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$EditorObservationsTableFilterComposer
    extends Composer<_$AppDatabase, $EditorObservationsTable> {
  $$EditorObservationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get possibleIntent => $composableBuilder(
    column: $table.possibleIntent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get intentConfidence => $composableBuilder(
    column: $table.intentConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get observations => $composableBuilder(
    column: $table.observations,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get overallImpression => $composableBuilder(
    column: $table.overallImpression,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get strengths => $composableBuilder(
    column: $table.strengths,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get teacherTriggered => $composableBuilder(
    column: $table.teacherTriggered,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pronouncedCount => $composableBuilder(
    column: $table.pronouncedCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get againstCount => $composableBuilder(
    column: $table.againstCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetRefType => $composableBuilder(
    column: $table.targetRefType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetRefId => $composableBuilder(
    column: $table.targetRefId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MessagesTableFilterComposer get messageId {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EditorObservationsTableOrderingComposer
    extends Composer<_$AppDatabase, $EditorObservationsTable> {
  $$EditorObservationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get possibleIntent => $composableBuilder(
    column: $table.possibleIntent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get intentConfidence => $composableBuilder(
    column: $table.intentConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get observations => $composableBuilder(
    column: $table.observations,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get overallImpression => $composableBuilder(
    column: $table.overallImpression,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get strengths => $composableBuilder(
    column: $table.strengths,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get teacherTriggered => $composableBuilder(
    column: $table.teacherTriggered,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pronouncedCount => $composableBuilder(
    column: $table.pronouncedCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get againstCount => $composableBuilder(
    column: $table.againstCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetRefType => $composableBuilder(
    column: $table.targetRefType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetRefId => $composableBuilder(
    column: $table.targetRefId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MessagesTableOrderingComposer get messageId {
    final $$MessagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableOrderingComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EditorObservationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EditorObservationsTable> {
  $$EditorObservationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get possibleIntent => $composableBuilder(
    column: $table.possibleIntent,
    builder: (column) => column,
  );

  GeneratedColumn<String> get intentConfidence => $composableBuilder(
    column: $table.intentConfidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get observations => $composableBuilder(
    column: $table.observations,
    builder: (column) => column,
  );

  GeneratedColumn<String> get overallImpression => $composableBuilder(
    column: $table.overallImpression,
    builder: (column) => column,
  );

  GeneratedColumn<String> get strengths =>
      $composableBuilder(column: $table.strengths, builder: (column) => column);

  GeneratedColumn<int> get teacherTriggered => $composableBuilder(
    column: $table.teacherTriggered,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pronouncedCount => $composableBuilder(
    column: $table.pronouncedCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get againstCount => $composableBuilder(
    column: $table.againstCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetRefType => $composableBuilder(
    column: $table.targetRefType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetRefId => $composableBuilder(
    column: $table.targetRefId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MessagesTableAnnotationComposer get messageId {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EditorObservationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EditorObservationsTable,
          EditorObservationRow,
          $$EditorObservationsTableFilterComposer,
          $$EditorObservationsTableOrderingComposer,
          $$EditorObservationsTableAnnotationComposer,
          $$EditorObservationsTableCreateCompanionBuilder,
          $$EditorObservationsTableUpdateCompanionBuilder,
          (EditorObservationRow, $$EditorObservationsTableReferences),
          EditorObservationRow,
          PrefetchHooks Function({bool sessionId, bool messageId})
        > {
  $$EditorObservationsTableTableManager(
    _$AppDatabase db,
    $EditorObservationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EditorObservationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EditorObservationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EditorObservationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<String> possibleIntent = const Value.absent(),
                Value<String> intentConfidence = const Value.absent(),
                Value<String> observations = const Value.absent(),
                Value<String> overallImpression = const Value.absent(),
                Value<String> strengths = const Value.absent(),
                Value<int> teacherTriggered = const Value.absent(),
                Value<int> pronouncedCount = const Value.absent(),
                Value<int> againstCount = const Value.absent(),
                Value<String?> targetRefType = const Value.absent(),
                Value<String?> targetRefId = const Value.absent(),
                Value<int> timestamp = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EditorObservationsCompanion(
                id: id,
                sessionId: sessionId,
                messageId: messageId,
                possibleIntent: possibleIntent,
                intentConfidence: intentConfidence,
                observations: observations,
                overallImpression: overallImpression,
                strengths: strengths,
                teacherTriggered: teacherTriggered,
                pronouncedCount: pronouncedCount,
                againstCount: againstCount,
                targetRefType: targetRefType,
                targetRefId: targetRefId,
                timestamp: timestamp,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                required String messageId,
                required String possibleIntent,
                required String intentConfidence,
                required String observations,
                required String overallImpression,
                Value<String> strengths = const Value.absent(),
                Value<int> teacherTriggered = const Value.absent(),
                Value<int> pronouncedCount = const Value.absent(),
                Value<int> againstCount = const Value.absent(),
                Value<String?> targetRefType = const Value.absent(),
                Value<String?> targetRefId = const Value.absent(),
                Value<int> timestamp = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EditorObservationsCompanion.insert(
                id: id,
                sessionId: sessionId,
                messageId: messageId,
                possibleIntent: possibleIntent,
                intentConfidence: intentConfidence,
                observations: observations,
                overallImpression: overallImpression,
                strengths: strengths,
                teacherTriggered: teacherTriggered,
                pronouncedCount: pronouncedCount,
                againstCount: againstCount,
                targetRefType: targetRefType,
                targetRefId: targetRefId,
                timestamp: timestamp,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EditorObservationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false, messageId = false}) {
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
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable:
                                    $$EditorObservationsTableReferences
                                        ._sessionIdTable(db),
                                referencedColumn:
                                    $$EditorObservationsTableReferences
                                        ._sessionIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (messageId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.messageId,
                                referencedTable:
                                    $$EditorObservationsTableReferences
                                        ._messageIdTable(db),
                                referencedColumn:
                                    $$EditorObservationsTableReferences
                                        ._messageIdTable(db)
                                        .id,
                              )
                              as T;
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

typedef $$EditorObservationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EditorObservationsTable,
      EditorObservationRow,
      $$EditorObservationsTableFilterComposer,
      $$EditorObservationsTableOrderingComposer,
      $$EditorObservationsTableAnnotationComposer,
      $$EditorObservationsTableCreateCompanionBuilder,
      $$EditorObservationsTableUpdateCompanionBuilder,
      (EditorObservationRow, $$EditorObservationsTableReferences),
      EditorObservationRow,
      PrefetchHooks Function({bool sessionId, bool messageId})
    >;
typedef $$CharacterFactsTableCreateCompanionBuilder =
    CharacterFactsCompanion Function({
      required String id,
      required String manuscriptId,
      required String name,
      Value<int?> firstSeenChapter,
      Value<int?> firstSeenAt,
      Value<String> assertions,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });
typedef $$CharacterFactsTableUpdateCompanionBuilder =
    CharacterFactsCompanion Function({
      Value<String> id,
      Value<String> manuscriptId,
      Value<String> name,
      Value<int?> firstSeenChapter,
      Value<int?> firstSeenAt,
      Value<String> assertions,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $$CharacterFactsTableReferences
    extends BaseReferences<_$AppDatabase, $CharacterFactsTable, CharacterFact> {
  $$CharacterFactsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ManuscriptsTable _manuscriptIdTable(_$AppDatabase db) =>
      db.manuscripts.createAlias(
        $_aliasNameGenerator(db.characterFacts.manuscriptId, db.manuscripts.id),
      );

  $$ManuscriptsTableProcessedTableManager get manuscriptId {
    final $_column = $_itemColumn<String>('manuscript_id')!;

    final manager = $$ManuscriptsTableTableManager(
      $_db,
      $_db.manuscripts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_manuscriptIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CharacterFactsTableFilterComposer
    extends Composer<_$AppDatabase, $CharacterFactsTable> {
  $$CharacterFactsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get firstSeenChapter => $composableBuilder(
    column: $table.firstSeenChapter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get firstSeenAt => $composableBuilder(
    column: $table.firstSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assertions => $composableBuilder(
    column: $table.assertions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ManuscriptsTableFilterComposer get manuscriptId {
    final $$ManuscriptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableFilterComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CharacterFactsTableOrderingComposer
    extends Composer<_$AppDatabase, $CharacterFactsTable> {
  $$CharacterFactsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get firstSeenChapter => $composableBuilder(
    column: $table.firstSeenChapter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get firstSeenAt => $composableBuilder(
    column: $table.firstSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assertions => $composableBuilder(
    column: $table.assertions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ManuscriptsTableOrderingComposer get manuscriptId {
    final $$ManuscriptsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableOrderingComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CharacterFactsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CharacterFactsTable> {
  $$CharacterFactsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get firstSeenChapter => $composableBuilder(
    column: $table.firstSeenChapter,
    builder: (column) => column,
  );

  GeneratedColumn<int> get firstSeenAt => $composableBuilder(
    column: $table.firstSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get assertions => $composableBuilder(
    column: $table.assertions,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ManuscriptsTableAnnotationComposer get manuscriptId {
    final $$ManuscriptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableAnnotationComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CharacterFactsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CharacterFactsTable,
          CharacterFact,
          $$CharacterFactsTableFilterComposer,
          $$CharacterFactsTableOrderingComposer,
          $$CharacterFactsTableAnnotationComposer,
          $$CharacterFactsTableCreateCompanionBuilder,
          $$CharacterFactsTableUpdateCompanionBuilder,
          (CharacterFact, $$CharacterFactsTableReferences),
          CharacterFact,
          PrefetchHooks Function({bool manuscriptId})
        > {
  $$CharacterFactsTableTableManager(
    _$AppDatabase db,
    $CharacterFactsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CharacterFactsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CharacterFactsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CharacterFactsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> manuscriptId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int?> firstSeenChapter = const Value.absent(),
                Value<int?> firstSeenAt = const Value.absent(),
                Value<String> assertions = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CharacterFactsCompanion(
                id: id,
                manuscriptId: manuscriptId,
                name: name,
                firstSeenChapter: firstSeenChapter,
                firstSeenAt: firstSeenAt,
                assertions: assertions,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String manuscriptId,
                required String name,
                Value<int?> firstSeenChapter = const Value.absent(),
                Value<int?> firstSeenAt = const Value.absent(),
                Value<String> assertions = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CharacterFactsCompanion.insert(
                id: id,
                manuscriptId: manuscriptId,
                name: name,
                firstSeenChapter: firstSeenChapter,
                firstSeenAt: firstSeenAt,
                assertions: assertions,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CharacterFactsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({manuscriptId = false}) {
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
                    if (manuscriptId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.manuscriptId,
                                referencedTable: $$CharacterFactsTableReferences
                                    ._manuscriptIdTable(db),
                                referencedColumn:
                                    $$CharacterFactsTableReferences
                                        ._manuscriptIdTable(db)
                                        .id,
                              )
                              as T;
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

typedef $$CharacterFactsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CharacterFactsTable,
      CharacterFact,
      $$CharacterFactsTableFilterComposer,
      $$CharacterFactsTableOrderingComposer,
      $$CharacterFactsTableAnnotationComposer,
      $$CharacterFactsTableCreateCompanionBuilder,
      $$CharacterFactsTableUpdateCompanionBuilder,
      (CharacterFact, $$CharacterFactsTableReferences),
      CharacterFact,
      PrefetchHooks Function({bool manuscriptId})
    >;
typedef $$EventFactsTableCreateCompanionBuilder =
    EventFactsCompanion Function({
      required String id,
      required String manuscriptId,
      required String name,
      Value<int?> chapter,
      required String eventType,
      Value<String?> causeEventId,
      Value<String?> effectEventId,
      Value<String> participants,
      Value<String> description,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });
typedef $$EventFactsTableUpdateCompanionBuilder =
    EventFactsCompanion Function({
      Value<String> id,
      Value<String> manuscriptId,
      Value<String> name,
      Value<int?> chapter,
      Value<String> eventType,
      Value<String?> causeEventId,
      Value<String?> effectEventId,
      Value<String> participants,
      Value<String> description,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $$EventFactsTableReferences
    extends BaseReferences<_$AppDatabase, $EventFactsTable, EventFact> {
  $$EventFactsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ManuscriptsTable _manuscriptIdTable(_$AppDatabase db) =>
      db.manuscripts.createAlias(
        $_aliasNameGenerator(db.eventFacts.manuscriptId, db.manuscripts.id),
      );

  $$ManuscriptsTableProcessedTableManager get manuscriptId {
    final $_column = $_itemColumn<String>('manuscript_id')!;

    final manager = $$ManuscriptsTableTableManager(
      $_db,
      $_db.manuscripts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_manuscriptIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$EventFactsTableFilterComposer
    extends Composer<_$AppDatabase, $EventFactsTable> {
  $$EventFactsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapter => $composableBuilder(
    column: $table.chapter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get causeEventId => $composableBuilder(
    column: $table.causeEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get effectEventId => $composableBuilder(
    column: $table.effectEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get participants => $composableBuilder(
    column: $table.participants,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ManuscriptsTableFilterComposer get manuscriptId {
    final $$ManuscriptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableFilterComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EventFactsTableOrderingComposer
    extends Composer<_$AppDatabase, $EventFactsTable> {
  $$EventFactsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapter => $composableBuilder(
    column: $table.chapter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get causeEventId => $composableBuilder(
    column: $table.causeEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get effectEventId => $composableBuilder(
    column: $table.effectEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get participants => $composableBuilder(
    column: $table.participants,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ManuscriptsTableOrderingComposer get manuscriptId {
    final $$ManuscriptsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableOrderingComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EventFactsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EventFactsTable> {
  $$EventFactsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get chapter =>
      $composableBuilder(column: $table.chapter, builder: (column) => column);

  GeneratedColumn<String> get eventType =>
      $composableBuilder(column: $table.eventType, builder: (column) => column);

  GeneratedColumn<String> get causeEventId => $composableBuilder(
    column: $table.causeEventId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get effectEventId => $composableBuilder(
    column: $table.effectEventId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get participants => $composableBuilder(
    column: $table.participants,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ManuscriptsTableAnnotationComposer get manuscriptId {
    final $$ManuscriptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableAnnotationComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EventFactsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EventFactsTable,
          EventFact,
          $$EventFactsTableFilterComposer,
          $$EventFactsTableOrderingComposer,
          $$EventFactsTableAnnotationComposer,
          $$EventFactsTableCreateCompanionBuilder,
          $$EventFactsTableUpdateCompanionBuilder,
          (EventFact, $$EventFactsTableReferences),
          EventFact,
          PrefetchHooks Function({bool manuscriptId})
        > {
  $$EventFactsTableTableManager(_$AppDatabase db, $EventFactsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventFactsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventFactsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EventFactsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> manuscriptId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int?> chapter = const Value.absent(),
                Value<String> eventType = const Value.absent(),
                Value<String?> causeEventId = const Value.absent(),
                Value<String?> effectEventId = const Value.absent(),
                Value<String> participants = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EventFactsCompanion(
                id: id,
                manuscriptId: manuscriptId,
                name: name,
                chapter: chapter,
                eventType: eventType,
                causeEventId: causeEventId,
                effectEventId: effectEventId,
                participants: participants,
                description: description,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String manuscriptId,
                required String name,
                Value<int?> chapter = const Value.absent(),
                required String eventType,
                Value<String?> causeEventId = const Value.absent(),
                Value<String?> effectEventId = const Value.absent(),
                Value<String> participants = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EventFactsCompanion.insert(
                id: id,
                manuscriptId: manuscriptId,
                name: name,
                chapter: chapter,
                eventType: eventType,
                causeEventId: causeEventId,
                effectEventId: effectEventId,
                participants: participants,
                description: description,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EventFactsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({manuscriptId = false}) {
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
                    if (manuscriptId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.manuscriptId,
                                referencedTable: $$EventFactsTableReferences
                                    ._manuscriptIdTable(db),
                                referencedColumn: $$EventFactsTableReferences
                                    ._manuscriptIdTable(db)
                                    .id,
                              )
                              as T;
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

typedef $$EventFactsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EventFactsTable,
      EventFact,
      $$EventFactsTableFilterComposer,
      $$EventFactsTableOrderingComposer,
      $$EventFactsTableAnnotationComposer,
      $$EventFactsTableCreateCompanionBuilder,
      $$EventFactsTableUpdateCompanionBuilder,
      (EventFact, $$EventFactsTableReferences),
      EventFact,
      PrefetchHooks Function({bool manuscriptId})
    >;
typedef $$SubplotFactsTableCreateCompanionBuilder =
    SubplotFactsCompanion Function({
      required String id,
      required String manuscriptId,
      required String name,
      Value<int?> introducedChapter,
      Value<int?> resolvedChapter,
      Value<int?> resolvedAt,
      Value<String> description,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });
typedef $$SubplotFactsTableUpdateCompanionBuilder =
    SubplotFactsCompanion Function({
      Value<String> id,
      Value<String> manuscriptId,
      Value<String> name,
      Value<int?> introducedChapter,
      Value<int?> resolvedChapter,
      Value<int?> resolvedAt,
      Value<String> description,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $$SubplotFactsTableReferences
    extends BaseReferences<_$AppDatabase, $SubplotFactsTable, SubplotFact> {
  $$SubplotFactsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ManuscriptsTable _manuscriptIdTable(_$AppDatabase db) =>
      db.manuscripts.createAlias(
        $_aliasNameGenerator(db.subplotFacts.manuscriptId, db.manuscripts.id),
      );

  $$ManuscriptsTableProcessedTableManager get manuscriptId {
    final $_column = $_itemColumn<String>('manuscript_id')!;

    final manager = $$ManuscriptsTableTableManager(
      $_db,
      $_db.manuscripts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_manuscriptIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SubplotFactsTableFilterComposer
    extends Composer<_$AppDatabase, $SubplotFactsTable> {
  $$SubplotFactsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get introducedChapter => $composableBuilder(
    column: $table.introducedChapter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get resolvedChapter => $composableBuilder(
    column: $table.resolvedChapter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ManuscriptsTableFilterComposer get manuscriptId {
    final $$ManuscriptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableFilterComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SubplotFactsTableOrderingComposer
    extends Composer<_$AppDatabase, $SubplotFactsTable> {
  $$SubplotFactsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get introducedChapter => $composableBuilder(
    column: $table.introducedChapter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get resolvedChapter => $composableBuilder(
    column: $table.resolvedChapter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ManuscriptsTableOrderingComposer get manuscriptId {
    final $$ManuscriptsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableOrderingComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SubplotFactsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SubplotFactsTable> {
  $$SubplotFactsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get introducedChapter => $composableBuilder(
    column: $table.introducedChapter,
    builder: (column) => column,
  );

  GeneratedColumn<int> get resolvedChapter => $composableBuilder(
    column: $table.resolvedChapter,
    builder: (column) => column,
  );

  GeneratedColumn<int> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ManuscriptsTableAnnotationComposer get manuscriptId {
    final $$ManuscriptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableAnnotationComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SubplotFactsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SubplotFactsTable,
          SubplotFact,
          $$SubplotFactsTableFilterComposer,
          $$SubplotFactsTableOrderingComposer,
          $$SubplotFactsTableAnnotationComposer,
          $$SubplotFactsTableCreateCompanionBuilder,
          $$SubplotFactsTableUpdateCompanionBuilder,
          (SubplotFact, $$SubplotFactsTableReferences),
          SubplotFact,
          PrefetchHooks Function({bool manuscriptId})
        > {
  $$SubplotFactsTableTableManager(_$AppDatabase db, $SubplotFactsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SubplotFactsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SubplotFactsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SubplotFactsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> manuscriptId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int?> introducedChapter = const Value.absent(),
                Value<int?> resolvedChapter = const Value.absent(),
                Value<int?> resolvedAt = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SubplotFactsCompanion(
                id: id,
                manuscriptId: manuscriptId,
                name: name,
                introducedChapter: introducedChapter,
                resolvedChapter: resolvedChapter,
                resolvedAt: resolvedAt,
                description: description,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String manuscriptId,
                required String name,
                Value<int?> introducedChapter = const Value.absent(),
                Value<int?> resolvedChapter = const Value.absent(),
                Value<int?> resolvedAt = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SubplotFactsCompanion.insert(
                id: id,
                manuscriptId: manuscriptId,
                name: name,
                introducedChapter: introducedChapter,
                resolvedChapter: resolvedChapter,
                resolvedAt: resolvedAt,
                description: description,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SubplotFactsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({manuscriptId = false}) {
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
                    if (manuscriptId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.manuscriptId,
                                referencedTable: $$SubplotFactsTableReferences
                                    ._manuscriptIdTable(db),
                                referencedColumn: $$SubplotFactsTableReferences
                                    ._manuscriptIdTable(db)
                                    .id,
                              )
                              as T;
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

typedef $$SubplotFactsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SubplotFactsTable,
      SubplotFact,
      $$SubplotFactsTableFilterComposer,
      $$SubplotFactsTableOrderingComposer,
      $$SubplotFactsTableAnnotationComposer,
      $$SubplotFactsTableCreateCompanionBuilder,
      $$SubplotFactsTableUpdateCompanionBuilder,
      (SubplotFact, $$SubplotFactsTableReferences),
      SubplotFact,
      PrefetchHooks Function({bool manuscriptId})
    >;
typedef $$OutlineEntitiesTableCreateCompanionBuilder =
    OutlineEntitiesCompanion Function({
      required String id,
      required String manuscriptId,
      required String entityType,
      required String entityKey,
      Value<String> aliases,
      Value<String> status,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });
typedef $$OutlineEntitiesTableUpdateCompanionBuilder =
    OutlineEntitiesCompanion Function({
      Value<String> id,
      Value<String> manuscriptId,
      Value<String> entityType,
      Value<String> entityKey,
      Value<String> aliases,
      Value<String> status,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $$OutlineEntitiesTableReferences
    extends
        BaseReferences<_$AppDatabase, $OutlineEntitiesTable, OutlineEntity> {
  $$OutlineEntitiesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ManuscriptsTable _manuscriptIdTable(_$AppDatabase db) =>
      db.manuscripts.createAlias(
        $_aliasNameGenerator(
          db.outlineEntities.manuscriptId,
          db.manuscripts.id,
        ),
      );

  $$ManuscriptsTableProcessedTableManager get manuscriptId {
    final $_column = $_itemColumn<String>('manuscript_id')!;

    final manager = $$ManuscriptsTableTableManager(
      $_db,
      $_db.manuscripts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_manuscriptIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$OutlineImpressionsTable, List<OutlineImpression>>
  _outlineImpressionsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.outlineImpressions,
        aliasName: $_aliasNameGenerator(
          db.outlineEntities.id,
          db.outlineImpressions.entityId,
        ),
      );

  $$OutlineImpressionsTableProcessedTableManager get outlineImpressionsRefs {
    final manager = $$OutlineImpressionsTableTableManager(
      $_db,
      $_db.outlineImpressions,
    ).filter((f) => f.entityId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _outlineImpressionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$OutlineEntitiesTableFilterComposer
    extends Composer<_$AppDatabase, $OutlineEntitiesTable> {
  $$OutlineEntitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityKey => $composableBuilder(
    column: $table.entityKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aliases => $composableBuilder(
    column: $table.aliases,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ManuscriptsTableFilterComposer get manuscriptId {
    final $$ManuscriptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableFilterComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> outlineImpressionsRefs(
    Expression<bool> Function($$OutlineImpressionsTableFilterComposer f) f,
  ) {
    final $$OutlineImpressionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.outlineImpressions,
      getReferencedColumn: (t) => t.entityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutlineImpressionsTableFilterComposer(
            $db: $db,
            $table: $db.outlineImpressions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$OutlineEntitiesTableOrderingComposer
    extends Composer<_$AppDatabase, $OutlineEntitiesTable> {
  $$OutlineEntitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityKey => $composableBuilder(
    column: $table.entityKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aliases => $composableBuilder(
    column: $table.aliases,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ManuscriptsTableOrderingComposer get manuscriptId {
    final $$ManuscriptsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableOrderingComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutlineEntitiesTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutlineEntitiesTable> {
  $$OutlineEntitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityKey =>
      $composableBuilder(column: $table.entityKey, builder: (column) => column);

  GeneratedColumn<String> get aliases =>
      $composableBuilder(column: $table.aliases, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ManuscriptsTableAnnotationComposer get manuscriptId {
    final $$ManuscriptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manuscriptId,
      referencedTable: $db.manuscripts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManuscriptsTableAnnotationComposer(
            $db: $db,
            $table: $db.manuscripts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> outlineImpressionsRefs<T extends Object>(
    Expression<T> Function($$OutlineImpressionsTableAnnotationComposer a) f,
  ) {
    final $$OutlineImpressionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.outlineImpressions,
          getReferencedColumn: (t) => t.entityId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$OutlineImpressionsTableAnnotationComposer(
                $db: $db,
                $table: $db.outlineImpressions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$OutlineEntitiesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutlineEntitiesTable,
          OutlineEntity,
          $$OutlineEntitiesTableFilterComposer,
          $$OutlineEntitiesTableOrderingComposer,
          $$OutlineEntitiesTableAnnotationComposer,
          $$OutlineEntitiesTableCreateCompanionBuilder,
          $$OutlineEntitiesTableUpdateCompanionBuilder,
          (OutlineEntity, $$OutlineEntitiesTableReferences),
          OutlineEntity,
          PrefetchHooks Function({
            bool manuscriptId,
            bool outlineImpressionsRefs,
          })
        > {
  $$OutlineEntitiesTableTableManager(
    _$AppDatabase db,
    $OutlineEntitiesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutlineEntitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutlineEntitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutlineEntitiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> manuscriptId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityKey = const Value.absent(),
                Value<String> aliases = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutlineEntitiesCompanion(
                id: id,
                manuscriptId: manuscriptId,
                entityType: entityType,
                entityKey: entityKey,
                aliases: aliases,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String manuscriptId,
                required String entityType,
                required String entityKey,
                Value<String> aliases = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutlineEntitiesCompanion.insert(
                id: id,
                manuscriptId: manuscriptId,
                entityType: entityType,
                entityKey: entityKey,
                aliases: aliases,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$OutlineEntitiesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({manuscriptId = false, outlineImpressionsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (outlineImpressionsRefs) db.outlineImpressions,
                  ],
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
                        if (manuscriptId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.manuscriptId,
                                    referencedTable:
                                        $$OutlineEntitiesTableReferences
                                            ._manuscriptIdTable(db),
                                    referencedColumn:
                                        $$OutlineEntitiesTableReferences
                                            ._manuscriptIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (outlineImpressionsRefs)
                        await $_getPrefetchedData<
                          OutlineEntity,
                          $OutlineEntitiesTable,
                          OutlineImpression
                        >(
                          currentTable: table,
                          referencedTable: $$OutlineEntitiesTableReferences
                              ._outlineImpressionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$OutlineEntitiesTableReferences(
                                db,
                                table,
                                p0,
                              ).outlineImpressionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.entityId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$OutlineEntitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutlineEntitiesTable,
      OutlineEntity,
      $$OutlineEntitiesTableFilterComposer,
      $$OutlineEntitiesTableOrderingComposer,
      $$OutlineEntitiesTableAnnotationComposer,
      $$OutlineEntitiesTableCreateCompanionBuilder,
      $$OutlineEntitiesTableUpdateCompanionBuilder,
      (OutlineEntity, $$OutlineEntitiesTableReferences),
      OutlineEntity,
      PrefetchHooks Function({bool manuscriptId, bool outlineImpressionsRefs})
    >;
typedef $$OutlineImpressionsTableCreateCompanionBuilder =
    OutlineImpressionsCompanion Function({
      required String id,
      required String entityId,
      required String impression,
      Value<String?> sourceChapterId,
      Value<int?> sourceChapterNo,
      Value<int> version,
      Value<String?> conflictWith,
      Value<String> status,
      Value<int> createdAt,
      Value<int> rowid,
    });
typedef $$OutlineImpressionsTableUpdateCompanionBuilder =
    OutlineImpressionsCompanion Function({
      Value<String> id,
      Value<String> entityId,
      Value<String> impression,
      Value<String?> sourceChapterId,
      Value<int?> sourceChapterNo,
      Value<int> version,
      Value<String?> conflictWith,
      Value<String> status,
      Value<int> createdAt,
      Value<int> rowid,
    });

final class $$OutlineImpressionsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $OutlineImpressionsTable,
          OutlineImpression
        > {
  $$OutlineImpressionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $OutlineEntitiesTable _entityIdTable(_$AppDatabase db) =>
      db.outlineEntities.createAlias(
        $_aliasNameGenerator(
          db.outlineImpressions.entityId,
          db.outlineEntities.id,
        ),
      );

  $$OutlineEntitiesTableProcessedTableManager get entityId {
    final $_column = $_itemColumn<String>('entity_id')!;

    final manager = $$OutlineEntitiesTableTableManager(
      $_db,
      $_db.outlineEntities,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_entityIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$OutlineImpressionsTableFilterComposer
    extends Composer<_$AppDatabase, $OutlineImpressionsTable> {
  $$OutlineImpressionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get impression => $composableBuilder(
    column: $table.impression,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceChapterId => $composableBuilder(
    column: $table.sourceChapterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sourceChapterNo => $composableBuilder(
    column: $table.sourceChapterNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conflictWith => $composableBuilder(
    column: $table.conflictWith,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$OutlineEntitiesTableFilterComposer get entityId {
    final $$OutlineEntitiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entityId,
      referencedTable: $db.outlineEntities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutlineEntitiesTableFilterComposer(
            $db: $db,
            $table: $db.outlineEntities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutlineImpressionsTableOrderingComposer
    extends Composer<_$AppDatabase, $OutlineImpressionsTable> {
  $$OutlineImpressionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get impression => $composableBuilder(
    column: $table.impression,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceChapterId => $composableBuilder(
    column: $table.sourceChapterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourceChapterNo => $composableBuilder(
    column: $table.sourceChapterNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conflictWith => $composableBuilder(
    column: $table.conflictWith,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$OutlineEntitiesTableOrderingComposer get entityId {
    final $$OutlineEntitiesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entityId,
      referencedTable: $db.outlineEntities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutlineEntitiesTableOrderingComposer(
            $db: $db,
            $table: $db.outlineEntities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutlineImpressionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutlineImpressionsTable> {
  $$OutlineImpressionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get impression => $composableBuilder(
    column: $table.impression,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceChapterId => $composableBuilder(
    column: $table.sourceChapterId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sourceChapterNo => $composableBuilder(
    column: $table.sourceChapterNo,
    builder: (column) => column,
  );

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get conflictWith => $composableBuilder(
    column: $table.conflictWith,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$OutlineEntitiesTableAnnotationComposer get entityId {
    final $$OutlineEntitiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entityId,
      referencedTable: $db.outlineEntities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutlineEntitiesTableAnnotationComposer(
            $db: $db,
            $table: $db.outlineEntities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutlineImpressionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutlineImpressionsTable,
          OutlineImpression,
          $$OutlineImpressionsTableFilterComposer,
          $$OutlineImpressionsTableOrderingComposer,
          $$OutlineImpressionsTableAnnotationComposer,
          $$OutlineImpressionsTableCreateCompanionBuilder,
          $$OutlineImpressionsTableUpdateCompanionBuilder,
          (OutlineImpression, $$OutlineImpressionsTableReferences),
          OutlineImpression,
          PrefetchHooks Function({bool entityId})
        > {
  $$OutlineImpressionsTableTableManager(
    _$AppDatabase db,
    $OutlineImpressionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutlineImpressionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutlineImpressionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutlineImpressionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> impression = const Value.absent(),
                Value<String?> sourceChapterId = const Value.absent(),
                Value<int?> sourceChapterNo = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String?> conflictWith = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutlineImpressionsCompanion(
                id: id,
                entityId: entityId,
                impression: impression,
                sourceChapterId: sourceChapterId,
                sourceChapterNo: sourceChapterNo,
                version: version,
                conflictWith: conflictWith,
                status: status,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String entityId,
                required String impression,
                Value<String?> sourceChapterId = const Value.absent(),
                Value<int?> sourceChapterNo = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String?> conflictWith = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutlineImpressionsCompanion.insert(
                id: id,
                entityId: entityId,
                impression: impression,
                sourceChapterId: sourceChapterId,
                sourceChapterNo: sourceChapterNo,
                version: version,
                conflictWith: conflictWith,
                status: status,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$OutlineImpressionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({entityId = false}) {
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
                    if (entityId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.entityId,
                                referencedTable:
                                    $$OutlineImpressionsTableReferences
                                        ._entityIdTable(db),
                                referencedColumn:
                                    $$OutlineImpressionsTableReferences
                                        ._entityIdTable(db)
                                        .id,
                              )
                              as T;
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

typedef $$OutlineImpressionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutlineImpressionsTable,
      OutlineImpression,
      $$OutlineImpressionsTableFilterComposer,
      $$OutlineImpressionsTableOrderingComposer,
      $$OutlineImpressionsTableAnnotationComposer,
      $$OutlineImpressionsTableCreateCompanionBuilder,
      $$OutlineImpressionsTableUpdateCompanionBuilder,
      (OutlineImpression, $$OutlineImpressionsTableReferences),
      OutlineImpression,
      PrefetchHooks Function({bool entityId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ManuscriptsTableTableManager get manuscripts =>
      $$ManuscriptsTableTableManager(_db, _db.manuscripts);
  $$VolumesTableTableManager get volumes =>
      $$VolumesTableTableManager(_db, _db.volumes);
  $$ChaptersTableTableManager get chapters =>
      $$ChaptersTableTableManager(_db, _db.chapters);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$DiagnosisResultsTableTableManager get diagnosisResults =>
      $$DiagnosisResultsTableTableManager(_db, _db.diagnosisResults);
  $$TeachingStateTableTableManager get teachingState =>
      $$TeachingStateTableTableManager(_db, _db.teachingState);
  $$ActiveProblemsTableTableManager get activeProblems =>
      $$ActiveProblemsTableTableManager(_db, _db.activeProblems);
  $$StudentModelsTableTableManager get studentModels =>
      $$StudentModelsTableTableManager(_db, _db.studentModels);
  $$SessionReferencesTableTableManager get sessionReferences =>
      $$SessionReferencesTableTableManager(_db, _db.sessionReferences);
  $$AppStatesTableTableManager get appStates =>
      $$AppStatesTableTableManager(_db, _db.appStates);
  $$ErrorLogsTableTableManager get errorLogs =>
      $$ErrorLogsTableTableManager(_db, _db.errorLogs);
  $$AttachedFilesTableTableManager get attachedFiles =>
      $$AttachedFilesTableTableManager(_db, _db.attachedFiles);
  $$TeacherSuggestionsTableTableManager get teacherSuggestions =>
      $$TeacherSuggestionsTableTableManager(_db, _db.teacherSuggestions);
  $$EditorObservationsTableTableManager get editorObservations =>
      $$EditorObservationsTableTableManager(_db, _db.editorObservations);
  $$CharacterFactsTableTableManager get characterFacts =>
      $$CharacterFactsTableTableManager(_db, _db.characterFacts);
  $$EventFactsTableTableManager get eventFacts =>
      $$EventFactsTableTableManager(_db, _db.eventFacts);
  $$SubplotFactsTableTableManager get subplotFacts =>
      $$SubplotFactsTableTableManager(_db, _db.subplotFacts);
  $$OutlineEntitiesTableTableManager get outlineEntities =>
      $$OutlineEntitiesTableTableManager(_db, _db.outlineEntities);
  $$OutlineImpressionsTableTableManager get outlineImpressions =>
      $$OutlineImpressionsTableTableManager(_db, _db.outlineImpressions);
}
