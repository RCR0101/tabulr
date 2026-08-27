/// A single-entry in-memory cache that can only be read by the owner that
/// populated it. This prevents process-wide service singletons from returning
/// one account's data after Firebase switches to another account.
class AccountScopedCache<T> {
  Object? _owner;
  T? _value;
  bool _hasValue = false;

  bool contains(Object? owner) => _hasValue && _owner == owner;

  T? read(Object? owner) => contains(owner) ? _value : null;

  void write(Object? owner, T value) {
    _owner = owner;
    _value = value;
    _hasValue = true;
  }

  void clear() {
    _owner = null;
    _value = null;
    _hasValue = false;
  }
}
