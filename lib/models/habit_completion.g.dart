// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'habit_completion.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetHabitCompletionCollection on Isar {
  IsarCollection<HabitCompletion> get habitCompletions => this.collection();
}

const HabitCompletionSchema = CollectionSchema(
  name: r'HabitCompletion',
  id: -9119310967514767545,
  properties: {
    r'completedAt': PropertySchema(
      id: 0,
      name: r'completedAt',
      type: IsarType.dateTime,
    ),
    r'date': PropertySchema(
      id: 1,
      name: r'date',
      type: IsarType.dateTime,
    ),
    r'habitId': PropertySchema(
      id: 2,
      name: r'habitId',
      type: IsarType.long,
    )
  },
  estimateSize: _habitCompletionEstimateSize,
  serialize: _habitCompletionSerialize,
  deserialize: _habitCompletionDeserialize,
  deserializeProp: _habitCompletionDeserializeProp,
  idName: r'id',
  indexes: {
    r'habitId_date': IndexSchema(
      id: -8738549928736890525,
      name: r'habitId_date',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'habitId',
          type: IndexType.value,
          caseSensitive: false,
        ),
        IndexPropertySchema(
          name: r'date',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    ),
    r'date': IndexSchema(
      id: -7552997827385218417,
      name: r'date',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'date',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _habitCompletionGetId,
  getLinks: _habitCompletionGetLinks,
  attach: _habitCompletionAttach,
  version: '3.1.0+1',
);

int _habitCompletionEstimateSize(
  HabitCompletion object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  return bytesCount;
}

void _habitCompletionSerialize(
  HabitCompletion object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.completedAt);
  writer.writeDateTime(offsets[1], object.date);
  writer.writeLong(offsets[2], object.habitId);
}

HabitCompletion _habitCompletionDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = HabitCompletion();
  object.completedAt = reader.readDateTime(offsets[0]);
  object.date = reader.readDateTime(offsets[1]);
  object.habitId = reader.readLong(offsets[2]);
  object.id = id;
  return object;
}

P _habitCompletionDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDateTime(offset)) as P;
    case 1:
      return (reader.readDateTime(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _habitCompletionGetId(HabitCompletion object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _habitCompletionGetLinks(HabitCompletion object) {
  return [];
}

void _habitCompletionAttach(
    IsarCollection<dynamic> col, Id id, HabitCompletion object) {
  object.id = id;
}

extension HabitCompletionQueryWhereSort
    on QueryBuilder<HabitCompletion, HabitCompletion, QWhere> {
  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhere> anyHabitIdDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'habitId_date'),
      );
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhere> anyDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'date'),
      );
    });
  }
}

extension HabitCompletionQueryWhere
    on QueryBuilder<HabitCompletion, HabitCompletion, QWhereClause> {
  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhereClause>
      idNotEqualTo(Id id) {
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

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhereClause> idBetween(
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

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhereClause>
      habitIdEqualToAnyDate(int habitId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'habitId_date',
        value: [habitId],
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhereClause>
      habitIdNotEqualToAnyDate(int habitId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'habitId_date',
              lower: [],
              upper: [habitId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'habitId_date',
              lower: [habitId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'habitId_date',
              lower: [habitId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'habitId_date',
              lower: [],
              upper: [habitId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhereClause>
      habitIdGreaterThanAnyDate(
    int habitId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'habitId_date',
        lower: [habitId],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhereClause>
      habitIdLessThanAnyDate(
    int habitId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'habitId_date',
        lower: [],
        upper: [habitId],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhereClause>
      habitIdBetweenAnyDate(
    int lowerHabitId,
    int upperHabitId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'habitId_date',
        lower: [lowerHabitId],
        includeLower: includeLower,
        upper: [upperHabitId],
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhereClause>
      habitIdDateEqualTo(int habitId, DateTime date) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'habitId_date',
        value: [habitId, date],
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhereClause>
      habitIdEqualToDateNotEqualTo(int habitId, DateTime date) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'habitId_date',
              lower: [habitId],
              upper: [habitId, date],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'habitId_date',
              lower: [habitId, date],
              includeLower: false,
              upper: [habitId],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'habitId_date',
              lower: [habitId, date],
              includeLower: false,
              upper: [habitId],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'habitId_date',
              lower: [habitId],
              upper: [habitId, date],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhereClause>
      habitIdEqualToDateGreaterThan(
    int habitId,
    DateTime date, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'habitId_date',
        lower: [habitId, date],
        includeLower: include,
        upper: [habitId],
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhereClause>
      habitIdEqualToDateLessThan(
    int habitId,
    DateTime date, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'habitId_date',
        lower: [habitId],
        upper: [habitId, date],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhereClause>
      habitIdEqualToDateBetween(
    int habitId,
    DateTime lowerDate,
    DateTime upperDate, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'habitId_date',
        lower: [habitId, lowerDate],
        includeLower: includeLower,
        upper: [habitId, upperDate],
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhereClause> dateEqualTo(
      DateTime date) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'date',
        value: [date],
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhereClause>
      dateNotEqualTo(DateTime date) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'date',
              lower: [],
              upper: [date],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'date',
              lower: [date],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'date',
              lower: [date],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'date',
              lower: [],
              upper: [date],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhereClause>
      dateGreaterThan(
    DateTime date, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'date',
        lower: [date],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhereClause>
      dateLessThan(
    DateTime date, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'date',
        lower: [],
        upper: [date],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterWhereClause> dateBetween(
    DateTime lowerDate,
    DateTime upperDate, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'date',
        lower: [lowerDate],
        includeLower: includeLower,
        upper: [upperDate],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension HabitCompletionQueryFilter
    on QueryBuilder<HabitCompletion, HabitCompletion, QFilterCondition> {
  QueryBuilder<HabitCompletion, HabitCompletion, QAfterFilterCondition>
      completedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'completedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterFilterCondition>
      completedAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'completedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterFilterCondition>
      completedAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'completedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterFilterCondition>
      completedAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'completedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterFilterCondition>
      dateEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'date',
        value: value,
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterFilterCondition>
      dateGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'date',
        value: value,
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterFilterCondition>
      dateLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'date',
        value: value,
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterFilterCondition>
      dateBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'date',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterFilterCondition>
      habitIdEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'habitId',
        value: value,
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterFilterCondition>
      habitIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'habitId',
        value: value,
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterFilterCondition>
      habitIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'habitId',
        value: value,
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterFilterCondition>
      habitIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'habitId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterFilterCondition>
      idGreaterThan(
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

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterFilterCondition>
      idLessThan(
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

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterFilterCondition>
      idBetween(
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
}

extension HabitCompletionQueryObject
    on QueryBuilder<HabitCompletion, HabitCompletion, QFilterCondition> {}

extension HabitCompletionQueryLinks
    on QueryBuilder<HabitCompletion, HabitCompletion, QFilterCondition> {}

extension HabitCompletionQuerySortBy
    on QueryBuilder<HabitCompletion, HabitCompletion, QSortBy> {
  QueryBuilder<HabitCompletion, HabitCompletion, QAfterSortBy>
      sortByCompletedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completedAt', Sort.asc);
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterSortBy>
      sortByCompletedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completedAt', Sort.desc);
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterSortBy> sortByDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'date', Sort.asc);
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterSortBy>
      sortByDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'date', Sort.desc);
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterSortBy> sortByHabitId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'habitId', Sort.asc);
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterSortBy>
      sortByHabitIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'habitId', Sort.desc);
    });
  }
}

extension HabitCompletionQuerySortThenBy
    on QueryBuilder<HabitCompletion, HabitCompletion, QSortThenBy> {
  QueryBuilder<HabitCompletion, HabitCompletion, QAfterSortBy>
      thenByCompletedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completedAt', Sort.asc);
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterSortBy>
      thenByCompletedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completedAt', Sort.desc);
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterSortBy> thenByDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'date', Sort.asc);
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterSortBy>
      thenByDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'date', Sort.desc);
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterSortBy> thenByHabitId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'habitId', Sort.asc);
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterSortBy>
      thenByHabitIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'habitId', Sort.desc);
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }
}

extension HabitCompletionQueryWhereDistinct
    on QueryBuilder<HabitCompletion, HabitCompletion, QDistinct> {
  QueryBuilder<HabitCompletion, HabitCompletion, QDistinct>
      distinctByCompletedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'completedAt');
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QDistinct> distinctByDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'date');
    });
  }

  QueryBuilder<HabitCompletion, HabitCompletion, QDistinct>
      distinctByHabitId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'habitId');
    });
  }
}

extension HabitCompletionQueryProperty
    on QueryBuilder<HabitCompletion, HabitCompletion, QQueryProperty> {
  QueryBuilder<HabitCompletion, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<HabitCompletion, DateTime, QQueryOperations>
      completedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'completedAt');
    });
  }

  QueryBuilder<HabitCompletion, DateTime, QQueryOperations> dateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'date');
    });
  }

  QueryBuilder<HabitCompletion, int, QQueryOperations> habitIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'habitId');
    });
  }
}
