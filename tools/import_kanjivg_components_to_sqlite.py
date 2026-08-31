from __future__ import annotations

import argparse
import json
import re
import shutil
import sqlite3
import tempfile
import urllib.request
import zipfile
from pathlib import Path
import xml.etree.ElementTree as ET


DEFAULT_RELEASE = "20250816"
DEFAULT_INPUT_PATH = Path(f"tools/source/kanjivg-{DEFAULT_RELEASE}-main")
DEFAULT_ANIMCJK_INPUT_PATH = Path("tools/source/animcjk-dictionaryJa.txt")
DEFAULT_DATABASE_PATH = Path("assets/dictionary/dictionary.db")
ANIMCJK_DICTIONARY_URL = (
    "https://raw.githubusercontent.com/parsimonhi/animCJK/"
    "refs/heads/master/dictionaryJa.txt"
)
ANIMCJK_SOURCE_VERSION = "master"
STANDARD_FILE_RE = re.compile(r"^(?P<codepoint>[0-9a-fA-F]{5})\.svg$")
BATCH_SIZE = 500
IDS_ARITY = {
    "⿰": 2,
    "⿱": 2,
    "⿲": 3,
    "⿳": 3,
    "⿴": 2,
    "⿵": 2,
    "⿶": 2,
    "⿷": 2,
    "⿸": 2,
    "⿹": 2,
    "⿺": 2,
    "⿻": 2,
}
IDS_IGNORED_TOKENS = {":", ".", "·"}
IDS_MISSING_MARKERS = {"?", "？"}


def attribute_by_local_name(element: ET.Element, local_name: str) -> str:
    direct_value = element.get(local_name)
    if direct_value:
        return direct_value.strip()

    for key, value in element.attrib.items():
        if key.rsplit("}", 1)[-1] == local_name and value:
            return value.strip()

    return ""


def find_standard_svg_files(input_path: Path) -> list[Path]:
    if not input_path.exists():
        return []

    if input_path.is_file():
        return [input_path] if STANDARD_FILE_RE.fullmatch(input_path.name) else []

    files = [
        path
        for path in input_path.rglob("*.svg")
        if STANDARD_FILE_RE.fullmatch(path.name)
    ]
    return sorted(files, key=lambda path: path.name.lower())


def _group_children(element: ET.Element) -> list[ET.Element]:
    return [
        child
        for child in list(element)
        if child.tag.rsplit("}", 1)[-1] == "g"
    ]


def _component_nodes(
    group: ET.Element,
    *,
    parent_element: str,
) -> list[dict[str, object]]:
    nodes: list[dict[str, object]] = []

    for child in _group_children(group):
        element = attribute_by_local_name(child, "element")
        original = attribute_by_local_name(child, "original")
        position = attribute_by_local_name(child, "position")
        radical = attribute_by_local_name(child, "radical")

        # KanjiVG sometimes uses structural wrapper groups with no semantic
        # element, and occasionally repeats the parent's element for part
        # bookkeeping. Lift those wrappers so the stored tree represents the
        # learner-visible component hierarchy instead of SVG internals.
        if not element or (element == parent_element and not original):
            nodes.extend(
                _component_nodes(
                    child,
                    parent_element=parent_element,
                )
            )
            continue

        children = _component_nodes(
            child,
            parent_element=element,
        )
        node: dict[str, object] = {"element": element}

        if original and original != element:
            node["original"] = original
        if position:
            node["position"] = position
        if radical:
            node["radical"] = radical
        if children:
            node["children"] = children

        nodes.append(node)

    return nodes


def parse_component_tree(svg_path: Path) -> tuple[str, str] | None:
    match = STANDARD_FILE_RE.fullmatch(svg_path.name)
    if match is None:
        return None

    codepoint = match.group("codepoint").lower()
    try:
        character = chr(int(codepoint, 16))
    except (ValueError, OverflowError):
        return None

    root = ET.parse(svg_path).getroot()
    root_group: ET.Element | None = None

    for group in root.iter():
        if group.tag.rsplit("}", 1)[-1] != "g":
            continue
        if attribute_by_local_name(group, "element") == character:
            root_group = group
            break

    if root_group is None:
        return None

    tree = _component_nodes(root_group, parent_element=character)
    if not tree:
        return None

    tree_json = json.dumps(
        tree,
        ensure_ascii=False,
        separators=(",", ":"),
    )
    return character, tree_json


def _ids_tokens(decomposition: str) -> list[str]:
    return [
        token
        for token in decomposition
        if not token.isspace()
        and not token.isdigit()
        and token not in IDS_IGNORED_TOKENS
    ]


def _parse_ids_expression(
    tokens: list[str],
    index: int,
) -> tuple[list[str], int]:
    if index >= len(tokens):
        return [], index

    token = tokens[index]
    index += 1

    arity = IDS_ARITY.get(token)
    if arity is None:
        if token in IDS_MISSING_MARKERS:
            return [], index
        return [token], index

    components: list[str] = []
    for _ in range(arity):
        child_components, index = _parse_ids_expression(tokens, index)
        components.extend(child_components)

    return components, index


def parse_animcjk_components(decomposition: str) -> list[str]:
    tokens = _ids_tokens(decomposition)
    if not tokens:
        return []

    components: list[str] = []
    index = 0
    while index < len(tokens):
        parsed_components, next_index = _parse_ids_expression(tokens, index)
        if next_index <= index:
            break
        components.extend(parsed_components)
        index = next_index

    return components


def load_animcjk_decompositions(input_path: Path) -> dict[str, str]:
    decompositions: dict[str, str] = {}

    with input_path.open("r", encoding="utf-8") as source:
        for line_number, line in enumerate(source, start=1):
            stripped = line.strip()
            if not stripped:
                continue

            try:
                record = json.loads(stripped)
            except json.JSONDecodeError as error:
                raise RuntimeError(
                    f"Invalid AnimCJK JSON on line {line_number}: {error}"
                ) from error

            character = str(record.get("character") or "").strip()
            decomposition = str(record.get("decomposition") or "").strip()
            if character and decomposition:
                decompositions[character] = decomposition

    return decompositions


def _kanjivg_children_for_component(
    component: str,
    kanjivg_trees: dict[str, str],
) -> list[dict[str, object]]:
    tree_json = kanjivg_trees.get(component)
    if not tree_json:
        return []

    try:
        decoded = json.loads(tree_json)
    except json.JSONDecodeError:
        return []

    if not isinstance(decoded, list):
        return []

    children = [node for node in decoded if isinstance(node, dict)]
    if (
        len(children) == 1
        and str(children[0].get("element") or "") == component
    ):
        return []

    return children


def build_animcjk_fallback_tree(
    character: str,
    decomposition: str,
    *,
    kanjivg_trees: dict[str, str],
) -> str | None:
    components = parse_animcjk_components(decomposition)
    nodes: list[dict[str, object]] = []

    for component in components:
        if not component or component == character:
            continue

        node: dict[str, object] = {"element": component}
        children = _kanjivg_children_for_component(component, kanjivg_trees)
        if children:
            node["children"] = children
        nodes.append(node)

    if not nodes:
        return None

    return json.dumps(
        nodes,
        ensure_ascii=False,
        separators=(",", ":"),
    )


def _download_release(destination: Path, release: str) -> Path:
    url = (
        "https://github.com/KanjiVG/kanjivg/archive/refs/tags/"
        f"r{release}.zip"
    )
    destination.parent.mkdir(parents=True, exist_ok=True)

    request = urllib.request.Request(
        url,
        headers={"User-Agent": "Gakuji dictionary build tool"},
    )
    print(f"Downloading KanjiVG {release}...")

    with urllib.request.urlopen(request, timeout=120) as response:
        with destination.open("wb") as output:
            shutil.copyfileobj(response, output)

    return destination


def _download_animcjk_dictionary(destination: Path) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(
        ANIMCJK_DICTIONARY_URL,
        headers={"User-Agent": "Gakuji dictionary build tool"},
    )
    print("Downloading AnimCJK Japanese decomposition dictionary...")

    with urllib.request.urlopen(request, timeout=120) as response:
        with destination.open("wb") as output:
            shutil.copyfileobj(response, output)

    return destination


def resolve_input_path(
    requested_input: Path,
    *,
    release: str,
    download_if_missing: bool,
) -> tuple[Path, tempfile.TemporaryDirectory[str] | None]:
    if find_standard_svg_files(requested_input):
        return requested_input, None

    if not download_if_missing:
        raise FileNotFoundError(
            f"KanjiVG SVG source not found at {requested_input}."
        )

    temp_directory = tempfile.TemporaryDirectory(prefix="gakuji_kanjivg_")
    temp_root = Path(temp_directory.name)
    archive_path = temp_root / f"kanjivg-{release}-main.zip"
    _download_release(archive_path, release)

    with zipfile.ZipFile(archive_path) as archive:
        archive.extractall(temp_root)

    if not find_standard_svg_files(temp_root):
        temp_directory.cleanup()
        raise RuntimeError("Downloaded KanjiVG archive contained no standard SVG files.")

    return temp_root, temp_directory


def resolve_animcjk_input_path(
    requested_input: Path,
    *,
    download_if_missing: bool,
) -> tuple[Path, tempfile.TemporaryDirectory[str] | None]:
    if requested_input.is_file():
        return requested_input, None

    if not download_if_missing:
        raise FileNotFoundError(
            f"AnimCJK Japanese dictionary not found at {requested_input}."
        )

    temp_directory = tempfile.TemporaryDirectory(prefix="gakuji_animcjk_")
    temp_root = Path(temp_directory.name)
    dictionary_path = temp_root / "dictionaryJa.txt"
    _download_animcjk_dictionary(dictionary_path)
    return dictionary_path, temp_directory


def create_schema(connection: sqlite3.Connection) -> None:
    connection.execute("DROP TABLE IF EXISTS kanji_component_trees")
    connection.execute(
        """
        CREATE TABLE kanji_component_trees (
            character TEXT PRIMARY KEY,
            tree_json TEXT NOT NULL,
            source_version TEXT NOT NULL
        )
        """
    )


def import_components(
    input_path: Path,
    database_path: Path,
    *,
    source_version: str,
    animcjk_input_path: Path = DEFAULT_ANIMCJK_INPUT_PATH,
    limit: int | None = None,
    download_if_missing: bool = True,
) -> None:
    if not database_path.exists():
        raise FileNotFoundError(f"Dictionary database not found: {database_path}")

    resolved_input, temp_directory = resolve_input_path(
        input_path,
        release=source_version,
        download_if_missing=download_if_missing,
    )
    resolved_animcjk_input, animcjk_temp_directory = resolve_animcjk_input_path(
        animcjk_input_path,
        download_if_missing=download_if_missing,
    )

    try:
        svg_files = find_standard_svg_files(resolved_input)
        if limit is not None:
            svg_files = svg_files[: max(0, limit)]

        animcjk_decompositions = load_animcjk_decompositions(
            resolved_animcjk_input
        )
        connection = sqlite3.connect(database_path)
        try:
            if connection.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name='kanji_entries'"
            ).fetchone() is None:
                raise RuntimeError(
                    "The database does not contain kanji_entries. Build the dictionary first."
                )

            create_schema(connection)
            batch: list[tuple[str, str, str]] = []
            kanjivg_trees: dict[str, str] = {}
            scanned_characters: set[str] = set()
            kanjivg_imported_count = 0
            animcjk_fallback_count = 0
            skipped_count = 0

            for svg_path in svg_files:
                match = STANDARD_FILE_RE.fullmatch(svg_path.name)
                if match is not None:
                    try:
                        scanned_characters.add(chr(int(match.group("codepoint"), 16)))
                    except (ValueError, OverflowError):
                        pass

                try:
                    parsed = parse_component_tree(svg_path)
                except ET.ParseError as error:
                    print(f"Skipping malformed SVG {svg_path}: {error}")
                    skipped_count += 1
                    continue

                if parsed is None:
                    skipped_count += 1
                    continue

                character, tree_json = parsed
                kanjivg_trees[character] = tree_json
                batch.append((character, tree_json, source_version))

                if len(batch) >= BATCH_SIZE:
                    connection.executemany(
                        """
                        INSERT OR REPLACE INTO kanji_component_trees
                            (character, tree_json, source_version)
                        VALUES (?, ?, ?)
                        """,
                        batch,
                    )
                    kanjivg_imported_count += len(batch)
                    batch.clear()

            if batch:
                connection.executemany(
                    """
                    INSERT OR REPLACE INTO kanji_component_trees
                        (character, tree_json, source_version)
                    VALUES (?, ?, ?)
                    """,
                    batch,
                )
                kanjivg_imported_count += len(batch)
                batch.clear()

            if limit is None:
                fallback_candidates = [
                    row[0]
                    for row in connection.execute(
                        "SELECT character FROM kanji_entries"
                    ).fetchall()
                    if row and row[0]
                ]
            else:
                fallback_candidates = sorted(scanned_characters)

            animcjk_source_version = f"animCJK:{ANIMCJK_SOURCE_VERSION}"
            for character in fallback_candidates:
                if character in kanjivg_trees:
                    continue

                decomposition = animcjk_decompositions.get(character)
                if not decomposition:
                    continue

                tree_json = build_animcjk_fallback_tree(
                    character,
                    decomposition,
                    kanjivg_trees=kanjivg_trees,
                )
                if tree_json is None:
                    continue

                batch.append((character, tree_json, animcjk_source_version))

                if len(batch) >= BATCH_SIZE:
                    connection.executemany(
                        """
                        INSERT OR REPLACE INTO kanji_component_trees
                            (character, tree_json, source_version)
                        VALUES (?, ?, ?)
                        """,
                        batch,
                    )
                    animcjk_fallback_count += len(batch)
                    batch.clear()

            if batch:
                connection.executemany(
                    """
                    INSERT OR REPLACE INTO kanji_component_trees
                        (character, tree_json, source_version)
                    VALUES (?, ?, ?)
                    """,
                    batch,
                )
                animcjk_fallback_count += len(batch)

            connection.commit()
            quick_check = connection.execute("PRAGMA quick_check").fetchone()[0]
            linked_count = connection.execute(
                """
                SELECT COUNT(*)
                FROM kanji_component_trees AS components
                INNER JOIN kanji_entries AS entries
                    ON entries.character = components.character
                """
            ).fetchone()[0]
            total_imported_count = (
                kanjivg_imported_count + animcjk_fallback_count
            )

            print(f"KanjiVG SVG files scanned: {len(svg_files):,}")
            print(f"KanjiVG component trees imported: {kanjivg_imported_count:,}")
            print(f"AnimCJK fallback trees imported: {animcjk_fallback_count:,}")
            print(f"Component trees imported: {total_imported_count:,}")
            print(f"Trees matching KANJIDIC entries: {linked_count:,}")
            print(f"KanjiVG files without a component tree: {skipped_count:,}")
            print(f"SQLite quick_check: {quick_check}")
            print(f"Database updated: {database_path}")
        finally:
            connection.close()
    finally:
        if temp_directory is not None:
            temp_directory.cleanup()
        if animcjk_temp_directory is not None:
            animcjk_temp_directory.cleanup()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Import KanjiVG's semantic component hierarchy into Gakuji's "
            "existing SQLite dictionary, using AnimCJK's Japanese decomposition "
            "data only when KanjiVG has no component tree, without touching the "
            "word, spelling, example, or stroke-order tables."
        )
    )
    parser.add_argument(
        "--input",
        type=Path,
        default=DEFAULT_INPUT_PATH,
        help=(
            "Extracted KanjiVG main-release folder. If it is missing, the "
            "matching official release is downloaded automatically."
        ),
    )
    parser.add_argument(
        "--animcjk-input",
        type=Path,
        default=DEFAULT_ANIMCJK_INPUT_PATH,
        help=(
            "AnimCJK dictionaryJa.txt used only as a fallback when KanjiVG has "
            "no component tree. If missing, it is downloaded automatically."
        ),
    )
    parser.add_argument(
        "--database",
        type=Path,
        default=DEFAULT_DATABASE_PATH,
        help="Existing Gakuji dictionary SQLite database.",
    )
    parser.add_argument(
        "--release",
        default=DEFAULT_RELEASE,
        help="KanjiVG release date used for source attribution/download.",
    )
    parser.add_argument(
        "--no-download",
        action="store_true",
        help=(
            "Fail instead of downloading KanjiVG or AnimCJK when a required "
            "source is missing."
        ),
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Optional development limit for testing.",
    )
    return parser


def main() -> None:
    args = build_parser().parse_args()
    import_components(
        args.input,
        args.database,
        source_version=args.release,
        animcjk_input_path=args.animcjk_input,
        limit=args.limit,
        download_if_missing=not args.no_download,
    )


if __name__ == "__main__":
    main()
