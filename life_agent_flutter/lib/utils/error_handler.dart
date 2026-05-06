import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// User-friendly error message from an exception.
String friendlyErrorMessage(Object error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Please check your internet and try again.';
      case DioExceptionType.connectionError:
        return 'No internet connection. Please check your network settings.';
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode;
        if (status == 401) return 'Session expired. Please sign in again.';
        if (status == 403) return 'You don\'t have permission for this action.';
        if (status == 404) return 'The requested resource was not found.';
        if (status == 429) return 'Too many requests. Please wait a moment.';
        if (status != null && status >= 500) {
          return 'Server error ($status). Please try again later.';
        }
        return 'Something went wrong. Please try again.';
      case DioExceptionType.cancel:
        return 'Request was cancelled.';
      case DioExceptionType.badCertificate:
        return 'Secure connection failed. Please try again.';
      default:
        return 'An unexpected error occurred. Please try again.';
    }
  }
  final msg = error.toString();
  if (msg.contains('Invalid login credentials')) {
    return 'Invalid email or password.';
  }
  if (msg.contains('Email not confirmed')) {
    return 'Please verify your email before signing in.';
  }
  if (msg.contains('User already registered')) {
    return 'An account with this email already exists.';
  }
  return msg.length > 120 ? '${msg.substring(0, 120)}…' : msg;
}

/// Show a snackbar with a retry action.
void showErrorSnackBar(
  BuildContext context,
  Object error, {
  VoidCallback? onRetry,
}) {
  if (!context.mounted) return;

  final msg = friendlyErrorMessage(error);
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: Duration(seconds: onRetry != null ? 8 : 4),
      content: Text(msg),
      action: onRetry != null
          ? SnackBarAction(
              label: 'Retry',
              textColor: Theme.of(context).colors.accent,
              onPressed: onRetry,
            )
          : null,
    ),
  );
}

/// Show a success snackbar.
void showSuccessSnackBar(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 3),
      content: Row(
        children: [
          Icon(
            Icons.check_circle,
            color: Theme.of(context).colors.success,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

/// Whether an error indicates the user's session has expired.
bool isAuthError(Object error) {
  if (error is DioException) {
    return error.response?.statusCode == 401;
  }
  return error.toString().contains('401') ||
      error.toString().contains('JWT') ||
      error.toString().contains('token') &&
          error.toString().contains('expired');
}
