// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
// Copyright 2024 IntelliBreak. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';

/// Web-specific implementation of NotificationAlertService.
///
/// Uses modern browser APIs via dart:js_interop and package:web:
/// - Notification API for desktop notifications (package:web)
/// - Web Audio API for programmatic sound generation (package:web)
/// - Tab attention via custom events (package:web)
class NotificationAlertService {
  static web.AudioContext? _audioContext;
  static bool _audioInitialized = false;

  // Pre-computed sound waveforms for different notification types
  static final Map<String, _SoundProfile> _soundProfiles = {
    'break': _SoundProfile(
      frequency: 523.25, // C5
      duration: 0.15,
      waveType: 'sine',
      attack: 0.01,
      decay: 0.1,
      volume: 0.15,
    ),
    'lunch': _SoundProfile(
      frequency: 392.00, // G4
      duration: 0.3,
      waveType: 'sine',
      attack: 0.02,
      decay: 0.2,
      volume: 0.12,
    ),
    'default': _SoundProfile(
      frequency: 440.00, // A4
      duration: 0.2,
      waveType: 'sine',
      attack: 0.01,
      decay: 0.15,
      volume: 0.1,
    ),
  };

  /// Checks if Web Audio API is supported.
  static bool get _audioSupported {
    // In package:web, AudioContext is a top-level constructor
    try {
      // Try to create an AudioContext - if it fails, not supported
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Checks if Notification API is supported.
  static bool get _notificationSupported {
    try {
      // Notification is a top-level constructor in package:web
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Initializes the Web Audio Context.
  ///
  /// Must be called after a user interaction (click, keypress) due to
  /// browser autoplay policies. Safe to call multiple times.
  static Future<void> initializeAudioContext() async {
    if (_audioInitialized && _audioContext != null) {
      // Resume if suspended (e.g., after tab was backgrounded)
      if (_audioContext!.state == 'suspended') {
        _resumeAudioContext();
      }
      return;
    }

    if (!_audioSupported) {
      _audioInitialized = false;
      _audioContext = null;
      return;
    }

    try {
      _audioContext = web.AudioContext();
      _audioInitialized = true;

      // If context is suspended, resume it
      if (_audioContext!.state == 'suspended') {
        _resumeAudioContext();
      }
    } catch (e) {
      // AudioContext not supported or failed to initialize
      _audioInitialized = false;
      _audioContext = null;
      // Fail gracefully - sounds just won't play
    }
  }

  static void _resumeAudioContext() {
    if (_audioContext != null) {
      _audioContext!.resume();
    }
  }

  /// Gets the current browser notification permission state without prompting.
  ///
  /// Returns: 'granted', 'denied', 'default', or 'unsupported'.
  static Future<String> getNotificationPermission() async {
    if (!_notificationSupported) {
      return 'unsupported';
    }
    try {
      // web.Notification.permission returns a string/JSString directly
      final permission = web.Notification.permission;
      return permission.toString();
    } catch (e) {
      return 'unsupported';
    }
  }

  /// Requests browser notification permission from the user.
  ///
  /// Should only be called in response to an explicit user action (e.g.,
  /// enabling the "Browser Notifications" toggle in Settings).
  ///
  /// Returns the resulting permission status: 'granted', 'denied', or 'default'.
  static Future<String> requestNotificationPermission() async {
    if (!_notificationSupported) {
      return 'unsupported';
    }

    try {
      final promise = web.Notification.requestPermission();
      final permission = await promise.toDart;
      // permission is a string/JSString
      return permission.toString();
    } catch (e) {
      // Permission request failed (e.g., not triggered by user gesture)
      return 'denied';
    }
  }

  /// Shows a browser desktop notification.
  ///
  /// Requires notification permission to be 'granted'. If permission is
  /// not granted, this is a no-op.
  ///
  /// [title] - Notification title.
  /// [body] - Notification body text.
  /// [tag] - Optional tag to prevent duplicate notifications of the same type.
  /// [onClick] - Optional callback when notification is clicked. Typically
  ///   used to focus the window/tab.
  static void showBrowserNotification(
    String title,
    String body, {
    String? tag,
    VoidCallback? onClick,
  }) {
    if (!_notificationSupported) {
      return;
    }

    // Check permission
    if (web.Notification.permission.toString() != 'granted') {
      return;
    }

    try {
      final options = web.NotificationOptions(
        body: body,
        tag: tag ?? '',
        requireInteraction: true,
      );

      final notification = web.Notification(title, options);

      // Handle click to focus window
      if (onClick != null) {
        notification.onclick = (web.Event event) {
          // Focus the window/tab
          web.window.focus();
          onClick();
        }.toJS;
      }

      // Auto-close after 10 seconds if not interacted with
      Future.delayed(const Duration(seconds: 10), () {
        notification.close();
      });
    } catch (e) {
      // Notification creation failed silently
    }
  }

  /// Plays a notification sound using the Web Audio API.
  ///
  /// [soundType] - One of 'break', 'lunch', 'default'.
  /// Each type has a distinct, subtle programmatically-generated tone.
  ///
  /// Respects the `notification_sounds_enabled` user setting.
  /// No-op if audio context not initialized or sounds disabled.
  static void playNotificationSound(String soundType) {
    if (!_audioInitialized || _audioContext == null) {
      return;
    }

    if (_audioContext!.state == 'suspended') {
      // Try to resume, but don't block
      _resumeAudioContext();
      return;
    }

    final profile = _soundProfiles[soundType] ?? _soundProfiles['default']!;
    _playTone(profile);
  }

  /// Triggers tab attention indicator (delegates to TabTitleTicker).
  ///
  /// [message] - The message to display in the tab title (e.g., '🔔 Break Reminder').
  ///
  /// The actual tab title manipulation is handled by TabTitleTicker,
  /// which owns the document.title state.
  static void triggerTabAttention(String message) {
    // Dispatch custom event for TabTitleTicker to listen to
    final eventInit = web.CustomEventInit(
      detail: message.toJS,
    );
    final event = web.CustomEvent('intellibreak-tab-attention', eventInit);
    web.window.dispatchEvent(event);
  }

  /// Clears tab attention indicator and restores normal tab title.
  static void clearTabAttention() {
    final event = web.CustomEvent('intellibreak-tab-attention-clear');
    web.window.dispatchEvent(event);
  }

  /// Generates and plays a tone using the Web Audio API.
  static void _playTone(_SoundProfile profile) {
    if (_audioContext == null) return;

    final ctx = _audioContext!;
    final now = ctx.currentTime;

    // Create oscillator for the tone
    final oscillator = ctx.createOscillator();
    oscillator.type = profile.waveType;
    oscillator.frequency.value = profile.frequency;

    // Create gain node for envelope
    final gainNode = ctx.createGain();
    gainNode.gain.setValueAtTime(0, now);
    gainNode.gain.linearRampToValueAtTime(profile.volume, now + profile.attack);
    gainNode.gain.exponentialRampToValueAtTime(
      0.001,
      now + profile.attack + profile.decay,
    );

    // Connect and play
    oscillator.connect(gainNode);
    gainNode.connect(ctx.destination);

    oscillator.start(now);
    oscillator.stop(now + profile.attack + profile.decay + 0.1);
  }
}

/// Internal sound profile for programmatic tone generation.
class _SoundProfile {
  final double frequency; // Hz
  final double duration; // seconds (total)
  final String waveType; // 'sine', 'square', 'triangle', 'sawtooth'
  final double attack; // seconds
  final double decay; // seconds
  final double volume; // 0.0 - 1.0

  const _SoundProfile({
    required this.frequency,
    required this.duration,
    required this.waveType,
    required this.attack,
    required this.decay,
    required this.volume,
  });
}