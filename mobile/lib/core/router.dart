import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../features/auth/login_screen.dart';
import '../features/common/ui.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/home_shell.dart';
import '../features/sites/site_detail_screen.dart';
import '../features/sites/site_form_screen.dart';
import '../features/sites/sites_screen.dart';
import '../features/tasks/task_form_screen.dart';
import '../features/tasks/tasks_screen.dart';
import '../features/visits/visit_form_screen.dart';
import '../features/voice/voice_screen.dart';
import '../models/site.dart';
import '../models/task.dart';
import '../models/visit.dart';
import '../state/providers.dart';

/// Bridges Riverpod auth state to go_router's `refreshListenable`.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._value);

  AsyncValue<AuthState> _value;

  AsyncValue<AuthState> get value => _value;

  set value(AsyncValue<AuthState> next) {
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _AuthListenable(ref.read(authProvider));
  ref.listen<AsyncValue<AuthState>>(authProvider, (_, next) => listenable.value = next);
  ref.onDispose(listenable.dispose);

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: listenable,
    redirect: (context, state) {
      final auth = listenable.value;
      final location = state.matchedLocation;
      final atSplash = location == '/splash';
      final atLogin = location == '/login';

      // First launch: wait for the stored session check before routing.
      if (auth.isLoading && !auth.hasValue) {
        return atSplash ? null : '/splash';
      }

      final signedIn = auth.value?.isAuthenticated ?? false;
      if (!signedIn) return atLogin ? null : '/login';
      if (atLogin || atSplash) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const _SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => HomeShell(shell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/sites',
                builder: (context, state) => const SitesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/voice',
                builder: (context, state) => const VoiceScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tasks',
                builder: (context, state) => const TasksScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      // Full-screen routes pushed above the tab shell.
      GoRoute(
        path: '/sites/new',
        builder: (context, state) => const SiteFormScreen(),
      ),
      GoRoute(
        path: '/sites/:id',
        builder: (context, state) => SiteDetailScreen(siteId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/sites/:id/edit',
        builder: (context, state) => SiteFormScreen(
          siteId: state.pathParameters['id'],
          initialSite: state.extra is Site ? state.extra! as Site : null,
        ),
      ),
      GoRoute(
        path: '/sites/:id/visits/new',
        builder: (context, state) => VisitFormScreen(
          siteId: state.pathParameters['id']!,
          initialVisit: state.extra is Visit ? state.extra! as Visit : null,
        ),
      ),
      GoRoute(
        path: '/sites/:id/visits/:visitId/edit',
        builder: (context, state) => VisitFormScreen(
          siteId: state.pathParameters['id']!,
          visitId: state.pathParameters['visitId'],
          initialVisit: state.extra is Visit ? state.extra! as Visit : null,
        ),
      ),
      GoRoute(
        path: '/tasks/new',
        builder: (context, state) => TaskFormScreen(
          siteId: state.uri.queryParameters['siteId'],
        ),
      ),
      GoRoute(
        path: '/tasks/:id/edit',
        builder: (context, state) => TaskFormScreen(
          taskId: state.pathParameters['id'],
          initialTask: state.extra is Task ? state.extra! as Task : null,
        ),
      ),
    ],
    errorBuilder: (context, state) => _NotFoundScreen(location: state.uri.toString()),
  );
});

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scheme.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: context.scheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(LucideIcons.briefcase, color: context.scheme.primaryForeground, size: 30),
            ),
            const SizedBox(height: 18),
            Text(
              'مدير الشغل',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: context.scheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scheme.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.circleAlert, size: 36, color: context.scheme.destructive),
                const SizedBox(height: 12),
                Text('الصفحة مش موجودة', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  location,
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.scheme.mutedForeground,
                  ),
                ),
                const SizedBox(height: 18),
                ShadButton.outline(
                  onPressed: () => context.go('/dashboard'),
                  child: const Text('ارجع للرئيسية'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
