import os
import tempfile
import unittest

import pandas as pd

from smart_import_engine import (
    analyze_excel,
    infer_student_education_level,
    merge_student_import_fields,
    split_class_branch,
)


class SmartImportEngineTest(unittest.TestCase):
    def _workbook(
        self,
        class_header="ŞUBE",
        class_value="11A",
        guardian_phone="0532 123 45 67",
    ):
        rows = [
            ["Öğrenci aktarımı raporu", "", "", "", "", "", "", ""],
            ["AD", "SOYAD", "KULLANICI ADI", "ŞİFRE", class_header, "VELİ ADI", "VELİ TELEFON", "TELEFON"],
            ["Ayşe", "Yılmaz", "ayse.yilmaz", "123456", class_value, "Murat Yılmaz", guardian_phone, "0532 999 00 11"],
        ]
        handle = tempfile.NamedTemporaryFile(suffix=".xlsx", delete=False)
        handle.close()
        with pd.ExcelWriter(handle.name) as writer:
            pd.DataFrame([["Not", "yardımcı sayfa"]]).to_excel(
                writer, sheet_name="Notlar", header=False, index=False
            )
            pd.DataFrame(rows).to_excel(
                writer, sheet_name="Öğrenciler", header=False, index=False
            )
        self.addCleanup(lambda: os.path.exists(handle.name) and os.unlink(handle.name))
        return handle.name

    def _workbook_with_columns(self, headers, row):
        handle = tempfile.NamedTemporaryFile(suffix=".xlsx", delete=False)
        handle.close()
        with pd.ExcelWriter(handle.name) as writer:
            pd.DataFrame([["Not", "yardımcı sayfa"]]).to_excel(
                writer, sheet_name="Notlar", header=False, index=False
            )
            pd.DataFrame([["Öğrenci aktarımı"], headers, row]).to_excel(
                writer, sheet_name="Öğrenciler", header=False, index=False
            )
        self.addCleanup(lambda: os.path.exists(handle.name) and os.unlink(handle.name))
        return handle.name

    def test_student_only_chooses_data_sheet_and_omits_guardians(self):
        result = analyze_excel(self._workbook(), "student", include_guardian=False)

        self.assertEqual(result["sheetName"], "Öğrenciler")
        self.assertEqual(result["headerRow"], 2)
        self.assertEqual(result["validCount"], 1)
        self.assertNotIn("guardianName", result["validRows"][0])
        self.assertNotIn("guardianPhone", result["validRows"][0])
        self.assertNotIn("phone", result["validRows"][0])
        self.assertEqual(result["warnings"], [])

    def test_legacy_sube_value_stays_the_canonical_class_name(self):
        result = analyze_excel(
            self._workbook(class_value="DERSLİK 11 SAY"), "student"
        )

        row = result["validRows"][0]
        self.assertEqual(row["className"], "DERSLİK 11 SAY")
        self.assertEqual(row["branch"], "")
        self.assertNotIn("educationLevel", row)

    def test_production_class_name_inference_uses_only_trusted_prefixes(self):
        for class_name in ["5-DERSLİK 5", "6-DERSLİK 6", "7-DERSLİK 4", "8-DERSLİK 9"]:
            self.assertEqual(infer_student_education_level(class_name), "LGS")
        for class_name in ["10-DERSLİK 6", "11-DERSLİK 4 SAY", "12-DERSLİK 13 EA", "MEZUN-DERSLİK 10"]:
            self.assertEqual(infer_student_education_level(class_name), "YKS")
        self.assertIsNone(infer_student_education_level("DERSLİK-16-SÖZEL"))
        self.assertEqual(
            split_class_branch("10-DERSLİK 6"), ("10-DERSLİK 6", "")
        )

        self.assertEqual(
            split_class_branch("DERSLİK-16-SÖZEL"), ("DERSLİK-16-SÖZEL", "")
        )

    def test_existing_richer_student_class_and_level_are_not_overwritten(self):
        merged = merge_student_import_fields(
            {
                "className": "8",
                "branch": "",
                "department": "",
                "educationLevel": "LGS",
            },
            {
                "className": "DERSLİK 9",
                "branch": "DERSLİK 9",
                "department": "LGS",
            },
        )

        self.assertEqual(merged["className"], "8")
        self.assertEqual(merged["branch"], "DERSLİK 9")
        self.assertEqual(merged["department"], "LGS")
        self.assertEqual(merged["educationLevel"], "LGS")

    def test_separate_sinif_sube_and_bolum_columns_stay_separate(self):
        result = analyze_excel(
            self._workbook_with_columns(
                [
                    "AD",
                    "SOYAD",
                    "KULLANICI ADI",
                    "ŞİFRE",
                    "SINIF",
                    "ŞUBE",
                    "BÖLÜM",
                    "ÖĞRENCİ NO",
                ],
                [
                    "Ayşe",
                    "Yılmaz",
                    "ayse.yilmaz",
                    "123456",
                    "8",
                    "DERSLİK 9",
                    "LGS",
                    "70004",
                ],
            ),
            "student",
        )

        row = result["validRows"][0]
        self.assertEqual(row["className"], "8")
        self.assertEqual(row["branch"], "DERSLİK 9")
        self.assertEqual(row["department"], "LGS")
        self.assertNotIn("studentNo", row)

    def test_guardian_mode_normalizes_phone_without_blocking_bad_phone(self):
        result = analyze_excel(
            self._workbook(guardian_phone="123"), "student", include_guardian=True
        )

        self.assertEqual(result["validCount"], 1)
        self.assertEqual(result["invalidCount"], 0)
        self.assertEqual(result["validRows"][0]["guardianName"], "Murat Yılmaz")
        self.assertNotIn("guardianPhone", result["validRows"][0])
        self.assertEqual(result["reviewCount"], 1)

    def test_manual_mapping_override_is_reported_and_reanalyzed(self):
        path = self._workbook(class_header="GRUP")
        result = analyze_excel(path, "student", overrides={"className": 4})

        self.assertEqual(result["validCount"], 1)
        self.assertTrue(
            any(
                detail["field"] == "className"
                and detail["header"] == "GRUP"
                and detail["confidence"] == "MANUAL"
                for detail in result["mappingDetails"]
            )
        )


if __name__ == "__main__":
    unittest.main()
