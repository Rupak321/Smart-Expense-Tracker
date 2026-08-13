import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/components/app_widgets.dart';
import '../../../core/models/user_profile_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_controller.dart';
import '../../../services/auth_service.dart';
import '../../../services/user_data_service.dart';
import 'bill_reminder_screen.dart';
import 'categories_screen.dart';
import 'main_navigation.dart';
import 'personal_details_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  String? _profileImagePath;

  @override
  Widget build(BuildContext context) {
    final bottomInset = NavShellInsets.of(context);

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(
          child: ScreenHeader(
            title: 'Account',
            subtitle: 'Profile and app preferences',
            icon: Icons.manage_accounts_rounded,
          ),
        ),
        SliverToBoxAdapter(
          child: StreamBuilder<UserProfileModel?>(
            stream: UserDataService.profileStream(),
            builder: (context, snapshot) {
              final profile = snapshot.data;
              final user = AuthService.currentUser;
              return _ProfileSummary(
                profile: profile,
                authUser: user,
                profileImagePath:
                    _profileImagePath ??
                    profile?.profileImagePath ??
                    user?.photoURL,
                onTap: _openPersonalDetails,
              );
            },
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppTokens.pageGutter,
              AppTokens.gapLg,
              AppTokens.pageGutter,
              bottomInset,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SettingsGroupLabel('Preferences'),
                _SettingsTile(
                  icon: Icons.person_rounded,
                  title: 'Personal Details',
                  subtitle: 'Name, phone, email, occupation, address',
                  onTap: _openPersonalDetails,
                ),
                const SizedBox(height: AppTokens.gapSm),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: AppThemeController.themeMode,
                  builder: (context, themeMode, child) {
                    return _SettingsTile(
                      icon: AppThemeController.iconFor(themeMode),
                      title: 'Appearance',
                      subtitle: AppThemeController.labelFor(themeMode),
                      onTap: _showAppearancePicker,
                    );
                  },
                ),
                const SizedBox(height: AppTokens.gapSm),
                _SettingsTile(
                  icon: Icons.label_rounded,
                  title: 'Categories',
                  subtitle: 'Rename, merge, and tidy up duplicates',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const CategoriesScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.gapSm),
                _SettingsTile(
                  icon: Icons.currency_rupee_rounded,
                  title: 'Currency',
                  subtitle: 'Nepalese Rupee (Rs.)',
                  onTap: () =>
                      _showSettingMessage('Currency settings are coming soon'),
                ),
                const SizedBox(height: AppTokens.gapLg),
                const _SettingsGroupLabel('Reminders'),
                _SettingsTile(
                  icon: Icons.notifications_rounded,
                  title: 'Bill Reminder',
                  subtitle: 'Electricity, internet, rent, EMI alerts',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const BillReminderScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.gapLg),
                const _SettingsGroupLabel('About'),
                _SettingsTile(
                  icon: Icons.info_rounded,
                  title: 'About App',
                  subtitle: 'Smart Expense v1.0.0',
                  onTap: _showAboutDialog,
                ),
                const SizedBox(height: AppTokens.gapSm),
                _SettingsTile(
                  icon: Icons.logout_rounded,
                  title: 'Log out',
                  subtitle: 'Sign out of this device',
                  isDestructive: true,
                  onTap: _confirmLogout,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openPersonalDetails() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const PersonalDetailsScreen()),
    );
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _showSettingMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showAppearancePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: ValueListenableBuilder<ThemeMode>(
            valueListenable: AppThemeController.themeMode,
            builder: (context, themeMode, child) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTokens.gapXl,
                      0,
                      AppTokens.gapXl,
                      AppTokens.gapSm,
                    ),
                    child: Text(
                      'Appearance',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  RadioGroup<ThemeMode>(
                    groupValue: themeMode,
                    onChanged: (value) {
                      if (value != null) {
                        AppThemeController.setThemeMode(value);
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final mode in ThemeMode.values)
                          RadioListTile<ThemeMode>(
                            value: mode,
                            secondary: Icon(AppThemeController.iconFor(mode)),
                            title: Text(AppThemeController.labelFor(mode)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTokens.gapMd),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showAboutDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    showAboutDialog(
      context: context,
      applicationName: 'Smart Expense',
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
        child: Icon(
          Icons.account_balance_wallet_rounded,
          color: colorScheme.primary,
        ),
      ),
      children: const [
        Text(
          'A simple app for tracking income, expenses, and spending habits.',
        ),
      ],
    );
  }

  Future<void> _confirmLogout() async {
    final colorScheme = Theme.of(context).colorScheme;
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need to sign in again to see your data on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (shouldLogout != true) return;

    await AuthService.logout();
    if (mounted) {
      _showSettingMessage('Signed out');
    }
  }
}

class _SettingsGroupLabel extends StatelessWidget {
  final String label;

  const _SettingsGroupLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: AppTokens.gapSm),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 11,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ProfileSummary extends StatelessWidget {
  final UserProfileModel? profile;
  final User? authUser;
  final String? profileImagePath;
  final VoidCallback? onTap;

  const _ProfileSummary({
    required this.profile,
    this.authUser,
    this.profileImagePath,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = profile?.name.trim().isNotEmpty == true
        ? profile!.name
        : authUser?.displayName?.trim().isNotEmpty == true
        ? authUser!.displayName!
        : 'Your Name';
    final phone = profile?.phoneNumber.trim().isNotEmpty == true
        ? profile!.phoneNumber
        : 'Add phone number';
    final address = profile?.address.trim().isNotEmpty == true
        ? profile!.address
        : 'Add address';
    final initial = name == 'Your Name'
        ? 'U'
        : name.substring(0, 1).toUpperCase();
    final imagePath =
        profileImagePath ?? profile?.profileImagePath ?? authUser?.photoURL;
    final hasProfileImage =
        imagePath != null &&
        imagePath.isNotEmpty &&
        (imagePath.startsWith('http') || File(imagePath).existsSync());

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.pageGutter,
        vertical: AppTokens.gapSm,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colorScheme.appHeroGradient,
              ),
              borderRadius: BorderRadius.circular(AppTokens.radiusLg),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.gapLg),
              child: Row(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: colorScheme.appOnHero.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                          image: hasProfileImage
                              ? DecorationImage(
                                  image: imagePath.startsWith('http')
                                      ? NetworkImage(imagePath) as ImageProvider
                                      : FileImage(File(imagePath)),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                      ),
                      if (!hasProfileImage)
                        Text(
                          initial,
                          style: TextStyle(
                            color: colorScheme.appOnHero,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: colorScheme.appCard,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colorScheme.appOnHero,
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.edit_rounded,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: AppTokens.gapLg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.appOnHero,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: AppTokens.gapSm),
                        _SummaryLine(icon: Icons.phone_rounded, text: phone),
                        const SizedBox(height: AppTokens.gapXs),
                        _SummaryLine(
                          icon: Icons.location_on_rounded,
                          text: address,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.appOnHero.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SummaryLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final onHero = Theme.of(
      context,
    ).colorScheme.appOnHero.withValues(alpha: 0.85);

    return Row(
      children: [
        Icon(icon, color: onHero, size: 14),
        const SizedBox(width: AppTokens.gapXs + 2),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: onHero,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = isDestructive ? colorScheme.error : colorScheme.primary;

    return Material(
      color: colorScheme.appCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        side: BorderSide(color: colorScheme.appBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          ),
          child: Icon(icon, color: accent, size: 21),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isDestructive ? colorScheme.error : colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
