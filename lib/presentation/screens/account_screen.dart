import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/models/user_profile_model.dart';
import '../../../core/theme/app_theme_controller.dart';
import '../../../services/auth_service.dart';
import '../../../services/user_data_service.dart';
import 'bill_reminder_screen.dart';
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
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: _AccountHeader()),
        SliverToBoxAdapter(
          child: StreamBuilder<UserProfileModel?>(
            stream: UserDataService.profileStream(),
            builder: (context, snapshot) {
              final profile = snapshot.data;
              final user = AuthService.currentUser;
              return _ProfileSummary(
                profile: profile,
                authUser: user,
                profileImagePath: _profileImagePath ?? profile?.profileImagePath ?? user?.photoURL,
                onTap: _openPersonalDetails,
              );
            },
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 170),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Settings',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                _SettingsTile(
                  icon: Icons.person_rounded,
                  title: 'Personal Details',
                  subtitle: 'Name, phone, email, occupation, address',
                  onTap: _openPersonalDetails,
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: AppThemeController.themeMode,
                  builder: (context, themeMode, child) {
                    final isDark = themeMode == ThemeMode.dark;

                    return _SettingsSwitchTile(
                      icon: isDark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      title: 'Dark Mode',
                      subtitle: isDark ? 'Dark theme on' : 'Light theme on',
                      value: isDark,
                      onChanged: AppThemeController.setDarkMode,
                    );
                  },
                ),
                const SizedBox(height: 10),
                _SettingsTile(
                  icon: Icons.currency_rupee_rounded,
                  title: 'Currency',
                  subtitle: 'Nepalese Rupee',
                  onTap: () => _showSettingMessage(
                    context,
                    'Currency settings are coming soon',
                  ),
                ),
                const SizedBox(height: 10),
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
                const SizedBox(height: 10),
                _SettingsTile(
                  icon: Icons.info_rounded,
                  title: 'About App',
                  subtitle: 'Smart Expense v1.0.0',
                  onTap: () => _showAboutDialog(context),
                ),
                const SizedBox(height: 12),
                _SettingsTile(
                  icon: Icons.exit_to_app,
                  title: 'Logout',
                  subtitle: 'Sign out',
                  onTap: _logout,
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

  void _showSettingMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Smart Expense',
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.account_balance_wallet,
            color: Theme.of(context).colorScheme.primary),
      ),
      children: const [
        Text(
          'A simple app for tracking income, expenses, and spending habits.',
        ),
      ],
    );
  }

  void _logout() {
    AuthService.logout();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Signed out')));
      // The app will automatically redirect to login screen on next rebuild
    }
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Account',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.manage_accounts_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
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
    final imagePath = profileImagePath ?? profile?.profileImagePath ?? authUser?.photoURL;
    final hasProfileImage = imagePath != null && imagePath.isNotEmpty &&
        (imagePath.startsWith('http') || File(imagePath).existsSync());

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.18),
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
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.onPrimary,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.edit,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                _SummaryLine(icon: Icons.phone_rounded, text: phone),
                const SizedBox(height: 4),
                _SummaryLine(icon: Icons.location_on_rounded, text: address),
              ],
            ),
          ),
        ],
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
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.82), size: 15),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.82),
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

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(context).textTheme.bodySmall?.color ??
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Theme.of(context).colorScheme.primary,
        secondary: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(context).textTheme.bodySmall?.color ??
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
