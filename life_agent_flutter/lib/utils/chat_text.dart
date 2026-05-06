import 'dart:convert';

/// Convert backend chat `reply` payloads into readable text.
///
/// We avoid raw `.toString()` on Maps because it looks untrusted/unpolished.
String normalizeReplyText(dynamic reply) {
  if (reply == null) return 'No response';
  if (reply is String) return reply;
  if (reply is num || reply is bool) return reply.toString();

  if (reply is Map || reply is List) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(reply);
    } catch (_) {
      return reply.toString();
    }
  }

  return reply.toString();
}

