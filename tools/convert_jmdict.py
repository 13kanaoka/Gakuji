import argparse
import gzip
import json
from pathlib import Path
import xml.etree.ElementTree as ET


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
    )


def convert_entry(entry):
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

    kanji = kebs[0] if kebs else (rebs[0] if rebs else "")
    reading = rebs[0] if rebs else kanji

    definitions = []
    part_of_speech_tags = []
    related_terms = []

    for sense in entry.findall("sense"):
        definitions.extend(
            text_of(gloss)
            for gloss in sense.findall("gloss")
            if text_of(gloss)
        )

        part_of_speech_tags.extend(
            text_of(pos)
            for pos in sense.findall("pos")
            if text_of(pos)
        )

        related_terms.extend(
            text_of(xref)
            for xref in sense.findall("xref")
            if text_of(xref)
        )

    definitions = unique(definitions)
    part_of_speech_tags = unique(part_of_speech_tags)
    related_terms = unique(related_terms)

    if not ent_seq or not kanji or not reading or not definitions:
        return None

    meaning = " / ".join(definitions[:3])

    return {
        "id": f"jmdict_{ent_seq}",
        "kanji": kanji,
        "reading": reading,
        "meaning": meaning,
        "partOfSpeech": part_of_speech_tags[0] if part_of_speech_tags else "word",
        "definitions": definitions,
        "isCommon": any(is_common_priority(priority) for priority in priorities),
        "relatedTerms": related_terms,
        "kanjiMeaning": meaning
    }


def open_jmdict(path):
    if path.suffix == ".gz":
        return gzip.open(path, "rt", encoding="utf-8")
    return path.open("r", encoding="utf-8")


def convert_jmdict(input_path, output_path, limit=None):
    terms = []

    with open_jmdict(input_path) as source:
        for event, element in ET.iterparse(source, events=("end",)):
            if element.tag != "entry":
                continue

            term = convert_entry(element)

            if term is not None:
                terms.append(term)

            element.clear()

            if limit is not None and len(terms) >= limit:
                break

    output_path.parent.mkdir(parents=True, exist_ok=True)

    with output_path.open("w", encoding="utf-8") as destination:
        json.dump(terms, destination, ensure_ascii=False, indent=2)

    print(f"Converted {len(terms)} entries")
    print(f"Wrote {output_path}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--limit", type=int)

    args = parser.parse_args()

    convert_jmdict(
        input_path=Path(args.input),
        output_path=Path(args.output),
        limit=args.limit,
    )


if __name__ == "__main__":
    main()