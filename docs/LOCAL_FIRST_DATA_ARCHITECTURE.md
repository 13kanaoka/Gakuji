# Gakuji Local-First Data Architecture

## Core rule

Gakuji's on-device SQLite database is the working source of truth for study data.
Firestore is only a synchronization junction between installations.

A network connection must never be required to:

- open the dictionary
- open decks or folders already on the device
- add/remove/edit terms
- study or review
- update FSRS state and review history
- save study progress or shuffle/review state
- use notes and reading-card edits
- change study preferences
- use games/high scores

The bundled dictionary remains local. The Japanese handwriting model is provisioned immediately on first launch and cached by ML Kit for later offline use.

## Runtime flow

```text
UI / Study / Dictionary
        |
        v
GakujiUserRepository
        |
        v
SQLite (gakuji_user.db)
SOURCE OF TRUTH
        |
        | background sync when registered + connected
        v
GakujiCloudSyncService
        |
        v
Firestore
```

### Startup

1. Firebase initializes for authentication, but study data is not loaded from Firestore.
2. The bundled dictionary starts loading in the background.
3. Japanese handwriting model provisioning starts in the background.
4. `GakujiUserDataStore.load()` opens the local workspace for the active UID.
5. The app becomes usable from SQLite.
6. For a registered account, background synchronization runs afterward.
7. If remote changes are found, they are merged into SQLite and the UI reloads from SQLite only when it is safe to do so.

A completely new installation with an existing account may temporarily show an empty local workspace until its first cloud seed completes, but the dictionary/app itself is not blocked by Firestore.

## Guest mode

Guest Mode uses Firebase Anonymous Auth only for a stable UID.

- Guest study data stays in `gakuji_user.db`.
- Anonymous users are denied Firestore access by security rules.
- No separate permanent guest cloud database exists.
- A temporary `gakuji_guest.db` reader remains only as a one-time migration bridge for builds that used the earlier guest implementation.

When a guest creates an account:

1. The anonymous Firebase user is linked to Email/Password or Google.
2. The UID remains unchanged.
3. The local SQLite database remains exactly where it is.
4. Cloud synchronization becomes enabled.
5. The local copy is mirrored to Firestore; it is not deleted or replaced.

## Registered accounts

A registered account still works from SQLite.

Local changes complete in this order:

```text
user action
  -> SQLite transaction succeeds
  -> UI continues normally
  -> local workspace marked dirty
  -> background sync scheduled
  -> Firestore updated when available
```

Cloud failures do not roll back local study actions.

### Sign out

For registered accounts, Gakuji flushes pending local work and attempts a final sync before removing the account's local workspace. If unsynced local changes cannot be mirrored, sign-out is blocked so those changes are not destroyed.

For guests, signing out intentionally discards the local guest workspace because no cloud copy exists.

## SQLite schema

Database version: 5.

Primary tables:

- `decks`
- `deck_terms`
- `folders`
- `folder_decks`
- `pinned_decks`
- `review_cards`
- `review_logs`
- `dictionary_notes`
- `reading_card_edits`
- `recent_searches`
- `user_preferences`
- `app_metadata`
- `sync_tombstones`

`deck_terms` uses `(deck_id, id)` as its primary key so the same lexical term may exist independently in more than one deck.

## Synchronization safety

### Dirty state and local change version

Every syncable local mutation marks the workspace dirty and increments `local_change_version`.

A cloud push records the version it started with. It clears the dirty flag only if the version is unchanged after network writes finish. If the user changed something while the upload was running, the newer local work stays dirty and another sync is scheduled.

### Tombstones

Local deletions that could otherwise be resurrected during a pre-push cloud pull are recorded in `sync_tombstones`.

Current tombstone types include:

- deck
- deck term
- folder
- folder membership
- pin
- review card
- reading-card edit
- preference

Tombstones remain until the corresponding cloud mirror completes successfully.

### Safe UI reload

A background cloud pull can take long enough for the user to keep working. `GakujiUserDataStore` tracks both the in-memory revision and SQLite change version. It only reloads the live UI from SQLite when neither changed during the network pass. If the user is actively changing data, Gakuji protects the current local UI and retries sync later instead of clobbering newer work.

### External writers / Manamoji

Before pushing a dirty local workspace, Gakuji performs a cloud merge. This lets remote-only decks/terms (including Manamoji additions) enter the local SQLite copy before the cloud mirror is written back.

Local deletions win through tombstones. Local deck settings remain local-first when local work is pending, while remote-only terms are preserved.

## Preferences

Study/user preferences that should follow the Gakuji account are stored in SQLite and participate in sync. Older SharedPreferences values are migrated once and removed.

Examples moved to SQLite include:

- review limits and daily usage counters
- writing grid preference
- Blue Card Text
- game high scores/options
- profile icon
- direct-save deck choice
- review-session state
- recently opened deck IDs (local write path; may be mirrored on later sync)

Device presentation settings such as the app theme remain local SharedPreferences intentionally because they are device UI state rather than study content.

## Network-backed features that remain intentionally separate

- Firebase Authentication
- username registry/account identity
- cloud synchronization itself
- first-install Japanese ML Kit model provisioning

These services may be unavailable offline, but they must not prevent access to already-local study data.

## Firestore role

Firestore should be thought of as an intersection:

```text
Phone SQLite <----> Firestore <----> Desktop SQLite
```

not as:

```text
UI ----> Firestore ----> study data
```

Future sync optimization can move from snapshot mirroring to per-entity/delta uploads without changing the local-first contract.
