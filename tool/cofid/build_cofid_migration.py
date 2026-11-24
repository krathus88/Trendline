"""Turns the published CoFID spreadsheet into a Supabase migration.

CoFID is McCance and Widdowson's Composition of Foods Integrated Dataset,
published by the UK government under the Open Government Licence v3.0:
https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid

Usage (Python 3.10+, standard library only):

    python tool/cofid/build_cofid_migration.py <cofid.xlsx> <output.sql>

The output replaces every row of public.reference_foods, so re-running it on
a new CoFID edition and adding the result as a new migration is all an update
needs. Never edit the generated file by hand.

What it does with the data:
  * values are per 100 g edible portion; alcoholic drinks (group Q) are
    per 100 ml, so they're converted with their specific gravity;
  * "Tr" (trace) becomes 0 and "N" (present, amount unknown) becomes null;
  * foods without kcal or carbohydrate (mostly spices) take every value
    from their USDA match in usda_nutrients.csv (USDA carbohydrate includes
    fibre, so fibre is taken off), or are left out if there's none; foods
    without protein or fat are left out;
  * fibre is AOAC fibre (what UK labels use); where CoFID has none it falls
    back to NSP (Englyst) fibre scaled to AOAC (x 24/18, per SACN); then
    to USDA FoodData Central, matched by hand in usda_fibre.csv and scaled
    to the food's dry matter; and else null (CoFID's "N": present, amount
    unknown). fibre_source records which. Every food with no CoFID fibre
    must have a reviewed row in usda_fibre.csv;
  * salt (g) = sodium (mg) x 2.5 / 1000;
  * CoFID gives carbohydrate and sugars as monosaccharide equivalents (so
    100 g of table sugar reads as 105 g). They're converted to actual
    weights, as UK labels declare them, with the user guide's factors. Energy
    (kcal) is CoFID's own figure and needs no change;
  * a friendlier display name is derived from CoFID's terse one
    ("Rice, white, basmati, raw" becomes "White rice, basmati, raw").
"""

from __future__ import annotations

import csv
import dataclasses
import os
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from dataclasses import dataclass

_NS = {
    "m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
}
_REL = "{%s}id" % _NS["r"]

# Sheet names and the CoFID column headings used (matched by heading, not
# position, so a reordered edition still loads or fails loudly).
_PROXIMATES = "1.3 Proximates"
_INORGANICS = "1.4 Inorganics"
_FACTORS = "1.2 Factors"

MAX_NAME = 200

# ---------------------------------------------------------------------------
# Reading the spreadsheet (xlsx is a zip of XML files)
# ---------------------------------------------------------------------------


def read_sheets(path: str, names: list[str]) -> dict[str, list[dict[str, str]]]:
    """The named sheets as lists of rows keyed by their heading row."""
    with zipfile.ZipFile(path) as z:
        shared = _shared_strings(z)
        workbook = ET.fromstring(z.read("xl/workbook.xml"))
        rels = {
            r.get("Id"): r.get("Target")
            for r in ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
        }
        targets = {
            s.get("name").strip(): rels[s.get(_REL)]
            for s in workbook.find("m:sheets", _NS)
        }
        out = {}
        for name in names:
            if name not in targets:
                raise SystemExit(f"Sheet {name!r} not found; is this CoFID?")
            target = targets[name].lstrip("/")
            if not target.startswith("xl/"):
                target = "xl/" + target
            out[name] = _keyed_rows(_cells(z.read(target), shared))
        return out


def _shared_strings(z: zipfile.ZipFile) -> list[str]:
    try:
        root = ET.fromstring(z.read("xl/sharedStrings.xml"))
    except KeyError:
        return []
    return [
        "".join(t.text or "" for t in si.iter("{%s}t" % _NS["m"]))
        for si in root.findall("m:si", _NS)
    ]


def _cells(xml: bytes, shared: list[str]) -> list[dict[str, str]]:
    rows = []
    for row in ET.fromstring(xml).iter("{%s}row" % _NS["m"]):
        cells = {}
        for c in row.findall("m:c", _NS):
            col = re.match(r"[A-Z]+", c.get("r")).group()
            kind = c.get("t")
            if kind == "inlineStr":
                value = "".join(t.text or "" for t in c.iter("{%s}t" % _NS["m"]))
            else:
                v = c.find("m:v", _NS)
                if v is None or v.text is None:
                    continue
                value = shared[int(v.text)] if kind == "s" else v.text
            cells[col] = value
        rows.append(cells)
    return rows


def _keyed_rows(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    """Rows keyed by heading. Data rows are the ones with a food code."""
    header = {col: text.strip() for col, text in rows[0].items()}
    keyed = []
    for row in rows[1:]:
        code = row.get("A", "").strip()
        if not re.fullmatch(r"\d{2}-\d{3,4}", code):
            continue  # the two extra heading rows (codes and long names)
        cells = {header[c]: v.strip() for c, v in row.items() if c in header}
        # Some sheets leave the code column's heading blank.
        cells["Food Code"] = code
        keyed.append(cells)
    return keyed


# ---------------------------------------------------------------------------
# Turning CoFID rows into reference foods
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ReferenceFood:
    cofid_code: str
    name: str
    display_name: str
    food_group: str
    kcal: float
    protein: float
    carbs: float
    fat: float
    fibre: float | None
    # Where the fibre figure comes from: CoFID's AOAC fibre ('aoac'), its NSP
    # fibre scaled to AOAC ('nsp') or USDA FoodData Central ('usda').
    fibre_source: str | None
    sugar: float | None
    salt: float | None
    edible_proportion: float | None
    # 'cofid', or 'usda' for the few foods CoFID gives no energy figure (most
    # spices), whose values all come from USDA FoodData Central.
    nutrients_source: str = "cofid"


class Unknown(Exception):
    """CoFID's "N": present, but the amount isn't known."""


def parse_value(raw: str | None) -> float:
    """A CoFID value: a number, "Tr" (trace, so 0) or "N" (raises Unknown)."""
    if raw is None or raw.strip() in ("", "N"):
        raise Unknown()
    text = raw.strip()
    if text == "Tr":
        return 0.0
    # Estimated values are sometimes bracketed, e.g. "(0.4)".
    text = text.removeprefix("(").removesuffix(")")
    try:
        value = float(text)
    except ValueError:
        raise SystemExit(f"Unexpected CoFID value {raw!r}") from None
    if value < 0:
        raise SystemExit(f"Negative CoFID value {raw!r}")
    return value


def _optional(raw: str | None) -> float | None:
    try:
        return parse_value(raw)
    except Unknown:
        return None


def to_reference_food(
    prox: dict[str, str],
    sodium_mg: str | None,
    edible: str | None,
    specific_gravity: str | None = None,
    usda: dict[str, str] | None = None,
) -> ReferenceFood | None:
    """One CoFID food, or None if it can't be used.

    [usda] is the food's reviewed row from usda_fibre.csv, used only when
    CoFID has no fibre figure.
    """
    group = prox.get("Group", "")
    name = " ".join(prox.get("Food Name", "").split())
    if not name or len(name) > MAX_NAME:
        return None
    try:
        kcal = parse_value(prox.get("Energy (kcal) (kcal)"))
        protein = parse_value(prox.get("Protein (g)"))
        fat = parse_value(prox.get("Fat (g)"))
        carbs = parse_value(prox.get("Carbohydrate (g)"))
    except Unknown:
        return None
    if kcal > 900 or protein > 100 or fat > 100:
        return None

    carbs, sugar = carbohydrate_by_weight(prox, carbs)
    water = _optional(prox.get("Water (g)"))
    # Estimated fibre never goes past the room the rest of the food leaves
    # (agar, nearly all fibre, would otherwise pass 100 g).
    room = 100.0 - (water or 0) - protein - fat - carbs
    fibre = _optional(prox.get("AOAC fibre (g)"))
    fibre_source = None if fibre is None else "aoac"
    if fibre is None:
        nsp = _optional(prox.get("NSP (g)"))
        if nsp is not None:
            fibre = max(nsp, min(nsp * NSP_TO_AOAC, room))
            fibre_source = "nsp"
    if fibre is None and usda is not None and usda.get("decision") == "usda":
        fibre = usda_fibre(usda, water)
        fibre = max(0.0, min(fibre, room)) if water is not None else fibre
        fibre_source = "usda"
    sodium = _optional(sodium_mg)
    salt = None if sodium is None else sodium * 2.5 / 1000

    # Alcoholic drinks are given per 100 ml: convert to per 100 g with the
    # drink's specific gravity (wine 1.00, spirits 0.95). Their alcohol
    # (7 kcal/g) is in the energy but isn't a macro, so their kcal is more
    # than protein, carbs and fat account for.
    if group.startswith("Q"):
        factor = 1 / _gravity(specific_gravity)
        kcal, protein, fat, carbs = (v * factor for v in (kcal, protein, fat, carbs))
        fibre = None if fibre is None else fibre * factor
        sugar = None if sugar is None else sugar * factor
        salt = None if salt is None else salt * factor
    salt = None if salt is None else round(salt, 2)

    # Fit the app's limits: carbohydrate at most 100 g, all macros at most
    # 105 g, sugar at most the carbohydrate. After the conversion to weight
    # only a few dried herbs (very high fibre) still need trimming.
    carbs = min(carbs, 100.0)
    carbs = max(0.0, min(carbs, 105.0 - protein - fat - (fibre or 0)))
    if protein + fat + (fibre or 0) > 105:
        return None
    if sugar is not None:
        sugar = min(sugar, carbs)
    if salt is not None and salt > 100:
        return None

    proportion = _optional(edible)
    if proportion is not None and not 0 < proportion <= 1:
        proportion = None

    return ReferenceFood(
        cofid_code=prox["Food Code"],
        name=name,
        display_name=display_name(name),
        food_group=group,
        kcal=round(kcal, 1),
        protein=round(protein, 1),
        carbs=_round_down(carbs),
        fat=round(fat, 1),
        fibre=None if fibre is None else round(fibre, 1),
        fibre_source=fibre_source,
        sugar=None if sugar is None else _round_down(sugar),
        salt=salt,
        edible_proportion=proportion,
    )


def usda_fibre(row: dict[str, str], cofid_water: float | None) -> float:
    """USDA's fibre, scaled to the CoFID food's dry matter, so a raw value
    fits a boiled food (or a dried one a soaked food)."""
    fibre = float(row["usda_fibre_g"])
    usda_water = row.get("usda_water_g")
    if cofid_water is None or not usda_water:
        return fibre
    return fibre * (100 - cofid_water) / (100 - float(usda_water))


def _gravity(raw: str | None) -> float:
    """A drink's specific gravity; 1.0 where CoFID gives none or an
    impossible one (it lists shandy at 0.50)."""
    try:
        value = float(raw) if raw else 1.0
    except ValueError:
        return 1.0
    return value if 0.9 <= value <= 1.2 else 1.0


# SACN (Carbohydrates and Health, 2015): the old 18 g/day NSP guideline is
# equivalent to about 24 g/day AOAC fibre. CoFID agrees: across the 784
# foods with both figures, NSP is a median 0.77 of AOAC.
NSP_TO_AOAC = 24 / 18

# CoFID user guide: carbohydrate is in monosaccharide equivalents; for the
# actual weight (what UK labels declare) divide starch by 1.10, sucrose and
# lactose (and so maltose, also a disaccharide) by 1.05, monosaccharides as
# given, and total carbohydrate by 1.05 when its parts aren't known.
_STARCH = 1.10
_DISACCHARIDE = 1.05
_MONO = ("Glucose (g)", "Galactose (g)", "Fructose (g)")
_DI = ("Sucrose (g)", "Maltose (g)", "Lactose (g)")


def carbohydrate_by_weight(
    prox: dict[str, str], total_me: float
) -> tuple[float, float | None]:
    """Carbohydrate and total sugars as actual weights, from CoFID's
    monosaccharide equivalents."""
    sugars_me = _optional(prox.get("Total sugars (g)"))
    parts = [_optional(prox.get(c)) for c in (*_MONO, *_DI)]
    if all(p is not None for p in parts):
        sugars = sum(parts[:3]) + sum(parts[3:]) / _DISACCHARIDE
    elif sugars_me is not None:
        sugars = sugars_me / _DISACCHARIDE
    else:
        sugars = None

    starch = _optional(prox.get("Starch (g)"))
    if starch is not None and sugars_me is not None and sugars is not None:
        # What's left is oligosaccharides and maltodextrins: glucose chains,
        # converted like starch.
        rest = max(0.0, total_me - starch - sugars_me)
        total = starch / _STARCH + sugars + rest / _STARCH
    else:
        total = total_me / _DISACCHARIDE
    if sugars is not None:
        sugars = min(sugars, total)
    return total, sugars


def _round_down(v: float) -> float:
    """Rounds to 0.1, downwards, so a trimmed value stays within its limit."""
    return int(round(v * 10, 6)) / 10


# ---------------------------------------------------------------------------
# Display names
# ---------------------------------------------------------------------------

# Heads where CoFID's second part is a variety that reads better in front:
# "Rice, white, raw" -> "White rice, raw".
_VARIETY_FIRST = {
    "Beans", "Biscuits", "Bread", "Burger", "Cabbage", "Cake", "Casserole",
    "Cheese", "Curry", "Eggs", "Flour", "Kidney", "Liver", "Milk", "Mushrooms",
    "Oil", "Pasta", "Pastry", "Pie", "Pudding", "Rice", "Salad", "Sauce",
    "Sausages", "Soup", "Yogurt",
}

# Heads where the second part is a cut, which reads better after:
# "Beef, sirloin steak, grilled" -> "Beef sirloin steak, grilled".
_CUT_AFTER = {"Beef", "Chicken", "Lamb", "Pork", "Turkey"}

# Second parts that describe the state or how it's prepared, not a variety
# or cut. Names with one of these second are left as they are.
_NOT_A_VARIETY = re.compile(
    r"^(?:raw|cooked|boiled|baked|fried|grilled|roasted|stewed|steamed|dried|"
    r"canned|frozen|fresh|whole|average|flesh|meat|skin|fat|lean|"
    r"homemade|retail|ready|instant|plain|portions|corn-fed|dark meat|"
    r"light meat|weighed|without|with|in)\b",
    re.IGNORECASE,
)

_PULSE = re.compile(r"\b(beans?|peas)$", re.IGNORECASE)


def _names_itself(head: str, second: str) -> bool:
    """Whether the variety already names the food on its own."""
    if head == "Beans" and _PULSE.search(second):
        return True
    last = second.split()[-1].lower()
    return last in (head.lower(), head.lower().removesuffix("s"))

_WORD_FIXES = [
    (re.compile(r"\bchick peas\b", re.IGNORECASE), "chickpeas"),
    (re.compile(r"\bchick pea\b", re.IGNORECASE), "chickpea"),
]


def display_name(name: str) -> str:
    """A friendlier name for search results, derived from CoFID's."""
    parts = [p.strip() for p in name.split(",")]
    head = parts[0]
    if len(parts) > 1 and parts[1] and not _NOT_A_VARIETY.match(parts[1]):
        second = parts[1]
        if head in _VARIETY_FIRST:
            if _names_itself(head, second):
                # "Beans, chick peas" -> "Chick peas";
                # "Pudding, Eve's pudding" -> "Eve's pudding".
                merged = second
            else:
                merged = f"{second} {head.lower()}"
            parts = [_capitalise(merged), *parts[2:]]
        elif head in _CUT_AFTER:
            if second[:1].isupper():  # "Lamb, New Zealand" -> "New Zealand lamb"
                merged = f"{second} {head.lower()}"
            else:
                merged = f"{head} {second}"
            parts = [merged, *parts[2:]]
    result = ", ".join(parts)
    for pattern, replacement in _WORD_FIXES:
        result = pattern.sub(
            lambda m, r=replacement: _capitalise(r) if m.group(0)[0].isupper() else r,
            result,
        )
    return result[:MAX_NAME]


def _capitalise(s: str) -> str:
    return s[:1].upper() + s[1:]


# ---------------------------------------------------------------------------
# SQL output
# ---------------------------------------------------------------------------


def sql_literal(value: object) -> str:
    """A SQL literal. Text is single-quoted with quotes doubled; nothing from
    the spreadsheet is ever placed in SQL any other way."""
    if value is None:
        return "null"
    if isinstance(value, float):
        return repr(round(value, 2))
    if isinstance(value, str):
        if any(ord(ch) < 32 for ch in value) or "\\" in value:
            raise SystemExit(f"Unexpected character in {value!r}")
        return "'" + value.replace("'", "''") + "'"
    raise TypeError(value)


_COLUMNS = (
    "cofid_code, name, display_name, food_group, kcal_100g, protein_100g, "
    "carbs_100g, fat_100g, fibre_100g, fibre_source, sugar_100g, salt_100g, "
    "edible_proportion, nutrients_source"
)


def to_sql(foods: list[ReferenceFood], source: str) -> str:
    rows = ",\n".join(
        "  ("
        + ", ".join(
            sql_literal(v)
            for v in (
                f.cofid_code, f.name, f.display_name, f.food_group, f.kcal,
                f.protein, f.carbs, f.fat, f.fibre, f.fibre_source, f.sugar,
                f.salt, f.edible_proportion, f.nutrients_source,
            )
        )
        + ")"
        for f in foods
    )
    return (
        "-- Generated by tool/cofid/build_cofid_migration.py from\n"
        f"-- {source}, tool/cofid/usda_fibre.csv and\n"
        "-- tool/cofid/usda_nutrients.csv. Do not edit by hand.\n"
        "--\n"
        "-- Contains public sector information licensed under the Open\n"
        "-- Government Licence v3.0 (McCance and Widdowson's Composition of\n"
        "-- Foods Integrated Dataset).\n"
        "--\n"
        "-- Fibre marked 'usda', and every value of foods whose\n"
        "-- nutrients_source is 'usda', are from U.S. Department of Agriculture,\n"
        "-- Agricultural Research Service. FoodData Central (SR Legacy, 2018),\n"
        "-- fdc.nal.usda.gov, public domain (CC0 1.0).\n\n"
        "delete from public.reference_foods;\n\n"
        f"insert into public.reference_foods ({_COLUMNS}) values\n"
        f"{rows};\n"
    )


USDA_FIBRE_CSV = os.path.join(os.path.dirname(os.path.abspath(__file__)), "usda_fibre.csv")


def read_usda_fibre(path: str = USDA_FIBRE_CSV) -> dict[tuple[str, str], dict[str, str]]:
    """The reviewed USDA matches for CoFID foods without a fibre figure."""
    with open(path, encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    decisions = {"usda", "edible_part", "unknown"}
    for row in rows:
        if row["decision"] not in decisions:
            raise SystemExit(f"Unknown decision in usda_fibre.csv: {row}")
    return {(r["cofid_code"], r["cofid_name"]): r for r in rows}


USDA_NUTRIENTS_CSV = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "usda_nutrients.csv"
)


def read_usda_nutrients(
    path: str = USDA_NUTRIENTS_CSV,
) -> dict[tuple[str, str], dict[str, str]]:
    """The reviewed USDA matches for CoFID foods without an energy figure."""
    with open(path, encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    for row in rows:
        if row["decision"] not in ("usda", "unknown"):
            raise SystemExit(f"Unknown decision in usda_nutrients.csv: {row}")
    return {(r["cofid_code"], r["cofid_name"]): r for r in rows}


def from_usda(prox: dict[str, str], usda: dict[str, str]) -> ReferenceFood | None:
    """A CoFID food CoFID gives no energy figure for, with every value from
    its reviewed USDA match.

    USDA carbohydrate is "by difference" and includes fibre; UK labels don't,
    so fibre is taken off.
    """
    def value(column: str) -> float | None:
        raw = usda.get(column, "")
        return float(raw) if raw else None

    kcal, protein, fat = value("kcal"), value("protein_g"), value("fat_g")
    by_difference = value("carbs_by_difference_g")
    if None in (kcal, protein, fat, by_difference):
        raise SystemExit(f"Incomplete USDA row: {usda}")
    fibre = value("fibre_g")
    carbs = max(0.0, by_difference - (fibre or 0))
    sugar = value("sugars_g")
    sodium = value("sodium_mg")
    carbs = max(0.0, min(carbs, 100.0, 105.0 - protein - fat - (fibre or 0)))
    if kcal > 900 or protein + fat + (fibre or 0) > 105:
        return None
    name = " ".join(prox["Food Name"].split())
    return ReferenceFood(
        cofid_code=prox["Food Code"],
        name=name,
        display_name=display_name(name),
        food_group=prox.get("Group", ""),
        kcal=round(kcal, 1),
        protein=round(protein, 1),
        carbs=_round_down(carbs),
        fat=round(fat, 1),
        fibre=None if fibre is None else round(fibre, 1),
        fibre_source=None if fibre is None else "usda",
        sugar=None if sugar is None else _round_down(min(sugar, carbs)),
        salt=None if sodium is None else round(sodium * 2.5 / 1000, 2),
        edible_proportion=None,
        nutrients_source="usda",
    )


def build(
    path: str,
    usda_path: str = USDA_FIBRE_CSV,
    usda_nutrients_path: str = USDA_NUTRIENTS_CSV,
) -> list[ReferenceFood]:
    sheets = read_sheets(path, [_PROXIMATES, _INORGANICS, _FACTORS])
    usda = read_usda_fibre(usda_path)
    usda_nutrients = read_usda_nutrients(usda_nutrients_path)
    # Rows are matched across sheets by code and name together: CoFID 2021
    # gives one code (13-669) to two different foods.
    sodium = {_key(r): r.get("Sodium (mg)") for r in sheets[_INORGANICS]}
    edible = {_key(r): r.get("Edible proportion") for r in sheets[_FACTORS]}
    gravity = {_key(r): r.get("Specific gravity") for r in sheets[_FACTORS]}
    foods = {}
    for row in sheets[_PROXIMATES]:
        key = _key(row)
        if key in foods:
            raise SystemExit(f"Duplicate CoFID food {key}")
        food = to_reference_food(
            row, sodium.get(key), edible.get(key), gravity.get(key), usda.get(key)
        )
        if _optional(row.get("Energy (kcal) (kcal)")) is None or _optional(
            row.get("Carbohydrate (g)")
        ) is None:
            # CoFID has no energy figure (most spices): every such food must
            # be reviewed in usda_nutrients.csv, even if it stays out.
            match = usda_nutrients.get(key)
            if match is None:
                raise SystemExit(
                    f"{key} has no energy figure and no row in usda_nutrients.csv"
                )
            if match["decision"] == "usda":
                food = from_usda(row, match)
        if food is not None:
            foods[key] = food

    # Foods weighed with their waste (peel, shells) take their fibre from
    # the edible-part food, scaled by energy (both come from one sample).
    by_code = {}
    for key, food in foods.items():
        by_code.setdefault(food.cofid_code, []).append(food)
    for key, row in usda.items():
        if row["decision"] != "edible_part" or key not in foods:
            continue
        food = foods[key]
        [base] = by_code[row["edible_part_of"]]
        if food.fibre is None and base.fibre is not None and base.kcal > 0:
            foods[key] = dataclasses.replace(
                food,
                fibre=round(base.fibre * food.kcal / base.kcal, 1),
                fibre_source=base.fibre_source,
            )

    unreviewed = [
        f.name
        for k, f in foods.items()
        # Foods with every value from USDA are reviewed in usda_nutrients.csv.
        if f.fibre is None and k not in usda and f.nutrients_source == "cofid"
    ]
    if unreviewed:
        raise SystemExit(
            f"{len(unreviewed)} foods have no fibre figure and no row in "
            f"usda_fibre.csv (review them first), e.g. {unreviewed[:3]}"
        )
    if len(foods) < 1000:
        raise SystemExit(f"Only {len(foods)} usable foods; is this CoFID?")
    return sorted(foods.values(), key=lambda f: (f.cofid_code, f.name))


def _key(row: dict[str, str]) -> tuple[str, str]:
    return row["Food Code"], " ".join(row.get("Food Name", "").split())


def main(argv: list[str]) -> None:
    if len(argv) != 3:
        raise SystemExit(__doc__)
    source, output = argv[1], argv[2]
    foods = build(source)
    name = source.replace("\\", "/").rsplit("/", 1)[-1]
    with open(output, "w", encoding="utf-8", newline="\n") as f:
        f.write(to_sql(foods, name))
    print(f"Wrote {len(foods)} foods to {output}")


if __name__ == "__main__":
    main(sys.argv)
