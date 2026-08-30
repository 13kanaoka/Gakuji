# Gakuji email verification mode

The active verification path is Firebase Auth's normal email-verification link.

The custom six-digit verification infrastructure is intentionally retained for a future rollout:

- `cloud_functions` remains a dependency.
- `sendCurrentEmailVerificationCode()` remains in `GakujiAccountAuthService`.
- `verifyCurrentEmailCode()` remains in `GakujiAccountAuthService`.
- Existing callable Cloud Functions / SMTP code can remain deployed or stored unchanged.

To switch back later, the app can move the verification gate back to the six-digit code UI and call `sendCurrentEmailVerificationCode()` instead of `sendCurrentEmailVerification()`.
