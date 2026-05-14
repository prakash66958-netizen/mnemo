// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'habit.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetHabitCollection on Isar {
  IsarCollection<Habit> get habits => this.collection();
}

const HabitSchema = CollectionSchema(
  name: r'Habit',
  id: 3896650575830519340,
  properties: {
    r'archived': PropertySchema(
      id: 0,
      name: r'archived',
      type: IsarType.bool,
    ),
    r'cloudId': PropertySchema(
      id: 1,
      name: r'cloudId',
      type: IsarType.string,
    ),
    r'colorValue': PropertySchema(
      id: 2,
      name: r'colorValue',
      type: IsarType.long,
    ),
    r'createdAt': PropertySchema(
      id: 3,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'deletedAt': PropertySchema(
      id: 4,
      name: r'deletedAt',
      type: IsarType.dateTime,
    ),
    r'emoji': PropertySchema(
      id: 5,
      name: r'emoji',
      type: IsarType.string,
    ),
    r'intervalEndHour': PropertySchema(
      id: 6,
      name: r'intervalEndHour',
      type: IsarType.long,
    ),
    r'intervalMinutes': PropertySchema(
      id: 7,
      name: r'intervalMinutes',
      type: IsarType.long,
    ),
    r'name': PropertySchema(
      id: 8,
      name: r'name',
      type: IsarType.string,
    ),
    r'notificationId': PropertySchema(
      id: 9,
      name: r'notificationId',
      type: IsarType.long,
    ),
    r'remindHour': PropertySchema(
      id: 10,
      name: r'remindHour',
      type: IsarType.long,
    ),
    r'remindMinute': PropertySchema(
      id: 11,
      name: r'remindMinute',
      type: IsarType.long,
    ),
    r'targetUnit': PropertySchema(
      id: 12,
      name: r'targetUnit',
      type: IsarType.string,
    ),
    r'targetValue': PropertySchema(
      id: 13,
      name: r'targetValue',
      type: IsarType.double,
    ),
    r'updatedAt': PropertySchema(
      id: 14,
      name: r'updatedAt',
      type: IsarType.dateTime,
    )
  },
  estimateSize: _habitEstimateSize,
  serialize: _habitSerialize,
  deserialize: _habitDeserialize,
  deserializeProp: _habitDeserializeProp,
  idName: r'id',
  indexes: {
    r'cloudId': IndexSchema(
      id: -1631172865471370506,
      name: r'cloudId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'cloudId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'archived': IndexSchema(
      id: 1684088774236579907,
      name: r'archived',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'archived',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _habitGetId,
  getLinks: _habitGetLinks,
  attach: _habitAttach,
  version: '3.1.0+1',
);

int _habitEstimateSize(
  Habit object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.cloudId.length * 3;
  {
    final value = object.emoji;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.name.length * 3;
  {
    final value = object.targetUnit;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _habitSerialize(
  Habit object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeBool(offsets[0], object.archived);
  writer.writeString(offsets[1], object.cloudId);
  writer.writeLong(offsets[2], object.colorValue);
  writer.writeDateTime(offsets[3], object.createdAt);
  writer.writeDateTime(offsets[4], object.deletedAt);
  writer.writeString(offsets[5], object.emoji);
  writer.writeLong(offsets[6], object.intervalEndHour);
  writer.writeLong(offsets[7], object.intervalMinutes);
  writer.writeString(offsets[8], object.name);
  writer.writeLong(offsets[9], object.notificationId);
  writer.writeLong(offsets[10], object.remindHour);
  writer.writeLong(offsets[11], object.remindMinute);
  writer.writeString(offsets[12], object.targetUnit);
  writer.writeDouble(offsets[13], object.targetValue);
  writer.writeDateTime(offsets[14], object.updatedAt);
}

Habit _habitDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = Habit();
  object.archived = reader.readBool(offsets[0]);
  object.cloudId = reader.readString(offsets[1]);
  object.colorValue = reader.readLong(offsets[2]);
  object.createdAt = reader.readDateTime(offsets[3]);
  object.deletedAt = reader.readDateTimeOrNull(offsets[4]);
  object.emoji = reader.readStringOrNull(offsets[5]);
  object.id = id;
  object.intervalEndHour = reader.readLong(offsets[6]);
  object.intervalMinutes = reader.readLong(offsets[7]);
  object.name = reader.readString(offsets[8]);
  object.notificationId = reader.readLong(offsets[9]);
  object.remindHour = reader.readLongOrNull(offsets[10]);
  object.remindMinute = reader.readLongOrNull(offsets[11]);
  object.targetUnit = reader.readStringOrNull(offsets[12]);
  object.targetValue = reader.readDoubleOrNull(offsets[13]);
  object.updatedAt = reader.readDateTime(offsets[14]);
  return object;
}

P _habitDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readBool(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readDateTime(offset)) as P;
    case 4:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 5:
      return (reader.readStringOrNull(offset)) as P;
    case 6:
      return (reader.readLong(offset)) as P;
    case 7:
      return (reader.readLong(offset)) as P;
    case 8:
      return (reader.readString(offset)) as P;
    case 9:
      return (reader.readLong(offset)) as P;
    case 10:
      return (reader.readLongOrNull(offset)) as P;
    case 11:
      return (reader.readLongOrNull(offset)) as P;
    case 12:
      return (reader.readStringOrNull(offset)) as P;
    case 13:
      return (reader.readDoubleOrNull(offset)) as P;
    case 14:
      return (reader.readDateTime(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _habitGetId(Habit object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _habitGetLinks(Habit object) {
  return [];
}

void _habitAttach(IsarCollection<dynamic> col, Id id, Habit object) {
  object.id = id;
}

extension HabitByIndex on IsarCollection<Habit> {
  Future<Habit?> getByCloudId(String cloudId) {
    return getByIndex(r'cloudId', [cloudId]);
  }

  Habit? getByCloudIdSync(String cloudId) {
    return getByIndexSync(r'cloudId', [cloudId]);
  }

  Future<bool> deleteByCloudId(String cloudId) {
    return deleteByIndex(r'cloudId', [cloudId]);
  }

  bool deleteByCloudIdSync(String cloudId) {
    return deleteByIndexSync(r'cloudId', [cloudId]);
  }

  Future<List<Habit?>> getAllByCloudId(List<String> cloudIdValues) {
    final values = cloudIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'cloudId', values);
  }

  List<Habit?> getAllByCloudIdSync(List<String> cloudIdValues) {
    final values = cloudIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'cloudId', values);
  }

  Future<int> deleteAllByCloudId(List<String> cloudIdValues) {
    final values = cloudIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'cloudId', values);
  }

  int deleteAllByCloudIdSync(List<String> cloudIdValues) {
    final values = cloudIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'cloudId', values);
  }

  Future<Id> putByCloudId(Habit object) {
    return putByIndex(r'cloudId', object);
  }

  Id putByCloudIdSync(Habit object, {bool saveLinks = true}) {
    return putByIndexSync(r'cloudId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByCloudId(List<Habit> objects) {
    return putAllByIndex(r'cloudId', objects);
  }

  List<Id> putAllByCloudIdSync(List<Habit> objects, {bool saveLinks = true}) {
    return putAllByIndexSync(r'cloudId', objects, saveLinks: saveLinks);
  }
}

extension HabitQueryWhereSort on QueryBuilder<Habit, Habit, QWhere> {
  QueryBuilder<Habit, Habit, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<Habit, Habit, QAfterWhere> anyArchived() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'archived'),
      );
    });
  }
}

extension HabitQueryWhere on QueryBuilder<Habit, Habit, QWhereClause> {
  QueryBuilder<Habit, Habit, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<Habit, Habit, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<Habit, Habit, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<Habit, Habit, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterWhereClause> cloudIdEqualTo(String cloudId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'cloudId',
        value: [cloudId],
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterWhereClause> cloudIdNotEqualTo(
      String cloudId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cloudId',
              lower: [],
              upper: [cloudId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cloudId',
              lower: [cloudId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cloudId',
              lower: [cloudId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'cloudId',
              lower: [],
              upper: [cloudId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<Habit, Habit, QAfterWhereClause> archivedEqualTo(bool archived) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'archived',
        value: [archived],
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterWhereClause> archivedNotEqualTo(
      bool archived) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'archived',
              lower: [],
              upper: [archived],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'archived',
              lower: [archived],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'archived',
              lower: [archived],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'archived',
              lower: [],
              upper: [archived],
              includeUpper: false,
            ));
      }
    });
  }
}

extension HabitQueryFilter on QueryBuilder<Habit, Habit, QFilterCondition> {
  QueryBuilder<Habit, Habit, QAfterFilterCondition> archivedEqualTo(
      bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'archived',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> cloudIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cloudId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> cloudIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'cloudId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> cloudIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'cloudId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> cloudIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'cloudId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> cloudIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'cloudId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> cloudIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'cloudId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> cloudIdContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'cloudId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> cloudIdMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'cloudId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> cloudIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cloudId',
        value: '',
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> cloudIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'cloudId',
        value: '',
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> colorValueEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'colorValue',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> colorValueGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'colorValue',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> colorValueLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'colorValue',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> colorValueBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'colorValue',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> createdAtEqualTo(
      DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> createdAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> createdAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> createdAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'createdAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> deletedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'deletedAt',
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> deletedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'deletedAt',
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> deletedAtEqualTo(
      DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'deletedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> deletedAtGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'deletedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> deletedAtLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'deletedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> deletedAtBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'deletedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> emojiIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'emoji',
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> emojiIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'emoji',
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> emojiEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'emoji',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> emojiGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'emoji',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> emojiLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'emoji',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> emojiBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'emoji',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> emojiStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'emoji',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> emojiEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'emoji',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> emojiContains(String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'emoji',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> emojiMatches(String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'emoji',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> emojiIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'emoji',
        value: '',
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> emojiIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'emoji',
        value: '',
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> intervalEndHourEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'intervalEndHour',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> intervalEndHourGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'intervalEndHour',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> intervalEndHourLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'intervalEndHour',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> intervalEndHourBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'intervalEndHour',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> intervalMinutesEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'intervalMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> intervalMinutesGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'intervalMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> intervalMinutesLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'intervalMinutes',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> intervalMinutesBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'intervalMinutes',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> nameContains(String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> nameMatches(String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> notificationIdEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'notificationId',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> notificationIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'notificationId',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> notificationIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'notificationId',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> notificationIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'notificationId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> remindHourIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'remindHour',
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> remindHourIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'remindHour',
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> remindHourEqualTo(
      int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'remindHour',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> remindHourGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'remindHour',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> remindHourLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'remindHour',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> remindHourBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'remindHour',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> remindMinuteIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'remindMinute',
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> remindMinuteIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'remindMinute',
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> remindMinuteEqualTo(
      int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'remindMinute',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> remindMinuteGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'remindMinute',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> remindMinuteLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'remindMinute',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> remindMinuteBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'remindMinute',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> targetUnitIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'targetUnit',
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> targetUnitIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'targetUnit',
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> targetUnitEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'targetUnit',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> targetUnitGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'targetUnit',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> targetUnitLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'targetUnit',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> targetUnitBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'targetUnit',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> targetUnitStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'targetUnit',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> targetUnitEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'targetUnit',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> targetUnitContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'targetUnit',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> targetUnitMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'targetUnit',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> targetUnitIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'targetUnit',
        value: '',
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> targetUnitIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'targetUnit',
        value: '',
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> targetValueIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'targetValue',
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> targetValueIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'targetValue',
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> targetValueEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'targetValue',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> targetValueGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'targetValue',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> targetValueLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'targetValue',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> targetValueBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'targetValue',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> updatedAtEqualTo(
      DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> updatedAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> updatedAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<Habit, Habit, QAfterFilterCondition> updatedAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'updatedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension HabitQueryObject on QueryBuilder<Habit, Habit, QFilterCondition> {}

extension HabitQueryLinks on QueryBuilder<Habit, Habit, QFilterCondition> {}

extension HabitQuerySortBy on QueryBuilder<Habit, Habit, QSortBy> {
  QueryBuilder<Habit, Habit, QAfterSortBy> sortByArchived() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'archived', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByArchivedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'archived', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByCloudId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cloudId', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByCloudIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cloudId', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByColorValue() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'colorValue', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByColorValueDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'colorValue', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByDeletedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'deletedAt', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByDeletedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'deletedAt', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByEmoji() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'emoji', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByEmojiDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'emoji', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByIntervalEndHour() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'intervalEndHour', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByIntervalEndHourDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'intervalEndHour', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByIntervalMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'intervalMinutes', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByIntervalMinutesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'intervalMinutes', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByNotificationId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'notificationId', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByNotificationIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'notificationId', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByRemindHour() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remindHour', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByRemindHourDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remindHour', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByRemindMinute() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remindMinute', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByRemindMinuteDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remindMinute', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByTargetUnit() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetUnit', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByTargetUnitDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetUnit', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByTargetValue() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetValue', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByTargetValueDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetValue', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension HabitQuerySortThenBy on QueryBuilder<Habit, Habit, QSortThenBy> {
  QueryBuilder<Habit, Habit, QAfterSortBy> thenByArchived() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'archived', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByArchivedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'archived', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByCloudId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cloudId', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByCloudIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cloudId', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByColorValue() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'colorValue', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByColorValueDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'colorValue', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByDeletedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'deletedAt', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByDeletedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'deletedAt', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByEmoji() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'emoji', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByEmojiDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'emoji', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByIntervalEndHour() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'intervalEndHour', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByIntervalEndHourDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'intervalEndHour', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByIntervalMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'intervalMinutes', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByIntervalMinutesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'intervalMinutes', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByNotificationId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'notificationId', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByNotificationIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'notificationId', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByRemindHour() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remindHour', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByRemindHourDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remindHour', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByRemindMinute() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remindMinute', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByRemindMinuteDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remindMinute', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByTargetUnit() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetUnit', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByTargetUnitDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetUnit', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByTargetValue() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetValue', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByTargetValueDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetValue', Sort.desc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<Habit, Habit, QAfterSortBy> thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension HabitQueryWhereDistinct on QueryBuilder<Habit, Habit, QDistinct> {
  QueryBuilder<Habit, Habit, QDistinct> distinctByArchived() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'archived');
    });
  }

  QueryBuilder<Habit, Habit, QDistinct> distinctByCloudId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cloudId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Habit, Habit, QDistinct> distinctByColorValue() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'colorValue');
    });
  }

  QueryBuilder<Habit, Habit, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<Habit, Habit, QDistinct> distinctByDeletedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'deletedAt');
    });
  }

  QueryBuilder<Habit, Habit, QDistinct> distinctByEmoji(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'emoji', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Habit, Habit, QDistinct> distinctByIntervalEndHour() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'intervalEndHour');
    });
  }

  QueryBuilder<Habit, Habit, QDistinct> distinctByIntervalMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'intervalMinutes');
    });
  }

  QueryBuilder<Habit, Habit, QDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Habit, Habit, QDistinct> distinctByNotificationId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'notificationId');
    });
  }

  QueryBuilder<Habit, Habit, QDistinct> distinctByRemindHour() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'remindHour');
    });
  }

  QueryBuilder<Habit, Habit, QDistinct> distinctByRemindMinute() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'remindMinute');
    });
  }

  QueryBuilder<Habit, Habit, QDistinct> distinctByTargetUnit(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'targetUnit', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Habit, Habit, QDistinct> distinctByTargetValue() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'targetValue');
    });
  }

  QueryBuilder<Habit, Habit, QDistinct> distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }
}

extension HabitQueryProperty on QueryBuilder<Habit, Habit, QQueryProperty> {
  QueryBuilder<Habit, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<Habit, bool, QQueryOperations> archivedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'archived');
    });
  }

  QueryBuilder<Habit, String, QQueryOperations> cloudIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cloudId');
    });
  }

  QueryBuilder<Habit, int, QQueryOperations> colorValueProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'colorValue');
    });
  }

  QueryBuilder<Habit, DateTime, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<Habit, DateTime?, QQueryOperations> deletedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'deletedAt');
    });
  }

  QueryBuilder<Habit, String?, QQueryOperations> emojiProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'emoji');
    });
  }

  QueryBuilder<Habit, int, QQueryOperations> intervalEndHourProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'intervalEndHour');
    });
  }

  QueryBuilder<Habit, int, QQueryOperations> intervalMinutesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'intervalMinutes');
    });
  }

  QueryBuilder<Habit, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<Habit, int, QQueryOperations> notificationIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'notificationId');
    });
  }

  QueryBuilder<Habit, int?, QQueryOperations> remindHourProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'remindHour');
    });
  }

  QueryBuilder<Habit, int?, QQueryOperations> remindMinuteProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'remindMinute');
    });
  }

  QueryBuilder<Habit, String?, QQueryOperations> targetUnitProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'targetUnit');
    });
  }

  QueryBuilder<Habit, double?, QQueryOperations> targetValueProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'targetValue');
    });
  }

  QueryBuilder<Habit, DateTime, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }
}
