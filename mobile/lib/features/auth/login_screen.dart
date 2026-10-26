import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/config.dart';
import '../../state/providers.dart';
import '../common/ui.dart';

/// Sign-in screen.
///
/// There is no public sign-up: an account is either seeded for the owner or
/// created with a one-time invitation code issued inside the company.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _workspaceName = TextEditingController();
  final _serverUrl = TextEditingController();

  bool _invitation = false;
  bool _createAccount = false;
  bool _busy = false;
  String? _error;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _loadLastEmail();
  }

  Future<void> _loadLastEmail() async {
    final email = await ref.read(sessionStoreProvider).readLastEmail();
    if (email != null && email.isNotEmpty && mounted) {
      _email.text = email;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    _name.dispose();
    _workspaceName.dispose();
    _serverUrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    final password = _password.text;
    final code = _code.text.trim();
    final name = _name.text.trim();

    if (_createAccount) {
      if (name.isEmpty || email.isEmpty || password.length < 8) {
        setState(() => _error = 'اكمل الاسم والبريد، والباسورد 8 حروف على الأقل.');
        return;
      }
    } else if (_invitation) {
      if (code.isEmpty || name.isEmpty || password.length < 8) {
        setState(() => _error = 'اكمل الكود والاسم، والباسورد 8 حروف على الأقل.');
        return;
      }
    } else {
      if (email.isEmpty || password.isEmpty) {
        setState(() => _error = 'اكتب البريد والباسورد.');
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final auth = ref.read(authProvider.notifier);
      if (_createAccount) {
        await auth.bootstrap(
          name: name,
          email: email,
          password: password,
          workspaceName: _workspaceName.text.trim().isEmpty
              ? null
              : _workspaceName.text.trim(),
        );
      } else if (_invitation) {
        await auth.acceptInvitation(code: code, name: name, password: password);
      } else {
        await auth.login(email: email, password: password);
      }
      // Navigation happens through the router redirect on auth state change.
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Brand(),
                  const SizedBox(height: 26),
                  if (AppConfig.configurationError != null) ...[
                    SurfaceCard(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Server URL',
                            style: context.texts.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Enter your backend URL (e.g. https://your-app.vercel.app/api/v1)',
                            style: context.texts.bodySmall?.copyWith(color: context.mutedText, height: 1.5),
                          ),
                          const SizedBox(height: 14),
                          LabeledField(
                            label: 'Server URL',
                            child: ShadInput(
                              controller: _serverUrl,
                              placeholder: const Text('https://...'),
                              textDirection: TextDirection.ltr,
                            ),
                          ),
                          const SizedBox(height: 14),
                          ShadButton(
                            size: ShadButtonSize.lg,
                            onPressed: _busy
                                ? null
                                : () async {
                                    final url = _serverUrl.text.trim();
                                    if (url.isEmpty) return;
                                    await ref.read(sessionStoreProvider).writeApiBaseUrl(url);
                                    AppConfig.setRuntimeOverride(url);
                                    setState(() {});
                                  },
                            child: const Text('Save & Connect'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  SurfaceCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _createAccount
                              ? 'إنشاء حساب جديد'
                              : _invitation
                                  ? 'تفعيل كود دعوة'
                                  : 'تسجيل الدخول',
                          style: context.texts.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _createAccount
                              ? 'أنشئ حسابك (أول مستخدم يصبح مالك الشركة).'
                              : _invitation
                                  ? 'الكود بيجي من مسؤول الشركة وبيتستخدم مرة واحدة.'
                                  : 'ادخل بحسابك عشان تشوف مواقع الشركة وشغلك.',
                          style: context.texts.bodySmall?.copyWith(
                            color: context.mutedText,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (_createAccount) ...[
                          LabeledField(
                            label: 'الاسم',
                            child: ShadInput(
                              controller: _name,
                              placeholder: const Text('اسمك الكامل'),
                              textCapitalization: TextCapitalization.words,
                              autofocus: true,
                            ),
                          ),
                          const SizedBox(height: 14),
                          LabeledField(
                            label: 'البريد الإلكتروني',
                            child: ShadInput(
                              controller: _email,
                              placeholder: const Text('name@company.com'),
                              keyboardType: TextInputType.emailAddress,
                              textDirection: TextDirection.ltr,
                              autofillHints: const [AutofillHints.email],
                            ),
                          ),
                          const SizedBox(height: 14),
                          LabeledField(
                            label: 'اسم الشركة (اختياري)',
                            child: ShadInput(
                              controller: _workspaceName,
                              placeholder: const Text('شركتي'),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ] else if (_invitation) ...[
                          LabeledField(
                            label: 'كود الدعوة',
                            child: ShadInput(
                              controller: _code,
                              placeholder: const Text('مثال: JM-8F2K-91QX'),
                              textDirection: TextDirection.ltr,
                              autofocus: true,
                            ),
                          ),
                          const SizedBox(height: 14),
                          LabeledField(
                            label: 'الاسم',
                            child: ShadInput(
                              controller: _name,
                              placeholder: const Text('اسمك الكامل'),
                              textCapitalization: TextCapitalization.words,
                            ),
                          ),
                          const SizedBox(height: 14),
                        ] else ...[
                          LabeledField(
                            label: 'البريد الإلكتروني',
                            child: ShadInput(
                              controller: _email,
                              placeholder: const Text('name@company.com'),
                              keyboardType: TextInputType.emailAddress,
                              textDirection: TextDirection.ltr,
                              autofillHints: const [AutofillHints.email],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        LabeledField(
                          label: 'الباسورد',
                          helper: _invitation ? '8 حروف على الأقل.' : null,
                          child: ShadInput(
                            controller: _password,
                            placeholder: const Text('••••••••'),
                            obscureText: _obscure,
                            textDirection: TextDirection.ltr,
                            onSubmitted: (_) => _submit(),
                            trailing: ShadIconButton.ghost(
                              width: 28,
                              height: 28,
                              icon: Icon(
                                _obscure ? LucideIcons.eye : LucideIcons.eyeOff,
                                size: 15,
                              ),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          ShadAlert.destructive(
                            icon: const Icon(LucideIcons.circleAlert, size: 16),
                            description: Text(_error!),
                          ),
                        ],
                        const SizedBox(height: 18),
                        ShadButton(
                          size: ShadButtonSize.lg,
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(_createAccount
                                  ? 'أنشئ الحساب'
                                  : _invitation
                                      ? 'فعّل الحساب'
                                      : 'دخول'),
                        ),
                        const SizedBox(height: 10),
                        ShadButton.ghost(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _createAccount = false;
                                    _invitation = !_invitation;
                                    _error = null;
                                  }),
                          child: Text(
                            _invitation ? 'عندي حساب بالفعل' : 'عندك كود دعوة؟',
                          ),
                        ),
                        if (!_invitation)
                          ShadButton.ghost(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _createAccount = !_createAccount;
                                      _error = null;
                                    }),
                            child: Text(
                              _createAccount
                                  ? 'عندي حساب بالفعل'
                                  : 'إنشاء حساب جديد (أول مستخدم)',
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _createAccount
                        ? 'هذا الخيار متاح فقط على قاعدة بيانات جديدة (أول مستخدم).'
                        : 'مفيش تسجيل مفتوح. كل حساب بيتم تفعيله بكود دعوة.',
                    textAlign: TextAlign.center,
                    style: context.texts.bodySmall?.copyWith(color: context.mutedText),
                  ),
                  if (AppConfig.apiBaseUrl.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      AppConfig.apiBaseUrl,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.ltr,
                      style: context.texts.labelSmall?.copyWith(
                        color: context.mutedText.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: context.scheme.primary,
            borderRadius: BorderRadius.circular(19),
          ),
          child: Icon(
            LucideIcons.briefcase,
            size: 28,
            color: context.scheme.primaryForeground,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'مدير الشغل',
          style: context.texts.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'زيارات المواقع والمهام، بالعربي.',
          style: context.texts.bodySmall?.copyWith(color: context.mutedText),
        ),
      ],
    );
  }
}
