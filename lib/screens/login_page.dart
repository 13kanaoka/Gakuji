import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';

import '../theme/app_text_styles.dart';
import '../data/passwords.dart';

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

  Future<void> _signInAsTestUser() async {
    setState(() {
      isSigningIn = true;
      errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: Passwords.email, 
        password: Passwords.password,
        );
    } catch (e) {
      setState(() {
        errorMessage = 'Yo login is shit twin';
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
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: _signInWithGoogle,
                      child: const Text('Sign in with Google'),
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _signInAsTestUser,
                        child: const Text('Sign in as Test User (debug)'),
                      ),
                    ],
                  ],
                ),
              ],
          ),
          ),
        ),
      );
  }
}