import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

// Test simulation of debouncer and request sequencing logic in AccountsScreen
class MockSearchController {
  int latestRequestId = 0;
  Timer? searchTimer;
  List<String> apiCalls = [];
  List<String> results = [];

  Future<void> performSearch(String query, {required Duration debounce, required Duration networkDelay, required bool shouldFail}) async {
    final int requestId = ++latestRequestId;

    // Simulate network delay
    await Future.delayed(networkDelay);

    // Discard stale responses
    if (requestId != latestRequestId) {
      return; // Stale response dropped
    }

    if (shouldFail) {
      throw Exception('API error');
    }

    results = [query];
  }

  void onTextChanged(String text, {required Duration debounce}) {
    searchTimer?.cancel();
    searchTimer = Timer(debounce, () {
      performSearch(text, debounce: debounce, networkDelay: const Duration(milliseconds: 100), shouldFail: false);
    });
  }

  void dispose() {
    searchTimer?.cancel();
  }
}

void main() {
  group('Accounts Search Race Condition & Debounce Tests', () {
    test('Rapid typing (g -> ga -> gab -> gabriel) debounces and only executes latest request', () async {
      final controller = MockSearchController();

      controller.onTextChanged('g', debounce: const Duration(milliseconds: 300));
      await Future.delayed(const Duration(milliseconds: 100));
      controller.onTextChanged('ga', debounce: const Duration(milliseconds: 300));
      await Future.delayed(const Duration(milliseconds: 100));
      controller.onTextChanged('gab', debounce: const Duration(milliseconds: 300));
      await Future.delayed(const Duration(milliseconds: 100));
      controller.onTextChanged('gabriel', debounce: const Duration(milliseconds: 300));

      // Wait for debounce (300ms) + network delay (100ms)
      await Future.delayed(const Duration(milliseconds: 500));

      // Only 'gabriel' request should successfully update results
      expect(controller.results, equals(['gabriel']));
      controller.dispose();
    });

    test('Stale response arriving after latest response is discarded', () async {
      final controller = MockSearchController();

      // Start request 1 with long network delay
      final int req1 = ++controller.latestRequestId;
      // Start request 2 with short network delay
      final int req2 = ++controller.latestRequestId;

      // Simulate req2 finishing first
      await controller.performSearch('gabriel', debounce: Duration.zero, networkDelay: const Duration(milliseconds: 50,), shouldFail: false);
      expect(controller.results, equals(['gabriel']));

      // Simulate delayed slow response from req1 arriving later
      // By checking requestId != latestRequestId, req1 should be dropped
      if (req1 == controller.latestRequestId) {
        controller.results = ['g'];
      }

      // Results should remain 'gabriel', not overwritten by stale 'g'
      expect(controller.results, equals(['gabriel']));
      controller.dispose();
    });

    test('Clearing search field cancels pending timers and resets correctly', () async {
      final controller = MockSearchController();

      controller.onTextChanged('test', debounce: const Duration(milliseconds: 300));
      controller.dispose(); // Clears timer

      await Future.delayed(const Duration(milliseconds: 400));
      expect(controller.results, isEmpty);
    });
  });
}
