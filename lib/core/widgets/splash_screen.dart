import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:firebase_auth/firebase_auth.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/home/presentation/root_tabs.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToNext();
  }

  Future<void> _navigateToNext() async {
    await Future.delayed(const Duration(milliseconds: 1950));
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    final Widget nextScreen = user != null
        ? const RootTabs()
        : const LoginPage();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const CupertinoPageScaffold(
      backgroundColor: Colors.black,
      child: Center(
        child: SizedBox(
          width: 470,
          height: 470,
          child: Image(
            image: AssetImage('assets/splash/SSS App.gif'),
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
