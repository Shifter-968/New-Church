import test from 'node:test'
import assert from 'node:assert/strict'
import { generateEventOccurrences } from './eventRecurrence.js'

test('daily recurrence keeps the time and duration', () => {
    const events = generateEventOccurrences({ startsAt: '2026-11-10T09:00', endsAt: '2026-11-10T10:30', frequency: 'daily', interval: 1, until: '2026-11-12' })
    assert.equal(events.length, 3)
    assert.equal(new Date(events[2].starts_at).getHours(), 9)
    assert.equal(new Date(events[2].ends_at) - new Date(events[2].starts_at), 90 * 60 * 1000)
})

test('weekly recurrence uses selected weekdays and interval', () => {
    const events = generateEventOccurrences({ startsAt: '2026-11-02T18:00', endsAt: '2026-11-02T19:00', frequency: 'weekly', interval: 1, weekdays: [0, 1], until: '2026-11-09' })
    assert.deepEqual(events.map((event) => new Date(event.starts_at).getDay()), [1, 0, 1])
})

test('daily and weekly recurrence honor intervals greater than one', () => {
    const daily = generateEventOccurrences({ startsAt: '2026-11-10T09:00', endsAt: '2026-11-10T10:00', frequency: 'daily', interval: 2, until: '2026-11-14' })
    assert.deepEqual(daily.map((event) => new Date(event.starts_at).getDate()), [10, 12, 14])
    const weekly = generateEventOccurrences({ startsAt: '2026-11-02T09:00', endsAt: '2026-11-02T10:00', frequency: 'weekly', interval: 2, weekdays: [1], until: '2026-11-30' })
    assert.deepEqual(weekly.map((event) => new Date(event.starts_at).getDate()), [2, 16, 30])
})

test('monthly recurrence clamps to the last day of shorter months', () => {
    const events = generateEventOccurrences({ startsAt: '2026-01-31T12:00', endsAt: '2026-01-31T13:00', frequency: 'monthly', interval: 1, until: '2026-03-31' })
    assert.deepEqual(events.map((event) => new Date(event.starts_at).getDate()), [31, 28, 31])
})

test('repeating schedules require an end date and enforce a creation cap', () => {
    assert.throws(() => generateEventOccurrences({ startsAt: '2026-11-10T09:00', endsAt: '2026-11-10T10:00', frequency: 'daily' }), /last date/)
    assert.throws(() => generateEventOccurrences({ startsAt: '2026-01-01T09:00', endsAt: '2026-01-01T10:00', frequency: 'daily', until: '2028-01-01' }), /more than 500/)
})