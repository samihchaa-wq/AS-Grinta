import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/feature_flags/domain/feature_flags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class FeatureFlagsRepository {
  Future<FeatureFlagsSnapshot> fetchFeatureFlags();

  Future<FeatureFlagsSnapshot> setSportsManagementEnabled({
    required bool enabled,
    String? justification,
  });
}

class SupabaseFeatureFlagsRepository implements FeatureFlagsRepository {
  SupabaseFeatureFlagsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<FeatureFlagsSnapshot> fetchFeatureFlags() async {
    final response = await _client.rpc('get_public_feature_flags');
    return FeatureFlagsSnapshot.fromRpc(response);
  }

  @override
  Future<FeatureFlagsSnapshot> setSportsManagementEnabled({
    required bool enabled,
    String? justification,
  }) async {
    final response = await _client.rpc(
      'set_sports_management_enabled',
      params: {
        'p_enabled': enabled,
        'p_justification': justification?.trim().isEmpty == true
            ? null
            : justification?.trim(),
      },
    );
    return FeatureFlagsSnapshot.fromRpc(response);
  }
}

final featureFlagsRepositoryProvider = Provider<FeatureFlagsRepository>((ref) {
  return SupabaseFeatureFlagsRepository(ref.watch(supabaseClientProvider));
});
