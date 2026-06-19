#!/usr/bin/env python3
"""
Build SadeBiL question banks from Wikidata structured data.

The important rule is not "many rows"; it is "one independent fact per row".
Every generated question is tied to a Wikidata entity/property/value pair, so
the script cannot inflate the bank by asking the same fact with different words.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


ENDPOINT = "https://query.wikidata.org/sparql"
USER_AGENT = "SadeBiLQuestionBuilder/1.0 (local Android quiz bank; contact: emrahkutay@gmail.com)"

CATEGORIES = [
    ("guncel", "Güncel", "Current"),
    ("teknoloji", "Teknoloji", "Technology"),
    ("sanat", "Sanat", "Art"),
    ("spor", "Spor", "Sports"),
    ("muzik", "Müzik", "Music"),
    ("tarih", "Tarih", "History"),
]

DIFFICULTIES_TR = ("kolay", "orta", "zor")
DIFFICULTIES_EN = ("easy", "medium", "hard")


@dataclass(frozen=True)
class Spec:
    name: str
    category: str
    difficulty: str
    kind: str
    query: str
    q_tr: str
    q_en: str
    fact_tr: str
    fact_en: str
    limit: int = 900


def entity_id(uri: str) -> str:
    return uri.rsplit("/", 1)[-1]


def clean_label(value: str) -> str:
    value = re.sub(r"\s+", " ", value or "").strip()
    value = re.sub(r"\s+\([^)]{1,32}\)$", "", value).strip()
    return value


def good_label(value: str) -> bool:
    value = clean_label(value)
    if len(value) < 2 or len(value) > 48:
        return False
    if re.fullmatch(r"[QP]\d+", value):
        return False
    if value.lower() in {"unknown", "bilinmeyen", "none", "yok"}:
        return False
    if value.count("/") > 1 or value.count("|") > 0:
        return False
    return bool(re.search(r"[A-Za-zÇĞİÖŞÜçğıöşü0-9]", value))


def year_from_wikidata(value: str) -> Optional[str]:
    match = re.match(r"^(-?\d{1,6})-", value or "")
    if not match:
        return None
    year = int(match.group(1))
    if year < 1 or year > 2026:
        return None
    return str(year)


def normalize_key(value: str) -> str:
    table = str.maketrans("çğıöşüÇĞİÖŞÜ", "cgiosuCGIOSU")
    value = value.translate(table).lower()
    value = re.sub(r"[^a-z0-9]+", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def short_hash(value: str) -> str:
    return hashlib.sha1(value.encode("utf-8")).hexdigest()[:10]


def wdq(cache_dir: Path, name: str, query: str) -> List[dict]:
    cache_dir.mkdir(parents=True, exist_ok=True)
    cache_path = cache_dir / f"{name}.json"
    if cache_path.exists():
        return json.loads(cache_path.read_text(encoding="utf-8"))

    params = urllib.parse.urlencode({"format": "json", "query": query})
    request = urllib.request.Request(
        f"{ENDPOINT}?{params}",
        headers={
            "Accept": "application/sparql-results+json",
            "User-Agent": USER_AGENT,
        },
    )
    last_error: Optional[Exception] = None
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=80) as response:
                payload = json.loads(response.read().decode("utf-8"))
            rows = payload.get("results", {}).get("bindings", [])
            cache_path.write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
            time.sleep(0.35)
            return rows
        except Exception as exc:  # pragma: no cover - network retry safety
            last_error = exc
            time.sleep(1.5 + attempt)
    raise RuntimeError(f"Wikidata query failed for {name}: {last_error}")


def label_query(body: str, langs: str, limit: int) -> str:
    return f"""
SELECT DISTINCT ?item ?itemLabel ?answer ?answerLabel ?sitelinks WHERE {{
  {body}
  ?item wikibase:sitelinks ?sitelinks.
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "{langs}". }}
}}
LIMIT {limit}
"""


def date_query(body: str, langs: str, limit: int) -> str:
    return f"""
SELECT DISTINCT ?item ?itemLabel ?date ?sitelinks WHERE {{
  {body}
  ?item wikibase:sitelinks ?sitelinks.
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "{langs}". }}
}}
LIMIT {limit}
"""


def build_specs(lang: str) -> List[Spec]:
    langs = "tr,en" if lang == "tr" else "en"

    def lq(body: str, limit: int = 900) -> str:
        return label_query(body, langs, limit)

    def dq(body: str, limit: int = 900) -> str:
        return date_query(body, langs, limit)

    current_country = """
             ?item wdt:P463 wd:Q1065.
             FILTER NOT EXISTS { ?item wdt:P576 ?dissolved. }
             FILTER NOT EXISTS { ?item wdt:P1366 ?replacedBy. }
             FILTER NOT EXISTS { ?item wdt:P31 wd:Q3024240. }
             FILTER NOT EXISTS { ?item wdt:P31 wd:Q28171280. }
             """

    def country_body(prop: str) -> str:
        return f"{current_country}\n             ?item wdt:{prop} ?answer."

    specs: List[Spec] = [
        # Güncel
        Spec("country-capital", "guncel", "kolay", "label",
             lq(country_body("P36"), 700),
             "{item} ülkesinin başkenti neresidir?",
             "What is the capital of {item}?",
             "{item} ülkesinin başkenti {answer}.",
             "The capital of {item} is {answer}."),
        Spec("country-currency", "guncel", "kolay", "label",
             lq(country_body("P38"), 700),
             "{item} ülkesinin para birimi nedir?",
             "What is the currency of {item}?",
             "{item} ülkesinin para birimi {answer}.",
             "The currency of {item} is {answer}."),
        Spec("country-continent", "guncel", "kolay", "label",
             lq(country_body("P30"), 700),
             "{item} hangi kıtadadır?",
             "Which continent is {item} in?",
             "{item}, {answer} kıtasında yer alır.",
             "{item} is in {answer}."),
        Spec("city-country", "guncel", "orta", "label",
             lq("?item wdt:P31 wd:Q515; wdt:P17 ?answer.", 900),
             "{item} hangi ülkededir?",
             "Which country is {item} in?",
             "{item}, {answer} sınırları içindedir.",
             "{item} is in {answer}."),
        Spec("org-headquarters", "guncel", "orta", "label",
             lq("?item wdt:P31 wd:Q43229; wdt:P159 ?answer.", 900),
             "{item} merkezi hangi şehirdedir?",
             "Where is {item} headquartered?",
             "{item} merkezinin bulunduğu yer {answer}.",
             "{item} is headquartered in {answer}."),
        Spec("org-inception", "guncel", "zor", "date",
             dq("?item wdt:P31 wd:Q43229; wdt:P571 ?date.", 900),
             "{item} hangi yılda kurulmuştur?",
             "In which year was {item} founded?",
             "{item} {answer} yılında kurulmuştur.",
             "{item} was founded in {answer}."),
        Spec("university-country", "guncel", "zor", "label",
             lq("?item wdt:P31 wd:Q3918; wdt:P17 ?answer.", 1100),
             "{item} hangi ülkededir?",
             "Which country is {item} in?",
             "{item}, {answer} içinde yer alır.",
             "{item} is in {answer}."),
        Spec("country-language", "guncel", "orta", "label",
             lq(country_body("P37"), 900),
             "{item} ülkesinin resmî dili nedir?",
             "What is an official language of {item}?",
             "{item} için resmî dil bilgilerinden biri {answer}.",
             "An official language of {item} is {answer}."),
        Spec("country-neighbor", "guncel", "zor", "label",
             lq(country_body("P47"), 1100),
             "{item} hangi ülkeyle sınır komşusudur?",
             "Which country borders {item}?",
             "{item} ülkesinin sınır komşularından biri {answer}.",
             "{item} borders {answer}."),
        Spec("university-inception", "guncel", "zor", "date",
             dq("?item wdt:P31 wd:Q3918; wdt:P571 ?date.", 1100),
             "{item} hangi yılda kurulmuştur?",
             "In which year was {item} founded?",
             "{item} {answer} yılında kurulmuştur.",
             "{item} was founded in {answer}."),

        # Teknoloji
        Spec("programming-language-creator", "teknoloji", "kolay", "label",
             lq("?item wdt:P31 wd:Q9143; wdt:P178 ?answer.", 1100),
             "{item} programlama dilinin geliştiricisi kimdir?",
             "Who developed the {item} programming language?",
             "{item} programlama dili {answer} tarafından geliştirilmiştir.",
             "{item} was developed by {answer}."),
        Spec("software-developer", "teknoloji", "kolay", "label",
             lq("?item wdt:P31 wd:Q7397; wdt:P178 ?answer.", 1200),
             "{item} yazılımını kim geliştirmiştir?",
             "Who developed {item}?",
             "{item} yazılımının geliştiricisi {answer}.",
             "{item} was developed by {answer}."),
        Spec("company-founder", "teknoloji", "orta", "label",
             lq("?item wdt:P31 wd:Q4830453; wdt:P112 ?answer.", 1200),
             "{item} şirketinin kurucusu kimdir?",
             "Who founded {item}?",
             "{item} kurucularından biri {answer}.",
             "{item} was founded by {answer}."),
        Spec("company-country", "teknoloji", "orta", "label",
             lq("?item wdt:P31 wd:Q4830453; wdt:P17 ?answer.", 1200),
             "{item} hangi ülkenin şirketidir?",
             "Which country is {item} associated with?",
             "{item}, {answer} merkezli bir şirkettir.",
             "{item} is associated with {answer}."),
        Spec("software-inception", "teknoloji", "zor", "date",
             dq("?item wdt:P31 wd:Q7397; wdt:P571 ?date.", 1200),
             "{item} hangi yılda ortaya çıkmıştır?",
             "In which year did {item} appear?",
             "{item} için başlangıç yılı {answer} olarak verilir.",
             "{item} dates to {answer}."),
        Spec("invention-inventor", "teknoloji", "zor", "label",
             lq("?item wdt:P31 wd:Q1183543; wdt:P61 ?answer.", 1200),
             "{item} kimin icadıdır?",
             "Who invented {item}?",
             "{item} icadı {answer} ile ilişkilidir.",
             "{item} is associated with inventor {answer}."),
        Spec("programming-language-inception", "teknoloji", "zor", "date",
             dq("?item wdt:P31 wd:Q9143; wdt:P571 ?date.", 1100),
             "{item} programlama dili hangi yılda ortaya çıkmıştır?",
             "In which year did the {item} programming language appear?",
             "{item} programlama dili {answer} yılında ortaya çıkmıştır.",
             "{item} appeared in {answer}."),
        Spec("programming-language-paradigm", "teknoloji", "orta", "label",
             lq("?item wdt:P31 wd:Q9143; wdt:P3966 ?answer.", 900),
             "{item} hangi programlama paradigmasıyla ilişkilidir?",
             "Which programming paradigm is {item} associated with?",
             "{item}, {answer} paradigmasıyla ilişkilidir.",
             "{item} is associated with {answer}."),

        # Sanat
        Spec("painting-creator", "sanat", "kolay", "label",
             lq("?item wdt:P31 wd:Q3305213; wdt:P170 ?answer.", 1400),
             "{item} adlı tablonun sanatçısı kimdir?",
             "Who created the painting {item}?",
             "{item} adlı tablonun sanatçısı {answer}.",
             "The painting {item} was created by {answer}."),
        Spec("novel-author", "sanat", "kolay", "label",
             lq("?item wdt:P31 wd:Q8261; wdt:P50 ?answer.", 1400),
             "{item} adlı romanın yazarı kimdir?",
             "Who wrote the novel {item}?",
             "{item} adlı romanın yazarı {answer}.",
             "The novel {item} was written by {answer}."),
        Spec("book-author", "sanat", "kolay", "label",
             lq("?item wdt:P31 wd:Q571; wdt:P50 ?answer.", 1400),
             "{item} adlı kitabın yazarı kimdir?",
             "Who wrote the book {item}?",
             "{item} adlı kitabın yazarı {answer}.",
             "The book {item} was written by {answer}."),
        Spec("film-director", "sanat", "kolay", "label",
             lq("?item wdt:P31 wd:Q11424; wdt:P57 ?answer.", 1400),
             "{item} filminin yönetmeni kimdir?",
             "Who directed the film {item}?",
             "{item} filminin yönetmeni {answer}.",
             "The film {item} was directed by {answer}."),
        Spec("museum-country", "sanat", "orta", "label",
             lq("?item wdt:P31 wd:Q33506; wdt:P17 ?answer.", 1000),
             "{item} hangi ülkededir?",
             "Which country is {item} in?",
             "{item}, {answer} içinde yer alan bir müzedir.",
             "{item} is a museum in {answer}."),
        Spec("artist-country", "sanat", "orta", "label",
             lq("?item wdt:P31 wd:Q5; wdt:P106/wdt:P279* wd:Q483501; wdt:P27 ?answer.", 1200),
             "{item} hangi ülkenin sanatçısıdır?",
             "Which country is artist {item} associated with?",
             "{item}, {answer} ile ilişkilendirilen bir sanatçıdır.",
             "{item} is associated with {answer}."),
        Spec("artwork-creator", "sanat", "zor", "label",
             lq("?item wdt:P31 wd:Q838948; wdt:P170 ?answer.", 1400),
             "{item} adlı eserin sanatçısı kimdir?",
             "Who created the artwork {item}?",
             "{item} adlı eserin sanatçısı {answer}.",
             "The artwork {item} was created by {answer}."),
        Spec("work-publication", "sanat", "zor", "date",
             dq("?item wdt:P31 wd:Q47461344; wdt:P577 ?date.", 1200),
             "{item} hangi yılda yayımlanmıştır?",
             "In which year was {item} published?",
             "{item} {answer} yılında yayımlanmıştır.",
             "{item} was published in {answer}."),

        # Spor
        Spec("athlete-sport", "spor", "kolay", "label",
             lq("?item wdt:P31 wd:Q5; wdt:P641 ?answer.", 1500),
             "{item} hangi sporla bilinir?",
             "Which sport is {item} known for?",
             "{item}, {answer} dalında bilinir.",
             "{item} is known for {answer}."),
        Spec("sports-club-sport", "spor", "kolay", "label",
             lq("?item wdt:P31 wd:Q847017; wdt:P641 ?answer.", 1200),
             "{item} hangi sporla ilişkilidir?",
             "Which sport is {item} associated with?",
             "{item}, {answer} dalıyla ilişkilidir.",
             "{item} is associated with {answer}."),
        Spec("sports-club-country-easy", "spor", "kolay", "label",
             lq("?item wdt:P31 wd:Q847017; wdt:P17 ?answer.", 700),
             "{item} hangi ülkenin kulübüdür?",
             "Which country is {item} from?",
             "{item}, {answer} kulübüdür.",
             "{item} is from {answer}."),
        Spec("athlete-country", "spor", "kolay", "label",
             lq("?item wdt:P31 wd:Q5; wdt:P641 ?sport; wdt:P27 ?answer.", 1400),
             "{item} hangi ülkenin sporcusudur?",
             "Which country is athlete {item} associated with?",
             "{item}, {answer} ile ilişkilendirilen bir sporcudur.",
             "{item} is associated with {answer}."),
        Spec("athlete-birthplace", "spor", "kolay", "label",
             lq("?item wdt:P31 wd:Q5; wdt:P641 ?sport; wdt:P19 ?answer.", 1400),
             "{item} nerede doğmuştur?",
             "Where was athlete {item} born?",
             "{item} için doğum yeri {answer} olarak verilir.",
             "{item} was born in {answer}."),
        Spec("athlete-birth-year", "spor", "kolay", "date",
             dq("?item wdt:P31 wd:Q5; wdt:P641 ?sport; wdt:P569 ?date.", 1400),
             "{item} hangi yılda doğmuştur?",
             "In which year was athlete {item} born?",
             "{item} {answer} yılında doğmuştur.",
             "{item} was born in {answer}."),
        Spec("stadium-country-easy", "spor", "kolay", "label",
             lq("?item wdt:P31 wd:Q483110; wdt:P17 ?answer.", 1000),
             "{item} hangi ülkededir?",
             "Which country is {item} in?",
             "{item}, {answer} içinde bulunan bir stadyumdur.",
             "{item} is a stadium in {answer}."),
        Spec("sports-club-country", "spor", "orta", "label",
             lq("?item wdt:P31 wd:Q847017; wdt:P17 ?answer.", 1400),
             "{item} hangi ülkenin kulübüdür?",
             "Which country is {item} from?",
             "{item}, {answer} kulübüdür.",
             "{item} is from {answer}."),
        Spec("athlete-sport-medium", "spor", "orta", "label",
             lq("?item wdt:P31 wd:Q5; wdt:P641 ?answer.", 1400),
             "{item} hangi sporla tanınır?",
             "Which sport is {item} known for?",
             "{item}, {answer} dalıyla tanınır.",
             "{item} is known for {answer}."),
        Spec("athlete-birthplace-medium", "spor", "orta", "label",
             lq("?item wdt:P31 wd:Q5; wdt:P641 ?sport; wdt:P19 ?answer.", 1400),
             "{item} nerede doğmuştur?",
             "Where was athlete {item} born?",
             "{item} için doğum yeri {answer}.",
             "{item} was born in {answer}."),
        Spec("stadium-location", "spor", "orta", "label",
             lq("?item wdt:P31 wd:Q483110; wdt:P131 ?answer.", 1200),
             "{item} hangi şehirde bulunur?",
             "Which city is {item} in?",
             "{item}, {answer} içinde bulunur.",
             "{item} is in {answer}."),
        Spec("sport-event-sport", "spor", "zor", "label",
             lq("?item wdt:P31 wd:Q16510064; wdt:P641 ?answer.", 1400),
             "{item} hangi sporla ilgilidir?",
             "Which sport is {item} part of?",
             "{item}, {answer} dalında düzenlenen bir etkinliktir.",
             "{item} is an event in {answer}."),
        Spec("sports-club-inception", "spor", "zor", "date",
             dq("?item wdt:P31 wd:Q847017; wdt:P571 ?date.", 1200),
             "{item} hangi yılda kurulmuştur?",
             "In which year was {item} founded?",
             "{item} {answer} yılında kurulmuştur.",
             "{item} was founded in {answer}."),
        Spec("stadium-country", "spor", "zor", "label",
             lq("?item wdt:P31 wd:Q483110; wdt:P17 ?answer.", 1200),
             "{item} hangi ülkededir?",
             "Which country is {item} in?",
             "{item}, {answer} içinde bulunan bir stadyumdur.",
             "{item} is a stadium in {answer}."),
        Spec("olympic-event-year", "spor", "zor", "date",
             dq("?item wdt:P31 wd:Q159821; wdt:P585 ?date.", 900),
             "{item} hangi yılda düzenlenmiştir?",
             "In which year was {item} held?",
             "{item} {answer} yılında düzenlenmiştir.",
             "{item} was held in {answer}."),
        Spec("athlete-birth-year-hard", "spor", "zor", "date",
             dq("?item wdt:P31 wd:Q5; wdt:P641 ?sport; wdt:P569 ?date.", 1400),
             "{item} hangi yılda doğmuştur?",
             "In which year was athlete {item} born?",
             "{item} {answer} yılında doğmuştur.",
             "{item} was born in {answer}."),

        # Müzik
        Spec("musician-instrument", "muzik", "kolay", "label",
             lq("?item wdt:P31 wd:Q5; wdt:P106/wdt:P279* wd:Q639669; wdt:P1303 ?answer.", 1400),
             "{item} hangi enstrümanla bilinir?",
             "Which instrument is {item} known for?",
             "{item}, {answer} ile bilinir.",
             "{item} is known for {answer}."),
        Spec("song-performer", "muzik", "kolay", "label",
             lq("?item wdt:P31 wd:Q7366; wdt:P175 ?answer.", 1500),
             "{item} şarkısını kim seslendirmiştir?",
             "Who performed the song {item}?",
             "{item} şarkısı {answer} tarafından seslendirilmiştir.",
             "The song {item} was performed by {answer}."),
        Spec("album-performer", "muzik", "orta", "label",
             lq("?item wdt:P31 wd:Q482994; wdt:P175 ?answer.", 1500),
             "{item} albümü hangi sanatçıya aittir?",
             "Which artist is the album {item} by?",
             "{item} albümü {answer} ile ilişkilidir.",
             "The album {item} is by {answer}."),
        Spec("music-group-country", "muzik", "orta", "label",
             lq("?item wdt:P31 wd:Q215380; wdt:P495 ?answer.", 1200),
             "{item} müzik grubu hangi ülkedendir?",
             "Which country is the music group {item} from?",
             "{item}, {answer} kökenli bir müzik grubudur.",
             "{item} is from {answer}."),
        Spec("song-composer", "muzik", "zor", "label",
             lq("?item wdt:P31 wd:Q7366; wdt:P86 ?answer.", 1500),
             "{item} adlı eserin bestecisi kimdir?",
             "Who composed {item}?",
             "{item} için besteci bilgisi {answer}.",
             "{item} was composed by {answer}."),
        Spec("album-year", "muzik", "zor", "date",
             dq("?item wdt:P31 wd:Q482994; wdt:P577 ?date.", 1500),
             "{item} albümü hangi yılda yayımlanmıştır?",
             "In which year was the album {item} released?",
             "{item} albümü {answer} yılında yayımlanmıştır.",
             "The album {item} was released in {answer}."),

        # Tarih
        Spec("battle-year", "tarih", "kolay", "date",
             dq("?item wdt:P31 wd:Q178561; wdt:P585 ?date.", 1400),
             "{item} hangi yılda gerçekleşmiştir?",
             "In which year did {item} happen?",
             "{item} {answer} yılında gerçekleşmiştir.",
             "{item} happened in {answer}."),
        Spec("treaty-year", "tarih", "kolay", "date",
             dq("?item wdt:P31 wd:Q131569; wdt:P585 ?date.", 1200),
             "{item} hangi yılda imzalanmıştır?",
             "In which year was {item} signed?",
             "{item} {answer} yılında imzalanmıştır.",
             "{item} was signed in {answer}."),
        Spec("war-start", "tarih", "orta", "date",
             dq("?item wdt:P31 wd:Q198; wdt:P580 ?date.", 1200),
             "{item} hangi yılda başlamıştır?",
             "In which year did {item} begin?",
             "{item} {answer} yılında başlamıştır.",
             "{item} began in {answer}."),
        Spec("arch-site-country", "tarih", "orta", "label",
             lq("?item wdt:P31 wd:Q839954; wdt:P17 ?answer.", 1200),
             "{item} hangi ülkededir?",
             "Which country is {item} in?",
             "{item}, {answer} içinde yer alan bir tarihî alandır.",
             "{item} is a historical site in {answer}."),
        Spec("historical-person-country", "tarih", "zor", "label",
             lq("?item wdt:P31 wd:Q5; wdt:P106 wd:Q82955; wdt:P27 ?answer.", 1200),
             "{item} hangi ülkeyle ilişkilidir?",
             "Which country is {item} associated with?",
             "{item}, {answer} ile ilişkilendirilen tarihî bir kişidir.",
             "{item} is associated with {answer}."),
        Spec("historical-person-birth", "tarih", "zor", "date",
             dq("?item wdt:P31 wd:Q5; wdt:P106 wd:Q82955; wdt:P569 ?date.", 1200),
             "{item} hangi yılda doğmuştur?",
             "In which year was {item} born?",
             "{item} {answer} yılında doğmuştur.",
             "{item} was born in {answer}."),
    ]
    return specs


def render(template: str, item: str, answer: str) -> str:
    out = template.replace("{item}", item).replace("{answer}", answer)
    return re.sub(r"\s+", " ", out).strip()


def make_label_rows(spec: Spec, bindings: Sequence[dict]) -> List[dict]:
    rows: List[dict] = []
    seen = set()
    for b in bindings:
        item = clean_label(b.get("itemLabel", {}).get("value", ""))
        answer = clean_label(b.get("answerLabel", {}).get("value", ""))
        if not good_label(item) or not good_label(answer):
            continue
        item_qid = entity_id(b.get("item", {}).get("value", ""))
        answer_qid = entity_id(b.get("answer", {}).get("value", ""))
        key = (item_qid, answer_qid, spec.name)
        if key in seen:
            continue
        seen.add(key)
        rows.append({
            "item": item,
            "answer": answer,
            "item_id": item_qid,
            "answer_id": answer_qid,
        })
    return rows


def make_date_rows(spec: Spec, bindings: Sequence[dict]) -> List[dict]:
    rows: List[dict] = []
    seen = set()
    for b in bindings:
        item = clean_label(b.get("itemLabel", {}).get("value", ""))
        year = year_from_wikidata(b.get("date", {}).get("value", ""))
        if not good_label(item) or not year:
            continue
        item_qid = entity_id(b.get("item", {}).get("value", ""))
        key = (item_qid, year, spec.name)
        if key in seen:
            continue
        seen.add(key)
        rows.append({
            "item": item,
            "answer": year,
            "item_id": item_qid,
            "answer_id": year,
        })
    return rows


def choose_wrong_labels(correct: str, pool: Sequence[str], seed: str) -> Optional[List[str]]:
    rng = random.Random(short_hash(seed))
    candidates = [p for p in pool if p != correct and normalize_key(p) != normalize_key(correct)]
    rng.shuffle(candidates)
    picked: List[str] = []
    for candidate in candidates:
        if candidate not in picked:
            picked.append(candidate)
        if len(picked) == 3:
            return picked
    return None


def choose_wrong_years(correct: str, pool: Sequence[str], seed: str) -> Optional[List[str]]:
    year = int(correct)
    rng = random.Random(short_hash(seed))
    near = [str(y) for y in range(max(1, year - 35), min(2026, year + 35) + 1) if y != year]
    candidates = list(dict.fromkeys(list(pool) + near))
    candidates = [c for c in candidates if c != correct and c.isdigit()]
    rng.shuffle(candidates)
    return candidates[:3] if len(candidates) >= 3 else None


def balanced_spec_order(rows: Sequence[Tuple[Spec, dict]], rng: random.Random) -> List[Tuple[Spec, dict]]:
    """Interleave question themes so one abundant Wikidata pattern cannot dominate a bank."""
    buckets: Dict[str, List[Tuple[Spec, dict]]] = {}
    for spec, row in rows:
        buckets.setdefault(spec.name, []).append((spec, row))
    for bucket in buckets.values():
        rng.shuffle(bucket)
    names = list(buckets.keys())
    rng.shuffle(names)
    ordered: List[Tuple[Spec, dict]] = []
    while names:
        rng.shuffle(names)
        next_names: List[str] = []
        for name in names:
            bucket = buckets.get(name, [])
            if bucket:
                ordered.append(bucket.pop())
            if bucket:
                next_names.append(name)
        names = next_names
    return ordered


def assemble_questions(lang: str, spec_rows: List[Tuple[Spec, List[dict]]], target_per_difficulty: int) -> Tuple[Dict[str, List[dict]], List[str]]:
    rng = random.Random(413024 if lang == "tr" else 240314)
    by_bucket: Dict[str, List[Tuple[Spec, dict]]] = {}
    answer_pools: Dict[str, List[str]] = {}
    warnings: List[str] = []

    for spec, rows in spec_rows:
        bucket = f"{spec.category}|{spec.difficulty}"
        by_bucket.setdefault(bucket, [])
        answer_pools.setdefault(spec.name, [])
        for row in rows:
            by_bucket[bucket].append((spec, row))
            answer_pools[spec.name].append(row["answer"])

    result: Dict[str, List[dict]] = {key: [] for key, _, _ in CATEGORIES}
    used_questions = set()
    used_fact_ids = set()

    for cat_key, cat_tr, cat_en in CATEGORIES:
        for diff in (DIFFICULTIES_TR if lang == "tr" else DIFFICULTIES_EN):
            source_diff = diff if lang == "tr" else {"easy": "kolay", "medium": "orta", "hard": "zor"}[diff]
            bucket = f"{cat_key}|{source_diff}"
            rows = balanced_spec_order(by_bucket.get(bucket, []), rng)
            made = 0
            made_by_spec: Dict[str, int] = {}
            for spec, row in rows:
                if made >= target_per_difficulty:
                    break
                category_name = cat_tr if lang == "tr" else cat_en
                question = render(spec.q_tr if lang == "tr" else spec.q_en, row["item"], row["answer"])
                fact = render(spec.fact_tr if lang == "tr" else spec.fact_en, row["item"], row["answer"])
                if len(question) < 10 or len(question) > 112:
                    continue
                item_key = normalize_key(row["item"])
                answer_key = normalize_key(row["answer"])
                question_key = normalize_key(question)
                if len(answer_key) > 3 and (answer_key in question_key or answer_key in item_key):
                    continue
                qkey = normalize_key(question)
                fact_id = f"{spec.name}:{row['item_id']}:{row['answer_id']}"
                if qkey in used_questions or fact_id in used_fact_ids:
                    continue
                if spec.kind == "date":
                    wrongs = choose_wrong_years(row["answer"], answer_pools.get(spec.name, []), fact_id)
                else:
                    wrongs = choose_wrong_labels(row["answer"], answer_pools.get(spec.name, []), fact_id)
                if not wrongs:
                    continue
                answers = [row["answer"]] + wrongs
                rng.shuffle(answers)
                correct = answers.index(row["answer"])
                qid = f"{lang}-{cat_key}-{source_diff}-{spec.name}-{short_hash(fact_id)}"
                result[cat_key].append({
                    "id": qid,
                    "category": category_name,
                    "difficulty": diff,
                    "question": question,
                    "answers": answers,
                    "correct": correct,
                    "fact": fact,
                    "source": "Wikidata CC0",
                    "source_id": fact_id,
                })
                used_questions.add(qkey)
                used_fact_ids.add(fact_id)
                made += 1
                made_by_spec[spec.name] = made_by_spec.get(spec.name, 0) + 1
            if made < target_per_difficulty:
                warnings.append(f"{lang}/{cat_key}/{diff}: {made}/{target_per_difficulty} gerçek soru üretildi.")
            for spec_name, count in sorted(made_by_spec.items()):
                if count > max(180, target_per_difficulty // 3):
                    warnings.append(f"{lang}/{cat_key}/{diff}: {spec_name} teması {count} kez geldi; tema çeşitliliği düşük olabilir.")
    return result, warnings


def write_bank(path: Path, questions: Sequence[dict]) -> None:
    path.write_text(json.dumps(list(questions), ensure_ascii=False, indent=2), encoding="utf-8")


def build_mix(category_banks: Dict[str, List[dict]], per_category_total: int, seed: int) -> List[dict]:
    rng = random.Random(seed)
    mixed: List[dict] = []
    per_cat = max(1, per_category_total // len(CATEGORIES))
    for key, _, _ in CATEGORIES:
        items = list(category_banks[key])
        rng.shuffle(items)
        mixed.extend(items[:per_cat])
    rng.shuffle(mixed)
    return mixed[:per_category_total]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--cache-dir", default=str(Path.home() / "AppData" / "Local" / "Temp" / "sadebil_wikidata_cache"))
    parser.add_argument("--asset-dir", default="", help="Output directory for generated question JSON files.")
    parser.add_argument("--target-per-difficulty", type=int, default=500)
    parser.add_argument("--mix-size", type=int, default=1500)
    parser.add_argument("--langs", default="tr,en", help="Comma-separated language banks to generate: tr,en")
    parser.add_argument("--skip-network", action="store_true")
    args = parser.parse_args()

    root = Path(args.root)
    asset_dir = Path(args.asset_dir) if args.asset_dir else root / "app" / "src" / "main" / "assets"
    cache_dir = Path(args.cache_dir)
    asset_dir.mkdir(parents=True, exist_ok=True)

    all_warnings: List[str] = []
    requested_langs = [part.strip() for part in args.langs.split(",") if part.strip()]
    for lang in requested_langs:
        spec_rows: List[Tuple[Spec, List[dict]]] = []
        for spec in build_specs(lang):
            cache_name = f"{lang}_{spec.name}_{short_hash(spec.query)}"
            try:
                cache_path = cache_dir / f"{cache_name}.json"
                if args.skip_network:
                    if cache_path.exists():
                        rows = json.loads(cache_path.read_text(encoding="utf-8"))
                    else:
                        rows = []
                        all_warnings.append(f"{lang}/{spec.category}/{spec.difficulty}/{spec.name}: cache yok, ağ atlandı.")
                else:
                    rows = wdq(cache_dir, cache_name, spec.query)
            except Exception as exc:
                print(f"{lang}/{spec.category}/{spec.difficulty}/{spec.name}: kaynak çekilemedi: {exc}")
                all_warnings.append(f"{lang}/{spec.category}/{spec.difficulty}/{spec.name}: kaynak çekilemedi.")
                rows = []
            parsed = make_date_rows(spec, rows) if spec.kind == "date" else make_label_rows(spec, rows)
            spec_rows.append((spec, parsed))
            print(f"{lang}/{spec.category}/{spec.difficulty}/{spec.name}: {len(parsed)} kaynak bilgi")
        category_banks, warnings = assemble_questions(lang, spec_rows, args.target_per_difficulty)
        all_warnings.extend(warnings)
        prefix = f"questions_{lang}"
        for cat_key, _, _ in CATEGORIES:
            write_bank(asset_dir / f"{prefix}_{cat_key}.json", category_banks[cat_key])
        mix = build_mix(category_banks, args.mix_size, 20260518 if lang == "tr" else 20260519)
        write_bank(asset_dir / f"{prefix}_mix.json", mix)
        write_bank(asset_dir / f"{prefix}.json", mix)
        total = sum(len(v) for v in category_banks.values())
        print(f"{lang}: {total} kategori sorusu, {len(mix)} mix sorusu yazıldı.")

    if all_warnings:
        print("\nUYARILAR")
        for warning in all_warnings:
            print(f"- {warning}")
    return 0 if not all_warnings else 2


if __name__ == "__main__":
    raise SystemExit(main())
