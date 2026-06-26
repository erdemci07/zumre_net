const XLSX = require("xlsx");
const Papa = require("papaparse");

function readFileRows({ fileBase64, fileName }) {
  if (!fileBase64 || !fileName) {
    throw new Error("Dosya bilgisi eksik.");
  }

  const lowerName = fileName.toLowerCase();
  const buffer = Buffer.from(fileBase64, "base64");

  if (lowerName.endsWith(".xlsx") || lowerName.endsWith(".xls")) {
    return readExcel(buffer);
  }

  if (lowerName.endsWith(".csv") || lowerName.endsWith(".txt")) {
    return readCsv(buffer);
  }

  throw new Error("Desteklenmeyen dosya türü. CSV, TXT, XLS veya XLSX yükleyin.");
}

function readExcel(buffer) {
  const workbook = XLSX.read(buffer, { type: "buffer" });

  const firstSheetName = workbook.SheetNames[0];

  if (!firstSheetName) {
    throw new Error("Excel dosyasında sayfa bulunamadı.");
  }

  const sheet = workbook.Sheets[firstSheetName];

  const rows = XLSX.utils.sheet_to_json(sheet, {
    header: 1,
    defval: "",
    raw: false,
  });

  return cleanRows(rows);
}

function readCsv(buffer) {
  let content = buffer.toString("utf8");

  if (content.includes("�")) {
    content = buffer.toString("latin1");
  }

  const delimiter = content.includes("\t") ? "\t" : ",";

  const parsed = Papa.parse(content, {
    delimiter,
    skipEmptyLines: true,
  });

  if (parsed.errors && parsed.errors.length > 0) {
    throw new Error(`CSV okuma hatası: ${parsed.errors[0].message}`);
  }

  return cleanRows(parsed.data);
}

function cleanRows(rows) {
  return rows
    .map((row) => row.map((cell) => String(cell ?? "").trim()))
    .filter((row) => row.some((cell) => cell !== ""));
}

module.exports = {
  readFileRows,
};