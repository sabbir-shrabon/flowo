import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../utils/error_handler.dart';

/// Checks if the user is authenticated. If not, shows the auth modal.
/// Calls [onAuthenticated] when the user is already authenticated or
/// after successful sign-in/sign-up. Returns true if authenticated.
Future<bool> requireAuth(
  BuildContext context,
  WidgetRef ref,
  VoidCallback onAuthenticated,
) async {
  final status = ref.read(authProvider.select((s) => s.status));
  if (status == AuthStatus.authenticated) {
    onAuthenticated();
    return true;
  }
  final success = await showAuthModal(context);
  if (success) {
    onAuthenticated();
  }
  return success;
}

/// Shows a Google-style sign-in dialog. Returns true if the user signed in
/// successfully, false if dismissed.
Future<bool> showAuthModal(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => const _AuthModalDialog(),
  ).then((v) => v ?? false);
}

class _AuthModalDialog extends ConsumerStatefulWidget {
  const _AuthModalDialog();

  @override
  ConsumerState<_AuthModalDialog> createState() => _AuthModalDialogState();
}

class _AuthModalDialogState extends ConsumerState<_AuthModalDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final auth = ref.read(authProvider.notifier);
      if (_isSignUp) {
        await auth.signUp(email, password);
      } else {
        await auth.signIn(email, password);
      }
      if (mounted) {
        Navigator.of(context).pop(true);
        // Navigate to today screen after successful sign-in
        context.go('/today');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
      _error = null;
    });

    try {
      await ref.read(authProvider.notifier).signInWithGoogle();
      if (mounted) {
        if (kIsWeb) {
          setState(() => _error = 'Redirecting to Google sign-in...');
          return;
        }
        Navigator.of(context).pop(true);
        context.go('/today');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Close button
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: Icon(Icons.close, size: 20, color: colors.textMuted),
                onPressed: () => Navigator.of(context).pop(false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),

            // Icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome, size: 28, color: colors.accent),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              _isSignUp ? 'Create account' : 'Sign in',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isSignUp
                  ? 'Start your adaptive planning journey'
                  : 'Sign in to save your progress & plans',
              style: TextStyle(color: colors.textSecondary, fontSize: 13.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Error
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: colors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: colors.error, fontSize: 12.5),
                ),
              ),

            // Google Sign-in Button
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _isGoogleLoading ? null : _signInWithGoogle,
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: colors.textPrimary,
                  side: BorderSide(
                    color: colors.textMuted.withValues(alpha: 0.3),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: _isGoogleLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _GoogleLogo(size: 18),
                label: Text(
                  _isSignUp ? 'Sign up with Google' : 'Sign in with Google',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Divider
            Row(
              children: [
                Expanded(
                  child: Divider(
                    color: colors.textMuted.withValues(alpha: 0.3),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'or',
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Divider(
                    color: colors.textMuted.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Email
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Email',
                hintStyle: TextStyle(color: colors.textMuted),
                prefixIcon: Icon(
                  Icons.email_outlined,
                  size: 18,
                  color: colors.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Password
            TextField(
              controller: _passwordController,
              obscureText: true,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: _isSignUp
                    ? 'Password (min 6 characters)'
                    : 'Password',
                hintStyle: TextStyle(color: colors.textMuted),
                prefixIcon: Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: colors.textMuted,
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),

            // Submit button
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _isSignUp ? 'Create Account' : 'Sign In',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 14),

            // Toggle sign in / sign up
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _isSignUp
                      ? 'Already have an account?'
                      : "Don't have an account?",
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isSignUp = !_isSignUp;
                      _error = null;
                    });
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                  ),
                  child: Text(
                    _isSignUp ? 'Sign In' : 'Sign Up',
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Google logo widget for OAuth button.
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

/// Paints the Google "G" logo.
class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    // Draw the Google "G" shape
    // Blue arc (right side)
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(
      Rect.fromLTWH(0, 0, w, h),
      -1.5708, // -90 degrees (top)
      2.0944, // 120 degrees
      false,
      paint,
    );

    // Red arc (top left)
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(
      Rect.fromLTWH(0, 0, w, h),
      2.0944, // 120 degrees
      1.0472, // 60 degrees
      false,
      paint,
    );

    // Yellow arc (bottom left)
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(
      Rect.fromLTWH(0, 0, w, h),
      3.1416, // 180 degrees
      1.0472, // 60 degrees
      false,
      paint,
    );

    // Green arc (bottom right)
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(
      Rect.fromLTWH(0, 0, w, h),
      4.1888, // 240 degrees
      1.0472, // 60 degrees
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
