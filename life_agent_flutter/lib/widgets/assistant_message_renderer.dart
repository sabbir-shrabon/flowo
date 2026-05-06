import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Renders assistant text as human-readable sections, bullets, and light cards.
///
/// No external packages; intentionally opinionated and minimal.
class AssistantMessageRenderer extends StatelessWidget {
  final String text;
  const AssistantMessageRenderer({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    final jsonWidget = _tryRenderJson(context, trimmed);
    if (jsonWidget != null) return jsonWidget;

    final blocks = _parseText(trimmed);
    if (blocks.isEmpty) {
      return Text(
        trimmed,
        style: TextStyle(
          color: context.colors.textPrimary,
          fontSize: 14,
          height: 1.45,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks
          .map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BlockWidget(block: b),
              ))
          .toList(),
    );
  }

  Widget? _tryRenderJson(BuildContext context, String trimmed) {
    final looksJson = trimmed.startsWith('{') || trimmed.startsWith('[');
    if (!looksJson) return null;
    try {
      final decoded = jsonDecode(trimmed);
      return _JsonWidget(value: decoded);
    } catch (_) {
      return null;
    }
  }

  List<_Block> _parseText(String text) {
    final lines = text.split('\n').map((l) => l.trimRight()).toList();
    final blocks = <_Block>[];

    String? currentTitle;
    final currentBody = <String>[];

    void flush() {
      final bodyText = currentBody.join('\n').trim();
      if ((currentTitle == null || currentTitle!.isEmpty) && bodyText.isEmpty) {
        currentBody.clear();
        currentTitle = null;
        return;
      }
      blocks.add(_Block(title: currentTitle, body: bodyText));
      currentBody.clear();
      currentTitle = null;
    }

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) {
        // paragraph boundary
        if (currentBody.isNotEmpty) flush();
        continue;
      }

      // Heading patterns
      if (line.startsWith('## ')) {
        flush();
        currentTitle = line.substring(3).trim();
        continue;
      }
      if (line.startsWith('# ')) {
        flush();
        currentTitle = line.substring(2).trim();
        continue;
      }

      // "Title:" style headings
      final looksLikeLabel =
          line.endsWith(':') && line.length <= 48 && !line.contains('http');
      if (looksLikeLabel) {
        flush();
        currentTitle = line.substring(0, line.length - 1).trim();
        continue;
      }

      currentBody.add(line);
    }

    flush();
    return blocks;
  }
}

class _Block {
  final String? title;
  final String body;
  _Block({required this.title, required this.body});
}

class _BlockWidget extends StatelessWidget {
  final _Block block;
  const _BlockWidget({required this.block});

  @override
  Widget build(BuildContext context) {
    final title = block.title?.trim();
    final body = block.body.trim();

    final bulletLines = body
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final isMostlyBullets = bulletLines.isNotEmpty &&
        bulletLines.where((l) => _isBullet(l)).length >=
            (bulletLines.length * 0.6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null && title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              title,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
              ),
            ),
          ),
        if (body.isNotEmpty)
          isMostlyBullets
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: bulletLines.map((l) {
                    final text = _stripBullet(l);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: context.colors.textMuted,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              text,
                              style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 14,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                )
              : Text(
                  body,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
      ],
    );
  }

  bool _isBullet(String line) {
    return line.startsWith('- ') ||
        line.startsWith('* ') ||
        line.startsWith('• ') ||
        RegExp(r'^\d+\.\s+').hasMatch(line);
  }

  String _stripBullet(String line) {
    if (line.startsWith('- ') || line.startsWith('* ')) {
      return line.substring(2).trim();
    }
    if (line.startsWith('• ')) return line.substring(2).trim();
    final m = RegExp(r'^(\d+)\.\s+').firstMatch(line);
    if (m != null) return line.substring(m.group(0)!.length).trim();
    return line.trim();
  }
}

class _JsonWidget extends StatelessWidget {
  final dynamic value;
  const _JsonWidget({required this.value});

  @override
  Widget build(BuildContext context) {
    if (value is List) {
      final list = value as List;
      if (list.isEmpty) return const SizedBox.shrink();
      // If list of strings: bullets
      final allStrings = list.every((e) => e is String);
      if (allStrings) {
        return _BlockWidget(
          block: _Block(title: null, body: (list as List<String>).map((e) => '- $e').join('\n')),
        );
      }
    }

    if (value is Map) {
      final map = (value as Map).map((k, v) => MapEntry('$k', v));
      // Render common keys as sections first
      final preferredOrder = [
        'summary',
        'goal',
        'plan',
        'next_steps',
        'nextSteps',
        'tasks',
        'milestones',
        'actions',
      ];

      final orderedKeys = <String>[
        ...preferredOrder.where(map.containsKey),
        ...map.keys.where((k) => !preferredOrder.contains(k)),
      ];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: orderedKeys.map((k) {
          final v = map[k];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _kv(context, k, v),
          );
        }).toList(),
      );
    }

    return Text(
      value.toString(),
      style: TextStyle(
        color: context.colors.textPrimary,
        fontSize: 14,
        height: 1.45,
      ),
    );
  }

  Widget _kv(BuildContext context, String key, dynamic v) {
    final label = key.replaceAll('_', ' ');
    if (v is String) {
      return _BlockWidget(block: _Block(title: label, body: v));
    }
    if (v is num || v is bool) {
      return _BlockWidget(block: _Block(title: label, body: v.toString()));
    }

    if (v is List) {
      final list = v;
      // List of maps -> compact cards
      final allMaps = list.isNotEmpty && list.every((e) => e is Map);
      if (allMaps) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            ...list.map((e) => _miniCard(context, (e as Map).cast())),
          ],
        );
      }

      // List of strings -> bullets
      final allStrings = list.isNotEmpty && list.every((e) => e is String);
      if (allStrings) {
        return _BlockWidget(
          block: _Block(
            title: label,
            body: (list as List<String>).map((e) => '- $e').join('\n'),
          ),
        );
      }
    }

    // Fallback: pretty JSON code block style
    String pretty = v.toString();
    try {
      const encoder = JsonEncoder.withIndent('  ');
      pretty = encoder.convert(v);
    } catch (_) {}

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            pretty,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 12,
              height: 1.35,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniCard(BuildContext context, Map<dynamic, dynamic> m) {
    final title = (m['title'] ?? m['name'] ?? m['task'] ?? m['milestone'])
        ?.toString();
    final desc = (m['description'] ??
            m['details'] ??
            m['why'] ??
            m['note'])
        ?.toString();

    final fallback = const JsonEncoder.withIndent('  ').convert(m);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null && title.trim().isNotEmpty)
            Text(
              title,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          if (desc != null && desc.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              desc,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          if ((title == null || title.trim().isEmpty) &&
              (desc == null || desc.trim().isEmpty)) ...[
            Text(
              fallback,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

