import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/app_lock_service.dart';

/// Stands in front of the app until the device authentication passes.
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _prompting = false;
  bool _refused = false;

  @override
  void initState() {
    super.initState();
    // Prompt as soon as the screen appears, so the usual case is one tap on
    // the sensor rather than a tap to ask and then the sensor.
    WidgetsBinding.instance.addPostFrameCallback((_) => _prompt());
  }

  Future<void> _prompt() async {
    if (_prompting) return;
    setState(() {
      _prompting = true;
      _refused = false;
    });

    final passed = await AppLockService.authenticate();
    if (!mounted) return;

    if (passed) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _prompting = false;
      _refused = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.gapXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.radiusXl),
                ),
                child: Icon(
                  Icons.lock_rounded,
                  size: 40,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppTokens.gapXl),
              Text(
                'SmartExpense is locked',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppTokens.gapSm),
              Text(
                _refused
                    ? 'Authentication was cancelled or did not match.'
                    : 'Confirm it is you to see your records.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppTokens.gapXl),
              if (_prompting)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else
                FilledButton.icon(
                  onPressed: _prompt,
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('Unlock'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
