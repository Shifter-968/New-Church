const MAX_OCCURRENCES = 500

export function generateEventOccurrences({ startsAt, endsAt, frequency = 'none', interval = 1, weekdays = [], until = '' }) {
    const start = new Date(startsAt)
    const end = new Date(endsAt)
    if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime()) || end < start) {
        throw new Error('Enter valid start and end times. The end must not be before the start.')
    }
    if (frequency === 'none') return [{ starts_at: start.toISOString(), ends_at: end.toISOString() }]
    if (!['daily', 'weekly', 'monthly'].includes(frequency)) throw new Error('Choose a supported repeat schedule.')
    if (!Number.isInteger(interval) || interval < 1 || interval > 365) throw new Error('Repeat interval must be between 1 and 365.')
    if (!until) throw new Error('Choose the last date for this repeating event.')

    const [year, month, day] = until.split('-').map(Number)
    const through = new Date(year, month - 1, day, 23, 59, 59, 999)
    if (Number.isNaN(through.getTime()) || through < start) throw new Error('The repeat end date must be on or after the event start date.')
    const duration = end.getTime() - start.getTime()
    const selectedDays = new Set(weekdays.length ? weekdays : [start.getDay()])
    const occurrences = []
    const cursor = new Date(start.getFullYear(), start.getMonth(), start.getDate())
    const startDay = new Date(start.getFullYear(), start.getMonth(), start.getDate())
    const weekStart = new Date(startDay)
    weekStart.setDate(weekStart.getDate() - ((weekStart.getDay() + 6) % 7))

    while (cursor <= through) {
        const daysFromStart = Math.round((Date.UTC(cursor.getFullYear(), cursor.getMonth(), cursor.getDate()) - Date.UTC(startDay.getFullYear(), startDay.getMonth(), startDay.getDate())) / 86400000)
        const monthsFromStart = (cursor.getFullYear() - start.getFullYear()) * 12 + cursor.getMonth() - start.getMonth()
        const daysFromWeekStart = Math.round((Date.UTC(cursor.getFullYear(), cursor.getMonth(), cursor.getDate()) - Date.UTC(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate())) / 86400000)
        const isOccurrence = frequency === 'daily'
            ? daysFromStart % interval === 0
            : frequency === 'weekly'
                ? Math.floor(daysFromWeekStart / 7) % interval === 0 && selectedDays.has(cursor.getDay())
                : monthsFromStart % interval === 0 && cursor.getDate() === Math.min(start.getDate(), new Date(cursor.getFullYear(), cursor.getMonth() + 1, 0).getDate())

        if (isOccurrence) {
            const occurrenceStart = new Date(cursor)
            occurrenceStart.setHours(start.getHours(), start.getMinutes(), start.getSeconds(), start.getMilliseconds())
            if (occurrenceStart >= start) {
                if (occurrences.length === MAX_OCCURRENCES) throw new Error(`This schedule creates more than ${MAX_OCCURRENCES} events. Choose a later repeat interval or an earlier end date.`)
                occurrences.push({ starts_at: occurrenceStart.toISOString(), ends_at: new Date(occurrenceStart.getTime() + duration).toISOString() })
            }
        }
        cursor.setDate(cursor.getDate() + 1)
    }

    if (!occurrences.length) throw new Error('This repeat schedule does not include any dates in the selected range.')
    return occurrences
}