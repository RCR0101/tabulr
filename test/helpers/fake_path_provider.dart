import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Points path_provider at a throwaway temp directory.
///
/// Anything that touches [LocalCacheService] hits the filesystem through
/// path_provider, which has no platform channel under `flutter test` and warns
/// (or throws) without this. [installFakePathProvider] is the one-liner every
/// such suite needs.
class FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

/// Installs a [FakePathProvider] rooted at a fresh temp dir and returns it.
/// [prefix] only labels the directory, to keep suites apart when debugging.
String installFakePathProvider(String prefix) {
  final root = Directory.systemTemp.createTempSync(prefix).path;
  PathProviderPlatform.instance = FakePathProvider(root);
  return root;
}
