// ignore_for_file: deprecated_member_use

import 'dart:html' as html;

Future<void> downloadIcsFile({
  required String contents,
  required String filename,
}) async {
  final blob = html.Blob(<Object>[contents], 'text/calendar;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';

  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
