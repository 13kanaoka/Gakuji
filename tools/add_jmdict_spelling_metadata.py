import argparse
import json
import sqlite3
from pathlib import Path
import xml.etree.ElementTree as ET

from convert_jmdict_to_sqlite_sense_based import (
    choose_preferred_spelling,
    collect_senses,
    collect_spelling_records,
    entry_is_usually_written_in_kana,
    open_jmdict,
    text_of,
)


def create_spelling_schema(connection):
    cursor = connection.cursor()
    cursor.execute("DROP TABLE IF EXISTS term_spellings")
    cursor.execute(
        """
        CREATE TABLE term_spellings (
            term_id TEXT NOT NULL,
            spelling TEXT NOT NULL,
            kind TEXT NOT NULL,
            position INTEGER NOT NULL,
            is_preferred INTEGER NOT NULL DEFAULT 0,
            usually_written_kana INTEGER NOT NULL DEFAULT 0,
            info_tags_json TEXT,
            priority_tags_json TEXT,
            restrictions_json TEXT,
            PRIMARY KEY (term_id, position)
        ) WITHOUT ROWID
        """
    )


def spelling_rows_for_entry(entry, known_term_ids):
    ent_seq = text_of(entry.find("ent_seq"))
    if not ent_seq:
        return []

    term_id = f"jmdict_{ent_seq}"
    if term_id not in known_term_ids:
        return []

    spellings = collect_spelling_records(entry)
    if not spellings:
        return []

    readings = [
        spelling["text"]
        for spelling in spellings
        if spelling["kind"] == "kana"
    ]
    kanji_spellings = [
        spelling["text"]
        for spelling in spellings
        if spelling["kind"] == "kanji"
    ]
    primary_reading = readings[0] if readings else (
        kanji_spellings[0] if kanji_spellings else ""
    )

    senses = collect_senses(entry)
    usually_written_in_kana = entry_is_usually_written_in_kana(senses)
    preferred_spelling = choose_preferred_spelling(
        spellings,
        usually_written_in_kana,
        primary_reading,
    )

    rows = []
    for spelling in spellings:
        rows.append(
            (
                term_id,
                spelling["text"],
                spelling["kind"],
                spelling["position"],
                1 if spelling["text"] == preferred_spelling else 0,
                1 if usually_written_in_kana else 0,
                json.dumps(spelling["info_tags"], ensure_ascii=False) if spelling["info_tags"] else None,
                json.dumps(spelling["priority_tags"], ensure_ascii=False) if spelling["priority_tags"] else None,
                json.dumps(spelling["restrictions"], ensure_ascii=False) if spelling["restrictions"] else None,
            )
        )

    return rows


def add_spelling_metadata(input_path, database_path):
    if not input_path.exists():
        raise FileNotFoundError(f"JMdict input file not found: {input_path}")
    if not database_path.exists():
        raise FileNotFoundError(f"Dictionary database not found: {database_path}")

    connection = sqlite3.connect(database_path)

    try:
        term_table = connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='terms'"
        ).fetchone()
        if term_table is None:
            raise RuntimeError("The database does not contain the terms table.")

        known_term_ids = {
            row[0]
            for row in connection.execute(
                "SELECT id FROM terms WHERE id LIKE 'jmdict_%'"
            )
        }

        print(f"Loaded {len(known_term_ids)} JMdict term ids from the database")

        with connection:
            create_spelling_schema(connection)
            cursor = connection.cursor()
            entry_count = 0
            row_count = 0

            with open_jmdict(input_path) as source:
                for _, element in ET.iterparse(source, events=("end",)):
                    if element.tag != "entry":
                        continue

                    rows = spelling_rows_for_entry(element, known_term_ids)
                    if rows:
                        cursor.executemany(
                            """
                            INSERT INTO term_spellings (
                                term_id,
                                spelling,
                                kind,
                                position,
                                is_preferred,
                                usually_written_kana,
                                info_tags_json,
                                priority_tags_json,
                                restrictions_json
                            )
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                            rows,
                        )
                        entry_count += 1
                        row_count += len(rows)

                    element.clear()

                    if entry_count > 0 and entry_count % 10000 == 0:
                        print(
                            f"Added spelling metadata for {entry_count} entries "
                            f"({row_count} written forms)..."
                        )

        connection.execute("ANALYZE term_spellings")
        connection.commit()

        print(f"Added spelling metadata for {entry_count} entries")
        print(f"Stored {row_count} written forms")
        print(f"Updated {database_path}")
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Add JMdict preferred/alternative written-form metadata to an "
            "existing Gakuji dictionary database without rebuilding its "
            "KANJIDIC, JLPT, or example-sentence tables."
        )
    )
    parser.add_argument("--input", required=True, help="JMdict XML or .gz source")
    parser.add_argument(
        "--database",
        default="assets/dictionary/dictionary.db",
        help="Existing Gakuji dictionary database to update in place",
    )
    args = parser.parse_args()

    add_spelling_metadata(
        input_path=Path(args.input),
        database_path=Path(args.database),
    )


if __name__ == "__main__":
    main()
