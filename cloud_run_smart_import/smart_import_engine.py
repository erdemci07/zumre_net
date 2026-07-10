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
        "ogrenci no",
        "öğrenci no",
        "numara",
        "no",
    ],
    "password": ["sifre", "şifre", "password", "parola", "sifre*", "şifre*", "password*", "parola*"],
    "className": ["sinif", "sınıf", "class", "sinifi"],
    "branch": ["sube", "şube", "branch"],
    "department": ["alan", "bolum", "bölüm", "program", "alan*", "bolum*", "bölüm*", "program*"],
    "studentNo": ["ogrenci no", "öğrenci no", "numara", "no", "ogrenci no*", "öğrenci no*", "numara*", "no*"],
    "phone": ["telefon", "telefon numarasi", "telefon numarası", "cep telefonu"],
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


def only_digits(value: Any) -> str:
    return re.sub(r"\D", "", clean_cell(value))


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
    text = clean_cell(value).upper()
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


def detect_header_row(df: pd.DataFrame, file_type: str, max_scan_rows: int = 15) -> int:
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

    return best_row_index


def build_mapping(headers: List[Any], file_type: str) -> Tuple[Dict[str, int], List[Dict[str, Any]]]:
    aliases = get_aliases(file_type)
    mapping: Dict[str, int] = {}
    ignored_headers: List[Dict[str, Any]] = []

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

    return mapping, ignored_headers


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


def normalize_student(row: List[Any], mapping: Dict[str, int]) -> Tuple[Dict[str, Any], List[str], List[str]]:
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

    parsed_class, parsed_branch = split_class_branch(class_name)

    if parsed_class:
        class_name = parsed_class

    if not branch and parsed_branch:
        branch = parsed_branch
        warnings.append("Şube sınıf alanından otomatik ayrıldı.")

    department = get_value(row, mapping, "department")
    student_no = get_value(row, mapping, "studentNo")
    phone = only_digits(get_value(row, mapping, "phone"))

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
        "studentNo": student_no,
        "phone": phone,
    }

    errors = validate_required(record, "student")

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


def analyze_excel(file_path: str, file_type: str) -> Dict[str, Any]:
    if file_type not in ["student", "teacher"]:
        raise ValueError("file_type student veya teacher olmalı.")

    path = Path(file_path)

    if not path.exists():
        raise FileNotFoundError(f"Dosya bulunamadı: {file_path}")

    df_raw = pd.read_excel(path, header=None, dtype=str)

    header_row = detect_header_row(df_raw, file_type)
    headers = df_raw.iloc[header_row].tolist()

    mapping, ignored_headers = build_mapping(headers, file_type)

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
            normalized, errors, warnings = normalize_student(row, mapping)

        if all(not clean_cell(v) for v in row):
            continue

        row_number = int(index) + 1

        if errors:
            invalid_rows.append({
                "rowNumber": row_number,
                "errors": errors,
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
        "totalRows": len(valid_rows) + len(invalid_rows),
        "validCount": len(valid_rows),
        "invalidCount": len(invalid_rows),
        "confidenceScore": score,
        "mapping": mapping,
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