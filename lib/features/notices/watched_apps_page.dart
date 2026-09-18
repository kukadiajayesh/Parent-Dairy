import 'package:flutter/material.dart';

import '../../core/errors/app_failure.dart';
import '../../core/services/notice_capture_service.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import 'notice_widgets.dart';

/// The watched-apps picker (prompt 03 §E.3): every launchable app, searchable,
/// with the ones that have already posted a captured notice on top and a
/// hint for anything that looks like a school app.
class WatchedAppsPage extends StatefulWidget {
  const WatchedAppsPage({super.key});

  /// package → label, filled the first time the list loads so the settings
  /// screen can name a watched app without reloading every icon.
  static final Map<String, String> labelCache = {};

  @override
  State<WatchedAppsPage> createState() => _WatchedAppsPageState();
}

class _WatchedAppsPageState extends State<WatchedAppsPage> {
  final _search = TextEditingController();
  List<InstalledApp>? _apps;
  AppFailure? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    final state = AppScope.read(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final apps = await state.noticeCapture.installedApps(refresh: refresh);
      for (final a in apps) {
        WatchedAppsPage.labelCache[a.packageName] = a.label;
      }
      if (mounted) setState(() => _apps = apps);
    } catch (error) {
      if (mounted) setState(() => _error = AppFailure.from(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(InstalledApp app, bool on) async {
    final state = AppScope.read(context);
    final current = state.watchedPackages;
    final next = on
        ? [...current.where((p) => p != app.packageName), app.packageName]
        : current.where((p) => p != app.packageName).toList();
    try {
      await state.setWatchedPackages(next);
    } catch (error) {
      if (!mounted) return;
      AppToast.failure(context, error, title: "Couldn't update the list");
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final watched = state.watchedPackages.toSet();
    final captured = state.packagesWithCaptures;
    final query = _search.text.trim().toLowerCase();

    final apps = (_apps ?? const <InstalledApp>[]).where((a) {
      if (query.isEmpty) return true;
      return a.label.toLowerCase().contains(query) || a.packageName.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) {
        int rank(InstalledApp x) => captured.contains(x.packageName)
            ? 0
            : (watched.contains(x.packageName) ? 1 : (x.looksLikeSchoolApp ? 2 : 3));
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });

    final hint = query.isEmpty
        ? (_apps ?? const <InstalledApp>[])
            .where((a) => a.looksLikeSchoolApp && !watched.contains(a.packageName))
            .firstOrNull
        : null;

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(
                title: 'Watched apps',
                subtitle: '${watched.length} selected',
                actions: [SectionAction(label: 'Refresh', onTap: _loading ? null : () => _load(refresh: true))],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: AppTextField(
                label: 'Search',
                controller: _search,
                hintText: 'Campus Care, school, ERP…',
                textCapitalization: TextCapitalization.none,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                children: [
                  if (_error != null)
                    ErrorStateView(
                      title: "Couldn't list your apps",
                      description: _error!.message,
                      actionLabel: 'Retry',
                      onAction: () => _load(refresh: true),
                      onCancel: () => Navigator.of(context).maybePop(),
                    )
                  else if (_loading && _apps == null)
                    const Skeletons(
                      child: Column(
                        children: [
                          SkeletonBox(height: 64, radius: 16),
                          SizedBox(height: 8),
                          SkeletonBox(height: 64, radius: 16),
                          SizedBox(height: 8),
                          SkeletonBox(height: 64, radius: 16),
                        ],
                      ),
                    )
                  else if (apps.isEmpty)
                    EmptyListNotice(
                      title: query.isEmpty ? 'No apps found' : 'Nothing matches',
                      description: query.isEmpty
                          ? 'The app list came back empty. Try Refresh.'
                          : 'Try the app\'s name as it appears on your home screen.',
                    )
                  else ...[
                    if (hint != null) ...[
                      AppCard(
                        radius: 16,
                        background: k.priC,
                        borderColor: k.priBd,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        onTap: () => _toggle(hint, true),
                        child: Row(
                          children: [
                            AppIconTile(label: hint.label, iconPng: hint.iconPng, size: 34),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Looks like your school app', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: k.priInk2)),
                                  Text(hint.label, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: k.priInk)),
                                ],
                              ),
                            ),
                            SectionAction(label: 'Watch', onTap: () => _toggle(hint, true)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    for (final app in apps) ...[
                      AppCard(
                        radius: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        onTap: () => _toggle(app, !watched.contains(app.packageName)),
                        child: Row(
                          children: [
                            AppIconTile(label: app.label, iconPng: app.iconPng),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(app.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                                  Text(
                                    captured.contains(app.packageName) ? 'Has posted notices' : app.packageName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11.5, color: k.tx4),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            AppSwitch(
                              value: watched.contains(app.packageName),
                              width: 48,
                              height: 28,
                              onChanged: (v) => _toggle(app, v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
