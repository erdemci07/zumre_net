// Pure reminder policy. No Firebase calls: easy to test in CI.
export const DEFAULT_PREFS = Object.freeze({
  gununAyeti: true, gununAyetiSaat: '08:30',
  nasilsin: true, nasilsinSaat: '20:30',
  kaldiginYer: false, haftaninIsmi: false,
  sessizBas: '23:00', sessizSon: '07:00',
})

export function validTime(x) {
  if (typeof x !== 'string' || !/^(?:[01][0-9]|2[0-3]):[0-5][0-9]$/.test(x)) return false
  return true
}

export function cleanPrefs(value) {
  const src = value && typeof value === 'object' ? value : {}
  const out = { ...DEFAULT_PREFS }
  for (const k of ['gununAyeti', 'nasilsin', 'kaldiginYer', 'haftaninIsmi'])
    if (typeof src[k] === 'boolean') out[k] = src[k]
  for (const k of ['gununAyetiSaat', 'nasilsinSaat', 'sessizBas', 'sessizSon'])
    if (validTime(src[k])) out[k] = src[k]
  return out
}

export function cleanTimezone(value) {
  if (typeof value !== 'string' || value.length > 70) return 'Europe/Istanbul'
  try { new Intl.DateTimeFormat('en', { timeZone: value }); return value }
  catch { return 'Europe/Istanbul' }
}

export function localParts(now, timeZone) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-US', {
    timeZone: cleanTimezone(timeZone), year: 'numeric', month: '2-digit',
    day: '2-digit', hour: '2-digit', minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(now).filter(x => x.type !== 'literal').map(x => [x.type, x.value]))
  return { day: `${parts.year}-${parts.month}-${parts.day}`,
    minute: Number(parts.hour) * 60 + Number(parts.minute) }
}

function minutes(s) { const [h, m] = s.split(':').map(Number); return h * 60 + m }

export function quiet(minute, start, end) {
  const a = minutes(start), b = minutes(end)
  if (a === b) return false // identical values disable quiet hours
  return a < b ? minute >= a && minute < b : minute >= a || minute < b
}

export function due(minute, time) {
  const at = minutes(time)
  // Scheduler fires every 15 minutes; allows a little execution delay.
  return minute >= at && minute < at + 15
}

export function daysBetween(older, newer) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(older || '') || !/^\d{4}-\d{2}-\d{2}$/.test(newer || '')) return null
  const diff = (Date.parse(newer + 'T00:00:00Z') - Date.parse(older + 'T00:00:00Z')) / 86400000
  return Number.isFinite(diff) ? diff : null
}

export function reminderFor(device, now = new Date()) {
  const pref = cleanPrefs(device.prefs)
  const { day, minute } = localParts(now, device.timeZone)
  if (quiet(minute, pref.sessizBas, pref.sessizSon)) return null
  // If the app was opened today, don't nudge them again.
  if (device.lastOpenDay === day) return null
  if (pref.gununAyeti && due(minute, pref.gununAyetiSaat)) return { type: 'morning', day, link: '/' }
  if (pref.nasilsin && due(minute, pref.nasilsinSaat)) return { type: 'evening', day, link: '/' }
  const inactivity = daysBetween(device.lastReadDay, day)
  const sinceReminder = daysBetween(device.lastReadReminderDay, day)
  if (pref.kaldiginYer && due(minute, '17:30') && inactivity !== null &&
      inactivity >= 3 && (sinceReminder === null || sinceReminder >= 7) &&
      Number.isInteger(device.lastReadSure) && device.lastReadSure >= 1 &&
      device.lastReadSure <= 114 && Number.isInteger(device.lastReadPart) &&
      device.lastReadPart >= 0) {
    return { type: 'reading', day, link: `/oku/${device.lastReadSure}/?b=${device.lastReadPart + 1}` }
  }
  // Esma is deliberately optional and never exposes personal mood data.
  if (pref.haftaninIsmi && due(minute, '11:00') &&
      new Date(day + 'T00:00:00Z').getUTCDay() === 0) {
    return { type: 'esma', day, link: '/esma/' }
  }
  return null
}

export function messageFor(type) {
  switch (type) {
    case 'morning': return {
      title: 'Güne küçük bir ayetle başlamak ister misin?',
      body: 'Bugünün ayeti seni bekliyor. Birkaç dakikanı kendine ayırabilirsin.',
    }
    case 'evening': return {
      title: 'Bugün gönlünden neler geçti?',
      body: 'Nasıl hissettiğini seç; sana eşlik edebilecek ayetleri birlikte keşfedelim.',
    }
    case 'reading': return {
      title: 'Kaldığın yer seni bekliyor',
      body: 'Son bıraktığın bölümden, kendi hızında okumaya devam edebilirsin.',
    }
    case 'esma': return {
      title: 'Bu hafta bir isimle düşünmeye ne dersin?',
      body: 'Esmâ’dan bir ismi ve anlamını keşfetmek için küçük bir davet.',
    }
    default: return null
  }
}
