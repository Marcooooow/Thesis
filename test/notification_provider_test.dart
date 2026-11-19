import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intellibreak/features/notifications/models/notification_model.dart';
import 'package:intellibreak/providers/notification_provider.dart';

void main() {
  group('NotificationProvider', () {
    late NotificationProvider provider;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      // Set default values for SharedPreferences in tests
      SharedPreferences.setMockInitialValues({});
    });

    setUp(() {
      provider = NotificationProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('initializes with empty state', () {
      expect(provider.notifications, isEmpty);
      expect(provider.isLoading, false);
      expect(provider.error, isNull);
      expect(provider.unreadCount, 0);
    });

    test('unreadCount calculates correctly from notifications', () {
      final unreadNotification1 = NotificationModel(
        id: 'notif-1',
        type: 'test',
        title: 'Title 1',
        message: 'Message 1',
        relatedEntityId: null,
        isRead: false,
        isActioned: false,
        createdAt: DateTime(2026, 9, 17),
      );

      final readNotification = NotificationModel(
        id: 'notif-2',
        type: 'test',
        title: 'Title 2',
        message: 'Message 2',
        relatedEntityId: null,
        isRead: true,
        isActioned: false,
        createdAt: DateTime(2026, 9, 17),
      );

      final unreadNotification2 = NotificationModel(
        id: 'notif-3',
        type: 'test',
        title: 'Title 3',
        message: 'Message 3',
        relatedEntityId: null,
        isRead: false,
        isActioned: false,
        createdAt: DateTime(2026, 9, 17),
      );

      // Create a provider and test unreadCount with manual state updates
      provider.testSetNotifications(
        [unreadNotification1, readNotification, unreadNotification2],
      );

      expect(provider.unreadCount, 2);
    });

    test('clear resets all state', () {
      final notification = NotificationModel(
        id: 'notif-1',
        type: 'test',
        title: 'Title',
        message: 'Message',
        relatedEntityId: null,
        isRead: false,
        isActioned: false,
        createdAt: DateTime(2026, 9, 17),
      );

      provider.testSetNotifications([notification]);
      expect(provider.notifications, isNotEmpty);

      provider.clear();

      expect(provider.notifications, isEmpty);
      expect(provider.isLoading, false);
      expect(provider.error, isNull);
    });

    test('listeners are notified on state change', () async {
      var notificationCount = 0;
      provider.addListener(() {
        notificationCount++;
      });

      provider.clear();

      await Future.delayed(const Duration(milliseconds: 10));
      expect(notificationCount, greaterThan(0));
    });
  });
}
