const crypto = require('crypto');
const nodemailer = require('nodemailer');
const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {defineJsonSecret} = require('firebase-functions/params');

initializeApp();

const REGION = 'us-central1';
const CODE_TTL_MS = 10 * 60 * 1000;
const RESEND_COOLDOWN_MS = 60 * 1000;
const MAX_ATTEMPTS = 5;

// One JSON secret keeps the SMTP credentials and the verification-code pepper
// out of source control. See EMAIL_VERIFICATION_SETUP.md for the expected shape.
const emailConfig = defineJsonSecret('GAKUJI_EMAIL_CONFIG');

function requireSignedIn(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'Please sign in again first.');
  }
  return request.auth.uid;
}

function normalizedEmail(email) {
  return String(email || '').trim().toLowerCase();
}

function hashCode({uid, email, code, salt, pepper}) {
  return crypto
    .createHash('sha256')
    .update(`${uid}:${normalizedEmail(email)}:${code}:${salt}:${pepper}`)
    .digest('hex');
}

function timingSafeHexEqual(left, right) {
  try {
    const a = Buffer.from(left, 'hex');
    const b = Buffer.from(right, 'hex');
    return a.length === b.length && crypto.timingSafeEqual(a, b);
  } catch (_) {
    return false;
  }
}

function mailTransport(config) {
  return nodemailer.createTransport({
    host: config.host,
    port: Number(config.port || 587),
    secure: config.secure === true,
    auth: {
      user: config.user,
      pass: config.pass,
    },
  });
}

function verificationEmail({code, config}) {
  const fromName = String(config.fromName || 'Gakuji').trim();
  const fromEmail = String(config.fromEmail || '').trim();
  if (!fromEmail) {
    throw new Error('GAKUJI_EMAIL_CONFIG.fromEmail is required.');
  }

  const text = [
    'Verify your email',
    '',
    'Use this code in Gakuji to finish creating your account:',
    '',
    code,
    '',
    'This code expires in 10 minutes.',
    '',
    'If you did not create a Gakuji account, you can ignore this email.',
  ].join('\n');

  const html = `
<!doctype html>
<html>
  <body style="margin:0;padding:0;background:#f8f6ef;font-family:Arial,sans-serif;color:#4a4a4a;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f8f6ef;padding:32px 16px;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:520px;background:#fffdf8;border:1px solid #e7e0d2;border-radius:20px;padding:36px;">
            <tr>
              <td align="center" style="font-size:30px;font-weight:700;color:#4f7ff7;padding-bottom:20px;">Gakuji</td>
            </tr>
            <tr>
              <td align="center" style="font-size:24px;font-weight:700;color:#4a4a4a;padding-bottom:12px;">Verify your email</td>
            </tr>
            <tr>
              <td align="center" style="font-size:15px;line-height:1.6;color:#777;padding-bottom:24px;">Use this code in Gakuji to finish creating your account.</td>
            </tr>
            <tr>
              <td align="center">
                <div style="display:inline-block;background:#f2f5ff;border:1px solid #d7e0ff;border-radius:16px;padding:16px 24px;font-size:32px;font-weight:700;letter-spacing:8px;color:#3f6fe5;">${code}</div>
              </td>
            </tr>
            <tr>
              <td align="center" style="font-size:14px;line-height:1.6;color:#999;padding-top:24px;">This code expires in 10 minutes.</td>
            </tr>
            <tr>
              <td align="center" style="font-size:13px;line-height:1.6;color:#aaa;padding-top:14px;">If you did not create a Gakuji account, you can ignore this email.</td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;

  return {
    from: `"${fromName.replace(/"/g, '')}" <${fromEmail}>`,
    subject: 'Your Gakuji verification code',
    text,
    html,
  };
}

exports.sendEmailVerificationCode = onCall(
  {
    region: REGION,
    secrets: [emailConfig],
  },
  async (request) => {
    const uid = requireSignedIn(request);
    const auth = getAuth();
    const db = getFirestore();
    const user = await auth.getUser(uid);

    if (user.emailVerified) {
      return {sent: false, alreadyVerified: true};
    }

    const email = normalizedEmail(user.email);
    if (!email) {
      throw new HttpsError(
        'failed-precondition',
        'This account does not have an email address to verify.',
      );
    }

    const config = emailConfig.value();
    if (!config || !config.pepper) {
      throw new HttpsError(
        'failed-precondition',
        'Gakuji email verification is not configured yet.',
      );
    }

    const now = Date.now();
    const code = crypto.randomInt(0, 1000000).toString().padStart(6, '0');
    const salt = crypto.randomBytes(16).toString('hex');
    const hash = hashCode({
      uid,
      email,
      code,
      salt,
      pepper: String(config.pepper),
    });
    const ref = db.collection('emailVerificationCodes').doc(uid);

    const reservation = await db.runTransaction(async (tx) => {
      const snapshot = await tx.get(ref);
      if (snapshot.exists) {
        const previous = snapshot.data();
        const sentAtMs = previous.sentAt instanceof Timestamp
          ? previous.sentAt.toMillis()
          : 0;
        const remaining = RESEND_COOLDOWN_MS - (now - sentAtMs);
        if (remaining > 0) {
          return {
            allowed: false,
            retryAfterSeconds: Math.max(1, Math.ceil(remaining / 1000)),
          };
        }
      }

      tx.set(ref, {
        uid,
        email,
        hash,
        salt,
        attempts: 0,
        sentAt: Timestamp.fromMillis(now),
        expiresAt: Timestamp.fromMillis(now + CODE_TTL_MS),
      });
      return {allowed: true};
    });

    if (!reservation.allowed) {
      throw new HttpsError(
        'resource-exhausted',
        `Please wait ${reservation.retryAfterSeconds}s before requesting another code.`,
      );
    }

    try {
      const transport = mailTransport(config);
      await transport.sendMail({
        ...verificationEmail({code, config}),
        to: email,
      });
    } catch (error) {
      // Do not leave a cooldown record behind when delivery itself failed.
      await ref.delete().catch(() => {});
      console.error('Verification email delivery failed:', error);
      throw new HttpsError(
        'internal',
        'Gakuji could not send the verification code. Please try again.',
      );
    }

    return {sent: true};
  },
);

exports.verifyEmailVerificationCode = onCall(
  {
    region: REGION,
    secrets: [emailConfig],
  },
  async (request) => {
    const uid = requireSignedIn(request);
    const code = String(request.data && request.data.code || '').trim();
    if (!/^\d{6}$/.test(code)) {
      throw new HttpsError('invalid-argument', 'Enter the 6-digit code from your email.');
    }

    const auth = getAuth();
    const db = getFirestore();
    const user = await auth.getUser(uid);
    if (user.emailVerified) {
      return {verified: true};
    }

    const email = normalizedEmail(user.email);
    if (!email) {
      throw new HttpsError(
        'failed-precondition',
        'This account does not have an email address to verify.',
      );
    }

    const config = emailConfig.value();
    if (!config || !config.pepper) {
      throw new HttpsError(
        'failed-precondition',
        'Gakuji email verification is not configured yet.',
      );
    }

    const ref = db.collection('emailVerificationCodes').doc(uid);
    const now = Date.now();

    const result = await db.runTransaction(async (tx) => {
      const snapshot = await tx.get(ref);
      if (!snapshot.exists) {
        return {status: 'missing'};
      }

      const record = snapshot.data();
      const expiresAtMs = record.expiresAt instanceof Timestamp
        ? record.expiresAt.toMillis()
        : 0;
      if (!expiresAtMs || expiresAtMs <= now) {
        tx.delete(ref);
        return {status: 'expired'};
      }

      const attempts = Number(record.attempts || 0);
      if (attempts >= MAX_ATTEMPTS) {
        tx.delete(ref);
        return {status: 'locked'};
      }

      // If the account email changed after the code was issued, the old code
      // must never verify the new address.
      if (normalizedEmail(record.email) !== email) {
        tx.delete(ref);
        return {status: 'expired'};
      }

      const suppliedHash = hashCode({
        uid,
        email,
        code,
        salt: String(record.salt || ''),
        pepper: String(config.pepper),
      });

      if (!timingSafeHexEqual(suppliedHash, String(record.hash || ''))) {
        const nextAttempts = attempts + 1;
        if (nextAttempts >= MAX_ATTEMPTS) {
          tx.delete(ref);
          return {status: 'locked'};
        }
        tx.update(ref, {attempts: nextAttempts});
        return {
          status: 'wrong',
          attemptsRemaining: MAX_ATTEMPTS - nextAttempts,
        };
      }

      tx.delete(ref);
      return {status: 'verified'};
    });

    switch (result.status) {
      case 'verified':
        await auth.updateUser(uid, {emailVerified: true});
        return {verified: true};
      case 'wrong':
        throw new HttpsError(
          'invalid-argument',
          `That code is incorrect. ${result.attemptsRemaining} attempts remaining.`,
        );
      case 'locked':
        throw new HttpsError(
          'resource-exhausted',
          'Too many incorrect attempts. Request a new code.',
        );
      case 'expired':
        throw new HttpsError(
          'failed-precondition',
          'That code has expired. Request a new one.',
        );
      case 'missing':
      default:
        throw new HttpsError(
          'failed-precondition',
          'No active verification code was found. Request a new one.',
        );
    }
  },
);
