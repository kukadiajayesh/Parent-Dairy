import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One AI call as the parent sees it: what, with which model and key, how
/// many tokens, how long, and whether it worked. Never the prompt, never
/// the reply, never the key.
@immutable
class AiActivityEntry {
  const AiActivityEntry({
    required this.at,
    required this.feature,
    required this.model,
    required this.keyLabel,
    required this.promptTokens,
    required this.responseTokens,
    required this.duration,
    required this.outcome,
  });

  final DateTime at;
  final String feature;
  final String model;
  final String keyLabel;
  final int promptTokens;
  final int responseTokens;
  final Duration duration;

  /// `ok`, or a short failure kind (`quota`, `invalidKey`, `cancelled`…).
  final String outcome;

  bool get succeeded => outcome == 'ok';
  int get totalTokens => promptTokens + responseTokens;

  Map<String, Object?> toJson() => {
    'at': at.toIso8601String(),
    'feature': feature,
    'model': model,
    'keyLabel': keyLabel,
    'promptTokens': promptTokens,
    'responseTokens': responseTokens,
    'durationMs': duration.inMilliseconds,
    'outcome': outcome,
  };

  factory AiActivityEntry.fromJson(Map<String, Object?> m) => AiActivityEntry(
    at: DateTime.tryParse((m['at'] ?? '').toString()) ?? DateTime(2000),
    feature: (m['feature'] ?? '').toString(),
    model: (m['model'] ?? '').toString(),
    keyLabel: (m['keyLabel'] ?? '').toString(),
    promptTokens: (m['promptTokens'] as num?)?.toInt() ?? 0,
    responseTokens: (m['responseTokens'] as num?)?.toInt() ?? 0,
    duration: Duration(milliseconds: (m['durationMs'] as num?)?.toInt() ?? 0),
    outcome: (m['outcome'] ?? 'unknown').toString(),
  );
}

/// The last [max] AI calls, in `SharedPreferences`. This is the cost-control
/// surface: there is no billing API for a free-tier key to read, so the app
/// keeps its own tally.
class AiActivityLog extends ChangeNotifier {
  AiActivityLog(this._prefs, {this.max = 100}) {
    _load();
  }

  static const key = 'ai.activity.v1';
  final SharedPreferences _prefs;
  final int max;

  List<AiActivityEntry> _entries = const [];

  /// Newest first.
  List<AiActivityEntry> get entries => List.unmodifiable(_entries);

  void _load() {
    try {
      final raw = _prefs.getString(key);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      _entries = [
        if (decoded is List)
          for (final e in decoded)
            if (e is Map) AiActivityEntry.fromJson(Map<String, Object?>.from(e)),
      ];
    } catch (_) {
      _entries = const [];
    }
  }

  Future<void> add(AiActivityEntry entry) async {
    _entries = [entry, ..._entries].take(max).toList();
    await _prefs.setString(key, jsonEncode([for (final e in _entries) e.toJson()]));
    notifyListeners();
  }

  Future<void> clear() async {
    _entries = const [];
    await _prefs.remove(key);
    notifyListeners();
  }

  /// Requests and tokens in the calendar month of [now].
  ({int requests, int tokens}) monthly(DateTime now) {
    var requests = 0;
    var tokens = 0;
    for (final e in _entries) {
      if (e.at.year == now.year && e.at.month == now.month) {
        requests++;
        tokens += e.totalTokens;
      }
    }
    return (requests: requests, tokens: tokens);
  }
}
