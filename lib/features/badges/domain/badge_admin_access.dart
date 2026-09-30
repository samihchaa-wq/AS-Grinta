import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Gestion sensible des badges : volontairement limitée à deux comptes.
///
/// Ce contrôle côté Flutter sert à masquer l'entrée et à bloquer la route.
/// Les écritures restent également protégées côté Supabase.
const badgeAdminProfileIds = <String>{
  '89f24276-dac0-4046-87a3-6c28e48fef3a',
  '5c681291-ec75-47ed-8bee-1b538b69cefe',
};

bool canManageBadges(AuthProfile? profile) {
  final id = profile?.id;
  return profile?.role.isAdmin == true &&
      profile?.isActive == true &&
      id != null &&
      badgeAdminProfileIds.contains(id);
}

final canManageBadgesProvider = Provider<bool>((ref) {
  return canManageBadges(ref.watch(authControllerProvider).profile);
});
