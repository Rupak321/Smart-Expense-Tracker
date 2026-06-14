// lib/features/auth/presentation/screens/login_screen.dart

import 'package:flutter/material.dart';
import 'main_navigation.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoginMode = true;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Brand palette
  static const _bgDark = Color(0xFF0D1117);
  static const _surface = Color(0xFF161B22);
  static const _cardBg = Color(0xFF1C2333);
  static const _teal = Color(0xFF2DD4BF);
  static const _tealDim = Color(0xFF14B8A6);
  static const _accent = Color(0xFF7C3AED);
  static const _textPrimary = Color(0xFFF0F6FF);
  static const _textMuted = Color(0xFF8B949E);
  static const _inputBg = Color(0xFF0D1117);
  static const _inputBorder = Color(0xFF30363D);

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _onLoginPressed() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainNavigation()),
      );
    }
  }

  void _switchMode(bool isLogin) {
    setState(() => _isLoginMode = isLogin);
    _fadeController
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Stack(
        children: [
          // ── Decorative blurred orbs ──────────────────────────
          Positioned(
            left: -60,
            top: -60,
            child: _Orb(size: 240, color: _teal.withValues(alpha: 0.12)),
          ),
          Positioned(
            right: -80,
            top: 80,
            child: _Orb(size: 200, color: _accent.withValues(alpha: 0.15)),
          ),
          Positioned(
            left: 40,
            bottom: -80,
            child: _Orb(size: 180, color: _teal.withValues(alpha: 0.08)),
          ),

          // ── Content ──────────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo + brand mark
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_teal, _accent],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: _teal.withValues(alpha: 0.35),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                          child: Icon(
                            Icons.account_balance_wallet_rounded,
                            color: Theme.of(context).colorScheme.onPrimary,
                            size: 32,
                          ),
                      ),
                    ),
                    const SizedBox(height: 20),
                      Center(
                        child: Text(
                          'SpendWise',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onBackground,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                      Center(
                        child: Text(
                          'Track every rupee, effortlessly.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onBackground.withValues(alpha: 0.85),
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    const SizedBox(height: 36),

                    // ── Card ──────────────────────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: _cardBg,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: _inputBorder,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 40,
                            offset: const Offset(0, 20),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Tab switcher — pill style
                          Container(
                            margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: _surface,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                _TabChip(
                                  label: 'Sign In',
                                  active: _isLoginMode,
                                  onTap: () => _switchMode(true),
                                ),
                                _TabChip(
                                  label: 'Create Account',
                                  active: !_isLoginMode,
                                  onTap: () => _switchMode(false),
                                ),
                              ],
                            ),
                          ),

                          // Form area
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (!_isLoginMode) ...[
                                    _InputField(
                                      label: 'Full Name',
                                      hint: 'Rupak Shrestha',
                                      icon: Icons.badge_outlined,
                                      textInputAction: TextInputAction.next,
                                      validator: (v) => (v == null || v.trim().isEmpty)
                                          ? 'Enter your full name'
                                          : null,
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  _InputField(
                                    label: 'Username',
                                    hint: 'rupak@987',
                                    icon: Icons.alternate_email_rounded,
                                    controller: _usernameController,
                                    textInputAction: TextInputAction.next,
                                    validator: (v) => (v == null || v.trim().isEmpty)
                                        ? 'Enter your username'
                                        : null,
                                  ),
                                  const SizedBox(height: 16),
                                  _InputField(
                                    label: 'Password',
                                    hint: '••••••••••',
                                    icon: Icons.lock_outline_rounded,
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    textInputAction: TextInputAction.done,
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        color: _textMuted,
                                        size: 20,
                                      ),
                                      onPressed: () => setState(
                                          () => _obscurePassword = !_obscurePassword),
                                    ),
                                    validator: (v) => (v == null || v.isEmpty)
                                        ? 'Enter your password'
                                        : null,
                                  ),
                                  if (_isLoginMode) ...[
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        'Forgot password?',
                                        style: TextStyle(
                                          color: _teal.withValues(alpha: 0.85),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 28),

                                  // CTA button
                                  _GradientButton(
                                    label: _isLoginMode ? 'Sign In' : 'Create Account',
                                    onPressed: _onLoginPressed,
                                  ),

                                  const SizedBox(height: 20),

                                  // Divider
                                  Row(
                                    children: [
                                      const Expanded(
                                          child: Divider(color: _inputBorder, thickness: 1)),
                                      Padding(
                                        padding:
                                            const EdgeInsets.symmetric(horizontal: 12),
                                        child: Text(
                                          'or continue with',
                                          style: TextStyle(
                                              color: _textMuted.withValues(alpha: 0.7),
                                              fontSize: 12),
                                        ),
                                      ),
                                      const Expanded(
                                          child: Divider(color: _inputBorder, thickness: 1)),
                                    ],
                                  ),

                                  const SizedBox(height: 20),

                                  // Social row
                                  Row(
                                    children: [
                                      Expanded(
                                          child: _SocialButton(
                                        label: 'Google',
                                        icon: Icons.g_mobiledata_rounded,
                                      )),
                                      const SizedBox(width: 12),
                                      Expanded(
                                          child: _SocialButton(
                                        label: 'Apple',
                                        icon: Icons.apple_rounded,
                                      )),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Footer note
                    Center(
                      child: Text(
                        'UI preview — authentication wired up next.',
                        style: TextStyle(
                          color: _textMuted.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────

class _Orb extends StatelessWidget {
  final double size;
  final Color color;
  const _Orb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  static const _teal = Color(0xFF2DD4BF);
  static const _accent = Color(0xFF7C3AED);
  static const _textPrimary = Color(0xFFF0F6FF);
  static const _textMuted = Color(0xFF8B949E);

  const _TabChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
                    colors: [_teal, _accent],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: active ? _textPrimary : _textMuted,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final Widget? suffixIcon;

  static const _teal = Color(0xFF2DD4BF);
  static const _inputBg = Color(0xFF0D1117);
  static const _inputBorder = Color(0xFF30363D);
  static const _textPrimary = Color(0xFFF0F6FF);
  static const _textMuted = Color(0xFF8B949E);

  const _InputField({
    required this.label,
    required this.hint,
    required this.icon,
    this.controller,
    this.obscureText = false,
    this.textInputAction,
    this.validator,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          textInputAction: textInputAction,
          validator: validator,
          style: const TextStyle(color: _textPrimary, fontSize: 15),
          decoration: InputDecoration(
            filled: true,
            fillColor: _inputBg,
            hintText: hint,
            hintStyle: TextStyle(color: _textMuted.withValues(alpha: 0.5), fontSize: 14),
            prefixIcon: Icon(icon, color: _teal, size: 20),
            suffixIcon: suffixIcon,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _inputBorder, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _teal, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ],
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  static const _teal = Color(0xFF2DD4BF);
  static const _accent = Color(0xFF7C3AED);

  const _GradientButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_teal, _accent],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _teal.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final IconData icon;

  static const _surface = Color(0xFF161B22);
  static const _inputBorder = Color(0xFF30363D);
  static const _textMuted = Color(0xFF8B949E);

  const _SocialButton({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _inputBorder, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () {},
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: _textMuted, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: _textMuted,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}