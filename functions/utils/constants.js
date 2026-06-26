const STUDENT_FIELD_ALIASES = {
  name: ["AD", "ADI", "OGRENCI ADI"],
  surname: ["SOYAD", "SOYADI", "OGRENCI SOYADI"],
  username: ["KULLANICI ADI", "KULLANICI", "USERNAME"],
  password: ["SIFRE", "SIFRE", "PAROLA", "PASSWORD", "0FRE", "FRE"],
  className: ["SINIF", "SINIFI"],
  branch: ["SUBE", "SB", "UBE"],
  studentNo: ["NO", "NUMARA", "OGRENCI NO", "OKUL NO", "NUMARA"],
department: [
  "BOLUM",
  "BOLU M",
  "BÖLÜM",
  "BÃLÃM",
  "BÃ–LÃœM",
  "BÄLÄM",
  "B L M",
  "ALAN",
  "PROGRAM",
  "BOLUMU"
],};

const TEACHER_FIELD_ALIASES = {
  name: ["AD", "ADI", "OGRETMEN ADI"],
  surname: ["SOYAD", "SOYADI", "OGRETMEN SOYADI"],
  username: ["KULLANICI ADI", "KULLANICI", "USERNAME"],
  password: ["SIFRE", "PAROLA", "PASSWORD"],
  subjects: ["DERS", "BRANS", "BRANSI", "SUBJECT"],
};

module.exports = {
  STUDENT_FIELD_ALIASES,
  TEACHER_FIELD_ALIASES,
};