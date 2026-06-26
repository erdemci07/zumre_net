import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:zumre_net/theme/app_theme.dart';
import 'package:zumre_net/screens/admin_home_screen.dart';
import 'package:zumre_net/screens/student_home_screen.dart';
import 'package:zumre_net/screens/teacher_home_screen.dart';
import 'package:zumre_net/auth/auth_service.dart';
import 'package:zumre_net/screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyBznoF8WcalY8k-tUexUTrooeDJdZHsM5w",
      appId: "1:542741706921:web:edd3b9eedb3b82feda91b8",
      messagingSenderId: "542741706921",
      projectId: "zumrenet-657e1",
      authDomain: "zumrenet-657e1.firebaseapp.com",
      storageBucket: "zumrenet-657e1.firebasestorage.app",
    ),
  );

  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<Widget> _getHomeScreen(BuildContext context, User user) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final roleData = await auth.getUserRole(user.uid);
    final role = roleData?['role'] ?? 'student';

    if (role == 'teacher') {
      return const TeacherHomeScreen();
    } else if (role == 'admin') {
      return const AdminHomeScreen();
    } else {
      return const StudentHomeScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
      ],
child: MaterialApp(
  title: 'ZümreNet',
  theme: AppTheme.theme,        debugShowCheckedModeBanner: false,

        home: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, authSnapshot) {
            if (authSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (!authSnapshot.hasData) {
              return const LoginScreen();
            }

            return FutureBuilder<Widget>(
              future: _getHomeScreen(context, authSnapshot.data!),
              builder: (context, roleSnapshot) {
                if (roleSnapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                if (roleSnapshot.hasError) {
  return Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Giriş başarılı ancak kullanıcı rolü okunamadı.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${roleSnapshot.error}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
              child: const Text('Tekrar Giriş Yap'),
            ),
          ],
        ),
      ),
    ),
  );
}

                return roleSnapshot.data ?? const LoginScreen();
              },
            );
          },
        ),

        routes: {
          '/login': (context) => const LoginScreen(),
          '/student': (context) => const StudentHomeScreen(),
          '/teacher': (context) => const TeacherHomeScreen(),
          '/admin': (context) => const AdminHomeScreen(),
        },
      ),
    );
  }
}