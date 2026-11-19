// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html';

void updateDocumentTitle(String title) {
  print('[TAB_TITLE] updateDocumentTitle called with: $title');
  if (document.title != title) {
    document.title = title;
    print('[TAB_TITLE] document.title set to: $document.title');
  } else {
    print('[TAB_TITLE] document.title unchanged: $document.title');
  }
}

void registerVisibilityCallback(void Function() onVisible) {
  print('[TAB_TITLE] registering visibility callback');
  document.onVisibilityChange.listen((_) {
    if (document.hidden == false) {
      print('[TAB_TITLE] visibility callback fired (document visible)');
      onVisible();
    }
  });
}
