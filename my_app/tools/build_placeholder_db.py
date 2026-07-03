"""Build a small placeholder dictionary.db from assets/dictionary/dictionary_words.json.

Use this while the real dictionary.db (distributed via GitHub releases) is
unavailable. Mirrors the schema of tools/convert_jmdict_to_sqlite.py so the
app's DictionaryService queries work unchanged. Keeps only common entries plus
a slice of the rest so the file stays small for app tests.

Usage (from my_app/):
    python3 tools/build_placeholder_db.py
"""
import argparse
import json
import re
import sqlite3
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = APP_ROOT / "assets/dictionary/dictionary_words.json"
DEFAULT_OUTPUT = APP_ROOT / "assets/dictionary/dictionary.db"

STOP_WORDS = {
    "a", "an", "and", "as", "at", "be", "by", "for", "from", "in", "into",
    "is", "it", "of", "on", "or", "the", "to", "with",
}


def simplified_definition(value):
    value = value.lower().strip()
    if value.startswith("to "):
        value = value[3:].strip()
    value = re.sub(r"\([^)]*\)", "", value)
    value = re.sub(r"\s+", " ", value)
    return value.strip()


def definition_words(value):
    for word in re.split(r"[^a-zA-Z]+", simplified_definition(value)):
        word = word.lower().strip()
        if word and word not in STOP_WORDS:
            yield word


def sense_base_weight(index):
    return {0: 2600, 1: 1900, 2: 1500, 3: 1100}.get(index, 750)


def add_keyword(weights, keyword, weight):
    keyword = keyword.lower().strip()
    if keyword and weight > weights.get(keyword, 0):
        weights[keyword] = weight


def keyword_weights_for(entry):
    weights = {}
    add_keyword(weights, entry["kanji"], 5000)
    add_keyword(weights, entry["reading"], 4900)

    for index, definition in enumerate(entry.get("definitions", [])):
        base = sense_base_weight(index)
        lower = definition.lower().strip()
        simplified = simplified_definition(definition)
        if lower.startswith("to "):
            add_keyword(weights, lower, base + 450)
            if simplified:
                add_keyword(weights, simplified, base + 650)
            for word in definition_words(definition):
                add_keyword(weights, word, base + 450)
        else:
            add_keyword(weights, lower, base + 100)
            if simplified:
                add_keyword(weights, simplified, base + 50)
            for word in definition_words(definition):
                add_keyword(weights, word, base - 250)

    return weights


def build_placeholder_db(source_path, output_path, uncommon_stride):
    entries = json.loads(source_path.read_text(encoding="utf-8"))
    print(f"Loaded {len(entries)} entries from {source_path}")

    common = [e for e in entries if e.get("isCommon")]
    uncommon = [e for e in entries if not e.get("isCommon")]
    # All common words + a stride of uncommon words keeps search realistic
    # while staying far under the real database's size.
    selected = common + uncommon[::uncommon_stride]
    print(f"Keeping {len(selected)} entries ({len(common)} common)")

    if output_path.exists():
        output_path.unlink()

    connection = sqlite3.connect(output_path)
    cursor = connection.cursor()
    cursor.execute(
        """
        CREATE TABLE terms (
            id TEXT PRIMARY KEY,
            kanji TEXT NOT NULL,
            reading TEXT NOT NULL,
            meaning TEXT NOT NULL,
            part_of_speech TEXT NOT NULL,
            is_common INTEGER NOT NULL DEFAULT 0,
            common_score INTEGER NOT NULL DEFAULT 0
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE definitions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            term_id TEXT NOT NULL,
            definition TEXT NOT NULL,
            position INTEGER NOT NULL
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE search_keywords (
            keyword TEXT NOT NULL,
            term_id TEXT NOT NULL,
            weight INTEGER NOT NULL DEFAULT 0
        )
        """
    )
    cursor.execute("CREATE INDEX idx_terms_kanji ON terms(kanji)")
    cursor.execute("CREATE INDEX idx_terms_reading ON terms(reading)")
    cursor.execute("CREATE INDEX idx_terms_common ON terms(is_common, common_score)")
    cursor.execute("CREATE INDEX idx_definitions_term_id ON definitions(term_id)")
    cursor.execute("CREATE INDEX idx_search_keywords_keyword ON search_keywords(keyword)")
    cursor.execute("CREATE INDEX idx_search_keywords_term_id ON search_keywords(term_id)")
    cursor.execute("CREATE INDEX idx_search_keywords_keyword_weight ON search_keywords(keyword, weight)")

    for entry in selected:
        # JSON has no common_score; approximate so ORDER BY common_score
        # still prefers common words.
        common_score = 100 if entry.get("isCommon") else 0
        cursor.execute(
            "INSERT INTO terms VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                entry["id"],
                entry.get("kanji", ""),
                entry.get("reading", ""),
                entry.get("meaning", ""),
                entry.get("partOfSpeech", "word"),
                1 if entry.get("isCommon") else 0,
                common_score,
            ),
        )
        for position, definition in enumerate(entry.get("definitions", [])):
            cursor.execute(
                "INSERT INTO definitions (term_id, definition, position) VALUES (?, ?, ?)",
                (entry["id"], definition, position),
            )
        for keyword, weight in keyword_weights_for(entry).items():
            cursor.execute(
                "INSERT INTO search_keywords VALUES (?, ?, ?)",
                (keyword, entry["id"], weight),
            )

    connection.commit()
    connection.execute("VACUUM")
    connection.close()
    size_mb = output_path.stat().st_size / 1024 / 1024
    print(f"Wrote {output_path} ({size_mb:.1f} MB)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default=str(DEFAULT_SOURCE))
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    parser.add_argument(
        "--uncommon-stride",
        type=int,
        default=40,
        help="Keep every Nth uncommon entry (lower = bigger database)",
    )

    args = parser.parse_args()

    build_placeholder_db(
        source_path=Path(args.input),
        output_path=Path(args.output),
        uncommon_stride=args.uncommon_stride,
    )


if __name__ == "__main__":
    main()
