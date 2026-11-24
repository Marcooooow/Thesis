// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:js_interop';
import 'package:web/web.dart' as web;

web.EventListener? _visibilityListener;
web.EventListener? _attentionListener;
web.EventListener? _clearAttentionListener;
void Function()? _currentCallback;
String? _attentionMessage;
bool _isAttentionActive = false;

void updateDocumentTitle(String title) {
  if (web.document.title != title) {
    web.document.title = title;
  }
}

void registerVisibilityCallback(void Function() onVisible) {
  if (_visibilityListener != null) {
    web.document.removeEventListener('visibilitychange', _visibilityListener!);
  }

  _currentCallback = onVisible;

  _visibilityListener = ( (web.Event event) {
    if (web.document.hidden == false && _currentCallback != null) {
      _currentCallback!();
    }
  }).toJS as web.EventListener;

  web.document.addEventListener('visibilitychange', _visibilityListener!);
}

void registerAttentionListeners({
  required void Function(String message) onAttention,
  required void Function() onClear,
}) {
  // Remove existing listeners if any
  if (_attentionListener != null) {
    web.window.removeEventListener('intellibreak-tab-attention', _attentionListener!);
    _attentionListener = null;
  }
  if (_clearAttentionListener != null) {
    web.window.removeEventListener('intellibreak-tab-attention-clear', _clearAttentionListener!);
    _clearAttentionListener = null;
  }

  _attentionListener = ((web.Event event) {
    final customEvent = event as web.CustomEvent;
    final detail = customEvent.detail;
    if (detail != null) {
      final message = detail.toString();
      onAttention(message);
    }
  }.toJS) as web.EventListener;

  _clearAttentionListener = ((web.Event event) {
    onClear();
  }).toJS as web.EventListener;

  web.window.addEventListener('intellibreak-tab-attention', _attentionListener!);
  web.window.addEventListener('intellibreak-tab-attention-clear', _clearAttentionListener!);
}

void unregisterAttentionListeners() {
  if (_attentionListener != null) {
    web.window.removeEventListener('intellibreak-tab-attention', _attentionListener!);
    _attentionListener = null;
  }
  if (_clearAttentionListener != null) {
    web.window.removeEventListener('intellibreak-tab-attention-clear', _clearAttentionListener!);
    _clearAttentionListener = null;
  }
  _attentionMessage = null;
  _isAttentionActive = false;
}

String? getAttentionMessage() => _attentionMessage;
bool get isAttentionActive => _isAttentionActive;

void setAttentionMessage(String? message, bool active) {
  _attentionMessage = message;
  _isAttentionActive = active;
}
