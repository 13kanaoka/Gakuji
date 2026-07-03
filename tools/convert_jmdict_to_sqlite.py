import argparse
import csv
import gzip
import re
import sqlite3
from pathlib import Path
import xml.etree.ElementTree as ET


STOP_WORDS = {
    "a",
    "an",
    "and",
    "as",
    "at",
    "be",
    "by",
    "for",
    "from",
    "in",
    "into",
    "is",
    "it",
    "of",
    "on",
    "or",
    "the",
    "to",
    "with",
}


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


def add_keyword(keyword_weights, keyword, weight):
    keyword = keyword.lower().strip()

    if not keyword:
        return

    current_weight = keyword_weights.get(keyword, 0)

    if weight > current_weight:
        keyword_weights[keyword] = weight


def load_learner_priority_keywords(path):
    priority_keywords = {}

    if path is None or not path.exists():
        return priority_keywords

    with path.open("r", encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)

        for row in reader:
            kanji = (row.get("kanji") or "").strip()
            reading = (row.get("reading") or "").strip()
            keyword = (row.get("english_keyword") or "").lower().strip()
            weight_text = (row.get("weight") or "4200").strip()

            if not kanji or not reading or not keyword:
                continue

            try:
                weight = int(weight_text)
            except ValueError:
                weight = 4200

            key = (kanji, reading)
            priority_keywords.setdefault(key, {})

            current_weight = priority_keywords[key].get(keyword, 0)

            if weight > current_weight:
                priority_keywords[key][keyword] = weight

    return priority_keywords


def add_learner_priority_keywords(
    keyword_weights,
    kanji,
    reading,
    learner_priority_keywords,
):
    priority_keywords = learner_priority_keywords.get((kanji, reading))

    if priority_keywords is None:
        return

    for keyword, weight in priority_keywords.items():
        add_keyword(keyword_weights, keyword, weight)


def is_common_priority(priority):
    return (
        priority.startswith("news1")
        or priority.startswith("ichi1")
        or priority.startswith("spec1")
        or priority.startswith("gai1")
        or priority.startswith("nf01")
        or priority.startswith("nf02")
        or priority.startswith("nf03")
        or priority.startswith("nf04")
        or priority.startswith("nf05")
        or priority.startswith("nf06")
        or priority.startswith("nf07")
        or priority.startswith("nf08")
        or priority.startswith("nf09")
        or priority.startswith("nf10")
    )


def priority_score(priorities):
    score = 0

    for priority in priorities:
        if priority.startswith("news1"):
            score += 140
        elif priority.startswith("ichi1"):
            score += 140
        elif priority.startswith("spec1"):
            score += 120
        elif priority.startswith("gai1"):
            score += 90
        elif priority.startswith("nf"):
            number = re.sub(r"[^0-9]", "", priority)

            if number:
                nf_value = int(number)
                score += max(0, 100 - nf_value)

    return score


def simplified_definition(value):
    value = value.lower().strip()

    if value.startswith("to "):
        value = value[3:].strip()

    value = re.sub(r"\([^)]*\)", "", value)
    value = re.sub(r"\s+", " ", value)

    return value.strip()


def definition_words(value):
    simplified = simplified_definition(value)

    for word in re.split(r"[^a-zA-Z]+", simplified):
        word = word.lower().strip()

        if not word:
            continue

        if word in STOP_WORDS:
            continue

        yield word


def is_to_definition(value):
    return value.lower().strip().startswith("to ")


def is_short_definition(value):
    words = list(definition_words(value))
    return 1 <= len(words) <= 2


def sense_base_weight(sense_index):
    if sense_index == 0:
        return 2600

    if sense_index == 1:
        return 1900

    if sense_index == 2:
        return 1500

    if sense_index == 3:
        return 1100

    return 750


def add_definition_keywords(keyword_weights, definition, base_weight):
    definition_lower = definition.lower().strip()
    simplified = simplified_definition(definition)

    if not definition_lower:
        return

    if is_to_definition(definition):
        add_keyword(keyword_weights, definition_lower, base_weight + 450)

        if simplified:
            add_keyword(keyword_weights, simplified, base_weight + 650)

        for word in definition_words(definition):
            add_keyword(keyword_weights, word, base_weight + 450)

        return

    if is_short_definition(definition):
        add_keyword(keyword_weights, definition_lower, base_weight + 150)

        if simplified:
            add_keyword(keyword_weights, simplified, base_weight + 100)

        for word in definition_words(definition):
            add_keyword(keyword_weights, word, base_weight + 50)

        return

    add_keyword(keyword_weights, definition_lower, base_weight + 100)

    if simplified:
        add_keyword(keyword_weights, simplified, base_weight + 50)

    for word in definition_words(definition):
        add_keyword(keyword_weights, word, base_weight - 250)


def collect_senses(entry):
    senses = []

    for sense_index, sense in enumerate(entry.findall("sense")):
        definitions = [
            text_of(gloss)
            for gloss in sense.findall("gloss")
            if text_of(gloss)
        ]

        part_of_speech_tags = [
            text_of(pos)
            for pos in sense.findall("pos")
            if text_of(pos)
        ]

        related_terms = [
            text_of(xref)
            for xref in sense.findall("xref")
            if text_of(xref)
        ]

        if definitions:
            senses.append(
                {
                    "index": sense_index,
                    "definitions": definitions,
                    "part_of_speech_tags": part_of_speech_tags,
                    "related_terms": related_terms,
                }
            )

    return senses


def convert_entry(entry, learner_priority_keywords):
    ent_seq = text_of(entry.find("ent_seq"))

    kebs = [
        text_of(k_ele.find("keb"))
        for k_ele in entry.findall("k_ele")
        if text_of(k_ele.find("keb"))
    ]

    rebs = [
        text_of(r_ele.find("reb"))
        for r_ele in entry.findall("r_ele")
        if text_of(r_ele.find("reb"))
    ]

    priorities = []

    for k_ele in entry.findall("k_ele"):
        priorities.extend(
            text_of(priority)
            for priority in k_ele.findall("ke_pri")
            if text_of(priority)
        )

    for r_ele in entry.findall("r_ele"):
        priorities.extend(
            text_of(priority)
            for priority in r_ele.findall("re_pri")
            if text_of(priority)
        )

    senses = collect_senses(entry)

    definitions = []
    part_of_speech_tags = []
    related_terms = []

    for sense in senses:
        definitions.extend(sense["definitions"])
        part_of_speech_tags.extend(sense["part_of_speech_tags"])
        related_terms.extend(sense["related_terms"])

    definitions = unique(definitions)
    part_of_speech_tags = unique(part_of_speech_tags)
    related_terms = unique(related_terms)

    kanji = kebs[0] if kebs else (rebs[0] if rebs else "")
    reading = rebs[0] if rebs else kanji

    if not ent_seq or not kanji or not reading or not definitions:
        return None

    term_id = f"jmdict_{ent_seq}"
    meaning = " / ".join(definitions[:3])
    part_of_speech = part_of_speech_tags[0] if part_of_speech_tags else "word"
    is_common = any(is_common_priority(priority) for priority in priorities)
    common_score = priority_score(priorities)

    keyword_weights = {}

    add_keyword(keyword_weights, kanji, 5000)
    add_keyword(keyword_weights, reading, 4900)

    for keb in kebs:
        add_keyword(keyword_weights, keb, 4800)

    for reb in rebs:
        add_keyword(keyword_weights, reb, 4700)

    for sense in senses:
        base_weight = sense_base_weight(sense["index"])

        for definition in sense["definitions"]:
            add_definition_keywords(
                keyword_weights=keyword_weights,
                definition=definition,
                base_weight=base_weight,
            )

    add_learner_priority_keywords(
        keyword_weights=keyword_weights,
        kanji=kanji,
        reading=reading,
        learner_priority_keywords=learner_priority_keywords,
    )

    return {
        "id": term_id,
        "kanji": kanji,
        "reading": reading,
        "meaning": meaning,
        "part_of_speech": part_of_speech,
        "definitions": definitions,
        "related_terms": related_terms,
        "is_common": 1 if is_common else 0,
        "common_score": common_score,
        "keyword_weights": keyword_weights,
    }


def open_jmdict(path):
    if path.suffix == ".gz":
        return gzip.open(path, "rt", encoding="utf-8")

    return path.open("r", encoding="utf-8")


def create_schema(connection):
    cursor = connection.cursor()

    cursor.execute("DROP TABLE IF EXISTS search_keywords")
    cursor.execute("DROP TABLE IF EXISTS definitions")
    cursor.execute("DROP TABLE IF EXISTS terms")

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

    connection.commit()


def insert_term(connection, term):
    cursor = connection.cursor()

    cursor.execute(
        """
        INSERT INTO terms (
            id,
            kanji,
            reading,
            meaning,
            part_of_speech,
            is_common,
            common_score
        )
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (
            term["id"],
            term["kanji"],
            term["reading"],
            term["meaning"],
            term["part_of_speech"],
            term["is_common"],
            term["common_score"],
        ),
    )

    for index, definition in enumerate(term["definitions"]):
        cursor.execute(
            """
            INSERT INTO definitions (
                term_id,
                definition,
                position
            )
            VALUES (?, ?, ?)
            """,
            (
                term["id"],
                definition,
                index,
            ),
        )

    for keyword, weight in term["keyword_weights"].items():
        cursor.execute(
            """
            INSERT INTO search_keywords (
                keyword,
                term_id,
                weight
            )
            VALUES (?, ?, ?)
            """,
            (
                keyword,
                term["id"],
                weight,
            ),
        )


def convert_jmdict_to_sqlite(
    input_path,
    output_path,
    learner_priority_path,
    limit=None,
):
    output_path.parent.mkdir(parents=True, exist_ok=True)

    if output_path.exists():
        output_path.unlink()

    learner_priority_keywords = load_learner_priority_keywords(
        learner_priority_path,
    )

    learner_priority_count = sum(
        len(keywords)
        for keywords in learner_priority_keywords.values()
    )

    print(f"Loaded {learner_priority_count} learner priority keyword mappings")

    connection = sqlite3.connect(output_path)
    create_schema(connection)

    converted_count = 0

    with open_jmdict(input_path) as source:
        for event, element in ET.iterparse(source, events=("end",)):
            if element.tag != "entry":
                continue

            term = convert_entry(
                entry=element,
                learner_priority_keywords=learner_priority_keywords,
            )

            if term is not None:
                insert_term(connection, term)
                converted_count += 1

                if converted_count % 1000 == 0:
                    connection.commit()
                    print(f"Converted {converted_count} entries...")

            element.clear()

            if limit is not None and converted_count >= limit:
                break

    connection.commit()
    connection.execute("VACUUM")
    connection.close()

    print(f"Converted {converted_count} entries")
    print(f"Wrote {output_path}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument(
        "--learner-priority",
        default="tools/source/learner_priority_words.csv",
    )
    parser.add_argument("--limit", type=int)

    args = parser.parse_args()

    convert_jmdict_to_sqlite(
        input_path=Path(args.input),
        output_path=Path(args.output),
        learner_priority_path=Path(args.learner_priority),
        limit=args.limit,
    )


if __name__ == "__main__":
    main()