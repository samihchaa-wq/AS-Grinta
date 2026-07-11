// Implémentation hors Web : les notifications push ne sont pas disponibles.
Future<bool> pushSupported() async => false;

Future<String> pushPermission() async => 'unsupported';

Future<String?> pushSubscribe(String vapidPublicKey) async => null;

Future<String?> pushCurrentSubscription() async => null;

Future<String?> pushUnsubscribe() async => null;
