// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'timetable_provider.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$TimetableState {
  List<Timetable> get timetables => throw _privateConstructorUsedError;
  Timetable? get currentTimetable => throw _privateConstructorUsedError;
  bool get isLoading => throw _privateConstructorUsedError;
  bool get isSaving => throw _privateConstructorUsedError;
  bool get hasUnsavedChanges => throw _privateConstructorUsedError;
  String? get error => throw _privateConstructorUsedError;

  /// Create a copy of TimetableState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TimetableStateCopyWith<TimetableState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TimetableStateCopyWith<$Res> {
  factory $TimetableStateCopyWith(
    TimetableState value,
    $Res Function(TimetableState) then,
  ) = _$TimetableStateCopyWithImpl<$Res, TimetableState>;
  @useResult
  $Res call({
    List<Timetable> timetables,
    Timetable? currentTimetable,
    bool isLoading,
    bool isSaving,
    bool hasUnsavedChanges,
    String? error,
  });
}

/// @nodoc
class _$TimetableStateCopyWithImpl<$Res, $Val extends TimetableState>
    implements $TimetableStateCopyWith<$Res> {
  _$TimetableStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TimetableState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? timetables = null,
    Object? currentTimetable = freezed,
    Object? isLoading = null,
    Object? isSaving = null,
    Object? hasUnsavedChanges = null,
    Object? error = freezed,
  }) {
    return _then(
      _value.copyWith(
            timetables:
                null == timetables
                    ? _value.timetables
                    : timetables // ignore: cast_nullable_to_non_nullable
                        as List<Timetable>,
            currentTimetable:
                freezed == currentTimetable
                    ? _value.currentTimetable
                    : currentTimetable // ignore: cast_nullable_to_non_nullable
                        as Timetable?,
            isLoading:
                null == isLoading
                    ? _value.isLoading
                    : isLoading // ignore: cast_nullable_to_non_nullable
                        as bool,
            isSaving:
                null == isSaving
                    ? _value.isSaving
                    : isSaving // ignore: cast_nullable_to_non_nullable
                        as bool,
            hasUnsavedChanges:
                null == hasUnsavedChanges
                    ? _value.hasUnsavedChanges
                    : hasUnsavedChanges // ignore: cast_nullable_to_non_nullable
                        as bool,
            error:
                freezed == error
                    ? _value.error
                    : error // ignore: cast_nullable_to_non_nullable
                        as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$TimetableStateImplCopyWith<$Res>
    implements $TimetableStateCopyWith<$Res> {
  factory _$$TimetableStateImplCopyWith(
    _$TimetableStateImpl value,
    $Res Function(_$TimetableStateImpl) then,
  ) = __$$TimetableStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    List<Timetable> timetables,
    Timetable? currentTimetable,
    bool isLoading,
    bool isSaving,
    bool hasUnsavedChanges,
    String? error,
  });
}

/// @nodoc
class __$$TimetableStateImplCopyWithImpl<$Res>
    extends _$TimetableStateCopyWithImpl<$Res, _$TimetableStateImpl>
    implements _$$TimetableStateImplCopyWith<$Res> {
  __$$TimetableStateImplCopyWithImpl(
    _$TimetableStateImpl _value,
    $Res Function(_$TimetableStateImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of TimetableState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? timetables = null,
    Object? currentTimetable = freezed,
    Object? isLoading = null,
    Object? isSaving = null,
    Object? hasUnsavedChanges = null,
    Object? error = freezed,
  }) {
    return _then(
      _$TimetableStateImpl(
        timetables:
            null == timetables
                ? _value._timetables
                : timetables // ignore: cast_nullable_to_non_nullable
                    as List<Timetable>,
        currentTimetable:
            freezed == currentTimetable
                ? _value.currentTimetable
                : currentTimetable // ignore: cast_nullable_to_non_nullable
                    as Timetable?,
        isLoading:
            null == isLoading
                ? _value.isLoading
                : isLoading // ignore: cast_nullable_to_non_nullable
                    as bool,
        isSaving:
            null == isSaving
                ? _value.isSaving
                : isSaving // ignore: cast_nullable_to_non_nullable
                    as bool,
        hasUnsavedChanges:
            null == hasUnsavedChanges
                ? _value.hasUnsavedChanges
                : hasUnsavedChanges // ignore: cast_nullable_to_non_nullable
                    as bool,
        error:
            freezed == error
                ? _value.error
                : error // ignore: cast_nullable_to_non_nullable
                    as String?,
      ),
    );
  }
}

/// @nodoc

class _$TimetableStateImpl
    with DiagnosticableTreeMixin
    implements _TimetableState {
  const _$TimetableStateImpl({
    final List<Timetable> timetables = const [],
    this.currentTimetable,
    this.isLoading = false,
    this.isSaving = false,
    this.hasUnsavedChanges = false,
    this.error,
  }) : _timetables = timetables;

  final List<Timetable> _timetables;
  @override
  @JsonKey()
  List<Timetable> get timetables {
    if (_timetables is EqualUnmodifiableListView) return _timetables;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_timetables);
  }

  @override
  final Timetable? currentTimetable;
  @override
  @JsonKey()
  final bool isLoading;
  @override
  @JsonKey()
  final bool isSaving;
  @override
  @JsonKey()
  final bool hasUnsavedChanges;
  @override
  final String? error;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'TimetableState(timetables: $timetables, currentTimetable: $currentTimetable, isLoading: $isLoading, isSaving: $isSaving, hasUnsavedChanges: $hasUnsavedChanges, error: $error)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'TimetableState'))
      ..add(DiagnosticsProperty('timetables', timetables))
      ..add(DiagnosticsProperty('currentTimetable', currentTimetable))
      ..add(DiagnosticsProperty('isLoading', isLoading))
      ..add(DiagnosticsProperty('isSaving', isSaving))
      ..add(DiagnosticsProperty('hasUnsavedChanges', hasUnsavedChanges))
      ..add(DiagnosticsProperty('error', error));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TimetableStateImpl &&
            const DeepCollectionEquality().equals(
              other._timetables,
              _timetables,
            ) &&
            (identical(other.currentTimetable, currentTimetable) ||
                other.currentTimetable == currentTimetable) &&
            (identical(other.isLoading, isLoading) ||
                other.isLoading == isLoading) &&
            (identical(other.isSaving, isSaving) ||
                other.isSaving == isSaving) &&
            (identical(other.hasUnsavedChanges, hasUnsavedChanges) ||
                other.hasUnsavedChanges == hasUnsavedChanges) &&
            (identical(other.error, error) || other.error == error));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    const DeepCollectionEquality().hash(_timetables),
    currentTimetable,
    isLoading,
    isSaving,
    hasUnsavedChanges,
    error,
  );

  /// Create a copy of TimetableState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TimetableStateImplCopyWith<_$TimetableStateImpl> get copyWith =>
      __$$TimetableStateImplCopyWithImpl<_$TimetableStateImpl>(
        this,
        _$identity,
      );
}

abstract class _TimetableState implements TimetableState {
  const factory _TimetableState({
    final List<Timetable> timetables,
    final Timetable? currentTimetable,
    final bool isLoading,
    final bool isSaving,
    final bool hasUnsavedChanges,
    final String? error,
  }) = _$TimetableStateImpl;

  @override
  List<Timetable> get timetables;
  @override
  Timetable? get currentTimetable;
  @override
  bool get isLoading;
  @override
  bool get isSaving;
  @override
  bool get hasUnsavedChanges;
  @override
  String? get error;

  /// Create a copy of TimetableState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TimetableStateImplCopyWith<_$TimetableStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
