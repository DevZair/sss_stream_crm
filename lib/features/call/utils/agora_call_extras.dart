import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';

/// Цвет индикатора аплинка (по смыслу SurajLad/utils getNetworkQualityBarColor).
Color agoraUplinkQualityColor(QualityType q) {
  switch (q) {
    case QualityType.qualityExcellent:
    case QualityType.qualityGood:
      return const Color(0xFF34C759);
    case QualityType.qualityPoor:
      return const Color(0xFFFFCC00);
    case QualityType.qualityBad:
    case QualityType.qualityVbad:
      return const Color(0xFFFF9500);
    case QualityType.qualityDown:
      return const Color(0xFFFF3B30);
    case QualityType.qualityUnknown:
    case QualityType.qualityUnsupported:
    case QualityType.qualityDetecting:
      return const Color(0xFF8E8E93);
  }
}

String agoraUplinkQualityLabel(QualityType q) {
  switch (q) {
    case QualityType.qualityExcellent:
      return 'Сеть: отлично';
    case QualityType.qualityGood:
      return 'Сеть: хорошо';
    case QualityType.qualityPoor:
      return 'Сеть: слабо';
    case QualityType.qualityBad:
      return 'Сеть: плохо';
    case QualityType.qualityVbad:
      return 'Сеть: очень плохо';
    case QualityType.qualityDown:
      return 'Нет сети';
    case QualityType.qualityUnknown:
    case QualityType.qualityUnsupported:
      return 'Сеть: —';
    case QualityType.qualityDetecting:
      return 'Проверка сети…';
  }
}

String formatCallDurationMmSs(int totalSeconds) {
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
