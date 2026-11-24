// Copyright 2024 IntelliBreak. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

/// Stub implementation of NotificationAlertService for non-web platforms.
///
/// All methods are no-ops. Used on mobile, desktop, and test environments
/// where browser APIs are not available.

class NotificationAlertService {
  static bool _audioInitialized = false;

  static Future<void> initializeAudioContext() async {
    // No-op on non-web platforms
    _audioInitialized = true;
  }

  static Future<String> getNotificationPermission() async {
    return 'unsupported';
  }

  static Future<String> requestNotificationPermission() async {
    return 'unsupported';
  }

  static void showBrowserNotification(
    String title,
    String body, {
    String? tag,
    VoidCallback? onClick,
  }) {
    // No-op on non-web platforms
  }

  static void playNotificationSound(String soundType) {
    // No-op on non-web platforms
  }

  static void triggerTabAttention(String message) {
    // No-op on non-web platforms
  }

  static void clearTabAttention() {
    // No-op on non-web platforms
  }
}