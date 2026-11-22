import assert from 'node:assert/strict'
import test from 'node:test'
import { cleanPrefs, cleanTimezone, due, quiet, localParts, reminderFor, daysBetween, messageFor } from './rules.mjs'

test('invalid user values are rejected and existing defaults remain safe', () => {
  const p = cleanPrefs({ nasilsin: false, gununAyetiSaat: '99:00', sessizBas: '22:30' })
  assert.equal(p.nasilsin, false)
  assert.equal(p.gununAyetiSaat, '08:30')
  assert.equal(p.sessizBas, '22:30')
  assert.equal(cleanTimezone('Not/AZone'), 'Europe/Istanbul')
})

test('quiet hours span midnight', () => {
  assert.equal(quiet(23 * 60, '23:00', '07:00'), true)
  assert.equal(quiet(6 * 60 + 59, '23:00', '07:00'), true)
  assert.equal(quiet(7 * 60, '23:00', '07:00'), false)
  assert.equal(due(8 * 60 + 39, '08:30'), true)
  assert.equal(due(8 * 60 + 45, '08:30'), false)
})

test('timezone conversion reflects Istanbul local time', () => {
  assert.deepEqual(localParts(new Date('2026-11-22T05:30:00Z'), 'Europe/Istanbul'),
    { day: '2026-11-22', minute: 510 })
})

test('day arithmetic survives month transitions', () => {
  assert.equal(daysBetween('2026-11-29', '2026-12-02'), 3)
})

test('morning reminder is deduplicated on client engagement', () => {
  const now = new Date('2026-11-22T05:30:00Z')
  assert.equal(reminderFor({ prefs: {}, timeZone: 'Europe/Istanbul' }, now)?.type, 'morning')
  assert.equal(reminderFor({ prefs: {}, timeZone: 'Europe/Istanbul', lastOpenDay: '2026-11-22' }, now), null)
})

test('reading reminder requires 3 days inactive and repeats no more than weekly', () => {
  const now = new Date('2026-11-22T14:30:00Z')
  const device = { prefs: { kaldiginYer: true }, timeZone: 'Europe/Istanbul',
    lastReadDay: '2026-11-19', lastReadSure: 2, lastReadPart: 3 }
  assert.deepEqual(reminderFor(device, now), { type: 'reading', day: '2026-11-22', link: '/oku/2/?b=4' })
  assert.equal(reminderFor({ ...device, lastReadReminderDay: '2026-11-20' }, now), null)
})

test('messages contain no mood history or unverified verses', () => {
  for (const type of ['morning', 'evening', 'reading', 'esma']) {
    assert.ok(messageFor(type).title)
    assert.ok(messageFor(type).body)
  }
})
