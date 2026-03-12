// Web-specific implementation using dart:html
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

String getSignalingUrl() {
  final loc = html.window.location;
  if (loc.hostname == 'localhost' || loc.hostname == '127.0.0.1') {
    return 'ws://localhost:8080';
  }
  return 'wss://screen-viewer-gqu3.onrender.com';
}
