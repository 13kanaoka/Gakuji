import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// The on-device source of truth for Gakuji study data.
///
/// Firestore is intentionally not involved in opening or using this database.
/// Cloud synchronization is handled separately by GakujiCloudSyncService.
class GakujiUserDatabase {
  static const String databaseName = 'gakuji_user.db';
  static const int databaseVersion = 6;

  static const String ownerUidMetadataKey = 'owner_uid';
  static const String pinnedUpdatedAtMetadataKey = 'pinned_updated_at';
  static const String lastCloudSyncMetadataKey = 'last_cloud_sync_at';
  static const String lastCloudRevisionMetadataKey = 'last_cloud_revision';
  static const String cloudBootstrapMetadataKey = 'cloud_bootstrap_complete';
  static const String localDirtyMetadataKey = 'local_dirty';
  static const String localChangeVersionMetadataKey = 'local_change_version';

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
        await _createLatestSchema(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createReviewTables(database);
        }
        if (oldVersion < 3) {
          await _upgradeToVersionThree(database);
        }
        if (oldVersion < 4) {
          await _createLocalFirstTables(database);
        }
        if (oldVersion < 5) {
          await _createSyncIndexes(database);
        }
        if (oldVersion < 6) {
          await _createDirtyEntityTable(database);
        }
      },
    );
  }

  static Future<void> _createLatestSchema(Database database) async {
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

    await _createReviewTables(database);
    await _createLocalFirstTables(database);
    await _createDirtyEntityTable(database);
    await _createSyncIndexes(database);
  }

  static Future<void> _createReviewTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS review_cards (
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
      CREATE TABLE IF NOT EXISTS review_logs (
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
  }

  static Future<void> _upgradeToVersionThree(Database database) async {
    final deckColumns = await database.rawQuery('PRAGMA table_info(decks)');
    final hasColorValue = deckColumns.any(
      (column) => column['name']?.toString() == 'color_value',
    );

    if (!hasColorValue) {
      await database.execute('ALTER TABLE decks ADD COLUMN color_value INTEGER');
    }

    // Older builds used term id as the global primary key. Deck terms are
    // deck-owned copies, so the real identity is (deck_id, id).
    await database.execute('''
      CREATE TABLE IF NOT EXISTS deck_terms_v3 (
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
      INSERT OR REPLACE INTO deck_terms_v3 (
        id, deck_id, source_id, term_json, marked, position, created_at, updated_at
      )
      SELECT
        id, deck_id, source_id, term_json, marked, position, created_at, updated_at
      FROM deck_terms
    ''');

    await database.execute('DROP TABLE deck_terms');
    await database.execute('ALTER TABLE deck_terms_v3 RENAME TO deck_terms');
  }

  static Future<void> _createLocalFirstTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS recent_searches (
        position INTEGER PRIMARY KEY,
        term_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS reading_card_edits (
        deck_id TEXT NOT NULL,
        term_id TEXT NOT NULL,
        source_id TEXT NOT NULL,
        edit_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(deck_id, term_id),
        FOREIGN KEY(deck_id) REFERENCES decks(id) ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS app_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS sync_tombstones (
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        deleted_at INTEGER NOT NULL,
        PRIMARY KEY(entity_type, entity_id)
      )
    ''');
  }


  static Future<void> _createDirtyEntityTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS sync_dirty_entities (
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        changed_at INTEGER NOT NULL,
        PRIMARY KEY(entity_type, entity_id)
      )
    ''');

    await database.execute(
      'CREATE INDEX IF NOT EXISTS sync_dirty_entities_changed_at_index '
      'ON sync_dirty_entities(changed_at)',
    );

    // Version 5 only knew that the workspace was dirty, not which entities
    // were dirty. Preserve any pending pre-v6 work as a one-time full snapshot
    // request so upgrading can never strand unsynchronized data.
    final dirtyRows = await database.query(
      'app_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [localDirtyMetadataKey],
      limit: 1,
    );
    final wasDirty = dirtyRows.isNotEmpty &&
        dirtyRows.first['value']?.toString() == 'true';
    if (wasDirty) {
      await database.insert(
        'sync_dirty_entities',
        {
          'entity_type': 'workspace',
          'entity_id': 'workspace',
          'changed_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  static Future<void> _createSyncIndexes(Database database) async {
    await database.execute(
      'CREATE INDEX IF NOT EXISTS deck_terms_deck_id_index ON deck_terms(deck_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS deck_terms_source_id_index ON deck_terms(source_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS folder_decks_folder_id_index ON folder_decks(folder_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS folder_decks_deck_id_index ON folder_decks(deck_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS review_cards_deck_id_index ON review_cards(deck_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS review_cards_due_at_index ON review_cards(due_at)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS review_logs_review_card_id_index ON review_logs(review_card_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS review_logs_reviewed_at_index ON review_logs(reviewed_at)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS sync_tombstones_deleted_at_index ON sync_tombstones(deleted_at)',
    );
  }

  static Future<String?> readMetadata(String key) async {
    final db = await database;
    final rows = await db.query(
      'app_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value']?.toString();
  }

  static Future<void> writeMetadata(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_metadata',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> deleteMetadata(String key) async {
    final db = await database;
    await db.delete('app_metadata', where: 'key = ?', whereArgs: [key]);
  }

  /// Clears personal study data from this device without touching Firestore.
  ///
  /// This is used on sign-out so another account never inherits the previous
  /// account's local workspace.
  static Future<void> clearUserData({bool keepOwner = false}) async {
    final db = await database;
    final owner = keepOwner ? await readMetadata(ownerUidMetadataKey) : null;

    await db.transaction((transaction) async {
      await transaction.delete('review_logs');
      await transaction.delete('review_cards');
      await transaction.delete('reading_card_edits');
      await transaction.delete('recent_searches');
      await transaction.delete('pinned_decks');
      await transaction.delete('folder_decks');
      await transaction.delete('deck_terms');
      await transaction.delete('folders');
      await transaction.delete('decks');
      await transaction.delete('dictionary_notes');
      await transaction.delete('user_preferences');
      await transaction.delete('sync_tombstones');
      await transaction.delete('sync_dirty_entities');
      await transaction.delete('app_metadata');

      if (owner != null && owner.isNotEmpty) {
        await transaction.insert(
          'app_metadata',
          {'key': ownerUidMetadataKey, 'value': owner},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  static Future<void> close() async {
    final existingDatabase = _database;
    if (existingDatabase == null) return;

    await existingDatabase.close();
    _database = null;
  }

  static Future<void> deleteUserDatabaseForDevelopment() async {
    final databasesPath = await getDatabasesPath();
    final databasePath = p.join(databasesPath, databaseName);

    await close();
    await deleteDatabase(databasePath);
  }
}
