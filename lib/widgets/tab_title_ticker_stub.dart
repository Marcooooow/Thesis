/// Stub implementation for non-web platforms.
void updateDocumentTitle(String title) {
  // No-op on non-web platforms
}

void registerVisibilityCallback(void Function() onVisible) {
  // No-op on non-web platforms
}

void registerAttentionListeners({
  required void Function(String message) onAttention,
  required void Function() onClear,
}) {
  // No-op on non-web platforms
}

void unregisterAttentionListeners() {
  // No-op on non-web platforms
}