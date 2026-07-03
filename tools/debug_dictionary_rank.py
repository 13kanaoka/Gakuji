import sqlite3
from pathlib import Path


DATABASE_PATH = Path("assets/dictionary/dictionary.db")
QUERY = "play"


def main():
    connection = sqlite3.connect(DATABASE_PATH)
    connection.row_factory = sqlite3.Row

    rows = connection.execute(
        """
        SELECT
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
        LIMIT 30
        """,
        [QUERY],
    ).fetchall()

    for index, row in enumerate(rows, start=1):
        print(
            f"{index:02}. "
            f"{row['kanji']} [{row['reading']}] | "
            f"weight={row['keyword_weight']} | "
            f"common={row['is_common']} | "
            f"common_score={row['common_score']} | "
            f"len={row['kanji_length']} | "
            f"{row['meaning']}"
        )

    connection.close()


if __name__ == "__main__":
    main()