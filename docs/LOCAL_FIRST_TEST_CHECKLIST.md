# Gakuji Local-First Test Checklist

Run these after applying the patch on your Flutter machine.

## 1. Build/analyzer

```powershell
flutter pub get
flutter analyze
flutter run -d emulator-5554
```

## 2. Existing registered account migration

1. Start with an account that already has Firestore decks.
2. Launch online once.
3. Confirm decks/folders/review state appear after background sync.
4. Close the app.
5. Disable Wi-Fi/data.
6. Relaunch.
7. Confirm decks, dictionary, review state, notes, and study progress still work.

## 3. Offline edits

With Wi-Fi disabled:

1. Create a deck.
2. Add/remove terms.
3. Change a deck color.
4. Study cards and advance progress.
5. Complete reviews.
6. Edit a reading card/note.
7. Change review limits / writing-grid preference.
8. Close and relaunch while still offline.
9. Confirm every change survived locally.
10. Re-enable network and verify Firestore receives the changes.

## 4. Cross-device sync

1. Change/add data on Device A.
2. Let Device A sync.
3. Open Device B online.
4. Pull to refresh or resume Gakuji.
5. Confirm SQLite on Device B receives the changes.
6. Disable network on Device B and confirm the synced copy remains usable.

## 5. Manamoji compatibility

1. Add a term to a Gakuji deck through Manamoji/cloud.
2. Keep Gakuji open on the phone and make an unrelated local edit.
3. Let Gakuji sync or pull-to-refresh.
4. Confirm the Manamoji term appears locally and the local edit remains.
5. Confirm Gakuji does not overwrite/remove the Manamoji-only term.

## 6. Deletions

Offline, delete each of the following and then reconnect:

- a deck
- a term from a deck
- a folder
- a folder membership
- a pin
- a review card through deck/review-mode changes
- a reading-card edit

Confirm deleted data does not reappear after the pre-push cloud pull and is removed from Firestore after sync.

## 7. Guest mode

1. Continue as Guest.
2. Create/edit/study data offline.
3. Relaunch and confirm it remains local.
4. Verify no `users/{guestUid}` study data is created in Firestore.
5. Upgrade the guest to Email/Password or Google.
6. Confirm the same local data remains immediately available.
7. Confirm it then appears in Firestore under the same UID.

## 8. Sign out safety

Registered account:

1. Make an offline change.
2. Try Sign Out while still offline.
3. Confirm Gakuji refuses to wipe the local workspace because the change is unsynced.
4. Reconnect and sign out again.
5. Confirm cloud data remains and the device-local workspace is cleared.

Guest:

1. Create guest data.
2. Sign out.
3. Confirm the local guest workspace is intentionally wiped.

## 9. First-start handwriting provisioning

1. Install clean while online.
2. Launch Gakuji and remain on Login for a while.
3. Enter Writing Study later and confirm the Japanese model is already available.
4. Relaunch offline and confirm handwriting recognition still works.

## 10. Dictionary

1. Disable network before launch.
2. Search Japanese and English terms.
3. Open dictionary details and kanji details.
4. Confirm dictionary behavior is unaffected by Firebase connectivity.
