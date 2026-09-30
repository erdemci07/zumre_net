import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import pandas as pd
from rapidfuzz import fuzz
from unidecode import unidecode


DOMAIN = "@bilimkalesi.com"
SUBJECT_MAP = {
    "matematik": "MATEMATİK",
    "fizik": "FİZİK",
    "kimya": "KİMYA",
    "biyoloji": "BİYOLOJİ",
    "turkce": "TÜRKÇE",
    "tarih": "TARİH",
    "cografya": "COĞRAFYA",
    "geometri": "GEOMETRİ",
}


STUDENT_ALIASES = {
    "name": ["ad", "adi", "isim", "ogrenci adi", "öğrenci adı*","ad*", "adi*", "isim*", "ogrenci adi*", "öğrenci adı*"],
    "surname": ["soyad", "soyadi", "soyisim","soyad*", "soyadi*", "soyisim*"],
    "fullName": ["ad soyad", "adi soyadi", "öğrenci", "ogrenci", "ogrenci adi soyadi", "öğrenci adı soyadı", "ad soyad*", "adi soyadi*", "öğrenci*", "ogrenci*", "ogrenci adi soyadi*", "öğrenci adı soyadı*"],
    "username": [
        "kullanici adi",
        "kullanici adi*",
        "kullanıcı adı",
        "kullanıcı adı*",
        "username",
        "username*",
        "tc",
        "tc no",
        "tc kimlik",
        "tc numarasi",
        "tc numarası",
    ],
    "password": ["sifre", "şifre", "password", "parola", "sifre*", "şifre*", "password*", "parola*"],
    "className": ["sinif", "sınıf", "class", "sinifi", "sinif seviyesi", "sınıf seviyesi", "hazirlik", "hazırlık"],
    "branch": ["sube", "şube", "branch", "sinif sube", "sınıf şube", "sinif şube", "sınıf sube", "derslik"],
    "department": ["bolum", "bölüm", "alan", "alan bolum", "alan bölüm", "alan/bolum", "alan/bölüm", "program", "alan*", "program*"],
    "guardianName": ["veli", "veli adi", "veli adı", "veli ad soyad", "veli ad soyadı", "anne baba adi", "anne baba adı", "yakin adi", "yakın adı"],
    "guardianSurname": ["veli soyad", "veli soyadı", "veli soyadi", "anne baba soyad", "anne baba soyadı", "yakin soyad", "yakın soyadı"],
    "guardianPhone": ["veli telefon", "veli telefonu", "veli gsm", "veli cep", "guardian phone"],
}

TEACHER_ALIASES = {
    "name": ["ad", "adi", "isim", "ogretmen adi", "öğretmen adı", "ad*", "adi*", "isim*", "ogretmen adi*", "öğretmen adı*"],
    "surname": ["soyad", "soyadi", "soyisim","soyad*", "soyadi*", "soyisim*"],
    "fullName": ["ad soyad", "adi soyadi", "ogretmen", "öğretmen*","ad soyad*", "adi soyadi*", "ogretmen*", "öğretmen*"],
    "username": [
        "kullanici adi",
        "kullanici adi*",
        "kullanıcı adı",
        "kullanıcı adı*",
        "username",
        "username*",
        "tc",
        "tc no",
        "tc kimlik",
        "tc numarasi",
        "tc numarası",
    ],
    "password": ["sifre", "şifre", "password", "parola", "sifre*", "şifre*", "password*", "parola*"],
    "subjects": [
    "brans",
    "branş",
    "brans*",
    "branş*",
    "ders",
    "dersi",
    "subject",
    "alan",
    "uzmanlik",
    "uzmanlık",
],
    "phone": ["telefon", "telefon numarasi", "telefon numarası", "cep telefonu"],
}


REQUIRED_FIELDS = {
    "student": ["name", "surname", "username", "password", "className"],
    "teacher": ["name", "surname", "username", "password", "subjects"],
}


FIELD_LABELS = {
    "name": "Öğrenci adı",
    "surname": "Öğrenci soyadı",
    "username": "Kullanıcı adı",
    "password": "Şifre",
    "className": "Sınıf/şube",
    "department": "Bölüm",
    "subjects": "Branş",
    "guardianName": "Veli adı",
    "guardianSurname": "Veli soyadı",
    "guardianPhone": "Veli telefon numarası",
}


VALID_EDUCATION_LEVELS = {"LGS", "YKS"}
YKS_DEPARTMENT_TOKENS = {
    "yks",
    "lise",
    "say",
    "sayisal",
    "ea",
    "esit agirlik",
    "esitagirlik",
    "sozel",
    "tyt",
    "ayt",
    "mezun",
}


IGNORED_HEADERS = [
    "email",
    "e posta",
    "e-posta",
    "mail",
    "mail adresi",
    "eposta",
    "tc numarasi",
    "tc numarası",
    "cinsiyet",
    "diploma no",
    "dogum tarihi",
    "doğum tarihi",
    "adres",
]


def normalize_text(value: Any) -> str:
    text = "" if value is None else str(value)
    text = unidecode(text)
    text = text.lower().strip()
    text = re.sub(r"[^a-z0-9\s]", " ", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def clean_cell(value: Any) -> str:
    if pd.isna(value):
        return ""

    text = str(value).strip()

    if text.endswith(".0"):
        text = text[:-2]

    return text.strip()


def valid_education_level(value: Any) -> Optional[str]:
    level = clean_cell(value).upper()
    return level if level in VALID_EDUCATION_LEVELS else None


def class_name_education_level(value: Any) -> Optional[str]:
    class_name = clean_cell(value).upper()
    if re.match(r"^(5|6|7|8)-", class_name):
        return "LGS"
    if re.match(r"^(9|10|11|12)-", class_name) or re.match(r"^MEZUN(?:-|$)", class_name):
        return "YKS"
    return None


def infer_student_education_level(class_name: Any, department: Any = "") -> Optional[str]:
    from_class_name = class_name_education_level(class_name)
    if from_class_name:
        return from_class_name

    department_key = normalize_text(department)
    if department_key in {"lgs", "ortaokul"}:
        return "LGS"
    if department_key in YKS_DEPARTMENT_TOKENS:
        return "YKS"
    return None


def class_name_information_quality(value: Any) -> int:
    class_name = clean_cell(value)
    if not class_name:
        return 0
    if class_name_education_level(class_name):
        return 3
    if normalize_text(class_name).startswith("derslik"):
        return 1
    return 2


def merge_student_import_fields(
    existing: Dict[str, Any], incoming: Dict[str, Any]
) -> Dict[str, Any]:
    existing_class_name = clean_cell(existing.get("className"))
    incoming_class_name = clean_cell(incoming.get("className"))
    if (
        existing_class_name
        and class_name_information_quality(existing_class_name)
        > class_name_information_quality(incoming_class_name)
    ):
        class_name = existing_class_name
    else:
        class_name = incoming_class_name or existing_class_name

    existing_level = valid_education_level(existing.get("educationLevel"))
    incoming_level = valid_education_level(incoming.get("educationLevel"))
    # A trusted canonical class prefix is the strongest signal. This lets an
    # annual 8 -> 9 import move the student from LGS to YKS instead of keeping
    # a stale educationLevel from the previous record.
    education_level = (
        class_name_education_level(class_name) or incoming_level or existing_level
    )

    return {
        "className": class_name,
        "branch": clean_cell(incoming.get("branch")) or clean_cell(existing.get("branch")),
        "department": clean_cell(incoming.get("department")) or clean_cell(existing.get("department")),
        "educationLevel": education_level,
    }


def only_digits(value: Any) -> str:
    return re.sub(r"\D", "", clean_cell(value))


def normalize_guardian_phone(value: Any) -> Optional[str]:
    digits = only_digits(value)
    if digits.startswith("0090"):
        digits = digits[4:]
    elif digits.startswith("90") and len(digits) == 12:
        digits = digits[2:]
    elif digits.startswith("0") and len(digits) == 11:
        digits = digits[1:]
    return digits if re.fullmatch(r"5\d{9}", digits) else None


def make_email(username: str) -> str:
    username = normalize_username(username)
    return f"{username}{DOMAIN}"


def normalize_username(value: Any) -> str:
    text = clean_cell(value)
    text = text.replace(" ", "")
    text = text.replace(".", "")
    text = text.replace("-", "")
    return text.lower()


def normalize_password(value: Any) -> str:
    password = clean_cell(value)

    if not password:
        return "123456"

    if len(password) < 6:
        return password.zfill(6)

    return password


def split_class_branch(value: str) -> Tuple[str, str]:
    source_value = clean_cell(value)
    if (
        re.match(r"^(5|6|7|8|9|10|11|12)-", source_value.upper())
        or re.match(r"^MEZUN(?:-|$)", source_value.upper())
        or source_value.upper().startswith("DERSLİK-")
    ):
        return source_value, ""

    text = source_value.upper()
    text = text.replace("_", " ")
    text = text.replace("-", " ")
    text = text.replace("/", " ")
    text = re.sub(r"\s+", " ", text).strip()

    if not text:
        return "", ""

    parts = text.split(" ")

    if len(parts) >= 2:
        return parts[0], parts[1]

    match = re.match(r"^(\d{1,2})([A-Z])$", text)
    if match:
        return match.group(1), match.group(2)

    return text, ""


def normalize_subjects(value: Any) -> List[str]:
    text = clean_cell(value)

    if not text:
        return []

    raw_parts = re.split(r"[,;/|]", text)

    subjects = []

    for part in raw_parts:
        item = part.strip()

        if not item:
            continue

        normalized_key = normalize_text(item)

        standard_subject = SUBJECT_MAP.get(
            normalized_key,
            item,
        )

        if standard_subject not in subjects:
            subjects.append(standard_subject)

    return subjects


def get_aliases(file_type: str) -> Dict[str, List[str]]:
    return TEACHER_ALIASES if file_type == "teacher" else STUDENT_ALIASES


def best_field_for_header(header: Any, aliases: Dict[str, List[str]]) -> Optional[Tuple[str, int]]:
    normalized_header = normalize_text(header)

    if not normalized_header:
        return None

    if normalized_header in [normalize_text(h) for h in IGNORED_HEADERS]:
        return None

    best_field = None
    best_score = 0

    for field, names in aliases.items():
        for alias in names:
            score = fuzz.ratio(normalized_header, normalize_text(alias))

            if score > best_score:
                best_score = score
                best_field = field

    if best_score >= 82 and best_field:
        return best_field, best_score

    return None


def detect_header_row(df: pd.DataFrame, file_type: str, max_scan_rows: int = 30) -> Tuple[int, int]:
    aliases = get_aliases(file_type)

    best_row_index = 0
    best_score = -1

    scan_limit = min(max_scan_rows, len(df))

    for row_index in range(scan_limit):
        row = df.iloc[row_index].tolist()

        score = 0
        matched_fields = set()

        for cell in row:
            result = best_field_for_header(cell, aliases)

            if result:
                field, match_score = result
                matched_fields.add(field)
                score += match_score

        score += len(matched_fields) * 100

        if score > best_score:
            best_score = score
            best_row_index = row_index

    return best_row_index, best_score


def build_mapping(headers: List[Any], file_type: str) -> Tuple[Dict[str, int], List[Dict[str, Any]], List[Dict[str, Any]]]:
    aliases = get_aliases(file_type)
    mapping: Dict[str, int] = {}
    ignored_headers: List[Dict[str, Any]] = []
    details: List[Dict[str, Any]] = []

    for index, header in enumerate(headers):
        normalized_header = normalize_text(header)

        if not normalized_header:
            continue

        if normalized_header in [normalize_text(h) for h in IGNORED_HEADERS]:
            ignored_headers.append({
                "index": index,
                "original": clean_cell(header),
                "reason": "ignored_email_or_unused_field",
            })
            continue

        result = best_field_for_header(header, aliases)

        if result:
            field, score = result

            if field not in mapping:
                mapping[field] = index
                details.append({"field": field, "header": clean_cell(header), "confidence": "EXACT" if score == 100 else "HIGH" if score >= 90 else "MEDIUM", "score": score})
            else:
                ignored_headers.append({
                    "index": index,
                    "original": clean_cell(header),
                    "reason": f"duplicate_for_{field}",
                    "score": score,
                })
        else:
            ignored_headers.append({
                "index": index,
                "original": clean_cell(header),
                "reason": "unknown_header",
            })

    return mapping, ignored_headers, details


def get_value(row: List[Any], mapping: Dict[str, int], field: str) -> str:
    index = mapping.get(field)

    if index is None or index >= len(row):
        return ""

    return clean_cell(row[index])


def validate_required(record: Dict[str, Any], file_type: str) -> List[str]:
    missing = []

    for field in REQUIRED_FIELDS[file_type]:
        value = record.get(field)

        if isinstance(value, list):
            if not value:
                missing.append(field)
        elif not clean_cell(value):
            missing.append(field)

    return missing


def format_validation_errors(fields: List[str]) -> List[str]:
    return [f"{FIELD_LABELS.get(field, field)} bilgisi bulunamadı." for field in fields]


def normalize_student(
    row: List[Any], mapping: Dict[str, int], include_guardian: bool = False
) -> Tuple[Dict[str, Any], List[str], List[str]]:
    warnings = []

    name = get_value(row, mapping, "name")
    surname = get_value(row, mapping, "surname")
    full_name = get_value(row, mapping, "fullName")

    if not full_name:
        full_name = f"{name} {surname}".strip()
    elif not name or not surname:
        parts = full_name.split()
        if len(parts) >= 2:
            name = name or " ".join(parts[:-1])
            surname = surname or parts[-1]

    username = normalize_username(get_value(row, mapping, "username"))
    password = normalize_password(get_value(row, mapping, "password"))

    class_name = get_value(row, mapping, "className")
    branch = get_value(row, mapping, "branch")
    is_legacy_branch_fallback = (
        mapping.get("className") is not None
        and mapping.get("className") == mapping.get("branch")
    )

    if is_legacy_branch_fallback:
        # A legacy ŞUBE column is the canonical class value as-is. It must not
        # be split or reused as a second branch value.
        branch = ""
    else:
        parsed_class, parsed_branch = split_class_branch(class_name)

        if parsed_class:
            class_name = parsed_class

        if not branch and parsed_branch:
            branch = parsed_branch
            warnings.append("Şube sınıf alanından otomatik ayrıldı.")

    department = get_value(row, mapping, "department")
    guardian_name = get_value(row, mapping, "guardianName") if include_guardian else ""
    guardian_surname = get_value(row, mapping, "guardianSurname") if include_guardian else ""
    guardian_raw_phone = get_value(row, mapping, "guardianPhone") if include_guardian else ""
    guardian_phone = normalize_guardian_phone(guardian_raw_phone) if guardian_raw_phone else ""

    record = {
        "role": "student",
        "name": name,
        "surname": surname,
        "fullName": full_name,
        "username": username,
        "identityKey": username,
        "email": make_email(username) if username else "",
        "password": password,
        "className": class_name,
        "branch": branch,
        "department": department,
    }

    education_level = infer_student_education_level(class_name, department)
    if education_level:
        record["educationLevel"] = education_level

    if include_guardian:
        if guardian_name:
            record["guardianName"] = guardian_name
        if guardian_surname:
            record["guardianSurname"] = guardian_surname
        if guardian_phone:
            record["guardianPhone"] = guardian_phone

    errors = validate_required(record, "student")
    if guardian_raw_phone and not guardian_phone:
        warnings.append("Veli telefon numarası geçersiz olduğu için aktarılmayacak.")

    return record, errors, warnings


def normalize_teacher(row: List[Any], mapping: Dict[str, int]) -> Tuple[Dict[str, Any], List[str], List[str]]:
    warnings = []

    name = get_value(row, mapping, "name")
    surname = get_value(row, mapping, "surname")
    full_name = get_value(row, mapping, "fullName")

    if not full_name:
        full_name = f"{name} {surname}".strip()
    elif not name or not surname:
        parts = full_name.split()
        if len(parts) >= 2:
            name = name or " ".join(parts[:-1])
            surname = surname or parts[-1]

    username = normalize_username(get_value(row, mapping, "username"))
    password = normalize_password(get_value(row, mapping, "password"))
    subjects = normalize_subjects(get_value(row, mapping, "subjects"))
    phone = only_digits(get_value(row, mapping, "phone"))

    record = {
        "role": "teacher",
        "name": name,
        "surname": surname,
        "fullName": full_name,
        "username": username,
        "identityKey": username,
        "email": make_email(username) if username else "",
        "password": password,
        "subjects": subjects,
        "teacherStatus": "absent",
        "weeklyAvailability": {},
        "phone": phone,
    }

    errors = validate_required(record, "teacher")

    return record, errors, warnings


def confidence_score(
    valid_count: int,
    invalid_count: int,
    warnings_count: int,
    mapping: Dict[str, int],
    file_type: str,
) -> int:
    total = valid_count + invalid_count

    if total == 0:
        return 0

    score = 100

    invalid_ratio = invalid_count / total
    score -= int(invalid_ratio * 50)

    score -= min(warnings_count * 2, 20)

    required = REQUIRED_FIELDS[file_type]
    missing_mapping = [field for field in required if field not in mapping]
    score -= len(missing_mapping) * 12

    return max(0, min(100, score))


def analyze_excel(file_path: str, file_type: str, overrides: Optional[Dict[str, int]] = None, include_guardian: bool = False) -> Dict[str, Any]:
    if file_type not in ["student", "teacher"]:
        raise ValueError("file_type student veya teacher olmalı.")

    path = Path(file_path)

    if not path.exists():
        raise FileNotFoundError(f"Dosya bulunamadı: {file_path}")

    workbook = pd.ExcelFile(path)
    candidates = []
    for sheet_name in workbook.sheet_names:
        candidate = pd.read_excel(path, sheet_name=sheet_name, header=None, dtype=str)
        header_index, score = detect_header_row(candidate, file_type)
        candidates.append((score, len(candidate), sheet_name, candidate, header_index))
    _, _, sheet_name, df_raw, header_row = max(candidates, key=lambda item: (item[0], item[1]))
    workbook.close()
    headers = df_raw.iloc[header_row].tolist()

    mapping, ignored_headers, mapping_details = build_mapping(headers, file_type)
    for field, index in (overrides or {}).items():
        if isinstance(index, int) and 0 <= index < len(headers):
            mapping[field] = index
            mapping_details = [item for item in mapping_details if item["field"] != field]
            mapping_details.append({"field": field, "header": clean_cell(headers[index]), "confidence": "MANUAL", "score": 100})
    # Legacy Edesis exports use ŞUBE as the only class/section column. Keep
    # its value intact rather than fabricating a grade from it.
    if file_type == "student" and "className" not in mapping and "branch" in mapping:
        branch_index = mapping["branch"]
        branch_detail = next(
            (item for item in mapping_details if item["field"] == "branch"), None
        )
        mapping["className"] = branch_index
        mapping_details = [item for item in mapping_details if item["field"] != "branch"]
        mapping_details.append({
            "field": "className",
            "header": clean_cell(headers[branch_index]),
            "confidence": branch_detail["confidence"] if branch_detail else "HIGH",
            "score": branch_detail["score"] if branch_detail else 90,
        })

    # Guardian columns are intentionally not part of a student-only import.
    # This makes the analysis payload itself safe to forward to /import.
    if file_type == "student" and not include_guardian:
        mapping.pop("guardianName", None)
        mapping.pop("guardianSurname", None)
        mapping.pop("guardianPhone", None)
        mapping_details = [
            item for item in mapping_details
            if item["field"] not in {"guardianName", "guardianSurname", "guardianPhone"}
        ]

    data_df = df_raw.iloc[header_row + 1:].copy()
    data_df = data_df.dropna(how="all")

    valid_rows = []
    invalid_rows = []
    warnings_all = []

    for index, row_values in data_df.iterrows():
        row = row_values.tolist()

        if file_type == "teacher":
            normalized, errors, warnings = normalize_teacher(row, mapping)
        else:
            normalized, errors, warnings = normalize_student(
                row, mapping, include_guardian=include_guardian
            )

        if all(not clean_cell(v) for v in row):
            continue

        row_number = int(index) + 1

        if errors:
            invalid_rows.append({
                "rowNumber": row_number,
                "errors": format_validation_errors(errors),
                "warnings": warnings,
                "raw": [clean_cell(v) for v in row],
                "normalized": normalized,
            })
        else:
            valid_rows.append(normalized)

        for warning in warnings:
            warnings_all.append({
                "rowNumber": row_number,
                "message": warning,
            })

    score = confidence_score(
        valid_count=len(valid_rows),
        invalid_count=len(invalid_rows),
        warnings_count=len(warnings_all),
        mapping=mapping,
        file_type=file_type,
    )

    return {
        "ok": len(invalid_rows) == 0,
        "type": file_type,
        "fileName": path.name,
        "headerRow": header_row + 1,
        "sheetName": sheet_name,
        "headers": [clean_cell(header) for header in headers],
        "mappingDetails": mapping_details,
        "guardianMode": include_guardian,
        "totalRows": len(valid_rows) + len(invalid_rows),
        "validCount": len(valid_rows),
        "invalidCount": len(invalid_rows),
        "reviewCount": len({warning["rowNumber"] for warning in warnings_all}),
        "confidenceScore": score,
        "mapping": mapping,
        "missingFields": [
            field for field in REQUIRED_FIELDS[file_type] if field not in mapping
        ],
        "ignoredHeaders": ignored_headers,
        "warnings": warnings_all,
        "preview": valid_rows[:10],
        "invalidPreview": invalid_rows[:10],
        "validRows": valid_rows,
    }


def main():
    if len(sys.argv) < 3:
        print("Kullanım:")
        print("python smart_import_engine.py <excel_path> <student|teacher>")
        sys.exit(1)

    file_path = sys.argv[1]
    file_type = sys.argv[2]

    result = analyze_excel(file_path, file_type)

    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
