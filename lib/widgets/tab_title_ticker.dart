import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/work_session_provider.dart';
import 'tab_title_ticker_stub.dart' if (dart.library.js_interop) 'tab_title_ticker_web.dart';

/// A widget that updates the browser tab title based on the current work-session state.
/// It uses a timer to update every second when a session is active,
/// and listens to WorkSessionProvider for state changes.
/// Also listens for notification attention events to temporarily modify the tab title.
class TabTitleTicker extends StatefulWidget {
  const TabTitleTicker({super.key});

  @override
  State<TabTitleTicker> createState() => _TabTitleTickerState();
}

class _TabTitleTickerState extends State<TabTitleTicker> {
  Timer? _timer;
  late final VoidCallback _sessionStateListener;
  WorkSessionProvider? _provider;
  String? _attentionMessage;
  bool _isAttentionActive = false;

  @override
  void initState() {
    super.initState();
    print('[TAB_TITLE] initState');
    // Capture provider reference while mounted instead of resolving via context in timer
    _provider = context.read<WorkSessionProvider>();
    print('[TAB_TITLE] provider acquired: $_provider');
    _startTimer();
    _registerVisibility();
    _registerAttentionListeners();
    _sessionStateListener = () {
      if (mounted) {
        print('[TAB_TITLE] session state listener called');
        _updateTitle();
      }
    };
    _provider?.addListener(_sessionStateListener);
    print('[TAB_TITLE] listener added');
  }

  void _registerAttentionListeners() {
    try {
      registerAttentionListeners(
        onAttention: (message) {
          if (mounted) {
            setState(() {
              _attentionMessage = message;
              _isAttentionActive = true;
            });
            _updateTitle();
          }
        },
        onClear: () {
          if (mounted) {
            setState(() {
              _attentionMessage = null;
              _isAttentionActive = false;
            });
            _updateTitle();
          }
        },
      );
      print('[TAB_TITLE] attention listeners registered');
    } catch (_) {
      print('[TAB_TITLE] attention listeners registration failed (non-web)');
    }
  }

  void _unregisterAttentionListeners() {
    try {
      unregisterAttentionListeners();
      _attentionMessage = null;
      _isAttentionActive = false;
      print('[TAB_TITLE] attention listeners unregistered');
    } catch (_) {
      // Non-web platform
    }
  }

  @override
  void dispose() {
    print('[TAB_TITLE] dispose');
    _timer?.cancel();
    _timer = null;
    _unregisterVisibility();
    _unregisterAttentionListeners();
    _provider?.removeListener(_sessionStateListener);
    _provider = null;
    super.dispose();
  }

  void _registerVisibility() {
    try {
      print('[TAB_TITLE] registering visibility callback');
      registerVisibilityCallback(() {
        if (mounted) {
          print('[TAB_TITLE] visibility callback fired');
          _updateTitle();
        }
      });
    } catch (_) {
      print('[TAB_TITLE] visibility callback registration failed');
    }
  }
  void _unregisterVisibility() {
    // Visibility change handled by timer continuing; update on return via timer
    print('[TAB_TITLE] unregistering visibility callback (no-op)');
  }

  void _startTimer() {
    print('[TAB_TITLE] starting timer');
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        print('[TAB_TITLE] timer tick');
        _updateTitle();
      }
    });
  }

  String _pageTitleForDestination() {
    // Reuse existing architecture; page-specific mapping can be added here
    // without creating a second title system. For now we keep the base name.
    return 'IntelliBreak';
  }

  void _updateTitle() {
    if (!mounted) {
      print('[TAB_TITLE] _updateTitle: not mounted');
      return;
    }
    final provider = _provider;
    if (provider == null) {
      print('[TAB_TITLE] _updateTitle: provider is null');
      return;
    }
    final state = provider.state;
    print('[TAB_TITLE] _updateTitle: isActive=${state.isActive}, startTime=${state.startTime}, currentTask=${state.currentTask?.title}, attentionActive=$_isAttentionActive, attentionMessage=$_attentionMessage');

    final pageTitle = _pageTitleForDestination();

    // If attention is active, show attention message but preserve session info if possible
    if (_isAttentionActive && _attentionMessage != null) {
      String title;
      if (state.isActive && state.startTime != null) {
        // Show attention message but keep session timer visible
        final elapsed = DateTime.now().difference(state.startTime!);
        final elapsedStr = _formatDuration(elapsed);
        if (state.currentTask?.title != null && state.currentTask!.title.isNotEmpty) {
          title = '$elapsedStr • ${state.currentTask!.title} — $_attentionMessage';
        } else {
          title = '$elapsedStr — $_attentionMessage';
        }
      } else {
        // No active session, just show attention message
        title = _attentionMessage!;
      }
      final fullTitle = pageTitle.isNotEmpty ? '$pageTitle — $title' : title;
      print('[TAB_TITLE] Setting document.title to (attention): $fullTitle');
      updateDocumentTitle(fullTitle);
      return;
    }

    // Normal title logic (no attention active)
    if (state.isActive && state.startTime != null) {
      final elapsed = DateTime.now().difference(state.startTime!);
      final elapsedStr = _formatDuration(elapsed);
      String title;
      if (state.currentTask?.title != null && state.currentTask!.title.isNotEmpty) {
        title = '$elapsedStr • ${state.currentTask!.title}';
      } else {
        title = elapsedStr;
      }
      final fullTitle = pageTitle.isNotEmpty ? '$pageTitle — $title' : title;
      print('[TAB_TITLE] Setting document.title to: $fullTitle');
      updateDocumentTitle(fullTitle);
      return;
    }
    final fullTitle = pageTitle.isNotEmpty ? pageTitle : 'IntelliBreak';
    print('[TAB_TITLE] Setting document.title to: $fullTitle');
    updateDocumentTitle(fullTitle);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    print('[TAB_TITLE] build');
    // No longer updating document.title here; done via timer, visibility, and state listener.
    return const SizedBox.shrink();
  }
}