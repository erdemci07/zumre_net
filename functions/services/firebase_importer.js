const admin = require("firebase-admin");

async function importUsers({ validRows, type }) {
  const db = admin.firestore();

  const summary = {
    totalValid: validRows.length,
    created: 0,
    updated: 0,
    failed: 0,
    errors: [],
  };

  for (const item of validRows) {
    const user = item.normalized;

    try {
      let authUser;
      let isNewUser = false;

      try {
        authUser = await admin.auth().getUserByEmail(user.email);
      } catch (e) {
        authUser = await admin.auth().createUser({
          email: user.email,
          password: user.password,
          displayName: user.fullName,
          disabled: false,
        });

        isNewUser = true;
      }

      const userData = {
        uid: authUser.uid,
        role: user.role,

        name: user.name,
        surname: user.surname,
        fullName: user.fullName,

        username: user.username,
        identityKey: user.identityKey,
        email: user.email,

        createdFrom: type === "teacher"
          ? "edesis_teacher_file"
          : "edesis_student_file",

        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (type === "student") {
        userData.className = user.className;
        userData.branch = user.branch;
        userData.studentNo = user.studentNo || "";
        userData.department = user.department || "";
      }

      if (type === "teacher") {
        userData.subjects = user.subjects || [];
        userData.teacherStatus = "available";
      }

      if (isNewUser) {
        userData.createdAt = admin.firestore.FieldValue.serverTimestamp();
      }

      await db.collection("users").doc(authUser.uid).set(userData, {
        merge: true,
      });

      if (isNewUser) {
        summary.created++;
      } else {
        summary.updated++;
      }
    } catch (e) {
      summary.failed++;
      summary.errors.push({
        rowNumber: item.rowNumber,
        fullName: user.fullName,
        username: user.username,
        message: e.message,
      });
    }
  }

  return summary;
}

module.exports = {
  importUsers,
};