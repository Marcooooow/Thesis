// Copyright 2024 IntelliBreak. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Notification alert service.
///
/// Provides cross-platform (web/non-web) access to browser notifications,
/// notification sounds, and tab attention indicators.
///
/// The actual implementation is selected via conditional export:
/// - `notification_alert_service_web.dart` on Flutter Web (uses `dart:js_interop` + `package:web`)
/// - `notification_alert_service_stub.dart` on other platforms (no-op)
///
/// Usage:
/// ```dart
/// // Initialize audio context on first user interaction
/// await NotificationAlertService.initializeAudioContext();
///
/// // Show browser notification
/// NotificationAlertService.showBrowserNotification(
///   'Break Reminder',
///   'Time for a short break!',
///   tag: 'break-reminder',
///   onClick: () => navigateToDashboard(),
/// );
///
/// // Play notification sound
/// NotificationAlertService.playNotificationSound('break');
///
/// // Trigger tab attention (delegates to TabTitleTicker)
/// NotificationAlertService.triggerTabAttention('🔔 Break Reminder');
/// ```

library;

export 'notification_alert_service_stub.dart'
    if (dart.library.js_interop) 'notification_alert_service_web.dart';