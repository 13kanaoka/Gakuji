import argparse
import gzip
import sqlite3
from pathlib import Path
import xml.etree.ElementTree as ET


LIST_SEPARATOR = ";"
BATCH_SIZE = 1000


def text_of(element):
    if element is None or element.text is None:
        return ""
    return element.text.strip()


def unique(values):
    seen = set()
    result = []

    for value in values:
        value = value.strip()

        if value and value not in seen:
            seen.add(value)
            result.append(value)

    return result


def integer_of(element):
    value = text_of(element)

    if not value:
        return None

    try:
        return int(value)
    except ValueError:
        return None


def joined(values):
    cleaned_values = []

    for value in unique(values):
        # Semicolons separate stored list items, so preserve source text by
        # replacing any embedded semicolon with a comma.
        cleaned_values.append(value.replace(LIST_SEPARATOR, ","))

    return LIST_SEPARATOR.join(cleaned_values)


def open_kanjidic(path):
    if path.suffix.lower() == ".gz":
        return gzip.open(path, "rt", encoding="utf-8")

    return path.open("r", encoding="utf-8")


def parse_character(character_element):
    character = text_of(character_element.find("literal"))

    if not character:
        return None

    radical = None

    for radical_value in character_element.findall("./radical/rad_value"):
        if radical_value.get("rad_type") == "classical":
            radical = integer_of(radical_value)
            break

    misc = character_element.find("misc")

    stroke_count = None
    grade = None
    jlpt_level = None
    frequency = None

    if misc is not None:
        stroke_count = integer_of(misc.find("stroke_count"))
        grade = integer_of(misc.find("grade"))
        jlpt_level = integer_of(misc.find("jlpt"))
        frequency = integer_of(misc.find("freq"))

    meanings = []
    onyomi = []
    kunyomi = []
    nanori = []

    reading_meaning = character_element.find("reading_meaning")

    if reading_meaning is not None:
        for reading_meaning_group in reading_meaning.findall("rmgroup"):
            for reading in reading_meaning_group.findall("reading"):
                reading_text = text_of(reading)
                reading_type = reading.get("r_type")

                if not reading_text:
                    continue

                if reading_type == "ja_on":
                    onyomi.append(reading_text)
                elif reading_type == "ja_kun":
                    kunyomi.append(reading_text)

            for meaning in reading_meaning_group.findall("meaning"):
                # In KANJIDIC2, meanings without m_lang are English.
                if meaning.get("m_lang") is None:
                    meaning_text = text_of(meaning)

                    if meaning_text:
                        meanings.append(meaning_text)

        nanori = [
            text_of(value)
            for value in reading_meaning.findall("nanori")
            if text_of(value)
        ]

    return (
        character,
        joined(meanings),
        joined(onyomi),
        joined(kunyomi),
        joined(nanori),
        stroke_count,
        grade,
        jlpt_level,
        frequency,
        radical,
        0,
    )


def table_exists(connection, table_name):
    row = connection.execute(
        """
        SELECT 1
        FROM sqlite_master
        WHERE type = 'table' AND name = ?
        LIMIT 1
        """,
        (table_name,),
    ).fetchone()

    return row is not None


def create_kanji_schema(connection):
    cursor = connection.cursor()

    cursor.execute("DROP TABLE IF EXISTS kanji_entries")

    cursor.execute(
        """
        CREATE TABLE kanji_entries (
            character TEXT PRIMARY KEY,
            meaning TEXT NOT NULL,
            onyomi TEXT,
            kunyomi TEXT,
            nanori TEXT,
            stroke_count INTEGER,
            grade INTEGER,
            jlpt_level INTEGER,
            frequency INTEGER,
            radical INTEGER,
            has_word_entry INTEGER NOT NULL DEFAULT 0
        )
        """
    )

    cursor.execute(
        """
        CREATE INDEX idx_kanji_entries_character
        ON kanji_entries(character)
        """
    )

    cursor.execute(
        """
        CREATE INDEX idx_kanji_entries_has_word_entry
        ON kanji_entries(has_word_entry)
        """
    )

    connection.commit()


def insert_batch(connection, rows):
    connection.executemany(
        """
        INSERT INTO kanji_entries (
            character,
            meaning,
            onyomi,
            kunyomi,
            nanori,
            stroke_count,
            grade,
            jlpt_level,
            frequency,
            radical,
            has_word_entry
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        rows,
    )


def update_word_entry_flags(connection):
    connection.execute(
        """
        UPDATE kanji_entries
        SET has_word_entry = CASE
            WHEN EXISTS (
                SELECT 1
                FROM terms
                WHERE terms.kanji = kanji_entries.character
            ) THEN 1
            ELSE 0
        END
        """
    )


def convert_kanjidic_to_sqlite(input_path, database_path, limit=None):
    if not input_path.exists():
        raise FileNotFoundError(f"KANJIDIC2 input file not found: {input_path}")

    if not database_path.exists():
        raise FileNotFoundError(
            "Dictionary database not found. Run convert_jmdict_to_sqlite.py "
            f"first: {database_path}"
        )

    connection = sqlite3.connect(database_path)

    try:
        if not table_exists(connection, "terms"):
            raise RuntimeError(
                "The database does not contain the terms table. "
                "Run convert_jmdict_to_sqlite.py first."
            )

        create_kanji_schema(connection)

        converted_count = 0
        missing_meaning_count = 0
        batch = []

        with open_kanjidic(input_path) as source:
            for _, element in ET.iterparse(source, events=("end",)):
                if element.tag != "character":
                    continue

                row = parse_character(element)

                if row is not None:
                    batch.append(row)
                    converted_count += 1

                    if not row[1]:
                        missing_meaning_count += 1

                    if len(batch) >= BATCH_SIZE:
                        insert_batch(connection, batch)
                        connection.commit()
                        batch.clear()
                        print(f"Converted {converted_count} kanji...")

                element.clear()

                if limit is not None and converted_count >= limit:
                    break

        if batch:
            insert_batch(connection, batch)

        update_word_entry_flags(connection)
        connection.commit()
        connection.execute("ANALYZE kanji_entries")
        connection.commit()

        word_entry_count = connection.execute(
            """
            SELECT COUNT(*)
            FROM kanji_entries
            WHERE has_word_entry = 1
            """
        ).fetchone()[0]

        print(f"Converted {converted_count} kanji")
        print(f"Kanji without an English meaning: {missing_meaning_count}")
        print(f"Kanji with an exact JMdict word entry: {word_entry_count}")
        print(f"Updated {database_path}")
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser(
        description="Import KANJIDIC2 data into an existing Gakuji dictionary database."
    )
    parser.add_argument("--input", required=True)
    parser.add_argument("--database", required=True)
    parser.add_argument("--limit", type=int)

    args = parser.parse_args()

    convert_kanjidic_to_sqlite(
        input_path=Path(args.input),
        database_path=Path(args.database),
        limit=args.limit,
    )


if __name__ == "__main__":
    main()
