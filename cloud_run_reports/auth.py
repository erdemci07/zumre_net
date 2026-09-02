from fastapi import Header, HTTPException
from firebase_admin import auth, firestore


def require_admin(authorization: str | None = Header(default=None)) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Oturum doğrulanamadı.")

    token = authorization.removeprefix("Bearer ").strip()
    if not token:
        raise HTTPException(status_code=401, detail="Oturum doğrulanamadı.")

    try:
        decoded = auth.verify_id_token(token)
    except Exception:
        raise HTTPException(status_code=401, detail="Oturum doğrulanamadı.")

    uid = decoded.get("uid")
    if not uid:
        raise HTTPException(status_code=401, detail="Oturum doğrulanamadı.")

    user_doc = firestore.client().collection("users").document(uid).get()
    if not user_doc.exists or user_doc.to_dict().get("role") != "admin":
        raise HTTPException(status_code=403, detail="Bu işlem için yetkiniz yok.")

    return uid
