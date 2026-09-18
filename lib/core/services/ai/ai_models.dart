/// Which job a model is being picked for. Each task has its own default so
/// the cheap classifier and the vision reader can be swapped independently
/// from the AI settings screen.
///
/// Defaults verified against https://ai.google.dev/gemini-api/docs/models on
/// 19 September 2026. They are only *fallbacks*: the settings picker is
/// populated from the live `models.list` call, and a default that has since
/// been retired surfaces as "That model is no longer available".
enum AiTask {
  generation('gemini-3.8-flash', 'Generation', 'Papers, quizzes, plans'),
  vision('gemini-3.8-flash', 'Vision', 'Paper scans, report cards'),
  classification('gemini-3.5-flash-lite', 'Classification', 'Notice extraction'),
  best('gemini-2.5-pro', 'Best quality', 'Opt-in for a harder paper');

  const AiTask(this.defaultModel, this.label, this.description);

  final String defaultModel;
  final String label;
  final String description;
}

/// One entry from `GET /v1beta/models`.
class GeminiModel {
  const GeminiModel({
    required this.id,
    required this.displayName,
    this.supportedMethods = const [],
    this.inputTokenLimit,
    this.outputTokenLimit,
  });

  /// `gemini-3.8-flash` — the `models/` prefix stripped.
  final String id;
  final String displayName;
  final List<String> supportedMethods;
  final int? inputTokenLimit;
  final int? outputTokenLimit;

  bool get supportsGenerate => supportedMethods.contains('generateContent');

  Map<String, Object?> toJson() => {
    'id': id,
    'displayName': displayName,
    'supportedMethods': supportedMethods,
    'inputTokenLimit': inputTokenLimit,
    'outputTokenLimit': outputTokenLimit,
  };

  factory GeminiModel.fromJson(Map<String, Object?> m) {
    final name = (m['name'] ?? m['id'] ?? '').toString();
    final methods = m['supportedGenerationMethods'] ?? m['supportedMethods'];
    return GeminiModel(
      id: name.startsWith('models/') ? name.substring(7) : name,
      displayName: (m['displayName'] ?? name).toString(),
      supportedMethods: methods is List
          ? [for (final e in methods) e.toString()]
          : const [],
      inputTokenLimit: (m['inputTokenLimit'] as num?)?.toInt(),
      outputTokenLimit: (m['outputTokenLimit'] as num?)?.toInt(),
    );
  }
}
