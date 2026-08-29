import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isLoginMode = true;
  bool _isSubmitting = false;
  bool _isGoogleSubmitting = false;
  bool _obscurePassword = true;

  /// Shown inside the card rather than only as a snackbar.
  ///
  /// A snackbar that has already timed out leaves the user looking at a form
  /// with no idea why nothing happened.
  String? _error;
  String? _notice;

  bool get _isBusy => _isSubmitting || _isGoogleSubmitting;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
      _notice = null;
    });

    final message = _isLoginMode
        ? await AuthService.signInWithEmailAndPassword(
            email: _emailController.text,
            password: _passwordController.text,
          )
        : await AuthService.registerWithEmailAndPassword(
            email: _emailController.text,
            password: _passwordController.text,
            name: _nameController.text,
          );

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _error = message;
    });
  }

  Future<void> _signInWithGoogle() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isGoogleSubmitting = true;
      _error = null;
      _notice = null;
    });

    final message = await AuthService.signInWithGoogle();

    if (!mounted) return;
    setState(() {
      _isGoogleSubmitting = false;
      _error = message;
    });
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _error = 'Enter your email address first, then tap this again.';
        _notice = null;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
      _notice = null;
    });

    final message = await AuthService.sendPasswordReset(email);

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _error = message;
      _notice = message == null
          ? 'If an account exists for $email, a reset link is on its way.'
          : null;
    });
  }

  void _setMode(bool loginMode) {
    if (_isLoginMode == loginMode || _isBusy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoginMode = loginMode;
      _error = null;
      _notice = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: DecoratedBox(
        // Echoes the balance card and report header, so the very first screen
        // already looks like the rest of the app instead of a plain slab.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.primary.withValues(alpha: 0.16),
              colorScheme.appBackground,
              colorScheme.appBackground,
            ],
            stops: const [0, 0.45, 1],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.gapXl,
                vertical: AppTokens.gapXl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _BrandMark(),
                    const SizedBox(height: AppTokens.gapXl),
                    _AuthCard(
                      formKey: _formKey,
                      isLoginMode: _isLoginMode,
                      isSubmitting: _isSubmitting,
                      isGoogleSubmitting: _isGoogleSubmitting,
                      obscurePassword: _obscurePassword,
                      error: _error,
                      notice: _notice,
                      nameController: _nameController,
                      emailController: _emailController,
                      passwordController: _passwordController,
                      onModeChanged: _setMode,
                      onToggleObscure: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      onSubmit: _submit,
                      onGoogle: _signInWithGoogle,
                      onForgotPassword: _forgotPassword,
                    ),
                    const SizedBox(height: AppTokens.gapXl),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppTokens.gapXs + 2),
                        Flexible(
                          child: Text(
                            'Your records stay private to your account.',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusXl),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.30),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            'assets/icon.png',
            fit: BoxFit.cover,
            // The launcher icon is the brand; if it is ever missing the screen
            // should still render rather than throw.
            errorBuilder: (context, error, stack) => ColoredBox(
              color: colorScheme.primary,
              child: Icon(
                Icons.account_balance_wallet_rounded,
                color: colorScheme.onPrimary,
                size: 42,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppTokens.gapLg),
        Text(
          'Smart Expense',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 30,
            fontWeight: FontWeight.w900,
            height: 1.1,
          ),
        ),
        const SizedBox(height: AppTokens.gapSm),
        Text(
          'Track what comes in, see where it goes.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 14,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _AuthCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final bool isLoginMode;
  final bool isSubmitting;
  final bool isGoogleSubmitting;
  final bool obscurePassword;
  final String? error;
  final String? notice;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;
  final VoidCallback onGoogle;
  final VoidCallback onForgotPassword;

  const _AuthCard({
    required this.formKey,
    required this.isLoginMode,
    required this.isSubmitting,
    required this.isGoogleSubmitting,
    required this.obscurePassword,
    required this.error,
    required this.notice,
    required this.nameController,
    required this.emailController,
    required this.passwordController,
    required this.onModeChanged,
    required this.onToggleObscure,
    required this.onSubmit,
    required this.onGoogle,
    required this.onForgotPassword,
  });

  bool get _isBusy => isSubmitting || isGoogleSubmitting;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppTokens.gapXl),
      decoration: BoxDecoration(
        color: colorScheme.appCard,
        borderRadius: BorderRadius.circular(AppTokens.radiusXl),
        border: Border.all(color: colorScheme.appBorder),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadowAt(0.07),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ModeSwitch(
              isLoginMode: isLoginMode,
              enabled: !_isBusy,
              onChanged: onModeChanged,
            ),
            const SizedBox(height: AppTokens.gapXl),
            if (error != null) ...[
              _Banner(
                message: error!,
                icon: Icons.error_outline_rounded,
                color: colorScheme.appExpense,
              ),
              const SizedBox(height: AppTokens.gapLg),
            ],
            if (notice != null) ...[
              _Banner(
                message: notice!,
                icon: Icons.mark_email_read_outlined,
                color: colorScheme.appIncome,
              ),
              const SizedBox(height: AppTokens.gapLg),
            ],
            // Animated so switching modes slides the name field in instead of
            // snapping the card to a new height.
            AnimatedSize(
              duration: AppTokens.motionFast,
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: isLoginMode
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: nameController,
                          enabled: !_isBusy,
                          textInputAction: TextInputAction.next,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.name],
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          validator: (value) {
                            if (isLoginMode) return null;
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppTokens.gapLg),
                      ],
                    ),
            ),
            TextFormField(
              controller: emailController,
              enabled: !_isBusy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your email';
                }
                if (!value.contains('@') || !value.contains('.')) {
                  return 'Please enter a valid email';
                }
                return null;
              },
            ),
            const SizedBox(height: AppTokens.gapLg),
            TextFormField(
              controller: passwordController,
              enabled: !_isBusy,
              obscureText: obscurePassword,
              textInputAction: TextInputAction.done,
              autofillHints: [
                isLoginMode
                    ? AutofillHints.password
                    : AutofillHints.newPassword,
              ],
              onFieldSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: isLoginMode ? null : 'At least 6 characters',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: obscurePassword ? 'Show password' : 'Hide password',
                  icon: Icon(
                    obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: onToggleObscure,
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password';
                }
                if (!isLoginMode && value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),
            if (isLoginMode)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isBusy ? null : onForgotPassword,
                  child: const Text('Forgot password?'),
                ),
              )
            else
              const SizedBox(height: AppTokens.gapLg),
            const SizedBox(height: AppTokens.gapSm),
            FilledButton(
              onPressed: _isBusy ? null : onSubmit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : Text(isLoginMode ? 'Sign in' : 'Create account'),
            ),
            const SizedBox(height: AppTokens.gapXl),
            Row(
              children: [
                Expanded(child: Divider(color: colorScheme.appBorder)),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.gapMd,
                  ),
                  child: Text(
                    'or continue with',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: colorScheme.appBorder)),
              ],
            ),
            const SizedBox(height: AppTokens.gapLg),
            OutlinedButton.icon(
              onPressed: _isBusy ? null : onGoogle,
              icon: isGoogleSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const SizedBox(width: 20, height: 20, child: _GoogleGlyph()),
              label: const Text('Continue with Google'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.onSurface,
                minimumSize: const Size.fromHeight(52),
                side: BorderSide(color: colorScheme.appBorder),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sign in / Create toggle.
class _ModeSwitch extends StatelessWidget {
  final bool isLoginMode;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ModeSwitch({
    required this.isLoginMode,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.appCardMuted,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Row(
        children: [
          _ModeTab(
            label: 'Sign in',
            selected: isLoginMode,
            enabled: enabled,
            onTap: () => onChanged(true),
          ),
          _ModeTab(
            label: 'Create',
            selected: !isLoginMode,
            enabled: enabled,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ModeTab({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppTokens.motionFast,
            curve: Curves.easeOut,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? colorScheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color color;

  const _Banner({
    required this.message,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTokens.gapMd),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppTokens.gapSm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Google mark, drawn rather than shipped as an asset.
///
/// The previous button used a plain letter "G" in the app's own teal, which
/// read as stray text rather than a provider badge.
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _GoogleGlyphPainter());
  }
}

class _GoogleGlyphPainter extends CustomPainter {
  const _GoogleGlyphPainter();

  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  static double _rad(double degrees) => degrees * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.23;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Canvas angles run clockwise from 3 o'clock, with y pointing down.
    void arc(Color color, double startDeg, double sweepDeg) {
      canvas.drawArc(
        rect,
        _rad(startDeg),
        _rad(sweepDeg),
        false,
        paint..color = color,
      );
    }

    arc(_blue, -62, 62); // upper right, running down to the bar
    arc(_green, 42, 90); // bottom
    arc(_yellow, 132, 76); // left
    arc(_red, 208, 90); // upper left across the top

    // The horizontal bar that turns the ring into a G.
    final centerY = size.height / 2;
    final barHeight = stroke * 0.95;
    canvas.drawRect(
      Rect.fromLTRB(
        size.width * 0.52,
        centerY - barHeight / 2,
        size.width - stroke * 0.1,
        centerY + barHeight / 2,
      ),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(covariant _GoogleGlyphPainter oldDelegate) => false;
}
