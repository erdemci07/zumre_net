import { initializeApp, getApps } from 'firebase-admin/app'
import { getAuth } from 'firebase-admin/auth'
import { getFirestore, FieldValue } from 'firebase-admin/firestore'
import { defineSecret } from 'firebase-functions/params'
import { onRequest } from 'firebase-functions/v2/https'
import webpush from 'web-push'

const SOURCE_PROJECT = 'paralel-okuma'
const ZUMRE_PROJECT = 'zumrenet-657e1'
const ALLOWED_ORIGIN = 'https://paralel-okuma.web.app'
const RUNTIME_IDENTITY = 'paralel-okuma-notifications@zumrenet-657e1.iam.gserviceaccount.com'
const publicVapid = defineSecret('PARALEL_PUSH_VAPID_PUBLIC')
const privateVapid = defineSecret('PARALEL_PUSH_VAPID_PRIVATE')
const sourceApp = getApps().find((app) => app.name === 'paralel-notify-source')
  ?? initializeApp({ projectId: SOURCE_PROJECT }, 'paralel-notify-source')
const destinationApp = getApps().find((app) => app.name === 'paralel-notify-destination')
  ?? initializeApp({ projectId: ZUMRE_PROJECT }, 'paralel-notify-destination')
const sourceDb = getFirestore(sourceApp)
const destinationDb = getFirestore(destinationApp)
const memberAuth = getAuth(sourceApp)

const preferences = {
  status_started: 'notifyStatusStarted',
  status_completed: 'notifyStatusCompleted',
  status_reset: 'notifyStatusStarted',
  comment_added: 'notifyCommentAdded',
  reading_plan_created: 'notifyPlanChanges',
  reading_plan_updated: 'notifyPlanChanges',
  book_started: 'notifyBookStarted',
}
const allowedTypes = new Set(Object.keys(preferences))
const isSubscription = (item) =>
  item && typeof item.endpoint === 'string'
    && item.endpoint.startsWith('https://')
    && typeof item.keys?.auth === 'string'
    && typeof item.keys?.p256dh === 'string'

function respond(res, status, body) {
  res.status(status).json(body)
}

function setCors(req, res) {
  const origin = req.get('origin')
  res.set('Vary', 'Origin')
  if (origin === ALLOWED_ORIGIN) {
    res.set('Access-Control-Allow-Origin', ALLOWED_ORIGIN)
    res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    res.set('Access-Control-Allow-Headers', 'Authorization, Content-Type')
  }
  return !origin || origin === ALLOWED_ORIGIN
}

async function verifyMember(req) {
  const authorization = req.get('authorization') || ''
  if (!authorization.startsWith('Bearer ')) throw Object.assign(new Error('Kimlik gerekli.'), { httpStatus: 401 })
  const verified = await memberAuth.verifyIdToken(authorization.slice(7))
  const profileSnap = await sourceDb.collection('users').doc(verified.uid).get()
  const profile = profileSnap.data()
  if (!profile || profile.isMember !== true || !['faruk', 'berfin'].includes(profile.profileId)) {
    throw Object.assign(new Error('Bu kullanıcı yetkili değil.'), { httpStatus: 403 })
  }
  return { uid: verified.uid, profileId: profile.profileId }
}

async function sendActivity(req, res) {
  const member = await verifyMember(req)
  const activityId = req.body?.activityId
  if (typeof activityId !== 'string' || !/^[A-Za-z0-9_-]{8,128}$/.test(activityId)) {
    return respond(res, 400, { error: 'Hareket kimliği geçersiz.' })
  }
  const activitySnap = await sourceDb.collection('activities').doc(activityId).get()
  if (!activitySnap.exists) return respond(res, 404, { error: 'Hareket bulunamadı.' })
  const activity = activitySnap.data()
  if (activity.actorUid !== member.uid || activity.actor !== member.profileId || !allowedTypes.has(activity.type)) {
    return respond(res, 403, { error: 'Hareket sahibi uyuşmuyor.' })
  }
  const createdMillis = activity.createdAt?.toMillis?.()
  if (!createdMillis || createdMillis < Date.now() - 24 * 60 * 60 * 1000 || createdMillis > Date.now() + 60_000) {
    return respond(res, 400, { error: 'Hareket gönderim süresi dolmuş.' })
  }

  // A persistent dispatch record stops duplicate requests and coordinates retries.
  const deliveryRef = destinationDb.collection('paralelNotificationDispatch').doc(activityId)
  const claimed = await destinationDb.runTransaction(async (tx) => {
    const previous = await tx.get(deliveryRef)
    const state = previous.data()
    if (state?.status === 'done' || (state?.status === 'processing' && state.startedAt?.toMillis?.() > Date.now() - 120_000)) {
      return false
    }
    tx.set(deliveryRef, {
      status: 'processing',
      actorUid: member.uid,
      bookId: String(activity.bookId ?? '').slice(0, 80),
      startedAt: FieldValue.serverTimestamp(),
    }, { merge: true })
    return true
  })
  if (!claimed) return respond(res, 200, { ok: true, duplicate: true })

  try {
    const members = await sourceDb.collection('users').where('isMember', '==', true).get()
    const recipients = members.docs.filter((doc) =>
      doc.id !== member.uid && ['faruk', 'berfin'].includes(doc.data().profileId))
    const bookId = String(activity.bookId ?? '')
    const bookSnap = bookId && /^[a-z0-9-]{1,80}$/.test(bookId)
      ? await sourceDb.collection('books').doc(bookId).get()
      : null
    const bookTitle = String(bookSnap?.data()?.title ?? 'kitap').slice(0, 90)
    const actor = member.profileId === 'faruk' ? 'Faruk' : 'Berfin'
    const label = String(activity.text ?? 'yeni bir okuma hareketi kaydetti.').slice(0, 180)
    const body = label.startsWith(actor) ? `${bookTitle}: ${label}` : `${actor} · ${bookTitle}: ${label}`
    const payloadBase = {
      notification: { title: 'Paralel Okuma 📚', body },
      data: { activityId, bookId },
    }

    webpush.setVapidDetails('https://zumrenet.com', publicVapid.value(), privateVapid.value())
    let delivered = 0
    let failed = 0
    for (const recipient of recipients) {
      if (recipient.data().notificationPrefs?.[preferences[activity.type]] === false) continue
      const recipientDevices = await recipient.ref.collection('devices').get()
      const link = `/${recipient.data().profileId}?book=${encodeURIComponent(bookId)}#activity`
      for (const device of recipientDevices.docs) {
        const info = device.data()
        if (info.type !== 'web_push' || !isSubscription(info.subscription)) continue
        const payload = JSON.stringify({ ...payloadBase, data: { ...payloadBase.data, link } })
        try {
          await webpush.sendNotification(info.subscription, payload, {
            TTL: 120,
            urgency: 'normal',
            topic: 'parallel' + activityId.slice(0, 20),
          })
          delivered++
        } catch (error) {
          failed++
          console.error('Paralel Okuma push failed', { status: error.statusCode, device: device.id })
        }
      }
    }
    await deliveryRef.set({
      status: failed ? 'partial' : 'done',
      delivered,
      failed,
      completedAt: FieldValue.serverTimestamp(),
    }, { merge: true })
    return respond(res, 200, { ok: true, delivered, failed })
  } catch (error) {
    await deliveryRef.set({ status: 'failed', updatedAt: FieldValue.serverTimestamp() }, { merge: true })
    throw error
  }
}

export const paralelNotifications = onRequest({
  region: 'us-central1',
  memory: '256MiB',
  maxInstances: 2,
  timeoutSeconds: 45,
  serviceAccount: RUNTIME_IDENTITY,
  secrets: [publicVapid, privateVapid],
  invoker: 'public',
}, async (req, res) => {
  if (!setCors(req, res)) return respond(res, 403, { error: 'Origin reddedildi.' })
  if (req.method === 'OPTIONS') return res.status(204).end()
  try {
    if (req.method === 'GET') {
      return respond(res, 200, { vapidPublicKey: publicVapid.value() })
    }
    if (req.method === 'POST') return await sendActivity(req, res)
    return respond(res, 405, { error: 'Yöntem desteklenmiyor.' })
  } catch (error) {
    console.error('Paralel notifications request failed', error)
    return respond(res, error.httpStatus ?? 500, { error: error.httpStatus ? error.message : 'Bildirim sunucusu hatası.' })
  }
})
