import argparse
import json
import re
import sqlite3
from pathlib import Path
import xml.etree.ElementTree as ET


DEFAULT_INPUT_PATH = Path("tools/source/kanjivg-20250816-main")
DEFAULT_DATABASE_PATH = Path("assets/dictionary/dictionary.db")
BATCH_SIZE = 500

STANDARD_FILE_RE = re.compile(r"^(?P<codepoint>[0-9a-fA-F]{5})\.svg$")
STROKE_ID_RE = re.compile(r"-s(?P<number>\d+)$")
KVG_NAMESPACE = "http://kanjivg.tagaini.net"


def table_exists(connection: sqlite3.Connection, table_name: str) -> bool:
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


def create_schema(connection: sqlite3.Connection) -> None:
    cursor = connection.cursor()

    cursor.execute("DROP TABLE IF EXISTS kanji_strokes")

    cursor.execute(
        """
        CREATE TABLE kanji_strokes (
            character TEXT PRIMARY KEY,
            codepoint TEXT NOT NULL,
            view_box TEXT NOT NULL,
            stroke_count INTEGER NOT NULL,
            strokes_json TEXT NOT NULL
        )
        """
    )

    cursor.execute(
        """
        CREATE INDEX idx_kanji_strokes_codepoint
        ON kanji_strokes(codepoint)
        """
    )

    connection.commit()


def find_standard_svg_files(input_path: Path) -> list[Path]:
    if not input_path.exists():
        raise FileNotFoundError(f"KanjiVG input folder not found: {input_path}")

    if input_path.is_file():
        if STANDARD_FILE_RE.fullmatch(input_path.name):
            return [input_path]

        raise ValueError(
            "KanjiVG input must be the extracted release folder, the kanji "
            "folder, or one standard five-digit SVG file."
        )

    files = [
        path
        for path in input_path.rglob("*.svg")
        if STANDARD_FILE_RE.fullmatch(path.name)
    ]

    # The main archive should contain one standard file per character. Sorting
    # by filename makes imports deterministic across operating systems.
    return sorted(files, key=lambda path: path.name.lower())


def attribute_by_local_name(element: ET.Element, local_name: str) -> str:
    direct_value = element.get(local_name)

    if direct_value:
        return direct_value.strip()

    for key, value in element.attrib.items():
        if key.rsplit("}", 1)[-1] == local_name and value:
            return value.strip()

    return ""


def parse_svg(svg_path: Path) -> tuple[str, str, int, str] | None:
    file_match = STANDARD_FILE_RE.fullmatch(svg_path.name)

    if file_match is None:
        return None

    codepoint = file_match.group("codepoint").lower()

    try:
        character = chr(int(codepoint, 16))
    except (ValueError, OverflowError):
        return None

    root = ET.parse(svg_path).getroot()
    view_box = root.get("viewBox", "0 0 109 109").strip() or "0 0 109 109"

    strokes_by_number: dict[int, dict[str, object]] = {}

    for element in root.iter():
        if element.tag.rsplit("}", 1)[-1] != "path":
            continue

        element_id = attribute_by_local_name(element, "id")
        id_match = STROKE_ID_RE.search(element_id)

        if id_match is None:
            continue

        path_data = attribute_by_local_name(element, "d")

        if not path_data:
            continue

        stroke_number = int(id_match.group("number"))
        stroke_type = element.get(f"{{{KVG_NAMESPACE}}}type") or attribute_by_local_name(
            element,
            "type",
        )

        strokes_by_number[stroke_number] = {
            "number": stroke_number,
            "path": path_data,
            "type": stroke_type,
        }

    if not strokes_by_number:
        return None

    strokes = [
        strokes_by_number[number]
        for number in sorted(strokes_by_number)
    ]

    strokes_json = json.dumps(
        strokes,
        ensure_ascii=False,
        separators=(",", ":"),
    )

    return character, codepoint, len(strokes), view_box, strokes_json


def insert_batch(
    connection: sqlite3.Connection,
    rows: list[tuple[str, str, int, str, str]],
) -> None:
    connection.executemany(
        """
        INSERT INTO kanji_strokes (
            character,
            codepoint,
            stroke_count,
            view_box,
            strokes_json
        )
        VALUES (?, ?, ?, ?, ?)
        """,
        rows,
    )


def import_kanjivg(
    input_path: Path,
    database_path: Path,
    limit: int | None = None,
) -> None:
    if not database_path.exists():
        raise FileNotFoundError(
            "Dictionary database not found. Build the dictionary database "
            f"first: {database_path}"
        )

    svg_files = find_standard_svg_files(input_path)

    if not svg_files:
        raise RuntimeError(
            "No standard KanjiVG SVG files were found. Expected files such "
            "as 04e00.svg inside the extracted release folder."
        )

    if limit is not None:
        svg_files = svg_files[: max(0, limit)]

    connection = sqlite3.connect(database_path)

    try:
        if not table_exists(connection, "kanji_entries"):
            raise RuntimeError(
                "The database does not contain kanji_entries. Run "
                "convert_kanjidic_to_sqlite.py before importing KanjiVG."
            )

        create_schema(connection)

        imported_count = 0
        skipped_count = 0
        batch: list[tuple[str, str, int, str, str]] = []

        for svg_path in svg_files:
            try:
                parsed = parse_svg(svg_path)
            except ET.ParseError as error:
                print(f"Skipping malformed SVG {svg_path}: {error}")
                skipped_count += 1
                continue

            if parsed is None:
                skipped_count += 1
                continue

            character, codepoint, stroke_count, view_box, strokes_json = parsed
            batch.append(
                (
                    character,
                    codepoint,
                    stroke_count,
                    view_box,
                    strokes_json,
                )
            )

            if len(batch) >= BATCH_SIZE:
                insert_batch(connection, batch)
                imported_count += len(batch)
                batch.clear()

        if batch:
            insert_batch(connection, batch)
            imported_count += len(batch)

        connection.commit()

        linked_count = connection.execute(
            """
            SELECT COUNT(*)
            FROM kanji_strokes AS strokes
            INNER JOIN kanji_entries AS entries
                ON entries.character = strokes.character
            """
        ).fetchone()[0]

        total_strokes = connection.execute(
            "SELECT COALESCE(SUM(stroke_count), 0) FROM kanji_strokes"
        ).fetchone()[0]

        print(f"KanjiVG files found: {len(svg_files):,}")
        print(f"Kanji stroke records imported: {imported_count:,}")
        print(f"Records matching KANJIDIC entries: {linked_count:,}")
        print(f"Individual stroke paths imported: {total_strokes:,}")
        print(f"Files skipped: {skipped_count:,}")
        print(f"Database updated: {database_path}")
    finally:
        connection.close()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Import standard KanjiVG stroke paths into Gakuji's SQLite "
            "dictionary database."
        )
    )
    parser.add_argument(
        "--input",
        type=Path,
        default=DEFAULT_INPUT_PATH,
        help=(
            "Extracted KanjiVG main-release folder, its kanji folder, or one "
            "standard five-digit SVG file."
        ),
    )
    parser.add_argument(
        "--database",
        type=Path,
        default=DEFAULT_DATABASE_PATH,
        help="Existing Gakuji dictionary SQLite database.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Optional development limit for testing a small number of SVGs.",
    )
    return parser


def main() -> None:
    args = build_parser().parse_args()

    import_kanjivg(
        input_path=args.input,
        database_path=args.database,
        limit=args.limit,
    )


if __name__ == "__main__":
    main()
