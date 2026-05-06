import 'package:flutter/material.dart';

const _planColors = [
  Color(0xFF1D9E75),
  Color(0xFFF07057),
  Color(0xFF9B87F5),
  Color(0xFF5B9CF6),
  Color(0xFFE8A843),
];

Color getPlanColor(int index) {
  return _planColors[index % _planColors.length];
}

Color getPlanColorBg(Color color, {double opacity = 0.09}) {
  return color.withValues(alpha: opacity);
}
