"""Tests for build_cofid_migration. Run: python -m unittest discover tool/cofid"""

import unittest

from build_cofid_migration import (
    Unknown,
    display_name,
    from_usda,
    parse_value,
    sql_literal,
    to_reference_food,
)


def _row(**overrides):
    row = {
        "Food Code": "13-001",
        "Food Name": "Bananas, flesh only",
        "Group": "FA",
        "Energy (kcal) (kcal)": "95",
        "Protein (g)": "1.2",
        "Fat (g)": "0.3",
        "Carbohydrate (g)": "20.3",
        "AOAC fibre (g)": "1.4",
        "NSP (g)": "1.1",
        "Total sugars (g)": "18.1",
    }
    row.update(overrides)
    return row


class ParseValueTest(unittest.TestCase):
    def test_numbers_and_trace(self):
        self.assertEqual(parse_value("12.5"), 12.5)
        self.assertEqual(parse_value("Tr"), 0.0)
        self.assertEqual(parse_value("(0.4)"), 0.4)

    def test_unknown(self):
        for raw in ("N", "", None):
            with self.assertRaises(Unknown):
                parse_value(raw)

    def test_rejects_junk_and_negatives(self):
        for raw in ("abc", "-1"):
            with self.assertRaises(SystemExit):
                parse_value(raw)


class ToReferenceFoodTest(unittest.TestCase):
    def test_converts_a_food(self):
        food = to_reference_food(_row(), sodium_mg="1", edible="0.66")
        self.assertEqual(food.kcal, 95)
        self.assertEqual(food.fibre, 1.4)
        self.assertEqual(food.salt, 0.0)  # 1 mg sodium rounds to 0.00 g salt
        self.assertEqual(food.edible_proportion, 0.66)
        self.assertEqual(food.display_name, "Bananas, flesh only")

    def test_salt_from_sodium(self):
        food = to_reference_food(_row(), sodium_mg="400", edible=None)
        self.assertEqual(food.salt, 1.0)

    def test_unknowns_become_null(self):
        food = to_reference_food(
            _row(**{"Total sugars (g)": "N"}), sodium_mg="N", edible="N"
        )
        self.assertIsNone(food.sugar)
        self.assertIsNone(food.salt)
        self.assertIsNone(food.edible_proportion)

    def test_fibre_falls_back_to_scaled_nsp_then_null(self):
        nsp = to_reference_food(
            _row(**{"AOAC fibre (g)": "N", "NSP (g)": "1.8"}), None, None
        )
        self.assertEqual(nsp.fibre, 2.4)  # 18 g NSP ~ 24 g AOAC
        agar = to_reference_food(
            _row(**{
                "Energy (kcal) (kcal)": "16",
                "Water (g)": "9.7",
                "Protein (g)": "1.3",
                "Fat (g)": "1.2",
                "Carbohydrate (g)": "Tr",
                "Total sugars (g)": "Tr",
                "AOAC fibre (g)": None,
                "NSP (g)": "81.1",
            }),
            None,
            None,
        )
        self.assertEqual(agar.fibre, 87.8, "scaled only as far as it fits")
        neither = to_reference_food(
            _row(**{"AOAC fibre (g)": None, "NSP (g)": "N"}), None, None
        )
        self.assertIsNone(neither.fibre)

    def test_trace_is_zero(self):
        food = to_reference_food(_row(**{"Fat (g)": "Tr"}), None, None)
        self.assertEqual(food.fat, 0)

    def test_skips_foods_missing_core_values(self):
        for column in (
            "Energy (kcal) (kcal)",
            "Protein (g)",
            "Fat (g)",
            "Carbohydrate (g)",
        ):
            self.assertIsNone(to_reference_food(_row(**{column: "N"}), None, None))

    def test_drinks_convert_from_per_100_ml(self):
        spirits = to_reference_food(
            _row(**{
                "Group": "QK",
                "Energy (kcal) (kcal)": "222",
                "Protein (g)": "Tr",
                "Fat (g)": "0",
                "Carbohydrate (g)": "Tr",
                "Total sugars (g)": "Tr",
            }),
            None,
            None,
            specific_gravity="0.95",
        )
        self.assertEqual(spirits.kcal, round(222 / 0.95, 1))

    def test_impossible_gravity_counts_as_water(self):
        shandy = to_reference_food(
            _row(Group="QA", **{"Energy (kcal) (kcal)": "11"}),
            None,
            None,
            specific_gravity="0.50",  # as CoFID lists shandy
        )
        self.assertEqual(shandy.kcal, 11)

    def test_fibre_records_its_source(self):
        self.assertEqual(to_reference_food(_row(), None, None).fibre_source, "aoac")
        nsp = to_reference_food(_row(**{"AOAC fibre (g)": "N"}), None, None)
        self.assertEqual(nsp.fibre_source, "nsp")

    def test_usda_fibre_scales_to_dry_matter(self):
        boiled = _row(**{
            "AOAC fibre (g)": "N", "NSP (g)": "N", "Water (g)": "70.0",
            "Carbohydrate (g)": "21.0",
        })
        usda = {"decision": "usda", "usda_fibre_g": "15.0", "usda_water_g": "10.0"}
        food = to_reference_food(boiled, None, None, usda=usda)
        self.assertEqual(food.fibre, 5.0)  # 15 x 30/90
        self.assertEqual(food.fibre_source, "usda")

    def test_unknown_decision_leaves_fibre_null(self):
        food = to_reference_food(
            _row(**{"AOAC fibre (g)": "N", "NSP (g)": "N"}),
            None,
            None,
            usda={"decision": "unknown"},
        )
        self.assertIsNone(food.fibre)
        self.assertIsNone(food.fibre_source)

    def test_carbohydrate_becomes_actual_weight(self):
        # Table sugar: 100 g of sucrose is 105 g as monosaccharides.
        sugar = to_reference_food(
            _row(**{
                "Energy (kcal) (kcal)": "394",
                "Protein (g)": "Tr",
                "Fat (g)": "0",
                "Carbohydrate (g)": "105.0",
                "Starch (g)": "0",
                "AOAC fibre (g)": "0",
                "Total sugars (g)": "105.0",
                "Glucose (g)": "0",
                "Galactose (g)": "0",
                "Fructose (g)": "0",
                "Sucrose (g)": "105.0",
                "Maltose (g)": "0",
                "Lactose (g)": "0",
            }),
            None,
            None,
        )
        self.assertEqual(sugar.carbs, 100)
        self.assertEqual(sugar.sugar, 100)

    def test_starch_and_sugars_convert_separately(self):
        # 66 g starch / 1.10 = 60; glucose 5 + fructose 5 as given;
        # sucrose 10.5 / 1.05 = 10; 2.2 g oligosaccharide / 1.10 = 2.
        food = to_reference_food(
            _row(**{
                "Carbohydrate (g)": "88.7",
                "Starch (g)": "66.0",
                "Total sugars (g)": "20.5",
                "Glucose (g)": "5.0",
                "Galactose (g)": "Tr",
                "Fructose (g)": "5.0",
                "Sucrose (g)": "10.5",
                "Maltose (g)": "0",
                "Lactose (g)": "0",
            }),
            None,
            None,
        )
        self.assertEqual(food.carbs, 82.0)  # 60 + 20 + 2
        self.assertEqual(food.sugar, 20.0)

    def test_carbohydrate_without_its_parts_divides_by_1_05(self):
        food = to_reference_food(_row(**{"Carbohydrate (g)": "21.0"}), None, None)
        self.assertEqual(food.carbs, 20.0)
        # Total sugars without the individual sugars: also / 1.05.
        self.assertEqual(food.sugar, round(18.1 / 1.05 - 0.05, 1))

    def test_trims_carbohydrate_to_the_app_limits(self):
        herb = to_reference_food(
            _row(**{
                "Protein (g)": "4.9",
                "Fat (g)": "15.2",
                "Carbohydrate (g)": "46.4",
                "AOAC fibre (g)": "42.6",
            }),
            None,
            None,
        )
        total = herb.protein + herb.fat + herb.carbs + herb.fibre
        self.assertLessEqual(total, 105)

    def test_skips_impossible_values(self):
        self.assertIsNone(
            to_reference_food(_row(**{"Energy (kcal) (kcal)": "950"}), None, None)
        )


class FromUsdaTest(unittest.TestCase):
    CUMIN = {
        "decision": "usda", "kcal": "375", "protein_g": "17.81", "fat_g": "22.27",
        "carbs_by_difference_g": "44.24", "fibre_g": "10.5", "sugars_g": "2.25",
        "sodium_mg": "168", "water_g": "8.06",
    }

    def test_takes_every_value_from_usda(self):
        food = from_usda(
            {"Food Code": "13-822", "Food Name": "Cumin seeds", "Group": "H"},
            self.CUMIN,
        )
        self.assertEqual(food.kcal, 375)
        self.assertEqual(food.protein, 17.8)
        self.assertEqual(food.carbs, 33.7)  # 44.24 by difference - 10.5 fibre
        self.assertEqual(food.fibre, 10.5)
        self.assertEqual(food.fibre_source, "usda")
        self.assertEqual(food.salt, 0.42)
        self.assertEqual(food.nutrients_source, "usda")

    def test_incomplete_rows_fail_loudly(self):
        with self.assertRaises(SystemExit):
            from_usda(
                {"Food Code": "13-822", "Food Name": "Cumin seeds"},
                {**self.CUMIN, "kcal": ""},
            )


class DisplayNameTest(unittest.TestCase):
    def test_variety_goes_first(self):
        self.assertEqual(
            display_name("Rice, white, basmati, raw"), "White rice, basmati, raw"
        )
        self.assertEqual(display_name("Liver, pig, raw"), "Pig liver, raw")
        self.assertEqual(display_name("Bread, wholemeal"), "Wholemeal bread")

    def test_variety_that_names_the_food(self):
        self.assertEqual(
            display_name("Beans, red kidney, dried"), "Red kidney beans, dried"
        )
        self.assertEqual(
            display_name("Beans, chick peas, dried"), "Chickpeas, dried"
        )
        self.assertEqual(
            display_name("Pudding, Eve's pudding, homemade"),
            "Eve's pudding, homemade",
        )

    def test_cut_goes_after(self):
        self.assertEqual(
            display_name("Beef, sirloin steak, grilled"),
            "Beef sirloin steak, grilled",
        )
        self.assertEqual(
            display_name("Lamb, New Zealand, leg, raw"),
            "New Zealand lamb, leg, raw",
        )

    def test_states_are_left_alone(self):
        for name in (
            "Chicken, whole, roasted",
            "Milk, whole, UHT",
            "Rice, raw",
            "Beef, fat, cooked",
            "Turkey, light meat, roasted",
        ):
            self.assertEqual(display_name(name), name)

    def test_other_names_unchanged(self):
        self.assertEqual(display_name("Garam masala"), "Garam masala")
        self.assertEqual(display_name("Bananas, flesh only"), "Bananas, flesh only")


class SqlLiteralTest(unittest.TestCase):
    def test_quotes_and_nulls(self):
        self.assertEqual(sql_literal("Eve's"), "'Eve''s'")
        self.assertEqual(sql_literal(None), "null")
        self.assertEqual(sql_literal(1.25), "1.25")

    def test_rejects_control_characters_and_backslashes(self):
        for bad in ("a\nb", "a\\b", "a\x00b"):
            with self.assertRaises(SystemExit):
                sql_literal(bad)


if __name__ == "__main__":
    unittest.main()
