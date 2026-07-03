import sqlite3

connection = sqlite3.connect("assets/dictionary/dictionary.db")

rows = connection.execute(
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
    ["立つ", "たつ", "stand"],
).fetchall()

print(rows)

connection.close()