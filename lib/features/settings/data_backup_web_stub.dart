// Stub used on non-web platforms.
void triggerWebDownload(List<int> bytes, String fileName) {
  throw UnsupportedError('Web download not available on this platform');
}
