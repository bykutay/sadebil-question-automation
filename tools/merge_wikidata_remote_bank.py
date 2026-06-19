#!/usr/bin/env python3
"""Merge verified Wikidata questions into the SadeBiL remote question bank.

The remote bank should refresh without becoming fragile. This script gives
Wikidata questions priority, then fills the remaining 1000 questions per
category/difficulty from the stable offline bank.
"""

from __future__ import annotations

import argparse
import json
import random
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


CATEGORIES = ["guncel", "teknoloji", "sanat", "spor", "muzik", "tarih"]
DIFFICULTIES = {
    "tr": ["kolay", "orta", "zor"],
    "en": ["easy", "medium", "hard"],
}


def norm(text: str) -> str:
    table = str.maketrans({
        "ı": "i", "ğ": "g", "ü": "u", "ş": "s", "ö": "o", "ç": "c",
        "İ": "i", "Ğ": "g", "Ü": "u", "Ş": "s", "Ö": "o", "Ç": "c",
    })
    return re.sub(r"[^a-z0-9]+", " ", (text or "").lower().translate(table)).strip()


def load_rows(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_rows(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")


def category_name(lang: str, category: str) -> str:
    tr = {
        "guncel": "Güncel",
        "teknoloji": "Teknoloji",
        "sanat": "Sanat",
        "spor": "Spor",
        "muzik": "Müzik",
        "tarih": "Tarih",
    }
    en = {
        "guncel": "Current",
        "teknoloji": "Technology",
        "sanat": "Art",
        "spor": "Sports",
        "muzik": "Music",
        "tarih": "History",
    }
    return (en if lang == "en" else tr)[category]


def row_key(row: dict) -> str:
    answer = ""
    answers = row.get("answers") or []
    correct = row.get("correct", -1)
    if isinstance(correct, int) and 0 <= correct < len(answers):
        answer = str(answers[correct])
    source_id = str(row.get("source_id") or "")
    if source_id:
        return "source:" + source_id
    return "qa:" + norm(str(row.get("question", ""))) + "|" + norm(answer)


def relabel(row: dict, lang: str, category: str, index: int) -> dict:
    out = dict(row)
    out["category"] = category_name(lang, category)
    old_id = str(out.get("id") or index)
    out["id"] = f"{lang}-{category}-remote-{index:05d}-{abs(hash(old_id)) & 0xffff:x}"
    return out


def choose_rows(
    lang: str,
    category: str,
    difficulty: str,
    base_rows: list[dict],
    wiki_rows: list[dict],
    target: int,
    wiki_limit: int,
    seed: int,
) -> list[dict]:
    rng = random.Random(seed)
    picked: list[dict] = []
    used: set[str] = set()

    wiki_candidates = [r for r in wiki_rows if r.get("difficulty") == difficulty]
    base_candidates = [r for r in base_rows if r.get("difficulty") == difficulty]
    rng.shuffle(wiki_candidates)
    rng.shuffle(base_candidates)

    for row in wiki_candidates:
        if len(picked) >= min(wiki_limit, target):
            break
        key = row_key(row)
        if key in used:
            continue
        picked.append(row)
        used.add(key)

    for row in base_candidates:
        if len(picked) >= target:
            break
        key = row_key(row)
        if key in used:
            continue
        picked.append(row)
        used.add(key)

    if len(picked) < target:
        raise RuntimeError(f"{lang}/{category}/{difficulty}: {len(picked)}/{target} soru tamamlanabildi.")

    return [relabel(row, lang, category, i + 1) for i, row in enumerate(picked[:target])]


def build_mix(category_rows: dict[str, list[dict]], per_category: int, seed: int) -> list[dict]:
    rng = random.Random(seed)
    out: list[dict] = []
    for category in CATEGORIES:
        rows = list(category_rows[category])
        rng.shuffle(rows)
        out.extend(rows[:per_category])
    rng.shuffle(out)
    return out


def build_language(args: argparse.Namespace, lang: str) -> dict[str, int]:
    base_dir = Path(args.base_dir)
    wiki_dir = Path(args.wikidata_dir)
    out_dir = Path(args.out_dir)
    category_rows: dict[str, list[dict]] = {}
    stats: Counter[str] = Counter()

    for category in CATEGORIES:
        base_rows = load_rows(base_dir / f"questions_{lang}_{category}.json")
        wiki_rows = load_rows(wiki_dir / f"questions_{lang}_{category}.json")
        merged: list[dict] = []
        for diff_index, difficulty in enumerate(DIFFICULTIES[lang]):
            rows = choose_rows(
                lang,
                category,
                difficulty,
                base_rows,
                wiki_rows,
                args.target_per_difficulty,
                args.wikidata_per_difficulty,
                seed=910241 + diff_index + len(category) * 37 + (11 if lang == "en" else 0),
            )
            merged.extend(rows)
            stats[f"{category}/{difficulty}"] = len(rows)
            stats[f"{category}/{difficulty}/wikidata"] = sum(1 for row in rows if str(row.get("source", "")).startswith("Wikidata"))

        category_rows[category] = merged
        write_rows(out_dir / f"questions_{lang}_{category}.json", merged)

    full: list[dict] = []
    for category in CATEGORIES:
        full.extend(category_rows[category])
    write_rows(out_dir / f"questions_{lang}.json", full)
    write_rows(out_dir / f"questions_{lang}_mix.json", build_mix(category_rows, args.mix_per_category, 20260619 + (1 if lang == "en" else 0)))
    return dict(stats)


def write_manifest(out_dir: Path, version: str, stats: dict[str, dict[str, int]]) -> None:
    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    manifest = {
        "version": version,
        "generatedAt": generated_at,
        "source": "SadeBiL curated bank + Wikidata CC0 refresh",
        "defaultRefreshHours": 24,
        "stats": stats,
        "languages": {
            "tr": {
                "full": "questions_tr.json",
                "categories": {cat: {"file": f"tr/{cat}.json", "refresh": "daily" if cat == "guncel" else "weekly"} for cat in CATEGORIES},
            },
            "en": {
                "full": "questions_en.json",
                "categories": {cat: {"file": f"en/{cat}.json", "refresh": "daily" if cat == "guncel" else "weekly"} for cat in CATEGORIES},
            },
        },
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")


def copy_category_aliases(out_dir: Path) -> None:
    for lang in ("tr", "en"):
        lang_dir = out_dir / lang
        lang_dir.mkdir(parents=True, exist_ok=True)
        for category in CATEGORIES:
            rows = load_rows(out_dir / f"questions_{lang}_{category}.json")
            write_rows(lang_dir / f"{category}.json", rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-dir", required=True)
    parser.add_argument("--wikidata-dir", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--target-per-difficulty", type=int, default=1000)
    parser.add_argument("--wikidata-per-difficulty", type=int, default=250)
    parser.add_argument("--mix-per-category", type=int, default=500)
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    stats = {
        "tr": build_language(args, "tr"),
        "en": build_language(args, "en"),
    }
    copy_category_aliases(out_dir)
    write_manifest(out_dir, args.version, stats)
    (out_dir / "_headers").write_text(
        "/*.json\n  Content-Type: application/json; charset=utf-8\n  Cache-Control: public, max-age=300, must-revalidate\n",
        encoding="ascii",
    )
    print(json.dumps(stats, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
