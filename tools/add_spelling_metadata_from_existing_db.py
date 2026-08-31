import argparse
import json
import re
import sqlite3
from pathlib import Path


KANJI_RE = re.compile(r"[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]")
HIRAGANA_RE = re.compile(r"[\u3041-\u3096]")
KATAKANA_RE = re.compile(r"[\u30A1-\u30FA]")


def create_spelling_schema(connection: sqlite3.Connection) -> None:
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


def is_katakana_reading(text: str) -> bool:
    if not KATAKANA_RE.search(text):
        return False
    # Mixed hiragana usually indicates an ordinary Japanese inflection rather
    # than an ateji/loanword spelling such as タバコ or イギリス.
    return not HIRAGANA_RE.search(text)


def primary_is_kanji_orthography(kanji: str, reading: str) -> bool:
    return kanji != reading and bool(KANJI_RE.search(kanji))


def choose_preferred(
    kanji: str,
    reading: str,
    surface_counts: dict[str, int],
) -> tuple[str, bool, str]:
    kanji = kanji.strip()
    reading = reading.strip()

    if not kanji:
        return reading, False, "reading-only"
    if not reading or kanji == reading:
        return kanji, False, "single-form"

    kanji_count = surface_counts.get(kanji, 0)
    reading_count = surface_counts.get(reading, 0)

    # Strong local corpus evidence is the safest inference available in an
    # already-built Gakuji DB. This correctly handles entries such as ここ and
    # ご while leaving ordinary kanji-first vocabulary alone.
    if reading_count >= 5 and reading_count >= max(kanji_count * 2, kanji_count + 5):
        return reading, True, "example-corpus"

    # Katakana readings paired with an allographic kanji spelling are normally
    # learner-facing in katakana (e.g. タバコ/煙草, イギリス/英吉利). This rule is
    # deliberately narrow; mixed kana/kanji native words do not trigger it.
    if primary_is_kanji_orthography(kanji, reading) and is_katakana_reading(reading):
        return reading, True, "katakana-orthography"

    return kanji, False, "existing-primary"


def load_surface_counts(connection: sqlite3.Connection) -> dict[str, dict[str, int]]:
    counts: dict[str, dict[str, int]] = {}
    for term_id, surface, count in connection.execute(
        """
        SELECT term_id, surface, COUNT(*)
        FROM example_tokens
        WHERE term_id IS NOT NULL AND TRIM(term_id) <> ''
        GROUP BY term_id, surface
        """
    ):
        term_id = str(term_id)
        surface = str(surface or "").strip()
        if not surface:
            continue
        counts.setdefault(term_id, {})[surface] = int(count)
    return counts


def load_high_weight_forms(
    connection: sqlite3.Connection,
) -> dict[str, list[tuple[str, int, int]]]:
    forms: dict[str, list[tuple[str, int, int]]] = {}
    # The current Gakuji converter gives written forms fixed high weights:
    # primary keb=5000, primary reb=4900, other keb=4800, other reb=4700.
    # Definition/search aliases are below this range.
    for rowid, term_id, keyword, weight in connection.execute(
        """
        SELECT rowid, term_id, keyword, weight
        FROM search_keywords
        WHERE weight IN (5000, 4900, 4800, 4700)
        ORDER BY rowid
        """
    ):
        term_id = str(term_id)
        keyword = str(keyword or "").strip()
        if not keyword:
            continue
        forms.setdefault(term_id, []).append((keyword, int(weight), int(rowid)))
    return forms


def build_rows(
    term_id: str,
    kanji: str,
    reading: str,
    weighted_forms: list[tuple[str, int, int]],
    surface_counts: dict[str, int],
) -> tuple[list[tuple], str]:
    preferred, usually_kana, reason = choose_preferred(
        kanji=kanji,
        reading=reading,
        surface_counts=surface_counts,
    )

    # Recover source order as closely as the existing DB allows. rowid follows
    # the insertion order used by the converter's ordered keyword dictionary.
    seen: set[str] = set()
    recovered: list[tuple[str, str, int]] = []

    def add(text: str, kind: str, rowid: int) -> None:
        text = text.strip()
        if not text or text in seen:
            return
        # A display form only needs one row even when the flattened source
        # makes the same surface look like both a k_ele and a reading fallback.
        seen.add(text)
        recovered.append((text, kind, rowid))

    for text, weight, rowid in weighted_forms:
        if text == reading or weight in (4900, 4700):
            kind = "kana"
        elif text == kanji and kanji == reading:
            kind = "kana"
        else:
            kind = "kanji"
        add(text, kind, rowid)

    # Always retain the current core fields even if the search index was built
    # by an older converter variant.
    add(
        kanji,
        "kana" if kanji == reading or not primary_is_kanji_orthography(kanji, reading) else "kanji",
        -2,
    )
    add(reading, "kana", -1)

    # Put kanji spellings first, then kana spellings, mirroring JMdict's k_ele /
    # r_ele structure while preserving recovered source order inside each kind.
    ordered = sorted(
        recovered,
        key=lambda value: (0 if value[1] == "kanji" else 1, value[2]),
    )

    rows: list[tuple] = []
    for position, (text, kind, _rowid) in enumerate(ordered):
        rows.append(
            (
                term_id,
                text,
                kind,
                position,
                1 if text == preferred else 0,
                1 if usually_kana else 0,
                None,
                None,
                None,
            )
        )

    if rows and not any(row[4] == 1 for row in rows):
        # The chosen form should always be present, but guard older/custom DBs.
        kind = "kana" if preferred == reading else "kanji"
        rows.append(
            (
                term_id,
                preferred,
                kind,
                len(rows),
                1,
                1 if usually_kana else 0,
                None,
                None,
                None,
            )
        )

    return rows, reason


def add_metadata(database_path: Path) -> None:
    if not database_path.exists():
        raise FileNotFoundError(f"Dictionary database not found: {database_path}")

    connection = sqlite3.connect(database_path)
    try:
        if connection.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='terms'"
        ).fetchone() is None:
            raise RuntimeError("The database does not contain the terms table.")
        if connection.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='search_keywords'"
        ).fetchone() is None:
            raise RuntimeError("The database does not contain search_keywords.")

        has_examples = connection.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='example_tokens'"
        ).fetchone() is not None

        surface_counts = load_surface_counts(connection) if has_examples else {}
        forms_by_term = load_high_weight_forms(connection)

        reason_counts: dict[str, int] = {}
        total_rows = 0
        total_terms = 0

        with connection:
            create_spelling_schema(connection)
            insert_cursor = connection.cursor()

            for term_id, kanji, reading in connection.execute(
                "SELECT id, kanji, reading FROM terms ORDER BY rowid"
            ):
                term_id = str(term_id)
                rows, reason = build_rows(
                    term_id=term_id,
                    kanji=str(kanji or ""),
                    reading=str(reading or ""),
                    weighted_forms=forms_by_term.get(term_id, []),
                    surface_counts=surface_counts.get(term_id, {}),
                )
                if not rows:
                    continue

                insert_cursor.executemany(
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
                total_terms += 1
                total_rows += len(rows)
                reason_counts[reason] = reason_counts.get(reason, 0) + 1

        connection.execute("ANALYZE term_spellings")
        connection.commit()

        print(f"Added metadata for {total_terms} terms")
        print(f"Stored {total_rows} written forms")
        for reason, count in sorted(reason_counts.items()):
            print(f"Preferred via {reason}: {count}")
        print(f"Updated {database_path}")
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Recover alternative spellings and conservative preferred-writing "
            "defaults from an already-built Gakuji dictionary database. Use "
            "add_jmdict_spelling_metadata.py instead when the original JMdict "
            "XML is available, because that preserves exact usage/restriction tags."
        )
    )
    parser.add_argument(
        "--database",
        default="assets/dictionary/dictionary.db",
        help="Existing Gakuji dictionary database to update in place",
    )
    args = parser.parse_args()
    add_metadata(Path(args.database))


if __name__ == "__main__":
    main()
