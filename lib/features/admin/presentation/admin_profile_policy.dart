import 'package:as_grinta/features/admin/data/admin_repository.dart';

class AdminProfileGroups {
  const AdminProfileGroups({
    required this.pending,
    required this.validated,
  });

  final List<AdminProfileItem> pending;
  final List<AdminProfileItem> validated;
}

AdminProfileGroups groupAdminProfiles(List<AdminProfileItem> profiles) {
  final pending = <AdminProfileItem>[];
  final validated = <AdminProfileItem>[];

  for (final profile in profiles) {
    if (profile.status == 'pending') {
      pending.add(profile);
    } else {
      validated.add(profile);
    }
  }

  return AdminProfileGroups(
    pending: List<AdminProfileItem>.unmodifiable(pending),
    validated: List<AdminProfileItem>.unmodifiable(validated),
  );
}

class AdminProfileActionPolicy {
  const AdminProfileActionPolicy({
    required this.isSelf,
    required this.isPending,
    required this.isArchived,
  });

  final bool isSelf;
  final bool isPending;
  final bool isArchived;

  bool get canValidate => !isSelf && isPending;
  bool get canReject => !isSelf && isPending;
  bool get canResetPassword => !isSelf && !isPending;
  bool get canArchive => !isSelf && !isPending && !isArchived;
  bool get canReactivate => !isSelf && !isPending && isArchived;
  bool get canDelete => !isSelf && !isPending;
}

AdminProfileActionPolicy adminProfileActionPolicy({
  required AdminProfileItem profile,
  required String? currentUserId,
}) {
  return AdminProfileActionPolicy(
    isSelf: currentUserId != null && currentUserId == profile.id,
    isPending: profile.status == 'pending',
    isArchived: profile.status == 'archived',
  );
}
