import csv
import sqlite3
from pathlib import Path


CSV_PATH = Path("tools/source/learner_priority_words.csv")
DB_PATH = Path("assets/dictionary/dictionary.db")

TARGET_KANJI = "遊ぶ"
TARGET_READING = "あそぶ"
TARGET_KEYWORD = "play"


def main():
    print("Checking CSV...")
    found_csv_rows = []

    with CSV_PATH.open("r", encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)

        for row in reader:
            kanji = (row.get("kanji") or "").strip()
            reading = (row.get("reading") or "").strip()
            keyword = (row.get("english_keyword") or "").strip()
            weight = (row.get("weight") or "").strip()

            if kanji == TARGET_KANJI or reading == TARGET_READING or keyword == TARGET_KEYWORD:
                found_csv_rows.append((kanji, reading, keyword, weight))

    for row in found_csv_rows:
        print("CSV:", row)

    print()
    print("Checking DB terms...")

    connection = sqlite3.connect(DB_PATH)

    term_rows = connection.execute(
        """
        SELECT id, kanji, reading, meaning
        FROM terms
        WHERE kanji = ?
           OR reading = ?
        ORDER BY kanji, reading
        """,
        [TARGET_KANJI, TARGET_READING],
    ).fetchall()

    for row in term_rows:
        print("TERM:", row)

    print()
    print("Checking DB keyword row...")

    keyword_rows = connection.execute(
        """
        SELECT
          t.id,
          t.kanji,
          t.reading,
          sk.keyword,
          sk.weight
        FROM terms t
        JOIN search_keywords sk ON t.id = sk.term_id
        WHERE t.kanji = ?
          AND t.reading = ?
          AND sk.keyword = ?
        """,
        [TARGET_KANJI, TARGET_READING, TARGET_KEYWORD],
    ).fetchall()

    for row in keyword_rows:
        print("KEYWORD:", row)

    if not keyword_rows:
        print("No exact keyword row found.")

    connection.close()


if __name__ == "__main__":
    main()