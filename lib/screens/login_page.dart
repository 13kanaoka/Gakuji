import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../theme/app_text_styles.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool isSigningIn = false;
  String? errorMessage;

  Future<void> _signInWithGoogle() async {
    setState(() {
      isSigningIn = true;
      errorMessage = null;
    });

    try {
      final googleUser = await GoogleSignIn.instance.authenticate();

      final googleAuth = googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch(e) {
      setState(() {
        errorMessage = 'Sign-in failed. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isSigningIn = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Gakuji',
                style: AppText.appTitle,
              ),
              const SizedBox(height: 40),
              if (isSigningIn)
                const CircularProgressIndicator()
              else
                ElevatedButton(
                  onPressed: _signInWithGoogle,
                  child: const Text('Sign in with Google'),
                ),
              if (errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
          ),
        ),
      );
  }
}