import { createHash, timingSafeEqual } from 'node:crypto'
import { initializeApp } from 'firebase-admin/app'
import { getFirestore, FieldValue } from 'firebase-admin/firestore'
import { defineSecret } from 'firebase-functions/params'
import { onRequest } from 'firebase-functions/v2/https'
import { onSchedule } from 'firebase-functions/v2/scheduler'
import webpush from 'web-push'
import { cleanPrefs, cleanTimezone, localParts, reminderFor, messageFor } from './rules.mjs'

// This dedicated codebase is isolated from ZümreNet's application functions.
initializeApp({ projectId: 'zumrenet-657e1' })
const db = getFirestore()
const RUNTIME_IDENTITY = 'ayet-rehberi-notifications@zumrenet-657e1.iam.gserviceaccount.com'
const publicKey = defineSecret('AYET_PUSH_VAPID_PUBLIC')
const privateKey = defineSecret('AYET_PUSH_VAPID_PRIVATE')
const ALLOWED_ORIGINS = new Set([
  'https://ayet-rehberi.web.app', 'https://ayet-rehberi.firebaseapp.com',
])
const COLLECTION = 'ayetPushDevices'
const DISPATCH = 'ayetPushDispatch'
const REGISTRATION_LIMIT = 'ayetPushRegistrationLimits'

function cors(req, res) {
  const origin = req.get('origin')
  res.set('Vary', 'Origin')
  if (origin && !ALLOWED_ORIGINS.has(origin)) return false
  if (origin) res.set('Access-Control-Allow-Origin', origin)
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
  res.set('Access-Control-Allow-Headers', 'Content-Type')
  res.set('Cache-Control', 'no-store')
  return true
}
function error(res, status, message) { return res.status(status).json({ error: message }) }
const digest = (s) => createHash('sha256').update(s).digest('hex')

function validateIdentity(body) {
  const id = body?.deviceId
  const secret = body?.deviceSecret
  if (typeof id !== 'string' || !/^[a-zA-Z0-9_-]{20,100}$/.test(id) ||
      typeof secret !== 'string' || !/^[a-f0-9]{64}$/.test(secret))
    throw Object.assign(new Error('Geçersiz cihaz kimliği.'), { status: 400 })
  return { id, hash: digest(secret) }
}
function sameHash(a, b) {
  if (typeof a !== 'string' || a.length !== 64 || b.length !== 64) return false
  return timingSafeEqual(Buffer.from(a, 'hex'), Buffer.from(b, 'hex'))
}
function validSubscription(s) {
  if (!s || typeof s !== 'object' || typeof s.endpoint !== 'string' ||
      s.endpoint.length > 2100 || !s.keys || typeof s.keys.p256dh !== 'string' ||
      typeof s.keys.auth !== 'string' ||
      !/^[A-Za-z0-9_-]{40,150}$/.test(s.keys.p256dh) ||
      !/^[A-Za-z0-9_-]{10,80}$/.test(s.keys.auth)) return false
  try {
    const u = new URL(s.endpoint)
    const h = u.hostname.toLowerCase()
    return u.protocol === 'https:' && !u.username && !u.password &&
      (!u.port || u.port === '443') &&
      (h === 'fcm.googleapis.com' || h === 'updates.push.services.mozilla.com' ||
       h.endsWith('.push.apple.com') || h.endsWith('.notify.windows.com'))
  } catch { return false }
}
function cleanDay(day) {
  return typeof day === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(day) ? day : null
}
function cleanSummary(body) {
  return {
    prefs: cleanPrefs(body.prefs),
    timeZone: cleanTimezone(body.timeZone),
    lastOpenDay: cleanDay(body.lastOpenDay),
    lastReadDay: cleanDay(body.lastReadDay),
    lastReadSure: Number.isInteger(body.lastReadSure) && body.lastReadSure >= 1 &&
      body.lastReadSure <= 114 ? body.lastReadSure : null,
    lastReadPart: Number.isInteger(body.lastReadPart) && body.lastReadPart >= 0 &&
      body.lastReadPart <= 500 ? body.lastReadPart : null,
  }
}
function pushConfig() {
  webpush.setVapidDetails('https://ayet-rehberi.web.app', publicKey.value(), privateKey.value())
}
async function send(subscription, kind, link) {
  pushConfig()
  return webpush.sendNotification(subscription, JSON.stringify({
    notification: messageFor(kind),
    data: { link, kind },
  }), { TTL: 60 * 60 * 3, urgency: 'normal' })
}
async function post(req, res) {
  if (!req.body || typeof req.body !== 'object' || JSON.stringify(req.body).length > 12000)
    return error(res, 400, 'İstek geçersiz.')
  const { id, hash } = validateIdentity(req.body)
  const ref = db.collection(COLLECTION).doc(id)
  const action = req.body.action
  if (action === 'subscribe') {
    if (!validSubscription(req.body.subscription)) return error(res, 400, 'Push aboneliği geçersiz.')
    const data = cleanSummary(req.body)
    const ip = String(req.ip || req.socket?.remoteAddress || 'unknown').slice(0, 130)
    const day = new Date().toISOString().slice(0, 10)
    const limitRef = db.collection(REGISTRATION_LIMIT).doc(digest(ip + ':' + day))
    const outcome = await db.runTransaction(async tx => {
      const existing = await tx.get(ref)
      if (existing.exists && !sameHash(existing.data().secretHash, hash)) return 'forbidden'
      // Public registration is not authenticated. Limit new registrations per client.
      // This is defense in depth, not a replacement for authenticated/App Check access.
      const limitSnap = !existing.exists ? await tx.get(limitRef) : null
      const count = limitSnap?.data()?.count || 0
      if (!existing.exists && count >= 8) return 'limited'
      if (!existing.exists) tx.set(limitRef, {
        count: count + 1, updatedAt: FieldValue.serverTimestamp(),
        expireAt: new Date(Date.now() + 48 * 3600_000),
      }, { merge: true })
      tx.set(ref, {
        ...data, secretHash: hash, subscription: {
          endpoint: req.body.subscription.endpoint,
          keys: { p256dh: req.body.subscription.keys.p256dh, auth: req.body.subscription.keys.auth },
        }, enabled: true, updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true })
      return 'ok'
    })
    if (outcome === 'limited') return error(res, 429, 'Bu bağlantıdan çok fazla cihaz kaydedildi.')
    if (outcome === 'forbidden') return error(res, 403, 'Cihaz anahtarı uyuşmadı.')
    return res.status(200).json({ ok: true })
  }

  const existing = await ref.get()
  if (!existing.exists || !sameHash(existing.data().secretHash, hash))
    return error(res, 403, 'Önce cihazı bağlayın.')
  if (action === 'unsubscribe') {
    // Erase the device and its delivery history when consent is revoked.
    const histories = await db.collection(DISPATCH).where('deviceId', '==', id).get()
    const batch = db.bulkWriter()
    for (const record of histories.docs) batch.delete(record.ref)
    batch.delete(ref)
    await batch.close()
    return res.status(200).json({ ok: true })
  }
  if (!existing.data().enabled) return error(res, 409, 'Bildirimler kapalı.')
  if (action === 'sync') {
    await ref.update({ ...cleanSummary(req.body), updatedAt: FieldValue.serverTimestamp() })
    return res.status(200).json({ ok: true })
  }
  if (action === 'test') {
    const last = existing.data().lastTestAt?.toMillis?.() ?? 0
    if (Date.now() - last < 60_000) return error(res, 429, 'Deneme için bir dakika bekleyin.')
    await ref.update({ lastTestAt: FieldValue.serverTimestamp() })
    pushConfig()
    await webpush.sendNotification(existing.data().subscription, JSON.stringify({
      notification: {
        title: 'Ayet Rehberi · Deneme bildirimi',
        body: 'Bağlantı çalışıyor. Sabah ve akşam hatırlatmaları artık bu cihazına ulaşabilir.',
      },
      data: { link: '/', kind: 'test' },
    }), { TTL: 120, urgency: 'normal' })
    return res.status(200).json({ ok: true })
  }
  return error(res, 400, 'Bilinmeyen işlem.')
}
export const ayetPushApi = onRequest({
  region: 'us-central1', memory: '256MiB', timeoutSeconds: 30, maxInstances: 3,
  serviceAccount: RUNTIME_IDENTITY,
  secrets: [publicKey, privateKey], invoker: 'public',
}, async (req, res) => {
  if (!cors(req, res)) return error(res, 403, 'Bu siteye erişim izni yok.')
  if (req.method === 'OPTIONS') return res.status(204).end()
  try {
    if (req.method === 'GET') return res.status(200).json({ vapidPublicKey: publicKey.value() })
    if (req.method === 'POST') return await post(req, res)
    return error(res, 405, 'Bu yöntem desteklenmiyor.')
  } catch (e) {
    console.error('Ayet push API:', e)
    return error(res, e.status || 500, e.status ? e.message : 'Bildirim sunucusu hatası.')
  }
})

export const dispatchAyetReminders = onSchedule({
  schedule: '*/15 * * * *', timeZone: 'UTC', region: 'us-central1',
  memory: '256MiB', timeoutSeconds: 180, maxInstances: 1,
  serviceAccount: RUNTIME_IDENTITY,
  secrets: [publicKey, privateKey],
}, async () => {
  const now = new Date()
  const snapshot = await db.collection(COLLECTION).where('enabled', '==', true).get()
  let delivered = 0, failed = 0, skipped = 0
  for (const device of snapshot.docs) {
    const d = device.data()
    if (!validSubscription(d.subscription)) { skipped++; continue }
    const selected = reminderFor(d, now)
    if (!selected) continue
    const localDate = localParts(now, d.timeZone).day
    // Separate dispatch record per device/day: at-most-once, max 2/day.
    const claimRef = db.collection(DISPATCH).doc(`${device.id}_${localDate}`)
    const claimed = await db.runTransaction(async tx => {
      const old = await tx.get(claimRef)
      const state = old.data() || {}
      const kinds = Array.isArray(state.types) ? state.types : []
      if (kinds.includes(selected.type) || kinds.length >= 2) return false
      tx.set(claimRef, {
        deviceId: device.id, types: [...kinds, selected.type], updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true })
      return true
    })
    if (!claimed) { skipped++; continue }
    try {
      await send(d.subscription, selected.type, selected.link)
      delivered++
      if (selected.type === 'reading')
        await device.ref.update({ lastReadReminderDay: localDate })
    } catch (e) {
      failed++
      console.warn('Ayet push failed:', { device: device.id, status: e.statusCode })
      if (e.statusCode === 404 || e.statusCode === 410)
        await device.ref.update({ enabled: false, disabledReason: 'subscription-expired' })
    }
  }
  console.info('Ayet push dispatch', { checked: snapshot.size, delivered, failed, skipped })
})
