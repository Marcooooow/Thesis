import 'package:flutter/material.dart';

/// Centralized error handling utility.
///
/// Use this function to show errors in a consistent way across the app.
/// - For normal recoverable errors, use [isDialog] = false (shows a SnackBar).
/// - For important workflow errors that block the user's action, use [isDialog] = true (shows a Dialog).
///
/// The caller must ensure the widget is mounted before calling this function.
void showError(BuildContext context, Object error, {bool isDialog = false}) {
  final String message = error.toString();
  if (isDialog) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(ctx).pop();
              },
            ),
          ],
        );
      },
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}