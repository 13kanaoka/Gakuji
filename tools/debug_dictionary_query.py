import argparse
import csv
import sqlite3
from pathlib import Path


DB_PATH = Path("assets/dictionary/dictionary.db")
CSV_PATH = Path("tools/source/learner_priority_words.csv")


def load_priority_rows(csv_path):
    if not csv_path.exists():
        return []

    rows = []

    with csv_path.open("r", encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)

        for row in reader:
            kanji = (row.get("kanji") or "").strip()
            reading = (row.get("reading") or "").strip()
            keyword = (row.get("english_keyword") or "").lower().strip()
            weight_text = (row.get("weight") or "").strip()
            level = (row.get("level") or "").strip()

            if not kanji or not reading or not keyword:
                continue

            try:
                weight = int(weight_text)
            except ValueError:
                weight = 0

            rows.append(
                {
                    "kanji": kanji,
                    "reading": reading,
                    "keyword": keyword,
                    "weight": weight,
                    "level": level,
                }
            )

    return rows


def print_priority_rows_for_query(connection, query, priority_rows):
    matching_rows = [
        row for row in priority_rows if row["keyword"] == query
    ]

    print("Learner priority CSV matches:")
    if not matching_rows:
        print("  None")
        print()
        return

    for row in matching_rows:
        db_rows = connection.execute(
            """
            SELECT
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
            [
                row["kanji"],
                row["reading"],
                row["keyword"],
            ],
        ).fetchall()

        if db_rows:
            db_weight = db_rows[0][3]
            status = "OK" if db_weight == row["weight"] else "MISMATCH"

            print(
                f"  {row['kanji']} [{row['reading']}] "
                f"{row['keyword']} csv={row['weight']} db={db_weight} "
                f"level={row['level']} {status}"
            )
        else:
            print(
                f"  {row['kanji']} [{row['reading']}] "
                f"{row['keyword']} csv={row['weight']} "
                f"level={row['level']} NOT FOUND IN DB"
            )

    print()


def debug_query(query, limit):
    if not DB_PATH.exists():
        print(f"Database not found: {DB_PATH}")
        return

    priority_rows = load_priority_rows(CSV_PATH)

    connection = sqlite3.connect(DB_PATH)
    connection.row_factory = sqlite3.Row

    print(f"Query: {query}")
    print(f"Database: {DB_PATH.resolve()}")
    print(f"Learner priority rows loaded: {len(priority_rows)}")
    print()

    print_priority_rows_for_query(
        connection=connection,
        query=query,
        priority_rows=priority_rows,
    )

    rows = connection.execute(
        """
        SELECT
          t.id,
          t.kanji,
          t.reading,
          t.meaning,
          t.is_common,
          t.common_score,
          MAX(sk.weight) AS keyword_weight,
          LENGTH(t.kanji) AS kanji_length
        FROM search_keywords sk
        JOIN terms t ON t.id = sk.term_id
        WHERE sk.keyword = ?
        GROUP BY t.id
        ORDER BY
          keyword_weight DESC,
          t.is_common DESC,
          t.common_score DESC,
          LENGTH(t.kanji) ASC
        LIMIT ?
        """,
        [query, limit],
    ).fetchall()

    print("Top database results:")
    if not rows:
        print("  No results")
        connection.close()
        return

    priority_lookup = {
        (row["kanji"], row["reading"], row["keyword"]): row
        for row in priority_rows
    }

    for index, row in enumerate(rows, start=1):
        priority_row = priority_lookup.get(
            (
                row["kanji"],
                row["reading"],
                query,
            )
        )

        if priority_row is None:
            priority_text = "priority=no"
        else:
            priority_text = (
                f"priority=yes csv={priority_row['weight']} "
                f"level={priority_row['level']}"
            )

        print(
            f"{index:02}. "
            f"{row['kanji']} [{row['reading']}] | "
            f"weight={row['keyword_weight']} | "
            f"common={row['is_common']} | "
            f"common_score={row['common_score']} | "
            f"len={row['kanji_length']} | "
            f"{priority_text} | "
            f"{row['meaning']}"
        )

    connection.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("query")
    parser.add_argument("--limit", type=int, default=25)

    args = parser.parse_args()

    query = args.query.lower().strip()

    if not query:
        print("Query cannot be empty")
        return

    debug_query(
        query=query,
        limit=args.limit,
    )


if __name__ == "__main__":
    main()