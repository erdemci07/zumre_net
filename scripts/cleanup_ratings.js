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
const apply = args.has("--apply");
const deleteLegacyCollections = args.has("--delete-legacy-collections");
const dryRun = !apply;

const ratingFields = [
  "rating",
  "comment",
  "ratingPopupClosed",
  "ratedAt",
];

admin.initializeApp();

const db = admin.firestore();
const fieldValue = admin.firestore.FieldValue;

async function cleanupQueueRatingFields() {
  const snapshot = await db.collection("queues").get();
  let matched = 0;
  let batch = db.batch();
  let batchSize = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const hasRatingField = ratingFields.some((field) =>
      Object.prototype.hasOwnProperty.call(data, field)
    );

    if (!hasRatingField) {
      continue;
    }

    matched += 1;

    if (!dryRun) {
      batch.update(doc.ref, {
        rating: fieldValue.delete(),
        comment: fieldValue.delete(),
        ratingPopupClosed: fieldValue.delete(),
        ratedAt: fieldValue.delete(),
      });
      batchSize += 1;

      if (batchSize >= 400) {
        await batch.commit();
        batch = db.batch();
        batchSize = 0;
      }
    }
  }

  if (!dryRun && batchSize > 0) {
    await batch.commit();
  }

  return matched;
}

async function countCollection(name) {
  const snapshot = await db.collection(name).get();
  return snapshot.size;
}

async function deleteCollection(name) {
  const snapshot = await db.collection(name).get();
  let batch = db.batch();
  let batchSize = 0;

  for (const doc of snapshot.docs) {
    batch.delete(doc.ref);
    batchSize += 1;

    if (batchSize >= 400) {
      await batch.commit();
      batch = db.batch();
      batchSize = 0;
    }
  }

  if (batchSize > 0) {
    await batch.commit();
  }

  return snapshot.size;
}

async function main() {
  console.log(dryRun ? "DRY RUN: no writes will be made." : "APPLY MODE");

  const queueMatches = await cleanupQueueRatingFields();
  console.log(
    `${queueMatches} queue document(s) contain rating fields: ${ratingFields.join(", ")}`
  );

  for (const collectionName of ["ratings", "feedback"]) {
    const count = await countCollection(collectionName);
    console.log(`${collectionName}: ${count} document(s) found.`);

    if (!dryRun && deleteLegacyCollections && count > 0) {
      const deleted = await deleteCollection(collectionName);
      console.log(`${collectionName}: ${deleted} document(s) deleted.`);
    }
  }

  if (dryRun) {
    console.log("Run with --apply to delete rating fields from queue documents.");
    console.log(
      "Add --delete-legacy-collections with --apply to delete ratings/feedback documents."
    );
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
