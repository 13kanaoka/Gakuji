import argparse
import gzip
import re
import sqlite3
import unicodedata
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path


DEFAULT_INPUT_PATH = Path("tools/source/examples.utf.gz")
DEFAULT_DATABASE_PATH = Path("assets/dictionary/dictionary.db")
DEFAULT_MAX_EXAMPLES_PER_SENSE = 8

SOURCE_KEY = "edrdg_tanaka"
SOURCE_NAME = "EDRDG Tanaka Corpus"
SOURCE_HOMEPAGE = "https://www.edrdg.org/wiki/Tanaka_Corpus.html"
SOURCE_NOTE = (
    "Example sentences imported from EDRDG's edited Tanaka Corpus. "
    "Include the required source acknowledgement in Gakuji's acknowledgements."
)

JAPANESE_CHARACTER_RE = re.compile(
    r"[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]"
)
ENGLISH_LETTER_RE = re.compile(r"[A-Za-z]")
URL_OR_EMAIL_RE = re.compile(
    r"(?:https?://|www\.|\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b)",
    re.IGNORECASE,
)
CONTROL_CHARACTER_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
ID_RE = re.compile(r"^(?P<japanese_id>\d+)_(?P<english_id>\d+)$")
SENSE_RE = re.compile(r"\[(?P<sense>\d+)\]")
SURFACE_RE = re.compile(r"\{(?P<surface>[^}]*)\}")
PAREN_RE = re.compile(r"\((?P<value>[^()]*)\)")
TRAILING_REFERENCE_RE = re.compile(r"\|\d+$")

SPELLING_WEIGHTS = {5000, 4800}
READING_WEIGHTS = {4900, 4700}
JAPANESE_ALIAS_MIN_WEIGHT = 4700

ENGLISH_STOP_WORDS = {
    "a", "an", "and", "are", "as", "at", "be", "been", "being", "by",
    "for", "from", "had", "has", "have", "he", "her", "hers", "him",
    "his", "i", "in", "into", "is", "it", "its", "me", "my", "of",
    "on", "or", "our", "ours", "she", "that", "the", "their", "theirs",
    "them", "they", "this", "those", "to", "was", "we", "were", "with",
    "you", "your", "yours",
}

IRREGULAR_ENGLISH_STEMS = {
    "ate": "eat",
    "eaten": "eat",
    "ran": "run",
    "running": "run",
    "went": "go",
    "gone": "go",
    "saw": "see",
    "seen": "see",
    "took": "take",
    "taken": "take",
    "gave": "give",
    "given": "give",
    "came": "come",
    "bought": "buy",
    "brought": "bring",
    "thought": "think",
    "wrote": "write",
    "written": "write",
    "spoke": "speak",
    "spoken": "speak",
    "drove": "drive",
    "driven": "drive",
}

SENSITIVE_ENGLISH_PATTERNS = [
    re.compile(pattern, re.IGNORECASE)
    for pattern in (
        r"\bsuicid(?:e|al)\b",
        r"\bself[- ]?harm\b",
        r"\bkill(?:ed|ing|s)?\b",
        r"\bmurder(?:ed|ing|s)?\b",
        r"\brape(?:d|s)?\b",
        r"\bsexual assault\b",
        r"\bchild abuse\b",
        r"\bdomestic violence\b",
        r"\bterroris(?:m|t|ts)\b",
        r"\bsuicide bomber\b",
        r"\bexecute(?:d|s)?\b",
        r"\bdeath row\b",
        r"\bcorpse\b",
        r"\bgenitals?\b",
        r"\bpenis\b",
        r"\bvagina\b",
        r"\bintercourse\b",
        r"\bprostitut(?:e|ion)\b",
    )
]

SENSITIVE_JAPANESE_PATTERNS = [
    re.compile(pattern)
    for pattern in (
        r"自殺",
        r"自傷",
        r"自爆",
        r"殺人",
        r"殺害",
        r"強姦",
        r"レイプ",
        r"性的暴行",
        r"児童虐待",
        r"家庭内暴力",
        r"テロ",
        r"死刑",
        r"遺体",
        r"陰茎",
        r"膣",
        r"売春",
    )
]


@dataclass(frozen=True)
class SenseRecord:
    sense_index: int
    position: int
    definition_keywords: frozenset[str]
    definition_phrases: tuple[str, ...]


@dataclass(frozen=True)
class TermRecord:
    term_id: str
    kanji: str
    reading: str
    is_common: bool
    common_score: int
    senses: tuple[SenseRecord, ...]

    def sense_by_index(self, sense_index: int) -> SenseRecord | None:
        for sense in self.senses:
            if sense.sense_index == sense_index:
                return sense
        return None


@dataclass(frozen=True)
class SentencePair:
    japanese_id: int
    english_id: int
    japanese: str
    english: str


@dataclass(frozen=True)
class ParsedIndexToken:
    headword: str
    reading: str
    surface: str
    sense_index: int | None
    is_checked: bool
    direct_term_id: str | None


@dataclass(frozen=True)
class ResolvedToken:
    term: TermRecord
    match_quality: int
    match_kind: str


@dataclass(frozen=True)
class ExampleTokenCandidate:
    surface: str
    headword: str
    reading: str
    term_id: str | None


@dataclass(frozen=True)
class ExampleCandidate:
    term_id: str
    sense_index: int
    japanese_id: int
    english_id: int
    japanese: str
    english: str
    is_checked: bool
    quality_score: int
    tokens: tuple[ExampleTokenCandidate, ...]


class ImportStats:
    def __init__(self):
        self.lines_read = 0
        self.a_lines = 0
        self.b_lines = 0
        self.complete_pairs = 0
        self.usable_pairs = 0
        self.rejected_pairs = 0
        self.tokens_parsed = 0
        self.tokens_skipped = 0
        self.direct_matches = 0
        self.alias_matches = 0
        self.unmatched_tokens = 0
        self.ambiguous_tokens = 0
        self.duplicate_candidates = 0
        self.sensitive_pairs = 0
        self.definition_mismatches = 0
        self.surface_mismatches = 0
        self.weak_second_examples = 0
        self.explicit_sense_matches = 0
        self.inferred_sense_matches = 0
        self.invalid_sense_tokens = 0
        self.ambiguous_sense_matches = 0


class TermLookup:
    def __init__(self):
        self.terms_by_id: dict[str, TermRecord] = {}
        self.alias_to_term_ids: dict[str, set[str]] = defaultdict(set)
        self.spellings_by_term_id: dict[str, set[str]] = defaultdict(set)
        self.readings_by_term_id: dict[str, set[str]] = defaultdict(set)

    def add_term(self, term: TermRecord):
        self.terms_by_id[term.term_id] = term

        kanji_key = normalize_alias(term.kanji)
        reading_key = normalize_alias(term.reading)

        if kanji_key:
            self.alias_to_term_ids[kanji_key].add(term.term_id)
            self.spellings_by_term_id[term.term_id].add(kanji_key)

        if reading_key:
            self.alias_to_term_ids[reading_key].add(term.term_id)
            self.readings_by_term_id[term.term_id].add(reading_key)

    def add_alias(self, term_id: str, alias: str, weight: int):
        if term_id not in self.terms_by_id:
            return

        alias_key = normalize_alias(alias)

        if not alias_key or not has_japanese_character(alias_key):
            return

        self.alias_to_term_ids[alias_key].add(term_id)

        if weight in SPELLING_WEIGHTS:
            self.spellings_by_term_id[term_id].add(alias_key)
        elif weight in READING_WEIGHTS:
            self.readings_by_term_id[term_id].add(alias_key)

    def resolve(
        self,
        token: ParsedIndexToken,
    ) -> tuple[ResolvedToken | None, str]:
        if token.direct_term_id is not None:
            direct_term = self.terms_by_id.get(token.direct_term_id)

            if direct_term is not None:
                return (
                    ResolvedToken(
                        term=direct_term,
                        match_quality=3000,
                        match_kind="direct",
                    ),
                    "matched",
                )

        headword_key = normalize_alias(token.headword)

        if not headword_key:
            return None, "unmatched"

        candidate_ids = set(self.alias_to_term_ids.get(headword_key, ()))

        if not candidate_ids:
            return None, "unmatched"

        reading_key = normalize_alias(token.reading)

        if reading_key:
            reading_candidates = {
                term_id
                for term_id in candidate_ids
                if reading_key in self.readings_by_term_id.get(term_id, ())
            }

            if reading_candidates:
                candidate_ids = reading_candidates
            else:
                return None, "unmatched"

        if len(candidate_ids) == 1:
            term_id = next(iter(candidate_ids))
            term = self.terms_by_id[term_id]
            quality = 2400 if reading_key else 1900

            return (
                ResolvedToken(
                    term=term,
                    match_quality=quality,
                    match_kind="alias",
                ),
                "matched",
            )

        exact_primary_ids = []

        for term_id in candidate_ids:
            term = self.terms_by_id[term_id]

            if normalize_alias(term.kanji) != headword_key:
                continue

            if reading_key and normalize_alias(term.reading) != reading_key:
                continue

            exact_primary_ids.append(term_id)

        if len(exact_primary_ids) == 1:
            term = self.terms_by_id[exact_primary_ids[0]]

            return (
                ResolvedToken(
                    term=term,
                    match_quality=2600 if reading_key else 2100,
                    match_kind="alias",
                ),
                "matched",
            )

        return None, "ambiguous"


def normalize_text(value: str) -> str:
    value = unicodedata.normalize("NFC", value)
    value = re.sub(r"\s+", " ", value)
    return value.strip()


def normalize_alias(value: str) -> str:
    return normalize_text(value).lower()


def has_japanese_character(value: str) -> bool:
    return JAPANESE_CHARACTER_RE.search(value) is not None


def english_stem(word: str) -> str:
    word = word.lower().strip("'\"")

    irregular = IRREGULAR_ENGLISH_STEMS.get(word)
    if irregular is not None:
        return irregular

    if len(word) > 5 and word.endswith("ing"):
        base = word[:-3]
        if len(base) >= 2 and base[-1] == base[-2]:
            base = base[:-1]
        return base

    if len(word) > 4 and word.endswith("ied"):
        return word[:-3] + "y"

    if len(word) > 4 and word.endswith("ed"):
        base = word[:-2]
        if base.endswith("i"):
            base = base[:-1] + "y"
        return base

    if len(word) > 4 and word.endswith("es"):
        return word[:-2]

    if len(word) > 3 and word.endswith("s"):
        return word[:-1]

    return word


def english_content_words(value: str) -> set[str]:
    words = set()

    for raw_word in re.findall(r"[A-Za-z]+(?:'[A-Za-z]+)?", value.lower()):
        stemmed = english_stem(raw_word)

        if not stemmed or stemmed in ENGLISH_STOP_WORDS:
            continue

        if len(stemmed) <= 1:
            continue

        words.add(stemmed)

    return words


def normalized_definition_phrase(value: str) -> str:
    value = re.sub(r"\([^)]*\)", " ", value.lower())
    value = re.sub(r"[^a-z]+", " ", value)
    value = re.sub(r"\s+", " ", value).strip()

    if value.startswith("to "):
        value = value[3:].strip()

    return value


def contains_sensitive_content(pair: SentencePair) -> bool:
    return any(pattern.search(pair.english) for pattern in SENSITIVE_ENGLISH_PATTERNS) or any(
        pattern.search(pair.japanese) for pattern in SENSITIVE_JAPANESE_PATTERNS
    )


def visible_surface_matches(pair: SentencePair, token: ParsedIndexToken) -> bool:
    candidates = [token.surface, token.headword, token.reading]

    return any(
        candidate and normalize_text(candidate) in pair.japanese
        for candidate in candidates
    )


def definition_alignment_score(english: str, sense: SenseRecord) -> int:
    translation_words = english_content_words(english)
    overlap = translation_words.intersection(sense.definition_keywords)
    score = len(overlap) * 450
    normalized_english = normalized_definition_phrase(english)

    for phrase in sense.definition_phrases:
        if not phrase:
            continue

        if phrase in normalized_english:
            score += 900

    return score


def resolve_sense(
    english: str,
    token: ParsedIndexToken,
    term: TermRecord,
) -> tuple[SenseRecord | None, int, str]:
    if token.sense_index is not None:
        # Tanaka/JMdict annotations use human-facing 1-based sense numbers.
        database_sense_index = token.sense_index - 1
        sense = term.sense_by_index(database_sense_index)

        if sense is None:
            return None, 0, "invalid"

        return sense, definition_alignment_score(english, sense), "explicit"

    ranked = [
        (definition_alignment_score(english, sense), sense)
        for sense in term.senses
    ]
    ranked.sort(key=lambda item: (item[0], -item[1].position), reverse=True)

    if not ranked or ranked[0][0] <= 0:
        return None, 0, "unmatched"

    best_score, best_sense = ranked[0]

    if len(ranked) > 1 and ranked[1][0] == best_score:
        return None, 0, "ambiguous"

    return best_sense, best_score, "inferred"


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


def open_corpus(path: Path):
    if not path.exists():
        raise FileNotFoundError(f"Tanaka Corpus file not found: {path}")

    if path.suffix.lower() == ".gz":
        return gzip.open(path, "rt", encoding="utf-8-sig", errors="strict")

    return path.open("r", encoding="utf-8-sig", errors="strict")


def parse_a_line(line: str) -> SentencePair | None:
    if not line.startswith("A:"):
        return None

    payload = line[2:].strip()
    content, marker, id_text = payload.rpartition("#ID=")

    if not marker:
        return None

    id_match = ID_RE.fullmatch(id_text.strip())

    if id_match is None:
        return None

    if "\t" in content:
        japanese, english = content.split("\t", 1)
    else:
        pieces = re.split(r"\s{2,}", content, maxsplit=1)

        if len(pieces) != 2:
            return None

        japanese, english = pieces

    japanese = normalize_text(japanese)
    english = normalize_text(english)

    if not japanese or not english:
        return None

    return SentencePair(
        japanese_id=int(id_match.group("japanese_id")),
        english_id=int(id_match.group("english_id")),
        japanese=japanese,
        english=english,
    )


def parse_index_token(raw_token: str) -> ParsedIndexToken | None:
    token = raw_token.strip()

    if not token:
        return None

    token = TRAILING_REFERENCE_RE.sub("", token)
    is_checked = token.endswith("~")

    if is_checked:
        token = token[:-1]

    surface_match = SURFACE_RE.search(token)
    surface = normalize_text(surface_match.group("surface")) if surface_match else ""
    token = SURFACE_RE.sub("", token)

    sense_match = SENSE_RE.search(token)
    sense_index = int(sense_match.group("sense")) if sense_match else None
    token = SENSE_RE.sub("", token)

    reading = ""
    direct_term_id = None

    for match in PAREN_RE.finditer(token):
        value = normalize_text(match.group("value"))

        if not value:
            continue

        if value.startswith("#") and value[1:].isdigit():
            direct_term_id = f"jmdict_{value[1:]}"
        elif not reading:
            reading = value

    headword = normalize_text(PAREN_RE.sub("", token))

    if not headword:
        return None

    return ParsedIndexToken(
        headword=headword,
        reading=reading,
        surface=surface,
        sense_index=sense_index,
        is_checked=is_checked,
        direct_term_id=direct_term_id,
    )


def sentence_pair_rejection_reason(pair: SentencePair) -> str | None:
    japanese_length = len(pair.japanese)
    english_length = len(pair.english)

    if japanese_length < 4 or japanese_length > 120:
        return "length"

    if english_length < 3 or english_length > 240:
        return "length"

    if not has_japanese_character(pair.japanese):
        return "language"

    if ENGLISH_LETTER_RE.search(pair.english) is None:
        return "language"

    if URL_OR_EMAIL_RE.search(pair.japanese) or URL_OR_EMAIL_RE.search(pair.english):
        return "url"

    if CONTROL_CHARACTER_RE.search(pair.japanese):
        return "control"

    if CONTROL_CHARACTER_RE.search(pair.english):
        return "control"

    if contains_sensitive_content(pair):
        return "sensitive"

    return None


def sentence_quality_score(
    pair: SentencePair,
    token: ParsedIndexToken,
    resolved: ResolvedToken,
    sense: SenseRecord,
    alignment_score: int,
) -> int:
    score = resolved.match_quality + alignment_score

    if token.is_checked:
        score += 5000

    surface = token.surface or token.headword

    if surface and surface in pair.japanese:
        score += 450
    elif token.headword in pair.japanese:
        score += 300

    if token.sense_index is not None:
        score += 1200
    else:
        score += max(0, 450 - sense.position * 80)

    if resolved.term.is_common:
        score += 100

    score += max(0, 650 - abs(len(pair.japanese) - 28) * 12)
    score += max(0, 350 - abs(len(pair.english) - 65) * 4)

    return score


def candidate_sort_key(candidate: ExampleCandidate):
    return (
        candidate.quality_score,
        1 if candidate.is_checked else 0,
        -len(candidate.japanese),
        -len(candidate.english),
        -candidate.japanese_id,
        -candidate.english_id,
    )


def add_candidate(
    candidates_by_sense: dict[tuple[str, int], list[ExampleCandidate]],
    candidate: ExampleCandidate,
    max_examples_per_sense: int,
    stats: ImportStats,
):
    key = (candidate.term_id, candidate.sense_index)
    candidates = candidates_by_sense[key]

    for existing in candidates:
        if (
            existing.japanese_id == candidate.japanese_id
            and existing.english_id == candidate.english_id
        ):
            stats.duplicate_candidates += 1
            return

    candidates.append(candidate)
    candidates.sort(key=candidate_sort_key, reverse=True)

    if len(candidates) > max_examples_per_sense:
        del candidates[max_examples_per_sense:]


def load_term_lookup(connection: sqlite3.Connection) -> TermLookup:
    lookup = TermLookup()

    if not table_exists(connection, "senses"):
        raise RuntimeError(
            "The database does not contain the sense-based schema. "
            "Run the revised convert_jmdict_to_sqlite.py first."
        )

    definitions_by_sense: dict[tuple[str, int], list[str]] = defaultdict(list)

    for term_id, sense_index, definition in connection.execute(
        """
        SELECT term_id, sense_index, definition
        FROM definitions
        ORDER BY term_id, sense_index, position
        """
    ):
        if term_id and definition:
            definitions_by_sense[(term_id, int(sense_index))].append(definition)

    senses_by_term_id: dict[str, list[SenseRecord]] = defaultdict(list)

    for term_id, sense_index, position in connection.execute(
        """
        SELECT term_id, sense_index, position
        FROM senses
        ORDER BY term_id, position
        """
    ):
        raw_definitions = definitions_by_sense.get(
            (term_id, int(sense_index)),
            [],
        )
        definition_keywords = set()
        definition_phrases = []

        for definition in raw_definitions:
            phrase = normalized_definition_phrase(definition)

            if not phrase:
                continue

            definition_keywords.update(english_content_words(phrase))

            if phrase not in definition_phrases:
                definition_phrases.append(phrase)

        senses_by_term_id[term_id].append(
            SenseRecord(
                sense_index=int(sense_index),
                position=int(position),
                definition_keywords=frozenset(definition_keywords),
                definition_phrases=tuple(definition_phrases),
            )
        )

    for row in connection.execute(
        """
        SELECT id, kanji, reading, is_common, common_score
        FROM terms
        """
    ):
        term_id = row[0]
        senses = tuple(senses_by_term_id.get(term_id, ()))

        if not senses:
            continue

        lookup.add_term(
            TermRecord(
                term_id=term_id,
                kanji=row[1] or "",
                reading=row[2] or "",
                is_common=row[3] == 1,
                common_score=int(row[4] or 0),
                senses=senses,
            )
        )

    if table_exists(connection, "search_keywords"):
        for row in connection.execute(
            """
            SELECT keyword, term_id, weight
            FROM search_keywords
            WHERE weight >= ?
            """,
            (JAPANESE_ALIAS_MIN_WEIGHT,),
        ):
            lookup.add_alias(
                term_id=row[1],
                alias=row[0] or "",
                weight=int(row[2] or 0),
            )

    return lookup


def create_example_schema(connection: sqlite3.Connection):
    cursor = connection.cursor()

    cursor.execute("DROP TABLE IF EXISTS example_tokens")
    cursor.execute("DROP TABLE IF EXISTS examples")
    cursor.execute("DROP TABLE IF EXISTS example_sources")

    cursor.execute(
        """
        CREATE TABLE example_sources (
            source_key TEXT PRIMARY KEY,
            source_name TEXT NOT NULL,
            source_homepage TEXT NOT NULL,
            source_note TEXT NOT NULL
        )
        """
    )

    cursor.execute(
        """
        CREATE TABLE examples (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            term_id TEXT NOT NULL,
            sense_index INTEGER NOT NULL,
            japanese TEXT NOT NULL,
            reading TEXT NOT NULL DEFAULT '',
            english TEXT NOT NULL,
            position INTEGER NOT NULL DEFAULT 0,
            source_key TEXT NOT NULL,
            source_japanese_id INTEGER,
            source_english_id INTEGER,
            is_checked INTEGER NOT NULL DEFAULT 0,
            quality_score INTEGER NOT NULL DEFAULT 0,
            UNIQUE(term_id, sense_index, source_japanese_id, source_english_id)
        )
        """
    )

    cursor.execute(
        """
        INSERT INTO example_sources (
            source_key,
            source_name,
            source_homepage,
            source_note
        )
        VALUES (?, ?, ?, ?)
        """,
        (
            SOURCE_KEY,
            SOURCE_NAME,
            SOURCE_HOMEPAGE,
            SOURCE_NOTE,
        ),
    )

    cursor.execute(
        """
        CREATE INDEX idx_examples_term_sense_position
        ON examples(term_id, sense_index, position)
        """
    )

    cursor.execute(
        """
        CREATE INDEX idx_examples_source_ids
        ON examples(source_japanese_id, source_english_id)
        """
    )

    cursor.execute(
        """
        CREATE TABLE example_tokens (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            example_id INTEGER NOT NULL,
            position INTEGER NOT NULL,
            surface TEXT NOT NULL,
            headword TEXT NOT NULL,
            reading TEXT NOT NULL DEFAULT '',
            term_id TEXT,
            UNIQUE(example_id, position),
            FOREIGN KEY(example_id) REFERENCES examples(id)
        )
        """
    )

    cursor.execute(
        """
        CREATE INDEX idx_example_tokens_example_position
        ON example_tokens(example_id, position)
        """
    )

    cursor.execute(
        """
        CREATE INDEX idx_example_tokens_term_id
        ON example_tokens(term_id)
        """
    )

    connection.commit()


def import_examples(
    input_path: Path,
    database_path: Path,
    max_examples_per_sense: int,
    limit: int | None,
):
    if max_examples_per_sense <= 0:
        raise ValueError("--max-per-sense must be greater than zero")

    if not database_path.exists():
        raise FileNotFoundError(f"Dictionary database not found: {database_path}")

    connection = sqlite3.connect(database_path)

    try:
        if not table_exists(connection, "terms"):
            raise RuntimeError(
                "The database does not contain a terms table. "
                "Run convert_jmdict_to_sqlite.py first."
            )

        print("Loading dictionary terms and Japanese aliases...")
        lookup = load_term_lookup(connection)
        alias_count = sum(len(ids) for ids in lookup.alias_to_term_ids.values())

        print(f"Loaded {len(lookup.terms_by_id)} dictionary terms")
        print(f"Loaded {alias_count} Japanese alias mappings")

        stats = ImportStats()
        candidates_by_sense: dict[tuple[str, int], list[ExampleCandidate]] = defaultdict(list)
        pending_pair: SentencePair | None = None

        with open_corpus(input_path) as source:
            for line in source:
                stats.lines_read += 1
                line = line.rstrip("\r\n")

                if line.startswith("A:"):
                    stats.a_lines += 1
                    pending_pair = parse_a_line(line)
                    continue

                if not line.startswith("B:"):
                    continue

                stats.b_lines += 1

                if pending_pair is None:
                    continue

                stats.complete_pairs += 1
                pair = pending_pair
                pending_pair = None

                rejection_reason = sentence_pair_rejection_reason(pair)

                if rejection_reason is not None:
                    stats.rejected_pairs += 1

                    if rejection_reason == "sensitive":
                        stats.sensitive_pairs += 1

                    continue

                stats.usable_pairs += 1
                raw_tokens = line[2:].strip().split()
                seen_term_senses_for_pair: set[tuple[str, int]] = set()
                parsed_tokens: list[
                    tuple[ParsedIndexToken, ResolvedToken | None, str]
                ] = []
                sentence_tokens: list[ExampleTokenCandidate] = []

                for raw_token in raw_tokens:
                    token = parse_index_token(raw_token)

                    if token is None:
                        stats.tokens_skipped += 1
                        continue

                    stats.tokens_parsed += 1
                    resolved, status = lookup.resolve(token)
                    parsed_tokens.append((token, resolved, status))
                    sentence_tokens.append(
                        ExampleTokenCandidate(
                            surface=token.surface or token.headword,
                            headword=token.headword,
                            reading=token.reading,
                            term_id=(
                                resolved.term.term_id
                                if resolved is not None
                                else None
                            ),
                        )
                    )

                frozen_sentence_tokens = tuple(sentence_tokens)

                for token, resolved, status in parsed_tokens:
                    if resolved is None:
                        if status == "ambiguous":
                            stats.ambiguous_tokens += 1
                        else:
                            stats.unmatched_tokens += 1
                        continue

                    if not visible_surface_matches(pair, token):
                        stats.surface_mismatches += 1
                        continue

                    sense, alignment_score, sense_status = resolve_sense(
                        pair.english,
                        token,
                        resolved.term,
                    )

                    if sense is None:
                        if sense_status == "invalid":
                            stats.invalid_sense_tokens += 1
                        elif sense_status == "ambiguous":
                            stats.ambiguous_sense_matches += 1
                        else:
                            stats.definition_mismatches += 1
                        continue

                    term_sense_key = (
                        resolved.term.term_id,
                        sense.sense_index,
                    )

                    if term_sense_key in seen_term_senses_for_pair:
                        continue

                    # Explicit Tanaka sense annotations are authoritative. For
                    # unannotated tokens, require English/gloss alignment.
                    if sense_status != "explicit" and alignment_score <= 0:
                        stats.definition_mismatches += 1
                        continue

                    seen_term_senses_for_pair.add(term_sense_key)

                    if sense_status == "explicit":
                        stats.explicit_sense_matches += 1
                    else:
                        stats.inferred_sense_matches += 1

                    if resolved.match_kind == "direct":
                        stats.direct_matches += 1
                    else:
                        stats.alias_matches += 1

                    score = sentence_quality_score(
                        pair,
                        token,
                        resolved,
                        sense,
                        alignment_score,
                    )

                    add_candidate(
                        candidates_by_sense=candidates_by_sense,
                        candidate=ExampleCandidate(
                            term_id=resolved.term.term_id,
                            sense_index=sense.sense_index,
                            japanese_id=pair.japanese_id,
                            english_id=pair.english_id,
                            japanese=pair.japanese,
                            english=pair.english,
                            is_checked=token.is_checked,
                            quality_score=score,
                            tokens=frozen_sentence_tokens,
                        ),
                        max_examples_per_sense=max_examples_per_sense,
                        stats=stats,
                    )

                if stats.complete_pairs % 10000 == 0:
                    print(
                        f"Processed {stats.complete_pairs} sentence pairs; "
                        f"{len(candidates_by_sense)} senses currently have examples..."
                    )

                if limit is not None and stats.complete_pairs >= limit:
                    break

        print("Creating examples tables...")
        create_example_schema(connection)

        rows = []
        selected_candidate_records: list[ExampleCandidate] = []

        terms_receiving_examples = set()

        for term_id, sense_index in sorted(candidates_by_sense):
            candidates = candidates_by_sense[(term_id, sense_index)]
            terms_receiving_examples.add(term_id)
            candidates.sort(key=candidate_sort_key, reverse=True)

            selected_candidates = candidates[:max_examples_per_sense]

            for position, candidate in enumerate(selected_candidates):
                rows.append(
                    (
                        candidate.term_id,
                        candidate.sense_index,
                        candidate.japanese,
                        "",
                        candidate.english,
                        position,
                        SOURCE_KEY,
                        candidate.japanese_id,
                        candidate.english_id,
                        1 if candidate.is_checked else 0,
                        candidate.quality_score,
                    )
                )
                selected_candidate_records.append(candidate)

        connection.executemany(
            """
            INSERT INTO examples (
                term_id,
                sense_index,
                japanese,
                reading,
                english,
                position,
                source_key,
                source_japanese_id,
                source_english_id,
                is_checked,
                quality_score
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            rows,
        )

        example_ids = {
            (
                row[1],
                int(row[2]),
                int(row[3]),
                int(row[4]),
            ): int(row[0])
            for row in connection.execute(
                """
                SELECT
                    id,
                    term_id,
                    sense_index,
                    source_japanese_id,
                    source_english_id
                FROM examples
                """
            )
        }

        token_rows = []

        for candidate in selected_candidate_records:
            example_id = example_ids.get(
                (
                    candidate.term_id,
                    candidate.sense_index,
                    candidate.japanese_id,
                    candidate.english_id,
                )
            )

            if example_id is None:
                continue

            for position, token in enumerate(candidate.tokens):
                if not token.surface and not token.headword:
                    continue

                token_rows.append(
                    (
                        example_id,
                        position,
                        token.surface,
                        token.headword,
                        token.reading,
                        token.term_id,
                    )
                )

                if len(token_rows) >= 50000:
                    connection.executemany(
                        """
                        INSERT INTO example_tokens (
                            example_id,
                            position,
                            surface,
                            headword,
                            reading,
                            term_id
                        )
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                        token_rows,
                    )
                    token_rows.clear()

        if token_rows:
            connection.executemany(
                """
                INSERT INTO example_tokens (
                    example_id,
                    position,
                    surface,
                    headword,
                    reading,
                    term_id
                )
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                token_rows,
            )

        connection.commit()
        connection.execute("ANALYZE examples")
        connection.execute("ANALYZE example_tokens")
        connection.commit()

        print()
        print(f"Read {stats.lines_read} corpus lines")
        print(f"Found {stats.complete_pairs} A/B sentence pairs")
        print(f"Usable sentence pairs: {stats.usable_pairs}")
        print(f"Rejected sentence pairs: {stats.rejected_pairs}")
        print(f"Rejected sensitive sentence pairs: {stats.sensitive_pairs}")
        print(f"Parsed Japanese index tokens: {stats.tokens_parsed}")
        print(f"Direct JMdict ID matches: {stats.direct_matches}")
        print(f"Alias matches: {stats.alias_matches}")
        print(f"Unmatched tokens: {stats.unmatched_tokens}")
        print(f"Ambiguous tokens skipped: {stats.ambiguous_tokens}")
        print(f"Rejected surface mismatches: {stats.surface_mismatches}")
        print(f"Rejected definition mismatches: {stats.definition_mismatches}")
        print(f"Explicit sense matches: {stats.explicit_sense_matches}")
        print(f"Inferred sense matches: {stats.inferred_sense_matches}")
        print(f"Invalid sense annotations skipped: {stats.invalid_sense_tokens}")
        print(f"Ambiguous inferred senses skipped: {stats.ambiguous_sense_matches}")
        print(f"Dictionary senses receiving examples: {len(candidates_by_sense)}")
        print(f"Dictionary terms receiving examples: {len(terms_receiving_examples)}")
        print(f"Inserted {len(rows)} example rows")
        print("Inserted token breakdown rows for selected examples")
        print(f"Updated {database_path}")
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Import example sentences from EDRDG's edited Tanaka Corpus "
            "into an existing Gakuji dictionary database."
        )
    )
    parser.add_argument(
        "--input",
        default=str(DEFAULT_INPUT_PATH),
        help=f"Tanaka Corpus path (default: {DEFAULT_INPUT_PATH})",
    )
    parser.add_argument(
        "--database",
        default=str(DEFAULT_DATABASE_PATH),
        help=f"Dictionary database path (default: {DEFAULT_DATABASE_PATH})",
    )
    parser.add_argument(
        "--max-per-sense",
        type=int,
        default=DEFAULT_MAX_EXAMPLES_PER_SENSE,
        help=(
            "Maximum number of ranked example sentences stored for each sense "
            f"(default: {DEFAULT_MAX_EXAMPLES_PER_SENSE})"
        ),
    )
    parser.add_argument(
        "--limit",
        type=int,
        help="Optional number of A/B sentence pairs to process for testing",
    )

    args = parser.parse_args()

    import_examples(
        input_path=Path(args.input),
        database_path=Path(args.database),
        max_examples_per_sense=args.max_per_sense,
        limit=args.limit,
    )


if __name__ == "__main__":
    main()
