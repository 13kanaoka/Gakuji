import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'gakuji_cloud_sync_service.dart';
import 'gakuji_user_data_store.dart';

class GakujiAuthProfile {
  final String uid;
  final String? email;
  final bool emailVerified;
  final bool hasPassword;
  final bool hasGoogle;

  const GakujiAuthProfile({
    required this.uid,
    required this.email,
    required this.emailVerified,
    required this.hasPassword,
    required this.hasGoogle,
  });
}

class GakujiAuthException implements Exception {
  final String message;

  const GakujiAuthException(this.message);

  @override
  String toString() => message;
}

class GakujiAccountAuthService {
  static FirebaseAuth get _auth => FirebaseAuth.instance;
  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static User get _currentUser {
    final user = _auth.currentUser;
    if (user == null) {
      throw const GakujiAuthException('You must be signed in first.');
    }
    return user;
  }

  static bool _hasProvider(User user, String providerId) {
    return user.providerData.any((provider) => provider.providerId == providerId);
  }

  /// Returns the Firebase Auth account details already restored on this device.
  ///
  /// This is intentionally synchronous so settings/account screens can render
  /// immediately without waiting on a network reload.
  static GakujiAuthProfile currentProfileFromCache() {
    final user = _currentUser;
    return GakujiAuthProfile(
      uid: user.uid,
      email: user.email,
      emailVerified: user.emailVerified,
      hasPassword: _hasProvider(user, 'password'),
      hasGoogle: _hasProvider(user, 'google.com'),
    );
  }

  static Future<GakujiAuthProfile> loadCurrentProfile({
    bool reload = true,
  }) async {
    if (reload) {
      await _currentUser.reload();
    }

    return currentProfileFromCache();
  }

  static Future<UserCredential> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw GakujiAuthException(_friendlyAuthMessage(error));
    }
  }

  static Future<UserCredential> signInAsGuest() async {
    try {
      return await _auth.signInAnonymously();
    } on FirebaseAuthException catch (error) {
      if (error.code == 'operation-not-allowed') {
        throw const GakujiAuthException(
          'Guest sign-in is not enabled for this Firebase project yet.',
        );
      }
      throw GakujiAuthException(_friendlyAuthMessage(error));
    }
  }

  static Future<UserCredential> createEmailPasswordAccount({
    required String email,
    required String password,
    bool sendVerification = true,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;
      if (sendVerification && user != null && !user.emailVerified) {
        await sendCurrentEmailVerification();
      }

      return credential;
    } on FirebaseAuthException catch (error) {
      throw GakujiAuthException(_friendlyAuthMessage(error));
    }
  }

  static Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      throw GakujiAuthException(_friendlyAuthMessage(error));
    }
  }

  static Future<GakujiAuthProfile> linkPassword({
    required String email,
    required String password,
  }) async {
    final user = _currentUser;
    final wasGuest = user.isAnonymous;

    if (wasGuest) {
      await GakujiUserDataStore.prepareGuestUpgrade();
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: email.trim(),
        password: password,
      );

      await user.linkWithCredential(credential);
      await user.reload();
      await _currentUser.getIdToken(true);
    } on FirebaseAuthException catch (error) {
      throw GakujiAuthException(_friendlyAuthMessage(error));
    }

    if (wasGuest) {
      await _finishGuestUpgradeOrThrow();
    }

    final refreshedUser = _currentUser;
    if (!refreshedUser.emailVerified) {
      try {
        await sendCurrentEmailVerification();
      } on GakujiAuthException catch (_) {
        // The account is already upgraded and the verification screen provides
        // a resend action, so a mail-delivery hiccup must not undo the account.
      }
    }

    return loadCurrentProfile(reload: true);
  }

  static Future<GakujiAuthProfile> linkGoogle() async {
    final user = _currentUser;
    final wasGuest = user.isAnonymous;

    if (wasGuest) {
      await GakujiUserDataStore.prepareGuestUpgrade();
    }

    try {
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      await user.linkWithCredential(credential);
      await user.reload();
      await _currentUser.getIdToken(true);
    } on FirebaseAuthException catch (error) {
      throw GakujiAuthException(_friendlyAuthMessage(error));
    } catch (_) {
      throw const GakujiAuthException('Could not connect Google right now.');
    }

    if (wasGuest) {
      await _finishGuestUpgradeOrThrow();
    }

    return loadCurrentProfile(reload: true);
  }

  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _currentUser;
    final email = user.email;

    if (email == null || email.isEmpty) {
      throw const GakujiAuthException(
        'This account does not have an email address yet.',
      );
    }

    if (!_hasProvider(user, 'password')) {
      throw const GakujiAuthException(
        'Add Email & Password sign-in before changing your password.',
      );
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (error) {
      throw GakujiAuthException(_friendlyAuthMessage(error));
    }
  }

  static Future<void> requestEmailChange({
    required String currentPassword,
    required String newEmail,
  }) async {
    final user = _currentUser;
    final currentEmail = user.email;

    if (currentEmail == null || currentEmail.isEmpty) {
      throw const GakujiAuthException(
        'This account does not have an email address yet.',
      );
    }

    if (!_hasProvider(user, 'password')) {
      throw const GakujiAuthException(
        'Add Email & Password sign-in before changing your email.',
      );
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: currentEmail,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.verifyBeforeUpdateEmail(newEmail.trim());
    } on FirebaseAuthException catch (error) {
      throw GakujiAuthException(_friendlyAuthMessage(error));
    }
  }

  /// Permanently deletes the registered Gakuji account.
  ///
  /// The caller must explicitly confirm the destructive action in the UI.
  /// Password accounts reauthenticate with [currentPassword]; Google-only
  /// accounts reauthenticate with Google. Cloud study data and the user root
  /// are removed before Firebase Auth is deleted. The active username is kept
  /// in the existing 14-day reservation state so it cannot be impersonated
  /// immediately after deletion.
  static Future<void> deleteCurrentAccount({String? currentPassword}) async {
    final initialUser = _currentUser;
    if (initialUser.isAnonymous) {
      throw const GakujiAuthException(
        'Guest Mode does not have a registered account to delete.',
      );
    }

    await GakujiCloudSyncService.suspendForAccountDeletion();
    var accountDeleted = false;

    try {
      await initialUser.reload();
      final user = _currentUser;

      await _reauthenticateForAccountDeletion(
        user,
        currentPassword: currentPassword,
      );
      await _deleteRemoteGakujiData(user);

      // Firebase requires a recent sign-in for account deletion. The explicit
      // reauthentication above keeps this deterministic instead of failing
      // after the cloud cleanup has already begun.
      await user.delete();
      accountDeleted = true;

      // Auth deletion succeeded. From here on cleanup is local/best-effort and
      // must never turn a successful account deletion into a misleading error.
      try {
        await GakujiUserDataStore.discardLocalAfterAccountDeletion();
      } catch (_) {}

      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    } on GakujiAuthException {
      rethrow;
    } on FirebaseAuthException catch (error) {
      throw GakujiAuthException(_friendlyAuthMessage(error));
    } catch (_) {
      throw const GakujiAuthException(
        'Gakuji could not delete this account. Your account and local data were kept. Check your connection and try again.',
      );
    } finally {
      GakujiCloudSyncService.resumeAfterAccountDeletion();
      if (!accountDeleted && FirebaseAuth.instance.currentUser != null) {
        // If cloud cleanup was interrupted, the local-first copy is still
        // intact. Queue a normal mirror so any partially removed study data is
        // repaired before the user retries deletion.
        GakujiCloudSyncService.schedulePush();
      }
    }
  }

  static Future<void> _reauthenticateForAccountDeletion(
    User user, {
    required String? currentPassword,
  }) async {
    if (_hasProvider(user, 'password')) {
      final email = user.email;
      final password = currentPassword ?? '';

      if (email == null || email.isEmpty) {
        throw const GakujiAuthException(
          'This account does not have an email address to confirm.',
        );
      }
      if (password.isEmpty) {
        throw const GakujiAuthException(
          'Enter your current password to delete this account.',
        );
      }

      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
      return;
    }

    if (_hasProvider(user, 'google.com')) {
      try {
        final googleUser = await GoogleSignIn.instance.authenticate();
        final googleAuth = googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );
        await user.reauthenticateWithCredential(credential);
        return;
      } on FirebaseAuthException {
        rethrow;
      } catch (_) {
        throw const GakujiAuthException(
          'Google sign-in could not be confirmed. Account deletion was cancelled.',
        );
      }
    }

    throw const GakujiAuthException(
      'Gakuji could not confirm this account. Sign in again and retry deletion.',
    );
  }

  static Future<void> _deleteRemoteGakujiData(User user) async {
    final firestore = FirebaseFirestore.instance;
    final userRef = firestore.collection('users').doc(user.uid);

    // Preserve the same anti-impersonation rule used by username changes: the
    // active name is reserved to this UID for 14 days, then becomes claimable.
    final userSnapshot = await userRef.get();
    final userData = userSnapshot.data() ?? <String, dynamic>{};
    final normalized = userData['usernameNormalized']?.toString().trim();
    if (normalized != null && normalized.isNotEmpty) {
      final usernameRef = firestore.collection('usernames').doc(normalized);
      final usernameSnapshot = await usernameRef.get();
      final usernameData = usernameSnapshot.data() ?? <String, dynamic>{};
      if (usernameSnapshot.exists &&
          usernameData['uid']?.toString() == user.uid &&
          usernameData['status']?.toString() == 'active') {
        final reservedUntil = DateTime.now().toUtc().add(
              const Duration(days: 14),
            );
        await usernameRef.set({
          'uid': user.uid,
          'status': 'reserved',
          'reservedUntil': Timestamp.fromDate(reservedUntil),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    // Deck term payloads now live in bounded `termChunks` subcollections.
    // Firestore does not cascade-delete subcollections when a parent document
    // is deleted, so clear those chunks before deleting each deck document.
    await _deleteDeckCollectionCompletely(userRef.collection('decks'));

    // These remaining study-data collections contain no nested cloud payloads.
    // Delete them in bounded batches so a large account is still handled safely.
    for (final collectionName in const [
      'folders',
      'reviewCards',
      'reviewLogs',
      'dictionaryNotes',
      'readingCardEdits',
    ]) {
      await _deleteCollectionCompletely(userRef.collection(collectionName));
    }

    await userRef.delete();
  }

  static Future<void> _deleteDeckCollectionCompletely(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    const batchSize = 100;

    while (true) {
      final snapshot = await collection.limit(batchSize).get();
      if (snapshot.docs.isEmpty) return;

      for (final deckDocument in snapshot.docs) {
        await _deleteCollectionCompletely(
          deckDocument.reference.collection('termChunks'),
        );
      }

      final batch = FirebaseFirestore.instance.batch();
      for (final deckDocument in snapshot.docs) {
        batch.delete(deckDocument.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < batchSize) return;
    }
  }

  static Future<void> _deleteCollectionCompletely(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    const batchSize = 350;

    while (true) {
      final snapshot = await collection.limit(batchSize).get();
      if (snapshot.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final document in snapshot.docs) {
        batch.delete(document.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < batchSize) return;
    }
  }

  /// Sends Firebase's normal email-verification link.
  ///
  /// This is the active verification path for now. The custom six-digit code
  /// infrastructure remains available below so Gakuji can switch back to it
  /// later without rebuilding the backend flow.
  static Future<void> sendCurrentEmailVerification() async {
    try {
      await _currentUser.reload();
      final user = _currentUser;
      if (user.emailVerified) return;

      await user.sendEmailVerification();
    } on FirebaseAuthException catch (error) {
      throw GakujiAuthException(_friendlyAuthMessage(error));
    }
  }

  /// Dormant custom-code sender retained for a future transactional-email
  /// rollout. This is intentionally not called by the current verification UI.
  static Future<void> sendCurrentEmailVerificationCode() async {
    try {
      await _currentUser.reload();
      final user = _currentUser;
      if (user.emailVerified) return;

      await _functions.httpsCallable('sendEmailVerificationCode').call();
    } on FirebaseFunctionsException catch (error) {
      throw GakujiAuthException(_friendlyFunctionsMessage(error));
    } on FirebaseAuthException catch (error) {
      throw GakujiAuthException(_friendlyAuthMessage(error));
    }
  }

  /// Verifies the six-digit code on the server. The Cloud Function marks the
  /// Firebase Auth user as emailVerified only after the server-side code check
  /// succeeds, then the client refreshes its local Firebase user/token.
  static Future<void> verifyCurrentEmailCode(String code) async {
    final normalized = code.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(normalized)) {
      throw const GakujiAuthException('Enter the 6-digit code from your email.');
    }

    try {
      final result = await _functions
          .httpsCallable('verifyEmailVerificationCode')
          .call(<String, dynamic>{'code': normalized});
      final data = Map<String, dynamic>.from(result.data as Map);
      final verified = data['verified'] == true;
      if (!verified) {
        throw const GakujiAuthException(
          'That verification code could not be confirmed.',
        );
      }

      await _currentUser.reload();
      await _currentUser.getIdToken(true);

      if (!_currentUser.emailVerified) {
        throw const GakujiAuthException(
          'Verification succeeded, but Gakuji could not refresh your account yet. Try again.',
        );
      }
    } on FirebaseFunctionsException catch (error) {
      throw GakujiAuthException(_friendlyFunctionsMessage(error));
    } on FirebaseAuthException catch (error) {
      throw GakujiAuthException(_friendlyAuthMessage(error));
    }
  }

  static Future<void> _finishGuestUpgradeOrThrow() async {
    try {
      await GakujiUserDataStore.finishGuestUpgrade();
    } catch (_) {
      throw const GakujiAuthException(
        'Your account was created, but Gakuji could not finish preparing your '
        'local study data for sync. Your data is still safe on this device and '
        'Gakuji can retry when you have a connection.',
      );
    }
  }


  static String _friendlyFunctionsMessage(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'unauthenticated':
        return 'Please sign in again before verifying your email.';
      case 'invalid-argument':
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'That verification code is not valid.';
      case 'failed-precondition':
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'That verification code has expired. Request a new one.';
      case 'resource-exhausted':
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'Too many attempts. Please wait and request a new code.';
      case 'permission-denied':
        return 'Gakuji could not verify this account.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Could not reach Gakuji verification. Check your connection and try again.';
      default:
        final message = error.message?.trim();
        if (message != null && message.isNotEmpty) return message;
        return 'Email verification could not be completed. Please try again.';
    }
  }

  static String _friendlyAuthMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'The email or password is incorrect.';
      case 'email-already-in-use':
        return 'That email is already connected to another account.';
      case 'credential-already-in-use':
        return 'That sign-in method is already connected to another Gakuji account.';
      case 'provider-already-linked':
        return 'That sign-in method is already connected.';
      case 'weak-password':
        return 'Use a stronger password with at least 6 characters.';
      case 'requires-recent-login':
        return 'Please sign in again before making this security change.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a little and try again.';
      case 'network-request-failed':
        return 'Could not reach Firebase. Check your connection and try again.';
      case 'operation-not-allowed':
        return 'Email & Password sign-in is not enabled for this Firebase project yet.';
      case 'user-disabled':
        return 'This account has been disabled.';
      default:
        final message = error.message?.trim();
        if (message != null && message.isNotEmpty) return message;
        return 'Authentication could not be completed. Please try again.';
    }
  }
}
