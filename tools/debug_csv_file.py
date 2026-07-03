import csv
from pathlib import Path


CSV_PATH = Path("tools/source/learner_priority_words.csv")

print("CSV path:")
print(CSV_PATH.resolve())
print()

print("Exists:")
print(CSV_PATH.exists())
print()

print("Raw lines containing 遊ぶ, あそぶ, or play:")
with CSV_PATH.open("r", encoding="utf-8-sig", newline="") as source:
    for line_number, line in enumerate(source, start=1):
        if "遊ぶ" in line or "あそぶ" in line or "play" in line:
            print(f"{line_number}: {line.rstrip()}")

print()
print("Parsed CSV headers and matching rows:")

with CSV_PATH.open("r", encoding="utf-8-sig", newline="") as source:
    reader = csv.DictReader(source)

    print("Headers:")
    print(reader.fieldnames)
    print()

    for row_number, row in enumerate(reader, start=2):
        kanji = (row.get("kanji") or "").strip()
        reading = (row.get("reading") or "").strip()
        keyword = (row.get("english_keyword") or "").strip()
        weight = (row.get("weight") or "").strip()

        if kanji == "遊ぶ" or reading == "あそぶ" or keyword == "play":
            print(f"Row {row_number}:")
            print(row)
            print("Parsed:", kanji, reading, keyword, weight)