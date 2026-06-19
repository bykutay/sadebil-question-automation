#!/usr/bin/env python3
"""Audit SadeBiL Turkish question banks before building an APK."""

from __future__ import annotations

import json
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path


CATEGORIES = ["guncel", "teknoloji", "sanat", "spor", "muzik", "tarih"]
DIFFICULTIES = ["kolay", "orta", "zor"]
MIN_COUNTS = {
    "kolay": 90,
    "orta": 300,
    "zor": 300,
}
BANNED_PATTERNS = [
    "genel olarak",
    "dogru anlasilirsa",
    "ne tur bir bilgidir",
    "neyi dusundurur",
    "hangi surec",
    "hangi temel sonucu",
    "temel olarak hangi",
    "sade anlatimla",
    "net ipucu",
    "ozet",
    "size neyi",
    "bu kavram",
    "hangi amacla ortaya cikar",
    "en yakin olarak",
    "gunumuze gore",
    "dogru yorum hangisidir",
    "konusunda dogru yorum",
    "sade ve dogru yorum",
    "kisa tanim",
    "temel tanim",
    "sade tanim",
    "hangi oyun durumunu",
    "hangi spor durumunu",
    "hangi mac durumudur",
    "hangi antrenman konusudur",
    "neyi ifade eder",
    "neyi anlatir",
    "neyi aciklar",
    "neyi gosterir",
]


def norm(text: str) -> str:
    table = str.maketrans({
        "ı": "i", "ğ": "g", "ü": "u", "ş": "s", "ö": "o", "ç": "c",
        "İ": "i", "Ğ": "g", "Ü": "u", "Ş": "s", "Ö": "o", "Ç": "c",
    })
    return re.sub(r"[^a-z0-9]+", " ", (text or "").lower().translate(table)).strip()


def rough_norm(text: str) -> str:
    return norm(text).replace("y", "i")


def correct_answer(row: dict) -> str:
    answers = row.get("answers") or []
    correct = row.get("correct", -1)
    if isinstance(correct, int) and 0 <= correct < len(answers):
        return str(answers[correct])
    return ""


def question_type(question: str) -> str:
    n = norm(question)
    if any(x in n for x in ["hangi yil", "hangi tarihte", "ne zaman", "when "]):
        return "date"
    if re.search(r"\bkac\b", n) or any(x in n for x in ["how many", "how much"]):
        return "number"
    if any(x in n for x in ["kimdir", "kim yapmistir", "kim yazmistir", "yazari kim", "yonetmeni kim", "kurucusu kim", "kim ", "who "]):
        return "person"
    if any(x in n for x in ["nerede", "neresidir", "hangi sehir", "hangi ulke", "baskenti", "where "]):
        return "place"
    if any(x in n for x in [
        "nedir", "ne demektir", "ne anlama", "neyi ifade", "neyi anlatir", "ne anlatir",
        "neye denir", "hangi tanim", "hangi aciklama", "hangi ifade", "hangi kavram",
        "hangi terim", "hangi kisa tanim", "dogru tanim", "uygun tanim", "what is",
        "what does", "which definition", "which explanation", "which idea"
    ]):
        return "definition"
    if any(x in n for x in ["ne ise yarar", "ne icin kullanilir", "neyle", "neyle ilgilidir", "ne kullanilir", "neyi gosterir", "what is used", "what does"]):
        return "function"
    if any(x in n for x in ["hangi alan", "hangi sanat", "hangi spor", "neyle ilgilidir", "hangi tur", "which sport", "which type"]):
        return "field"
    if any(x in n for x in ["hangi sirket", "hangi marka"]):
        return "brand"
    return "other"


def is_date_question(question: str) -> bool:
    n = norm(question)
    if "ne zaman ve nasil" in n:
        return False
    return any(x in n for x in [
        "hangi yil", "hangi yilda", "hangi tarihte", "kac yilinda", "ne zaman",
        "yilla anilir", "yilla bilinir", "in which year", "what year", "which year",
    ])


def is_date_answer(answer: str) -> bool:
    value = (answer or "").strip()
    return bool(
        re.fullmatch(r"(MÖ\s*)?\d{1,4}", value)
        or re.fullmatch(r"\d{1,2}\s+[A-Za-zÇĞİÖŞÜçğıöşü]+\s+\d{3,4}", value)
    )


def is_number_question(question: str) -> bool:
    n = norm(question)
    return bool(re.search(r"\bkac\b", n)) or any(x in n for x in ["how many", "how much"])


def is_number_answer(answer: str) -> bool:
    value = (answer or "").strip()
    if re.fullmatch(r"\d+'y?[ae]\s+\d+", value, re.IGNORECASE):
        return True
    return bool(re.fullmatch(
        r"\d+([.,]\d+)?(\s*(derece|cm|metre|km|kg|saat|gün|ay|yıl|puan|kişi|oyuncu|halka))?",
        value,
        re.IGNORECASE,
    ))


def is_action_answer(answer: str) -> bool:
    n = norm(answer)
    return bool(re.search(
        r"(mak|mek|ma|me|mayi|meyi|etmek|yapmak|saglamak|korumak|dinlemek|yazmak|okumak|baglanmak|saklamak|olcmek|izlemek|gondermek|almak|vermek|acmak|kapatmak|kullanmak|duzeltmek|yonetmek|tasimak|paylasmak|vurmak|atmak|kosmak)$",
        n,
    ))


def is_motion_answer(answer: str) -> bool:
    n = norm(answer)
    return any(x in n for x in ["vurus", "atis", "yumruk", "adim", "durus", "hareket", "kosu", "tekme", "hamle", "stil", "teknik", "sicrama", "kaldiris"])


def incompatible_question_answers(question: str, answers: list[str]) -> str | None:
    n = norm(question)
    if any(x in n for x in ["ne icin kullanilir", "ne ise yarar", "ne amacla kullanilir", "hangi amacla kullanilir"]):
        if not all(is_action_answer(option) for option in answers):
            return "kullanım sorusunda eylem olmayan şık var"
    if any(x in n for x in ["hangi hareketi", "hangi vurusu", "hangi atisi"]):
        if not all(is_motion_answer(option) for option in answers):
            return "hareket sorusunda hareket olmayan şık var"
    if any(x in n for x in ["hangi oyun durumunu", "hangi spor durumunu", "hangi mac durumudur", "hangi antrenman konusudur"]):
        return "belirsiz yapay spor kalıbı"
    return None


def audit(root: Path) -> int:
    configured = os.environ.get("SADEBIL_GENERATED_ASSETS")
    generated = Path(configured) if configured else Path.home() / "sadebil_generated_assets"
    asset_dir = generated if generated.exists() else root / "app" / "src" / "main" / "assets"
    failures: list[str] = []
    warnings: list[str] = []
    report: list[str] = []

    for category in CATEGORIES:
        path = asset_dir / f"questions_tr_{category}.json"
        rows = json.loads(path.read_text(encoding="utf-8"))
        counts = Counter(row.get("difficulty") for row in rows)
        report.append(f"{category}: " + ", ".join(f"{d}={counts.get(d, 0)}" for d in DIFFICULTIES) + f", toplam={len(rows)}")

        for difficulty in DIFFICULTIES:
            if counts.get(difficulty, 0) < MIN_COUNTS[difficulty]:
                failures.append(f"{category}/{difficulty}: soru sayısı düşük ({counts.get(difficulty, 0)})")

        seen_questions: set[str] = set()
        type_counts: dict[str, Counter] = defaultdict(Counter)
        for row in rows:
            question = str(row.get("question", "")).strip()
            answer = correct_answer(row)
            difficulty = str(row.get("difficulty", ""))
            nq = norm(question)
            na = norm(answer)

            if not question.endswith("?"):
                failures.append(f"{category}/{difficulty}: soru işareti yok: {question}")
            if nq in seen_questions:
                failures.append(f"{category}/{difficulty}: tekrar soru: {question}")
            seen_questions.add(nq)

            if any(pattern in nq for pattern in BANNED_PATTERNS):
                failures.append(f"{category}/{difficulty}: yasak kalıp: {question}")
            if len(na) > 3 and (na in nq or rough_norm(answer) in rough_norm(question)):
                failures.append(f"{category}/{difficulty}: cevap sorunun içinde: {question} => {answer}")
            answers = [str(x) for x in (row.get("answers") or [])]
            if is_date_question(question):
                for option in answers:
                    if not is_date_answer(option):
                        failures.append(f"{category}/{difficulty}: tarih sorusunda metin şık var: {question} => {option}")
            elif is_number_question(question):
                for option in answers:
                    if not is_number_answer(option):
                        failures.append(f"{category}/{difficulty}: sayı sorusunda sayısal olmayan şık var: {question} => {option}")
            mismatch = incompatible_question_answers(question, answers)
            if mismatch:
                failures.append(f"{category}/{difficulty}: {mismatch}: {question} => {answers}")

            if difficulty == "kolay":
                if len(question) > 92:
                    failures.append(f"{category}/kolay: kolay soru çok uzun: {question}")
                source = str(row.get("source", ""))
                if not source.startswith("SadeBiL curated"):
                    failures.append(f"{category}/kolay: kolay soru kürasyon dışı: {question}")

            type_counts[difficulty][question_type(question)] += 1

        for difficulty, counter in type_counts.items():
            top_type, top_count = counter.most_common(1)[0]
            total = sum(counter.values())
            if total >= 30 and top_count / total > 0.72:
                item = f"{category}/{difficulty}: tek soru kalıbı fazla baskın ({top_type} {top_count}/{total})"
                if difficulty == "kolay":
                    failures.append(item)
                else:
                    warnings.append(item)

    print("QUESTION QUALITY REPORT")
    print("\n".join(report))
    if warnings:
        print("\nWARNINGS")
        for item in warnings[:80]:
            print("- " + item)
    if failures:
        print("\nFAILURES")
        for item in failures[:120]:
            print("- " + item)
        if len(failures) > 120:
            print(f"- ... {len(failures) - 120} ek hata daha")
        return 1
    print("\nOK: Türkçe soru bankası kalite kapısından geçti.")
    return 0


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: audit_question_quality.py <SadeBilAndroidRoot>")
        return 2
    return audit(Path(sys.argv[1]))


if __name__ == "__main__":
    raise SystemExit(main())
