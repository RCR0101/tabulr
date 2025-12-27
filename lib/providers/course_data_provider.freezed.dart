// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'course_data_provider.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$CourseDataState {
  List<Course> get courses => throw _privateConstructorUsedError;
  bool get isLoading => throw _privateConstructorUsedError;
  bool get isLoadingMore => throw _privateConstructorUsedError;
  bool get hasMore => throw _privateConstructorUsedError;
  DocumentSnapshot<Object?>? get lastDocument =>
      throw _privateConstructorUsedError;
  DateTime? get lastFetchTime => throw _privateConstructorUsedError;
  Campus? get cachedCampus => throw _privateConstructorUsedError;
  String? get cachedVersion => throw _privateConstructorUsedError;
  String? get error => throw _privateConstructorUsedError;
  Map<String, dynamic>? get metadata => throw _privateConstructorUsedError;

  /// Create a copy of CourseDataState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $CourseDataStateCopyWith<CourseDataState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CourseDataStateCopyWith<$Res> {
  factory $CourseDataStateCopyWith(
    CourseDataState value,
    $Res Function(CourseDataState) then,
  ) = _$CourseDataStateCopyWithImpl<$Res, CourseDataState>;
  @useResult
  $Res call({
    List<Course> courses,
    bool isLoading,
    bool isLoadingMore,
    bool hasMore,
    DocumentSnapshot<Object?>? lastDocument,
    DateTime? lastFetchTime,
    Campus? cachedCampus,
    String? cachedVersion,
    String? error,
    Map<String, dynamic>? metadata,
  });
}

/// @nodoc
class _$CourseDataStateCopyWithImpl<$Res, $Val extends CourseDataState>
    implements $CourseDataStateCopyWith<$Res> {
  _$CourseDataStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of CourseDataState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? courses = null,
    Object? isLoading = null,
    Object? isLoadingMore = null,
    Object? hasMore = null,
    Object? lastDocument = freezed,
    Object? lastFetchTime = freezed,
    Object? cachedCampus = freezed,
    Object? cachedVersion = freezed,
    Object? error = freezed,
    Object? metadata = freezed,
  }) {
    return _then(
      _value.copyWith(
            courses:
                null == courses
                    ? _value.courses
                    : courses // ignore: cast_nullable_to_non_nullable
                        as List<Course>,
            isLoading:
                null == isLoading
                    ? _value.isLoading
                    : isLoading // ignore: cast_nullable_to_non_nullable
                        as bool,
            isLoadingMore:
                null == isLoadingMore
                    ? _value.isLoadingMore
                    : isLoadingMore // ignore: cast_nullable_to_non_nullable
                        as bool,
            hasMore:
                null == hasMore
                    ? _value.hasMore
                    : hasMore // ignore: cast_nullable_to_non_nullable
                        as bool,
            lastDocument:
                freezed == lastDocument
                    ? _value.lastDocument
                    : lastDocument // ignore: cast_nullable_to_non_nullable
                        as DocumentSnapshot<Object?>?,
            lastFetchTime:
                freezed == lastFetchTime
                    ? _value.lastFetchTime
                    : lastFetchTime // ignore: cast_nullable_to_non_nullable
                        as DateTime?,
            cachedCampus:
                freezed == cachedCampus
                    ? _value.cachedCampus
                    : cachedCampus // ignore: cast_nullable_to_non_nullable
                        as Campus?,
            cachedVersion:
                freezed == cachedVersion
                    ? _value.cachedVersion
                    : cachedVersion // ignore: cast_nullable_to_non_nullable
                        as String?,
            error:
                freezed == error
                    ? _value.error
                    : error // ignore: cast_nullable_to_non_nullable
                        as String?,
            metadata:
                freezed == metadata
                    ? _value.metadata
                    : metadata // ignore: cast_nullable_to_non_nullable
                        as Map<String, dynamic>?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$CourseDataStateImplCopyWith<$Res>
    implements $CourseDataStateCopyWith<$Res> {
  factory _$$CourseDataStateImplCopyWith(
    _$CourseDataStateImpl value,
    $Res Function(_$CourseDataStateImpl) then,
  ) = __$$CourseDataStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    List<Course> courses,
    bool isLoading,
    bool isLoadingMore,
    bool hasMore,
    DocumentSnapshot<Object?>? lastDocument,
    DateTime? lastFetchTime,
    Campus? cachedCampus,
    String? cachedVersion,
    String? error,
    Map<String, dynamic>? metadata,
  });
}

/// @nodoc
class __$$CourseDataStateImplCopyWithImpl<$Res>
    extends _$CourseDataStateCopyWithImpl<$Res, _$CourseDataStateImpl>
    implements _$$CourseDataStateImplCopyWith<$Res> {
  __$$CourseDataStateImplCopyWithImpl(
    _$CourseDataStateImpl _value,
    $Res Function(_$CourseDataStateImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of CourseDataState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? courses = null,
    Object? isLoading = null,
    Object? isLoadingMore = null,
    Object? hasMore = null,
    Object? lastDocument = freezed,
    Object? lastFetchTime = freezed,
    Object? cachedCampus = freezed,
    Object? cachedVersion = freezed,
    Object? error = freezed,
    Object? metadata = freezed,
  }) {
    return _then(
      _$CourseDataStateImpl(
        courses:
            null == courses
                ? _value._courses
                : courses // ignore: cast_nullable_to_non_nullable
                    as List<Course>,
        isLoading:
            null == isLoading
                ? _value.isLoading
                : isLoading // ignore: cast_nullable_to_non_nullable
                    as bool,
        isLoadingMore:
            null == isLoadingMore
                ? _value.isLoadingMore
                : isLoadingMore // ignore: cast_nullable_to_non_nullable
                    as bool,
        hasMore:
            null == hasMore
                ? _value.hasMore
                : hasMore // ignore: cast_nullable_to_non_nullable
                    as bool,
        lastDocument:
            freezed == lastDocument
                ? _value.lastDocument
                : lastDocument // ignore: cast_nullable_to_non_nullable
                    as DocumentSnapshot<Object?>?,
        lastFetchTime:
            freezed == lastFetchTime
                ? _value.lastFetchTime
                : lastFetchTime // ignore: cast_nullable_to_non_nullable
                    as DateTime?,
        cachedCampus:
            freezed == cachedCampus
                ? _value.cachedCampus
                : cachedCampus // ignore: cast_nullable_to_non_nullable
                    as Campus?,
        cachedVersion:
            freezed == cachedVersion
                ? _value.cachedVersion
                : cachedVersion // ignore: cast_nullable_to_non_nullable
                    as String?,
        error:
            freezed == error
                ? _value.error
                : error // ignore: cast_nullable_to_non_nullable
                    as String?,
        metadata:
            freezed == metadata
                ? _value._metadata
                : metadata // ignore: cast_nullable_to_non_nullable
                    as Map<String, dynamic>?,
      ),
    );
  }
}

/// @nodoc

class _$CourseDataStateImpl implements _CourseDataState {
  const _$CourseDataStateImpl({
    final List<Course> courses = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.lastDocument,
    this.lastFetchTime,
    this.cachedCampus,
    this.cachedVersion,
    this.error,
    final Map<String, dynamic>? metadata,
  }) : _courses = courses,
       _metadata = metadata;

  final List<Course> _courses;
  @override
  @JsonKey()
  List<Course> get courses {
    if (_courses is EqualUnmodifiableListView) return _courses;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_courses);
  }

  @override
  @JsonKey()
  final bool isLoading;
  @override
  @JsonKey()
  final bool isLoadingMore;
  @override
  @JsonKey()
  final bool hasMore;
  @override
  final DocumentSnapshot<Object?>? lastDocument;
  @override
  final DateTime? lastFetchTime;
  @override
  final Campus? cachedCampus;
  @override
  final String? cachedVersion;
  @override
  final String? error;
  final Map<String, dynamic>? _metadata;
  @override
  Map<String, dynamic>? get metadata {
    final value = _metadata;
    if (value == null) return null;
    if (_metadata is EqualUnmodifiableMapView) return _metadata;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  String toString() {
    return 'CourseDataState(courses: $courses, isLoading: $isLoading, isLoadingMore: $isLoadingMore, hasMore: $hasMore, lastDocument: $lastDocument, lastFetchTime: $lastFetchTime, cachedCampus: $cachedCampus, cachedVersion: $cachedVersion, error: $error, metadata: $metadata)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CourseDataStateImpl &&
            const DeepCollectionEquality().equals(other._courses, _courses) &&
            (identical(other.isLoading, isLoading) ||
                other.isLoading == isLoading) &&
            (identical(other.isLoadingMore, isLoadingMore) ||
                other.isLoadingMore == isLoadingMore) &&
            (identical(other.hasMore, hasMore) || other.hasMore == hasMore) &&
            (identical(other.lastDocument, lastDocument) ||
                other.lastDocument == lastDocument) &&
            (identical(other.lastFetchTime, lastFetchTime) ||
                other.lastFetchTime == lastFetchTime) &&
            (identical(other.cachedCampus, cachedCampus) ||
                other.cachedCampus == cachedCampus) &&
            (identical(other.cachedVersion, cachedVersion) ||
                other.cachedVersion == cachedVersion) &&
            (identical(other.error, error) || other.error == error) &&
            const DeepCollectionEquality().equals(other._metadata, _metadata));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    const DeepCollectionEquality().hash(_courses),
    isLoading,
    isLoadingMore,
    hasMore,
    lastDocument,
    lastFetchTime,
    cachedCampus,
    cachedVersion,
    error,
    const DeepCollectionEquality().hash(_metadata),
  );

  /// Create a copy of CourseDataState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CourseDataStateImplCopyWith<_$CourseDataStateImpl> get copyWith =>
      __$$CourseDataStateImplCopyWithImpl<_$CourseDataStateImpl>(
        this,
        _$identity,
      );
}

abstract class _CourseDataState implements CourseDataState {
  const factory _CourseDataState({
    final List<Course> courses,
    final bool isLoading,
    final bool isLoadingMore,
    final bool hasMore,
    final DocumentSnapshot<Object?>? lastDocument,
    final DateTime? lastFetchTime,
    final Campus? cachedCampus,
    final String? cachedVersion,
    final String? error,
    final Map<String, dynamic>? metadata,
  }) = _$CourseDataStateImpl;

  @override
  List<Course> get courses;
  @override
  bool get isLoading;
  @override
  bool get isLoadingMore;
  @override
  bool get hasMore;
  @override
  DocumentSnapshot<Object?>? get lastDocument;
  @override
  DateTime? get lastFetchTime;
  @override
  Campus? get cachedCampus;
  @override
  String? get cachedVersion;
  @override
  String? get error;
  @override
  Map<String, dynamic>? get metadata;

  /// Create a copy of CourseDataState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CourseDataStateImplCopyWith<_$CourseDataStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
