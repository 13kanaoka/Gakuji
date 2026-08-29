# Gakuji code-based email verification

This patch replaces Firebase Authentication's verification-link email with a
server-generated six-digit code that the user enters directly inside Gakuji.

## What changes

- Firebase Auth still owns the account and the `emailVerified` flag.
- A callable Cloud Function generates a six-digit code, stores only a salted
  hash in Firestore, and emails the code through SMTP.
- The code expires after 10 minutes.
- Resends are rate-limited to one per 60 seconds on the server.
- A code gets at most 5 incorrect attempts.
- Successful verification updates Firebase Auth's `emailVerified` field using
  the Admin SDK, then the Flutter client reloads its Firebase user/token.
- The client cannot read or write the verification-code collection.

## One-time setup

Cloud Functions deployment requires the Firebase project to be on the Blaze plan.
For normal low-volume verification traffic, Firebase still provides no-cost usage
quotas, but a billing account must be attached before functions can be deployed.

### 1. Install the Flutter dependency

From the project root:

```powershell
flutter pub get
```

The patch adds `cloud_functions: ^6.3.6` to `pubspec.yaml`.

### 2. Choose an SMTP sender

Use an email provider/account that can send SMTP mail. For a production-looking
email, use a sender on your own verified domain when you have one, for example:

```text
Gakuji <noreply@your-domain.com>
```

Configure SPF/DKIM with that provider so verification mail is less likely to be
sent to spam.

### 3. Store the mail settings as a Firebase secret

From the project root:

```powershell
firebase functions:secrets:set GAKUJI_EMAIL_CONFIG
```

When prompted, paste one JSON object with your SMTP values:

```json
{
  "host": "smtp.example.com",
  "port": 587,
  "secure": false,
  "user": "SMTP_USERNAME",
  "pass": "SMTP_PASSWORD",
  "fromEmail": "noreply@your-domain.com",
  "fromName": "Gakuji",
  "pepper": "PUT_A_LONG_RANDOM_SECRET_HERE"
}
```

For SMTP port 465, set `secure` to `true`. For 587, it is normally `false`.
The `pepper` should be a long random value and must never be committed to Git.

### 4. Install the server dependencies

```powershell
cd functions
npm install
cd ..
```

### 5. Deploy the functions and rules

```powershell
firebase deploy --only functions,firestore:rules
```

The functions use `us-central1`; the Flutter client is configured for the same
region.

## Test flow

1. Create a new Email & Password Gakuji account.
2. Confirm the email contains a six-digit code and no Firebase verification URL.
3. Enter a wrong code once and confirm it is rejected.
4. Enter the correct code and confirm Gakuji proceeds past the verification gate.
5. Sign out and sign back in; the account should remain verified.
6. Test Resend Code and confirm the 60-second cooldown is enforced.
7. Wait more than 10 minutes with a code and confirm it expires.

## Important

This replaces only the **new-account email verification** flow. Firebase's
password-reset and verify-before-email-change flows still use Firebase action
links. Those can be redesigned separately without changing this verification
code flow.
