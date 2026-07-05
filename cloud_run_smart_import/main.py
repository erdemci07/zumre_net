import base64
import tempfile
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import firebase_admin
from firebase_admin import auth, firestore

from smart_import_engine import analyze_excel

app = FastAPI()

if not firebase_admin._apps:
    firebase_admin.initialize_app()

db = firestore.client()


class AnalyzeRequest(BaseModel):
    fileBase64: str
    fileName: str
    type: str


class ImportRequest(BaseModel):
    type: str
    validRows: list


@app.post("/analyze")
def analyze_file(request: AnalyzeRequest):
    if request.type not in ["student", "teacher"]:
        raise HTTPException(status_code=400, detail="Geçersiz dosya tipi.")

    try:
        file_bytes = base64.b64decode(request.fileBase64)

        suffix = ".xlsx"
        if request.fileName.lower().endswith(".xls"):
            suffix = ".xls"

        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            tmp.write(file_bytes)
            tmp_path = tmp.name

        return analyze_excel(tmp_path, request.type)

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/import")
def import_users(request: ImportRequest):
    if request.type not in ["student", "teacher"]:
        raise HTTPException(status_code=400, detail="Geçersiz aktarım tipi.")

    if not request.validRows:
        raise HTTPException(status_code=400, detail="Aktarılacak kayıt yok.")

    created = 0
    updated = 0
    failed = 0
    failed_rows = []

    for row in request.validRows:
        try:
            email = row.get("email")
            password = row.get("password", "123456")
            username = row.get("username")

            if not email or not username:
                failed += 1
                failed_rows.append({
                    "row": row,
                    "error": "email veya username eksik",
                })
                continue

            try:
                user = auth.get_user_by_email(email)
                uid = user.uid
                auth.update_user(uid, password=password)
                updated += 1
            except auth.UserNotFoundError:
                user = auth.create_user(
                    email=email,
                    password=password,
                    display_name=row.get("fullName", ""),
                )
                uid = user.uid
                created += 1

            user_data = {
                "uid": uid,
                "role": request.type,
                "email": email,
                "username": username,
                "identityKey": row.get("identityKey", username),
                "name": row.get("name", ""),
                "surname": row.get("surname", ""),
                "fullName": row.get("fullName", ""),
                "phone": row.get("phone", ""),
                "updatedAt": firestore.SERVER_TIMESTAMP,
            }
            if request.type == "student":
                user_data.update({
                    "className": row.get("className", ""),
                    "branch": row.get("branch", ""),
                    "department": row.get("department", ""),
                    "studentNo": row.get("studentNo", ""),
                })

            doc_ref = db.collection("users").document(uid)
            existing_doc = doc_ref.get()

            if request.type == "teacher":
                user_data.update({
                    "subjects": row.get("subjects", []),
                })

                if not existing_doc.exists:
                    user_data.update({
                        "teacherStatus": "absent",
                        "weeklyAvailability": {},
                    })

            if not existing_doc.exists:
                user_data["createdAt"] = firestore.SERVER_TIMESTAMP

            doc_ref.set(user_data, merge=True)

        except Exception as e:
            failed += 1
            failed_rows.append({
                "row": row,
                "error": str(e),
            })

    return {
        "ok": failed == 0,
        "type": request.type,
        "totalValid": len(request.validRows),
        "created": created,
        "updated": updated,
        "failed": failed,
        "failedRows": failed_rows[:20],
    }