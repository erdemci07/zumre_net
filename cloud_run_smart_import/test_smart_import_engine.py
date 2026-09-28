import os
import tempfile
import unittest

import pandas as pd

from smart_import_engine import analyze_excel


class SmartImportEngineTest(unittest.TestCase):
    def _workbook(self, class_header="ŞUBE", guardian_phone="0532 123 45 67"):
        rows = [
            ["Öğrenci aktarımı raporu", "", "", "", "", "", ""],
            ["AD", "SOYAD", "KULLANICI ADI", "ŞİFRE", class_header, "VELİ ADI", "VELİ TELEFON"],
            ["Ayşe", "Yılmaz", "ayse.yilmaz", "123456", "11A", "Murat Yılmaz", guardian_phone],
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

    def test_student_only_chooses_data_sheet_and_omits_guardians(self):
        result = analyze_excel(self._workbook(), "student", include_guardian=False)

        self.assertEqual(result["sheetName"], "Öğrenciler")
        self.assertEqual(result["headerRow"], 2)
        self.assertEqual(result["validCount"], 1)
        self.assertNotIn("guardianName", result["validRows"][0])
        self.assertNotIn("guardianPhone", result["validRows"][0])
        self.assertEqual(result["warnings"], [])

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
