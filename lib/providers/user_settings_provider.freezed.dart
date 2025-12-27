// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'user_settings_provider.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$UserSettingsState {
  UserSettings? get userSettings => throw _privateConstructorUsedError;
  bool get isLoading => throw _privateConstructorUsedError;
  bool get isSaving => throw _privateConstructorUsedError;
  String? get error => throw _privateConstructorUsedError;

  /// Create a copy of UserSettingsState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $UserSettingsStateCopyWith<UserSettingsState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UserSettingsStateCopyWith<$Res> {
  factory $UserSettingsStateCopyWith(
    UserSettingsState value,
    $Res Function(UserSettingsState) then,
  ) = _$UserSettingsStateCopyWithImpl<$Res, UserSettingsState>;
  @useResult
  $Res call({
    UserSettings? userSettings,
    bool isLoading,
    bool isSaving,
    String? error,
  });
}

/// @nodoc
class _$UserSettingsStateCopyWithImpl<$Res, $Val extends UserSettingsState>
    implements $UserSettingsStateCopyWith<$Res> {
  _$UserSettingsStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of UserSettingsState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? userSettings = freezed,
    Object? isLoading = null,
    Object? isSaving = null,
    Object? error = freezed,
  }) {
    return _then(
      _value.copyWith(
            userSettings:
                freezed == userSettings
                    ? _value.userSettings
                    : userSettings // ignore: cast_nullable_to_non_nullable
                        as UserSettings?,
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
abstract class _$$UserSettingsStateImplCopyWith<$Res>
    implements $UserSettingsStateCopyWith<$Res> {
  factory _$$UserSettingsStateImplCopyWith(
    _$UserSettingsStateImpl value,
    $Res Function(_$UserSettingsStateImpl) then,
  ) = __$$UserSettingsStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    UserSettings? userSettings,
    bool isLoading,
    bool isSaving,
    String? error,
  });
}

/// @nodoc
class __$$UserSettingsStateImplCopyWithImpl<$Res>
    extends _$UserSettingsStateCopyWithImpl<$Res, _$UserSettingsStateImpl>
    implements _$$UserSettingsStateImplCopyWith<$Res> {
  __$$UserSettingsStateImplCopyWithImpl(
    _$UserSettingsStateImpl _value,
    $Res Function(_$UserSettingsStateImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of UserSettingsState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? userSettings = freezed,
    Object? isLoading = null,
    Object? isSaving = null,
    Object? error = freezed,
  }) {
    return _then(
      _$UserSettingsStateImpl(
        userSettings:
            freezed == userSettings
                ? _value.userSettings
                : userSettings // ignore: cast_nullable_to_non_nullable
                    as UserSettings?,
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

class _$UserSettingsStateImpl
    with DiagnosticableTreeMixin
    implements _UserSettingsState {
  const _$UserSettingsStateImpl({
    this.userSettings,
    this.isLoading = false,
    this.isSaving = false,
    this.error,
  });

  @override
  final UserSettings? userSettings;
  @override
  @JsonKey()
  final bool isLoading;
  @override
  @JsonKey()
  final bool isSaving;
  @override
  final String? error;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'UserSettingsState(userSettings: $userSettings, isLoading: $isLoading, isSaving: $isSaving, error: $error)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'UserSettingsState'))
      ..add(DiagnosticsProperty('userSettings', userSettings))
      ..add(DiagnosticsProperty('isLoading', isLoading))
      ..add(DiagnosticsProperty('isSaving', isSaving))
      ..add(DiagnosticsProperty('error', error));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UserSettingsStateImpl &&
            (identical(other.userSettings, userSettings) ||
                other.userSettings == userSettings) &&
            (identical(other.isLoading, isLoading) ||
                other.isLoading == isLoading) &&
            (identical(other.isSaving, isSaving) ||
                other.isSaving == isSaving) &&
            (identical(other.error, error) || other.error == error));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, userSettings, isLoading, isSaving, error);

  /// Create a copy of UserSettingsState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$UserSettingsStateImplCopyWith<_$UserSettingsStateImpl> get copyWith =>
      __$$UserSettingsStateImplCopyWithImpl<_$UserSettingsStateImpl>(
        this,
        _$identity,
      );
}

abstract class _UserSettingsState implements UserSettingsState {
  const factory _UserSettingsState({
    final UserSettings? userSettings,
    final bool isLoading,
    final bool isSaving,
    final String? error,
  }) = _$UserSettingsStateImpl;

  @override
  UserSettings? get userSettings;
  @override
  bool get isLoading;
  @override
  bool get isSaving;
  @override
  String? get error;

  /// Create a copy of UserSettingsState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$UserSettingsStateImplCopyWith<_$UserSettingsStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
