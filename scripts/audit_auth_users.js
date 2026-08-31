const path = require("path");

let admin;

try {
  admin = require("firebase-admin");
} catch (_) {
  admin = require(path.join(
    __dirname,
    "..",
    "functions",
    "node_modules",
    "firebase-admin"
  ));
}

const args = new Set(process.argv.slice(2));
const deleteOrphanAuth = args.has("--delete-orphan-auth");

admin.initializeApp();

const db = admin.firestore();

async function listAllAuthUsers() {
  const users = [];
  let nextPageToken;

  do {
    const result = await admin.auth().listUsers(1000, nextPageToken);
    users.push(...result.users);
    nextPageToken = result.pageToken;
  } while (nextPageToken);

  return users;
}

async function listFirestoreUsers() {
  const snapshot = await db.collection("users").get();
  return snapshot.docs.map((doc) => ({
    uid: doc.id,
    email: doc.data().email || "",
    role: doc.data().role || "",
  }));
}

async function main() {
  const [authUsers, firestoreUsers] = await Promise.all([
    listAllAuthUsers(),
    listFirestoreUsers(),
  ]);

  const firestoreByUid = new Map(
    firestoreUsers.map((user) => [user.uid, user])
  );
  const authByUid = new Map(authUsers.map((user) => [user.uid, user]));

  const orphanAuthUsers = authUsers
    .filter((user) => !firestoreByUid.has(user.uid))
    .map((user) => ({
      uid: user.uid,
      email: user.email || "",
      disabled: user.disabled === true,
    }));

  const firestoreWithoutAuth = firestoreUsers
    .filter((user) => !authByUid.has(user.uid))
    .map((user) => ({
      uid: user.uid,
      email: user.email,
      role: user.role,
    }));

  console.log("Auth / Firestore kullanıcı denetimi");
  console.log({
    authUserCount: authUsers.length,
    firestoreUserCount: firestoreUsers.length,
    orphanAuthUserCount: orphanAuthUsers.length,
    firestoreWithoutAuthCount: firestoreWithoutAuth.length,
    mode: deleteOrphanAuth ? "DELETE_ORPHAN_AUTH" : "DRY_RUN",
  });

  console.log("Auth var / Firestore yok:");
  console.table(orphanAuthUsers);

  console.log("Firestore var / Auth yok:");
  console.table(firestoreWithoutAuth);

  if (!deleteOrphanAuth) {
    console.log(
      "Dry run tamamlandı. Auth kullanıcıları silinmedi. Silmek için bilinçli olarak --delete-orphan-auth kullanın."
    );
    return;
  }

  for (const user of orphanAuthUsers) {
    await admin.auth().deleteUser(user.uid);
    console.log("Orphan Auth kullanıcısı silindi:", {
      uid: user.uid,
      email: user.email,
    });
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Audit script hata verdi:", error);
    process.exit(1);
  });
