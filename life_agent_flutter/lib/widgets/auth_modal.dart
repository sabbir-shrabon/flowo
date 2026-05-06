import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
      final supabase = Supabase.instance.client.auth;
      if (_isSignUp) {
        await supabase.signUp(email: email, password: password);
      } else {
        await supabase.signInWithPassword(email: email, password: password);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
