const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const { readFileRows } = require("./services/excel_reader");
const { mapHeaders, hasRequiredFields } = require("./services/header_mapper");
const { validateRows } = require("./services/validator");
const { importUsers } = require("./services/firebase_importer");

admin.initializeApp();

exports.analyzeEdesisFile = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Giriş yapılmamış.");
  }

  const { fileBase64, fileName, type } = request.data;

  if (!["student", "teacher"].includes(type)) {
    throw new HttpsError("invalid-argument", "Geçersiz aktarım tipi.");
  }

  const rows = readFileRows({ fileBase64, fileName });

  if (rows.length < 2) {
    throw new HttpsError(
      "invalid-argument",
      "Dosyada aktarılacak kayıt bulunamadı."
    );
  }

  const headers = rows[0];
  const dataRows = rows.slice(1);

  const { mapping, unknownHeaders } = mapHeaders(headers, type);
  const requiredCheck = hasRequiredFields(mapping, type);
  const { validRows, invalidRows } = validateRows(dataRows, mapping, type);

  return {
    ok: requiredCheck.ok,
    type,
    fileName,
    totalColumns: headers.length,
    totalRows: dataRows.length,
    validCount: validRows.length,
    invalidCount: invalidRows.length,
    mapping,
    missingFields: requiredCheck.missing,
    usedHeaders: Object.keys(mapping),
    ignoredHeaders: unknownHeaders,
    preview: validRows.slice(0, 10).map((r) => r.normalized),
    invalidPreview: invalidRows.slice(0, 10),
  };
});

exports.importEdesisFile = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Giriş yapılmamış.");
  }

  const { fileBase64, fileName, type } = request.data;

  if (!["student", "teacher"].includes(type)) {
    throw new HttpsError("invalid-argument", "Geçersiz aktarım tipi.");
  }

  const rows = readFileRows({ fileBase64, fileName });

  if (rows.length < 2) {
    throw new HttpsError(
      "invalid-argument",
      "Dosyada aktarılacak kayıt bulunamadı."
    );
  }

  const headers = rows[0];
  const dataRows = rows.slice(1);

  const { mapping, unknownHeaders } = mapHeaders(headers, type);
  const requiredCheck = hasRequiredFields(mapping, type);

  if (!requiredCheck.ok) {
    throw new HttpsError(
      "invalid-argument",
      `Eksik zorunlu alanlar: ${requiredCheck.missing.join(", ")}`
    );
  }

  const { validRows, invalidRows } = validateRows(dataRows, mapping, type);
  const importSummary = await importUsers({ validRows, type });

  return {
    ok: true,
    type,
    fileName,
    totalColumns: headers.length,
    totalRows: dataRows.length,
    validCount: validRows.length,
    invalidCount: invalidRows.length,
    ignoredHeaders: unknownHeaders,
    invalidPreview: invalidRows.slice(0, 20),
    importSummary,
  };
});

exports.updateUserPassword = onCall(async (request) => {
  try {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Giriş yapılmamış.");
    }

    const adminDoc = await admin
      .firestore()
      .collection("users")
      .doc(request.auth.uid)
      .get();

    if (!adminDoc.exists || adminDoc.data().role !== "admin") {
      throw new HttpsError("permission-denied", "Bu işlem için yetkiniz yok.");
    }

    const { uid, password } = request.data;

    if (!uid || !password || password.length < 6) {
      throw new HttpsError(
        "invalid-argument",
        "Şifre en az 6 karakter olmalıdır."
      );
    }

    await admin.auth().updateUser(uid, { password });

    return {
      success: true,
      message: "Şifre güncellendi.",
    };
  } catch (error) {
    console.error("updateUserPassword error:", error);

    if (error instanceof HttpsError) {
      throw error;
    }

    throw new HttpsError(
      "internal",
      error.message || "Şifre güncellenemedi."
    );
  }
});