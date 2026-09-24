import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../auth/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;

  final String _domain = "@bilimkalesi.com";

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
  if (_isLoading) return;

  final username = _usernameController.text.trim().toLowerCase();
  final password = _passwordController.text.trim();

  if (username.isEmpty || password.isEmpty) {
    _showLoginErrorDialog(
      title: 'Eksik Bilgi',
      message: 'Lütfen kullanıcı adı ve şifre alanlarını doldurun.',
    );
    return;
  }

  setState(() => _isLoading = true);

  try {
    final fullEmail = username.contains('@') ? username : username + _domain;

    final auth = Provider.of<AuthService>(context, listen: false);
    await auth.signIn(fullEmail, password);
    TextInput.finishAutofillContext(shouldSave: true);

  } catch (e) {
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    _showLoginErrorDialog(
      title: 'Giriş Başarısız',
      message: 'Kullanıcı adı veya şifre hatalı.\nLütfen tekrar deneyin.',
    );
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}
void _showLoginErrorDialog({
  required String title,
  required String message,
}) {
  if (!mounted) return;

  showDialog(
    context: context,
    builder: (context) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 26),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF061B26),
                Color(0xFF0E3A8A),
                Color(0xFF2B1055),
              ],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.45),
                    width: 1.4,
                  ),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.redAccent,
                  size: 36,
                ),
              ),

              const SizedBox(height: 18),

              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C3DFF),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  child: const Text(
                    'Tamam',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

  @override
Widget build(BuildContext context) {
  return Scaffold(
    body: Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF061B26),
            Color(0xFF0E3A8A),
            Color(0xFF2B1055),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 22,
            right: 22,
            child: IgnorePointer(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 1, height: 42, color: Colors.white70),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Berfin Güler',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontFamily: 'cursive',
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w400,
                          letterSpacing: .5,
                        ),
                      ),
                      SizedBox(height: 1),
                      Text(
                        'tarafından geliştirildi',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          letterSpacing: .2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 82, 22, 22),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Image.asset(
                    'assets/images/bilim_kalesi_logo.jpeg',
                    height: 76,
                    fit: BoxFit.contain,
                  ),
                ),

                const SizedBox(height: 22),

                const Text(
                  'ZümreNet',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                const Text(
                  'Bilim Kalesi Eğitim Kurumları için\nAkıllı Zümre ve Etüt Yönetim Sistemi',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    height: 1.35,
                  ),
                ),

               const SizedBox(height: 28),

AutofillGroup(
  child: Column(
    children: [
      TextField(
        controller: _usernameController,
        autofillHints: const [
          AutofillHints.username,
          AutofillHints.email,
        ],
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: 'Kullanıcı Adı',
          labelStyle: const TextStyle(color: Colors.white70),
          suffixText: _domain,
          suffixStyle: const TextStyle(
            color: Colors.white38,
            fontStyle: FontStyle.italic,
          ),
          prefixIcon: const Icon(
            Icons.person_outline,
            color: Colors.white70,
          ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
        autocorrect: false,
        enableSuggestions: false,
      ),

      const SizedBox(height: 16),

      TextField(
        controller: _passwordController,
        autofillHints: const [
          AutofillHints.password,
        ],
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _login(),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: 'Şifre',
          labelStyle: const TextStyle(color: Colors.white70),
          prefixIcon: const Icon(
            Icons.lock_outline,
            color: Colors.white70,
          ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    ],
  ),
),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C3DFF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Giriş Yap',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 18),

                const Text(
                  'ZümreNet × Bilim Kalesi',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
          ),
        ],
      ),
    ),
  );
}
}