import 'dart:convert';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PersonalDataRepository {
  const PersonalDataRepository(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>> exportMyData() async {
    final response = await _client.rpc('export_my_personal_data');
    if (response is Map<String, dynamic>) return response;
    if (response is Map) return Map<String, dynamic>.from(response);
    throw StateError('L’export personnel est indisponible.');
  }

  static String prettyJson(Map<String, dynamic> data) {
    return const JsonEncoder.withIndent('  ').convert(data);
  }
}

final personalDataRepositoryProvider = Provider<PersonalDataRepository>((ref) {
  return PersonalDataRepository(ref.watch(supabaseClientProvider));
});
