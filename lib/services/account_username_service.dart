import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GakujiUsernameProfile {
  final String? username;
  final String? usernameNormalized;
  final String? previousUsername;
  final String? previousUsernameNormalized;
  final DateTime? usernameCreatedAt;
  final DateTime? usernameUpdatedAt;
  final DateTime? usernameChangeAvailableAt;

  const GakujiUsernameProfile({
    required this.username,
    required this.usernameNormalized,
    required this.previousUsername,
    required this.previousUsernameNormalized,
    required this.usernameCreatedAt,
    required this.usernameUpdatedAt,
    required this.usernameChangeAvailableAt,
  });

  bool get hasUsername => username != null && username!.isNotEmpty;

  bool get hasPreviousUsername =>
      previousUsername != null && previousUsername!.isNotEmpty;

  bool get isChangeCooldownActive {
    final availableAt = usernameChangeAvailableAt;
    if (availableAt == null) return false;
    return DateTime.now().toUtc().isBefore(availableAt);
  }
}

class GakujiUsernameValidation {
  final bool isValid;
  final String normalized;
  final String? message;

  const GakujiUsernameValidation({
    required this.isValid,
    required this.normalized,
    this.message,
  });
}

class GakujiUsernameAvailability {
  final bool isAvailable;
  final bool isCurrentUsername;
  final String message;

  const GakujiUsernameAvailability({
    required this.isAvailable,
    required this.isCurrentUsername,
    required this.message,
  });
}

class GakujiUsernameException implements Exception {
  final String message;

  const GakujiUsernameException(this.message);

  @override
  String toString() => message;
}

class GakujiUsernameService {
  static const Duration usernameChangeCooldown = Duration(days: 14);

  // Existing accounts created before this rollout are grandfathered in.
  // Accounts created at or after this instant must claim a username before
  // entering the main app. Keep this value stable once the feature ships.
  static final DateTime usernameRequiredSinceUtc =
      DateTime.utc(2026, 8, 21, 3, 56);

  static const Set<String> _reservedNames = {
    'admin',
    'administrator',
    'gakuji',
    'help',
    'mod',
    'moderator',
    'official',
    'staff',
    'support',
    'system',
  };

  // This is intentionally a conservative first-pass client filter. It is not
  // intended to replace authoritative server-side moderation.
  static const Set<String> _blockedExactTerms = {
    'asshole',
    'bitch',
    'cock',
    'cunt',
    'dick',
    'fuck',
    'fucker',
    'fucking',
    'nigga',
    'nigger',
    'pussy',
    'shit',
  };

  static const List<String> _blockedContainedTerms = [
    'faggot',
    'fuck',
    'nigga',
    'nigger',
  ];

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static GakujiUsernameProfile? _cachedProfile;
  static String? _cachedProfileUid;

  static GakujiUsernameProfile? get cachedCurrentProfile {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _cachedProfileUid != user.uid) return null;
    return _cachedProfile;
  }

  static User get _currentUser {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const GakujiUsernameException('You must be signed in first.');
    }
    return user;
  }

  static String normalize(String rawUsername) {
    return rawUsername.trim().toLowerCase();
  }

  static bool shouldRequireInitialUsername({
    required User user,
    required GakujiUsernameProfile profile,
  }) {
    if (profile.hasUsername) return false;

    final createdAt = user.metadata.creationTime?.toUtc();
    if (createdAt == null) {
      // If Firebase cannot tell us when an older account was created, prefer
      // grandfathering it rather than unexpectedly locking the user out.
      return false;
    }

    return !createdAt.isBefore(usernameRequiredSinceUtc);
  }

  static GakujiUsernameValidation validate(String rawUsername) {
    final trimmed = rawUsername.trim();
    final normalized = normalize(rawUsername);

    if (trimmed.length < 3 || trimmed.length > 20) {
      return GakujiUsernameValidation(
        isValid: false,
        normalized: normalized,
        message: 'Username must be 3–20 characters.',
      );
    }

    if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(trimmed)) {
      return GakujiUsernameValidation(
        isValid: false,
        normalized: normalized,
        message: 'Use only letters, numbers, and underscores.',
      );
    }

    if (_isReserved(normalized)) {
      return GakujiUsernameValidation(
        isValid: false,
        normalized: normalized,
        message: 'That username is reserved by Gakuji.',
      );
    }

    if (containsRestrictedLanguage(rawUsername)) {
      return GakujiUsernameValidation(
        isValid: false,
        normalized: normalized,
        message: 'That username contains a restricted term.',
      );
    }

    return GakujiUsernameValidation(
      isValid: true,
      normalized: normalized,
    );
  }

  /// Uses the same restricted-language rules as username validation for other
  /// user-authored labels, such as deck names.
  static bool containsRestrictedLanguage(String rawText) {
    return _containsBlockedLanguage(normalize(rawText));
  }

  static Future<GakujiUsernameProfile> loadCurrentProfile({
    bool forceRefresh = false,
  }) async {
    final user = _currentUser;

    if (!forceRefresh &&
        _cachedProfileUid == user.uid &&
        _cachedProfile != null) {
      return _cachedProfile!;
    }

    final userRef = _firestore.collection('users').doc(user.uid);
    final snapshot = await userRef.get();
    final userData = snapshot.data() ?? <String, dynamic>{};
    var profile = _profileFromData(userData);

    // One-time recovery for usernames changed before the explicit previous-name
    // fields existed. The username registry already reserves that old name for
    // this user, so recover only the user's own still-active reservation.
    if (profile.isChangeCooldownActive && !profile.hasPreviousUsername) {
      final recovered = await _recoverReservedPreviousUsername(
        userUid: user.uid,
        changeAvailableAt: profile.usernameChangeAvailableAt,
      );

      if (recovered != null) {
        final recoveredData = <String, dynamic>{
          ...userData,
          'previousUsername': recovered.key,
          'previousUsernameNormalized': recovered.value,
        };

        await userRef.set({
          'previousUsername': recovered.key,
          'previousUsernameNormalized': recovered.value,
        }, SetOptions(merge: true));

        profile = _profileFromData(recoveredData);
      }
    }

    _cachedProfileUid = user.uid;
    _cachedProfile = profile;

    return profile;
  }

  static Future<GakujiUsernameAvailability> checkAvailability(
    String rawUsername,
  ) async {
    final validation = validate(rawUsername);
    if (!validation.isValid) {
      return GakujiUsernameAvailability(
        isAvailable: false,
        isCurrentUsername: false,
        message: validation.message ?? 'That username cannot be used.',
      );
    }

    final user = _currentUser;
    final profile = await loadCurrentProfile();

    if (profile.usernameNormalized == validation.normalized) {
      return const GakujiUsernameAvailability(
        isAvailable: false,
        isCurrentUsername: true,
        message: 'This is your current username.',
      );
    }

    final registrySnapshot = await _firestore
        .collection('usernames')
        .doc(validation.normalized)
        .get();

    if (!registrySnapshot.exists) {
      return const GakujiUsernameAvailability(
        isAvailable: true,
        isCurrentUsername: false,
        message: 'Username available.',
      );
    }

    final data = registrySnapshot.data() ?? <String, dynamic>{};
    final ownerUid = data['uid']?.toString();
    final status = data['status']?.toString() ?? 'active';
    final reservedUntil = _readDateTime(data['reservedUntil']);
    final now = DateTime.now().toUtc();

    if (status == 'reserved' &&
        reservedUntil != null &&
        !now.isBefore(reservedUntil)) {
      return const GakujiUsernameAvailability(
        isAvailable: true,
        isCurrentUsername: false,
        message: 'Username available.',
      );
    }

    if (ownerUid == user.uid && status == 'reserved') {
      return const GakujiUsernameAvailability(
        isAvailable: false,
        isCurrentUsername: false,
        message: 'That previous username is still in its 14-day reservation.',
      );
    }

    return const GakujiUsernameAvailability(
      isAvailable: false,
      isCurrentUsername: false,
      message: 'Username already taken.',
    );
  }

  static Future<GakujiUsernameProfile> saveUsername(
    String rawUsername,
  ) async {
    final validation = validate(rawUsername);
    if (!validation.isValid) {
      throw GakujiUsernameException(
        validation.message ?? 'That username cannot be used.',
      );
    }

    final user = _currentUser;
    final displayUsername = rawUsername.trim();
    final normalized = validation.normalized;
    final firestore = _firestore;
    final userRef = firestore.collection('users').doc(user.uid);
    final newUsernameRef = firestore.collection('usernames').doc(normalized);
    final now = DateTime.now().toUtc();

    await firestore.runTransaction((transaction) async {
      // Firestore transactions require reads before writes. Read both of the
      // documents that decide whether this claim is legal up front.
      final userSnapshot = await transaction.get(userRef);
      final newUsernameSnapshot = await transaction.get(newUsernameRef);

      final userData = userSnapshot.data() ?? <String, dynamic>{};
      final currentUsername = userData['username']?.toString().trim();
      final currentNormalized =
          userData['usernameNormalized']?.toString().trim().toLowerCase() ??
          (currentUsername == null ? null : normalize(currentUsername));
      final changeAvailableAt = _readDateTime(
        userData['usernameChangeAvailableAt'],
      );

      if (currentNormalized == normalized) {
        return;
      }

      final isRename = currentNormalized != null && currentNormalized.isNotEmpty;

      if (isRename &&
          changeAvailableAt != null &&
          now.isBefore(changeAvailableAt)) {
        throw GakujiUsernameException(
          'You can change your username again after the 14-day cooldown.',
        );
      }

      if (newUsernameSnapshot.exists) {
        final registryData =
            newUsernameSnapshot.data() ?? <String, dynamic>{};
        final ownerUid = registryData['uid']?.toString();
        final status = registryData['status']?.toString() ?? 'active';
        final reservedUntil = _readDateTime(registryData['reservedUntil']);
        final reservationExpired = status == 'reserved' &&
            reservedUntil != null &&
            !now.isBefore(reservedUntil);

        if (!reservationExpired) {
          if (ownerUid == user.uid && status == 'reserved') {
            throw const GakujiUsernameException(
              'That previous username is still in its 14-day reservation.',
            );
          }
          throw const GakujiUsernameException('Username already taken.');
        }
      }

      DateTime? nextChangeAt;

      if (isRename) {
        nextChangeAt = now.add(usernameChangeCooldown);
        final oldUsernameRef = firestore
            .collection('usernames')
            .doc(currentNormalized);

        transaction.set(oldUsernameRef, {
          'uid': user.uid,
          'username': currentUsername,
          'status': 'reserved',
          'reservedUntil': Timestamp.fromDate(nextChangeAt),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      transaction.set(newUsernameRef, {
        'uid': user.uid,
        'username': displayUsername,
        'status': 'active',
        'reservedUntil': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final userUpdate = <String, dynamic>{
        'username': displayUsername,
        'usernameNormalized': normalized,
        'usernameUpdatedAt': FieldValue.serverTimestamp(),
        'usernameChangeAvailableAt': nextChangeAt == null
            ? FieldValue.delete()
            : Timestamp.fromDate(nextChangeAt),
      };

      if (isRename) {
        userUpdate['previousUsername'] = currentUsername;
        userUpdate['previousUsernameNormalized'] = currentNormalized;
      } else {
        userUpdate['usernameCreatedAt'] = FieldValue.serverTimestamp();
        userUpdate['previousUsername'] = FieldValue.delete();
        userUpdate['previousUsernameNormalized'] = FieldValue.delete();
      }

      transaction.set(userRef, userUpdate, SetOptions(merge: true));
    });

    return loadCurrentProfile(forceRefresh: true);
  }

  static Future<GakujiUsernameProfile> revertToPreviousUsername() async {
    final user = _currentUser;
    final firestore = _firestore;
    final userRef = firestore.collection('users').doc(user.uid);
    final now = DateTime.now().toUtc();

    await firestore.runTransaction((transaction) async {
      final userSnapshot = await transaction.get(userRef);
      final userData = userSnapshot.data() ?? <String, dynamic>{};

      final currentUsername = userData['username']?.toString().trim();
      final currentNormalized =
          userData['usernameNormalized']?.toString().trim().toLowerCase() ??
          (currentUsername == null ? null : normalize(currentUsername));
      final previousUsername = userData['previousUsername']?.toString().trim();
      final previousNormalized = userData['previousUsernameNormalized']
              ?.toString()
              .trim()
              .toLowerCase() ??
          (previousUsername == null ? null : normalize(previousUsername));
      final changeAvailableAt = _readDateTime(
        userData['usernameChangeAvailableAt'],
      );

      if (currentUsername == null ||
          currentUsername.isEmpty ||
          currentNormalized == null ||
          currentNormalized.isEmpty ||
          previousUsername == null ||
          previousUsername.isEmpty ||
          previousNormalized == null ||
          previousNormalized.isEmpty) {
        throw const GakujiUsernameException(
          'There is no previous username to revert to.',
        );
      }

      if (changeAvailableAt == null || !now.isBefore(changeAvailableAt)) {
        throw const GakujiUsernameException(
          'The revert window for your previous username has ended.',
        );
      }

      final currentUsernameRef =
          firestore.collection('usernames').doc(currentNormalized);
      final previousUsernameRef =
          firestore.collection('usernames').doc(previousNormalized);

      final currentUsernameSnapshot = await transaction.get(currentUsernameRef);
      final previousUsernameSnapshot =
          await transaction.get(previousUsernameRef);

      if (!currentUsernameSnapshot.exists || !previousUsernameSnapshot.exists) {
        throw const GakujiUsernameException(
          'Could not verify the usernames needed for this revert.',
        );
      }

      final currentRegistryData =
          currentUsernameSnapshot.data() ?? <String, dynamic>{};
      final previousRegistryData =
          previousUsernameSnapshot.data() ?? <String, dynamic>{};
      final previousReservedUntil =
          _readDateTime(previousRegistryData['reservedUntil']);

      if (currentRegistryData['uid']?.toString() != user.uid ||
          currentRegistryData['status']?.toString() != 'active') {
        throw const GakujiUsernameException(
          'Your current username could not be verified.',
        );
      }

      if (previousRegistryData['uid']?.toString() != user.uid ||
          previousRegistryData['status']?.toString() != 'reserved' ||
          previousReservedUntil == null ||
          !now.isBefore(previousReservedUntil)) {
        throw const GakujiUsernameException(
          'Your previous username is no longer reserved for this account.',
        );
      }

      // Reverting does not restart the 14-day cooldown. The username being
      // replaced stays reserved only until the original cooldown deadline.
      transaction.set(currentUsernameRef, {
        'uid': user.uid,
        'username': currentUsername,
        'status': 'reserved',
        'reservedUntil': Timestamp.fromDate(changeAvailableAt),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.set(previousUsernameRef, {
        'uid': user.uid,
        'username': previousUsername,
        'status': 'active',
        'reservedUntil': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.set(userRef, {
        'username': previousUsername,
        'usernameNormalized': previousNormalized,
        'usernameUpdatedAt': FieldValue.serverTimestamp(),
        'usernameChangeAvailableAt': Timestamp.fromDate(changeAvailableAt),
        'previousUsername': FieldValue.delete(),
        'previousUsernameNormalized': FieldValue.delete(),
      }, SetOptions(merge: true));
    });

    return loadCurrentProfile(forceRefresh: true);
  }

  static Future<MapEntry<String, String>?> _recoverReservedPreviousUsername({
    required String userUid,
    required DateTime? changeAvailableAt,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('usernames')
          .where('uid', isEqualTo: userUid)
          .get();
      final now = DateTime.now().toUtc();

      MapEntry<String, String>? bestMatch;
      Duration? bestDistance;

      for (final document in snapshot.docs) {
        final data = document.data();
        if (data['status']?.toString() != 'reserved') continue;

        final reservedUntil = _readDateTime(data['reservedUntil']);
        if (reservedUntil == null || !now.isBefore(reservedUntil)) continue;

        final normalized = document.id.trim().toLowerCase();
        if (normalized.isEmpty) continue;

        final storedUsername = data['username']?.toString().trim();
        final displayUsername =
            storedUsername == null || storedUsername.isEmpty
                ? normalized
                : storedUsername;

        if (changeAvailableAt == null) {
          return MapEntry(displayUsername, normalized);
        }

        final distanceMilliseconds =
            (reservedUntil.millisecondsSinceEpoch -
                    changeAvailableAt.millisecondsSinceEpoch)
                .abs();
        final distance = Duration(milliseconds: distanceMilliseconds);

        if (bestDistance == null || distance < bestDistance) {
          bestDistance = distance;
          bestMatch = MapEntry(displayUsername, normalized);
        }
      }

      return bestMatch;
    } catch (_) {
      // Keep normal profile loading usable if the migration query is not yet
      // permitted or the network is temporarily unavailable.
      return null;
    }
  }

  static GakujiUsernameProfile _profileFromData(
    Map<String, dynamic>? data,
  ) {
    final username = data?['username']?.toString().trim();
    final normalized = data?['usernameNormalized']?.toString().trim();
    final previousUsername = data?['previousUsername']?.toString().trim();
    final previousNormalized =
        data?['previousUsernameNormalized']?.toString().trim();

    return GakujiUsernameProfile(
      username: username == null || username.isEmpty ? null : username,
      usernameNormalized: normalized == null || normalized.isEmpty
          ? (username == null || username.isEmpty ? null : normalize(username))
          : normalized.toLowerCase(),
      previousUsername:
          previousUsername == null || previousUsername.isEmpty
              ? null
              : previousUsername,
      previousUsernameNormalized:
          previousNormalized == null || previousNormalized.isEmpty
              ? (previousUsername == null || previousUsername.isEmpty
                    ? null
                    : normalize(previousUsername))
              : previousNormalized.toLowerCase(),
      usernameCreatedAt: _readDateTime(data?['usernameCreatedAt']),
      usernameUpdatedAt: _readDateTime(data?['usernameUpdatedAt']),
      usernameChangeAvailableAt: _readDateTime(
        data?['usernameChangeAvailableAt'],
      ),
    );
  }

  static DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    return null;
  }

  static bool _isReserved(String normalized) {
    if (_reservedNames.contains(normalized)) return true;

    for (final reserved in _reservedNames) {
      if (normalized.startsWith('${reserved}_')) return true;

      if (normalized.startsWith(reserved) &&
          normalized.length > reserved.length) {
        final suffix = normalized.substring(reserved.length);
        if (RegExp(r'^[0-9]+$').hasMatch(suffix)) return true;
      }
    }

    return false;
  }

  static bool _containsBlockedLanguage(String normalized) {
    final canonical = _moderationCanonical(normalized);
    final lettersOnly = canonical.replaceAll(RegExp(r'[^a-z]'), '');

    final wordTokens = canonical
        .split(RegExp(r'[^a-z]+'))
        .where((token) => token.isNotEmpty);

    if (_blockedExactTerms.contains(canonical) ||
        _blockedExactTerms.contains(lettersOnly) ||
        wordTokens.any(_blockedExactTerms.contains)) {
      return true;
    }

    for (final blockedTerm in _blockedContainedTerms) {
      if (canonical.contains(blockedTerm) ||
          lettersOnly.contains(blockedTerm)) {
        return true;
      }
    }

    return false;
  }

  static String _moderationCanonical(String normalized) {
    return normalized
        .replaceAll('_', '')
        .replaceAll('0', 'o')
        .replaceAll('1', 'i')
        .replaceAll('3', 'e')
        .replaceAll('4', 'a')
        .replaceAll('5', 's')
        .replaceAll('7', 't');
  }
}
