void openUrl(String url) {
  // No-op on non-web platforms; use url_launcher instead.
}

void addBeforeUnloadListener(bool Function() shouldWarn) {}

void removeBeforeUnloadListener() {}

void addPageHideListener(void Function() callback) {}

void clearLocalStorageItem(String key) {}

void usePathUrlStrategy() {}

void downloadBlob(List<int> bytes, String filename) {}
