import 'package:as_grinta/core/security/password_policy.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/name_validation.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/core/widgets/photo_crop_preview.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _surnomController;
  String? _localError;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(authControllerProvider).profile;
    _firstNameController = TextEditingController(
      text: profile?.firstName ?? '',
    );
    _lastNameController = TextEditingController(text: profile?.lastName ?? '');
    _surnomController = TextEditingController(text: profile?.surnom ?? '');
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _surnomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final profile = authState.profile;
    final busy = authState.isLoading;
    final displayName = profile?.fullName.isNotEmpty == true
        ? profile!.fullName
        : 'Profil utilisateur';

    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              border: Border.all(
                color: AppTheme.outline.withValues(alpha: .56),
              ),
            ),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.surfaceHigh,
                        border: Border.all(
                          color: AppTheme.primaryBright.withValues(alpha: .36),
                        ),
                      ),
                      child: PlayerAvatar(
                        photoUrl: profile?.photoUrl,
                        name: profile?.displayName ?? '',
                        size: 96,
                      ),
                    ),
                    Positioned(
                      right: -2,
                      bottom: 0,
                      child: Material(
                        color: AppTheme.primary,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: busy ? null : _pickAndUploadPhoto,
                          child: const Padding(
                            padding: EdgeInsets.all(9),
                            child: Icon(
                              Icons.photo_camera_rounded,
                              size: 17,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  displayName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.25,
                      ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if ((profile?.username ?? '').isNotEmpty)
                      _ProfileMetaChip(
                        icon: Icons.alternate_email_rounded,
                        label: profile!.username!,
                      ),
                    _ProfileMetaChip(
                      icon: Icons.shield_outlined,
                      label: profile == null
                          ? 'Rôle inconnu'
                          : switch (profile.role) {
                              AuthRole.admin => 'Admin',
                              AuthRole.pronostiqueur => 'Joueur',
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Ta photo apparaît sur les compositions.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.textFaint),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _SectionHeading(
            icon: Icons.person_outline_rounded,
            title: 'Informations personnelles',
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _firstNameController,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Prénom',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _lastNameController,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nom',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _surnomController,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Surnom (optionnel)',
                      prefixIcon: Icon(Icons.sports_soccer_rounded),
                      helperText: 'Il s’affiche à la place du prénom.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : _saveProfile,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: GrintaProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: const Text('Enregistrer les modifications'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : () => _changePassword(context),
            icon: const Icon(Icons.lock_reset_rounded),
            label: const Text('Changer le mot de passe'),
          ),
          if (_localError != null || authState.error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.error.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: .3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _localError ?? authState.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (ref.watch(isAdminViewProvider)) ...[
            const SizedBox(height: 24),
            const _SectionHeading(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Administration',
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => context.push('/admin'),
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: const Text('Ouvrir l’administration'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final cropped = await cropProfilePhoto(context, bytes);
    if (cropped == null) return;
    await ref
        .read(authControllerProvider.notifier)
        .uploadPhoto(bytes: cropped, fileExt: 'png');
    if (!mounted) return;
    final error = ref.read(authControllerProvider).error;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error ?? 'Photo mise à jour.')));
  }

  Future<void> _saveProfile() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final surnom = _surnomController.text.trim();
    if (firstName.isEmpty || lastName.isEmpty) {
      setState(() => _localError = 'Le prénom et le nom sont obligatoires.');
      return;
    }
    if (!isValidPersonName(firstName) || !isValidPersonName(lastName)) {
      setState(
        () => _localError =
            'Le prénom et le nom ne doivent contenir que des lettres '
                '(ni emoji, ni chiffre, ni symbole).',
      );
      return;
    }
    if (surnom.isNotEmpty && !isValidPersonName(surnom)) {
      setState(
        () => _localError =
            'Le surnom ne doit contenir que des lettres (ni emoji, ni chiffre, '
                'ni symbole).',
      );
      return;
    }
    setState(() => _localError = null);
    await ref.read(authControllerProvider.notifier).updateProfile(
          firstName: firstName,
          lastName: lastName,
          surnom: surnom,
        );
    if (!mounted) return;
    if (ref.read(authControllerProvider).error == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profil enregistré.')));
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final passwordController = TextEditingController();
    final confirmationController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        String? validationError;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Changer le mot de passe'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Un AutofillGroup dédié + un seul champ marqué
                // "newPassword" : avec deux champs identiquement tagués,
                // certains navigateurs (Safari en particulier) confondent
                // les deux champs après la confirmation et le premier
                // redevient impossible à retoucher (le clavier ne se
                // réaffiche plus).
                AutofillGroup(
                  child: Column(
                    children: [
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: const InputDecoration(
                          labelText: 'Nouveau mot de passe',
                          helperText: PasswordPolicy.helperText,
                          helperMaxLines: 2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmationController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirmation',
                        ),
                      ),
                    ],
                  ),
                ),
                if (validationError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    validationError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () {
                  final password = passwordController.text;
                  final policyError = PasswordPolicy.validate(password);
                  final error = policyError ??
                      (password != confirmationController.text
                          ? 'Les deux mots de passe ne correspondent pas.'
                          : null);
                  if (error != null) {
                    setDialogState(() => validationError = error);
                    return;
                  }
                  Navigator.pop(dialogContext, password);
                },
                child: const Text('Modifier'),
              ),
            ],
          ),
        );
      },
    );
    passwordController.dispose();
    confirmationController.dispose();
    if (result == null || !mounted) return;
    await ref.read(authControllerProvider.notifier).updatePassword(result);
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primaryBright),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _ProfileMetaChip extends StatelessWidget {
  const _ProfileMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.outline.withValues(alpha: .44)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.textFaint),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
