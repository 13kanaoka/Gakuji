import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local-only storage used while Firebase Auth is anonymous.
///
/// The anonymous Firebase UID is only an identity handle. Guest study data is
/// intentionally kept out of Firestore until the anonymous account is linked
/// to a real sign-in method.
class GakujiGuestDatabase {
  static const String databaseName = 'gakuji_guest.db';
  static const int databaseVersion = 1;

  static Database? _database;

  static Future<Database> get database async {
    final existingDatabase = _database;
    if (existingDatabase != null) return existingDatabase;

    final openedDatabase = await _openDatabase();
    _database = openedDatabase;
    return openedDatabase;
  }

  static Future<Database> _openDatabase() async {
    final databasesPath = await getDatabasesPath();
    final databasePath = p.join(databasesPath, databaseName);

    return openDatabase(
      databasePath,
      version: databaseVersion,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE decks (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            color_value INTEGER,
            review_enabled INTEGER NOT NULL DEFAULT 0,
            active_study_mode TEXT NOT NULL DEFAULT 'study',
            review_enabled_at INTEGER,
            last_study_index INTEGER NOT NULL DEFAULT 0,
            is_shuffled INTEGER NOT NULL DEFAULT 0,
            position INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');

        await database.execute('''
          CREATE TABLE deck_terms (
            id TEXT NOT NULL,
            deck_id TEXT NOT NULL,
            source_id TEXT NOT NULL,
            term_json TEXT NOT NULL,
            marked INTEGER NOT NULL DEFAULT 0,
            position INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY(deck_id, id),
            FOREIGN KEY(deck_id) REFERENCES decks(id) ON DELETE CASCADE,
            UNIQUE(deck_id, source_id)
          )
        ''');

        await database.execute('''
          CREATE TABLE folders (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            position INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');

        await database.execute('''
          CREATE TABLE folder_decks (
            folder_id TEXT NOT NULL,
            deck_id TEXT NOT NULL,
            position INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            PRIMARY KEY(folder_id, deck_id),
            FOREIGN KEY(folder_id) REFERENCES folders(id) ON DELETE CASCADE,
            FOREIGN KEY(deck_id) REFERENCES decks(id) ON DELETE CASCADE
          )
        ''');

        await database.execute('''
          CREATE TABLE pinned_decks (
            deck_id TEXT PRIMARY KEY,
            position INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            FOREIGN KEY(deck_id) REFERENCES decks(id) ON DELETE CASCADE
          )
        ''');

        await database.execute('''
          CREATE TABLE dictionary_notes (
            source_id TEXT PRIMARY KEY,
            note TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');

        await database.execute('''
          CREATE TABLE user_preferences (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');

        await database.execute('''
          CREATE TABLE review_cards (
            id TEXT PRIMARY KEY,
            deck_id TEXT NOT NULL,
            term_id TEXT NOT NULL,
            card_type TEXT NOT NULL,
            fsrs_card_json TEXT NOT NULL,
            due_at INTEGER NOT NULL,
            last_reviewed_at INTEGER,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            FOREIGN KEY(deck_id) REFERENCES decks(id) ON DELETE CASCADE,
            UNIQUE(deck_id, term_id, card_type)
          )
        ''');

        await database.execute('''
          CREATE TABLE review_logs (
            id TEXT PRIMARY KEY,
            review_card_id TEXT NOT NULL,
            rating INTEGER NOT NULL,
            reviewed_at INTEGER NOT NULL,
            fsrs_log_json TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            FOREIGN KEY(review_card_id)
              REFERENCES review_cards(id)
              ON DELETE CASCADE
          )
        ''');

        await database.execute(
          'CREATE INDEX deck_terms_deck_id_index ON deck_terms(deck_id)',
        );
        await database.execute(
          'CREATE INDEX deck_terms_source_id_index ON deck_terms(source_id)',
        );
        await database.execute(
          'CREATE INDEX folder_decks_folder_id_index ON folder_decks(folder_id)',
        );
        await database.execute(
          'CREATE INDEX folder_decks_deck_id_index ON folder_decks(deck_id)',
        );
        await database.execute(
          'CREATE INDEX review_cards_deck_id_index ON review_cards(deck_id)',
        );
        await database.execute(
          'CREATE INDEX review_cards_due_at_index ON review_cards(due_at)',
        );
        await database.execute(
          'CREATE INDEX review_logs_review_card_id_index ON review_logs(review_card_id)',
        );
        await database.execute(
          'CREATE INDEX review_logs_reviewed_at_index ON review_logs(reviewed_at)',
        );
      },
    );
  }

  static Future<void> clearUserData() async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete('review_logs');
      await transaction.delete('review_cards');
      await transaction.delete('pinned_decks');
      await transaction.delete('folder_decks');
      await transaction.delete('deck_terms');
      await transaction.delete('folders');
      await transaction.delete('decks');
      await transaction.delete('dictionary_notes');
      await transaction.delete('user_preferences');
    });
  }

  static Future<void> close() async {
    final existingDatabase = _database;
    if (existingDatabase == null) return;

    await existingDatabase.close();
    _database = null;
  }
}
