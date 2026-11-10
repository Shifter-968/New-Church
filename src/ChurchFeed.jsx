import React, { lazy, Suspense, useEffect, useState } from 'react'
import { CalendarDays, Megaphone, Trash2 } from 'lucide-react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'
import AudiencePicker from './AudiencePicker'
import { generateEventOccurrences } from './eventRecurrence'

const CalendarGrid = lazy(() => import('./CalendarGrid.jsx'))
const EventLocationPicker = lazy(() => import('./EventLocationPicker.jsx'))

const config = {
  announcements: { table: 'announcements', title: 'Church announcements', icon: Megaphone, sort: 'created_at' },
  calendar: { table: 'church_events', title: 'Church calendar', icon: CalendarDays, sort: 'starts_at' },
}
const blank = { title: '', content: '', starts_at: '', ends_at: '', location: '', location_latitude: '', location_longitude: '', recurrence_frequency: 'none', recurrence_interval: '1', recurrence_weekdays: [], recurrence_until: '' }
const dateTime = (value) => new Date(value).toLocaleString()
const dateOnly = (value) => value ? new Date(value).toLocaleDateString() : ''
const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
function recurrenceLabel(item) {
  if (!item.recurrence_frequency || item.recurrence_frequency === 'none') return ''
  const interval = Number(item.recurrence_interval || 1)
  const unit = item.recurrence_frequency === 'daily' ? 'day' : item.recurrence_frequency === 'weekly' ? 'week' : 'month'
  const cadence = interval === 1 ? `Every ${unit}` : `Every ${interval} ${unit}s`
  if (item.recurrence_frequency !== 'weekly' || !item.recurrence_weekdays?.length) return cadence
  return `${cadence} · ${item.recurrence_weekdays.map((day) => weekdays[day]).join(', ')}`
}
function localDateTime(value) {
  const date = new Date(value)
  const two = (number) => String(number).padStart(2, '0')
  return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())}T${two(date.getHours())}:${two(date.getMinutes())}`
}

export default function ChurchFeed({ page, orgId, organizations, owner, canAdmin }) {
  const current = config[page]
  const [filter, setFilter] = useState(owner ? '' : orgId)
  const [targetOrg, setTargetOrg] = useState(orgId || '')
  const [eventFilter, setEventFilter] = useState('upcoming')
  const [search, setSearch] = useState('')
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState('')
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [editing, setEditing] = useState(null)
  const [form, setForm] = useState(blank)
  const [reload, setReload] = useState(0)
  const [audience, setAudience] = useState({ everyone: true, roles: [], teams: [] })
  const [audienceOptions, setAudienceOptions] = useState([])
  const [optionsLoading, setOptionsLoading] = useState(false)
  const [optionsError, setOptionsError] = useState('')
  const [calendarRange, setCalendarRange] = useState(null)

  useEffect(() => {
    let active = true
    setAudienceOptions([]); setOptionsError('')
    if (!targetOrg || !(owner || canAdmin)) { setOptionsLoading(false); return () => { active = false } }
    setOptionsLoading(true)
    supabase.rpc('audience_options', { target_org: targetOrg }).then(({ data, error: requestError }) => {
      if (!active) return
      if (requestError) setOptionsError(`Unable to load audiences: ${requestError.message}`)
      else setAudienceOptions(data)
      setOptionsLoading(false)
    }).catch((err) => { if (active) { setOptionsError(`Unable to load audiences: ${err.message}`); setOptionsLoading(false) } })
    return () => { active = false }
  }, [targetOrg, owner, canAdmin])

  useEffect(() => {
    let active = true
    setLoading(true); setLoadError(''); setError(''); setItems([])
    let request = supabase.from(current.table).select('*').order(current.sort, { ascending: page === 'calendar' }).limit(page === 'calendar' ? 1000 : 100)
    if (filter) request = request.eq('organization_id', filter)
    if (page === 'calendar' && eventFilter === 'upcoming') request = request.gte('ends_at', new Date().toISOString())
    if (page === 'calendar' && calendarRange) request = request.gte('ends_at', calendarRange.start).lt('starts_at', calendarRange.end)
    request.then(({ data, error: requestError }) => {
      if (!active) return
      if (requestError) setLoadError(`Unable to load records: ${requestError.message}`)
      else setItems(data)
      setLoading(false)
    })
    return () => { active = false }
  }, [page, filter, eventFilter, reload, current.table, current.sort, calendarRange])

  const update = (key) => (event) => setForm((value) => {
    const next = { ...value, [key]: event.target.value }
    if (key === 'starts_at' && value.recurrence_frequency === 'weekly' && !value.recurrence_weekdays.length && next.starts_at) {
      next.recurrence_weekdays = [new Date(next.starts_at).getDay()]
    }
    return next
  })
  function edit(item) {
    setError(''); setMessage(''); setEditing(item); setTargetOrg(item.organization_id)
    setForm({ ...blank, title: item.title, content: page === 'calendar' ? item.description : item.content, starts_at: page === 'calendar' ? localDateTime(item.starts_at) : '', ends_at: page === 'calendar' ? localDateTime(item.ends_at) : '', location: item.location || '', location_latitude: item.location_latitude ?? '', location_longitude: item.location_longitude ?? '', recurrence_frequency: item.recurrence_frequency || 'none', recurrence_interval: String(item.recurrence_interval || 1), recurrence_weekdays: item.recurrence_weekdays || [], recurrence_until: item.recurrence_until || '' })
    setAudience({ everyone: item.audience_everyone, roles: item.audience_roles, teams: item.audience_teams })
  }
  function clearForm() { setEditing(null); setForm(blank); setTargetOrg(orgId || ''); setAudience({ everyone: true, roles: [], teams: [] }) }
  async function save(event) {
    event.preventDefault(); setError(''); setMessage('')
    if (!targetOrg) { setError('Select a church.'); return }
    if (optionsLoading || optionsError) { setError('Audience options are not available. Please reload before saving.'); return }
    if (!audience.everyone && !audience.roles.length && !audience.teams.length) { setError('Select at least one role, ministry or department, or choose everyone.'); return }
    if (!form.title.trim() || (page === 'announcements' && !form.content.trim())) { setError('Enter a title and message.'); return }
    const start = new Date(form.starts_at)
    const end = new Date(form.ends_at)
    let occurrences = []
    const recurrenceWeekdays = form.recurrence_frequency === 'weekly'
      ? form.recurrence_weekdays.length ? form.recurrence_weekdays : [start.getDay()]
      : []
    if (page === 'calendar') {
      try {
        occurrences = generateEventOccurrences({ startsAt: form.starts_at, endsAt: form.ends_at, frequency: form.recurrence_frequency, interval: Number(form.recurrence_interval), weekdays: recurrenceWeekdays, until: form.recurrence_until })
      } catch (validationError) { setError(validationError.message); return }
    }
    if (!editing && occurrences.length > 52 && !window.confirm(`This will create ${occurrences.length} individual event occurrences. Continue?`)) return
    const audienceFields = { audience_everyone: audience.everyone, audience_roles: audience.roles, audience_teams: audience.teams }
    const fields = page === 'calendar' ? { title: form.title.trim(), description: form.content.trim(), starts_at: start.toISOString(), ends_at: end.toISOString(), location: form.location.trim(), location_latitude: form.location_latitude === '' ? null : Number(form.location_latitude), location_longitude: form.location_longitude === '' ? null : Number(form.location_longitude), ...audienceFields } : { title: form.title.trim(), content: form.content.trim(), ...audienceFields }
    setBusy('save')
    try {
      const recurrenceSeriesId = form.recurrence_frequency === 'none' ? null : crypto.randomUUID()
      const request = editing
        ? supabase.from(current.table).update(fields).eq('id', editing.id).eq('organization_id', editing.organization_id)
        : supabase.from(current.table).insert(occurrences.map((occurrence) => ({
          ...fields,
          starts_at: occurrence.starts_at,
          ends_at: occurrence.ends_at,
          organization_id: targetOrg,
          recurrence_series_id: recurrenceSeriesId,
          recurrence_frequency: form.recurrence_frequency,
          recurrence_interval: Number(form.recurrence_interval),
          recurrence_weekdays: recurrenceWeekdays,
          recurrence_until: form.recurrence_frequency === 'none' ? null : form.recurrence_until,
        })))
      const { data, error: saveError } = await request.select('id')
      if (saveError) throw saveError
      if (!data?.length || (!editing && data.length !== occurrences.length)) throw new Error('The saved event count did not match the requested schedule. Refresh to check what was created.')
      setMessage(editing ? 'This event occurrence was updated.' : page === 'calendar' ? occurrences.length > 1 ? `${occurrences.length} event occurrences created.` : 'Event created.' : 'Announcement published.')
      clearForm(); setReload((value) => value + 1)
    } catch (saveError) { setError(saveError.message || 'Unable to save. Please try again.') } finally { setBusy('') }
  }
  async function remove(item) {
    if (!window.confirm(`Permanently delete "${item.title}"?`)) return
    setBusy(item.id); setError(''); setMessage('')
    try {
      const { data, error: deleteError } = await supabase.from(current.table).delete().eq('id', item.id).eq('organization_id', item.organization_id).select('id')
      if (deleteError) throw deleteError
      if (!data?.length) throw new Error('No record was deleted. Check your permissions.')
      if (editing?.id === item.id) clearForm()
      setMessage('Record deleted.'); setReload((value) => value + 1)
    } catch (deleteError) { setError(deleteError.message || 'Unable to delete. Please try again.') } finally { setBusy('') }
  }
  const Icon = current.icon
  const visibleItems = items.filter((item) => `${item.title} ${page === 'calendar' ? `${item.description || ''} ${item.location || ''}` : item.content || ''}`.toLowerCase().includes(search.trim().toLowerCase()))
  const calendarEvents = visibleItems.map((item) => ({
    id: item.id,
    title: item.title,
    start: item.starts_at,
    end: item.ends_at,
    extendedProps: { location: item.location, description: item.description, repeatLabel: recurrenceLabel(item) },
  }))
  if (page === 'calendar') return <div className="event-calendar-layout">
    <section className="directory-card my-card event-calendar-panel">
      <div className="my-card-heading"><span className="stat-icon mint"><Icon size={20} /></span><div><h2>{current.title}</h2><p>{owner ? 'Support view across churches.' : 'Events available to your account.'}</p></div></div>
      {owner && <label>Filter by church<select value={filter} onChange={(event) => setFilter(event.target.value)}><option value="">All churches</option>{organizations.map((org) => <option key={org.id} value={org.id}>{org.name}</option>)}</select></label>}
      <label className="calendar-filter">Events<select value={eventFilter} onChange={(event) => setEventFilter(event.target.value)}><option value="upcoming">Ongoing and upcoming</option><option value="all">All events</option></select></label>
      <label className="calendar-search">Search events<input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search title or location" /></label>
      {loadError && <div className="notice notice-error" role="alert">{loadError}</div>}{error && <div className="notice notice-error" role="alert">{error}</div>}{message && <div className="notice" role="status">{message}</div>}
      {loading ? <p>Loading events…</p> : loadError ? null : <Suspense fallback={<p>Loading calendar…</p>}><CalendarGrid events={calendarEvents} items={items} owner={owner} canAdmin={canAdmin} edit={edit} onRangeChange={(range) => setCalendarRange(range)} /></Suspense>}
      {visibleItems.length > 0 && <div className="event-calendar-count">Showing {visibleItems.length} of {items.length} loaded events{items.length >= 1000 ? ' · refine the church or search filter to narrow results' : ''}</div>}
    </section>
    {(owner || canAdmin) && <section className="directory-card my-card event-calendar-editor">
      <h2>{editing ? 'Edit event occurrence' : 'Add an event'}</h2>
      <p>{editing ? 'Only this occurrence will change; the rest of the repeating schedule stays as created.' : 'Choose a schedule, audience, and optional in-person map pin.'}</p>
      {optionsError && <div className="notice notice-error" role="alert">{optionsError}</div>}
      <form className="my-form" onSubmit={save}>
        {owner && <label>Church<select value={targetOrg} onChange={(event) => { setTargetOrg(event.target.value); setAudience({ everyone: true, roles: [], teams: [] }) }} disabled={Boolean(editing)} required><option value="">Select a church</option>{organizations.map((org) => <option key={org.id} value={org.id}>{org.name}</option>)}</select></label>}
        <label>Title<input maxLength={200} required value={form.title} onChange={update('title')} /></label>
        <label>Description<textarea maxLength={10000} value={form.content} onChange={update('content')} /></label>
        <div className="form-grid"><label>Starts<input type="datetime-local" required value={form.starts_at} onChange={update('starts_at')} /></label><label>Ends<input type="datetime-local" required value={form.ends_at} onChange={update('ends_at')} /></label></div>
        <Suspense fallback={<p>Loading map…</p>}><EventLocationPicker location={form.location} latitude={form.location_latitude} longitude={form.location_longitude} disabled={Boolean(busy)} onChange={(values) => setForm((value) => ({ ...value, ...values }))} /></Suspense>
        {!editing && <fieldset className="event-repeat">
          <legend>Repeat event</legend>
          <label>Frequency<select value={form.recurrence_frequency} onChange={(event) => setForm((value) => ({ ...value, recurrence_frequency: event.target.value, recurrence_weekdays: event.target.value === 'weekly' && !value.recurrence_weekdays.length && value.starts_at ? [new Date(value.starts_at).getDay()] : value.recurrence_weekdays }))}><option value="none">Does not repeat</option><option value="daily">Every day</option><option value="weekly">Every week</option><option value="monthly">Every month</option></select></label>
          {form.recurrence_frequency !== 'none' && <>
            <label>Repeat every<input type="number" min="1" max="365" value={form.recurrence_interval} onChange={update('recurrence_interval')} /><small>{form.recurrence_frequency === 'daily' ? 'day(s)' : form.recurrence_frequency === 'weekly' ? 'week(s)' : 'month(s)'}</small></label>
            {form.recurrence_frequency === 'weekly' && <fieldset className="event-weekdays"><legend>On these days</legend><div>{weekdays.map((day, index) => <label key={day}><input type="checkbox" checked={form.recurrence_weekdays.includes(index)} onChange={(event) => setForm((value) => ({ ...value, recurrence_weekdays: event.target.checked ? [...value.recurrence_weekdays, index].sort() : value.recurrence_weekdays.filter((weekday) => weekday !== index) }))} />{day}</label>)}</div></fieldset>}
            <label>Repeat until<input type="date" required value={form.recurrence_until} onChange={update('recurrence_until')} /><small>Creates up to 500 individual event dates.</small></label>
          </>}
        </fieldset>}
        {editing && form.recurrence_frequency !== 'none' && <p className="event-series-note">Part of a repeating schedule through {dateOnly(form.recurrence_until)}. Use this form to change this occurrence only.</p>}
        {optionsLoading ? <p>Loading audience options…</p> : <AudiencePicker options={audienceOptions} audience={audience} onChange={setAudience} disabled={Boolean(busy) || Boolean(optionsError) || !targetOrg} />}
        <div className="my-item-actions"><button className="button button-dark" disabled={Boolean(busy) || optionsLoading || Boolean(optionsError)} aria-busy={busy === 'save'}><ActionLabel busy={busy === 'save'} pending="Saving…">{editing ? 'Save occurrence' : 'Create event'}</ActionLabel></button>{editing && <><button className="button button-outline" disabled={Boolean(busy)} type="button" onClick={clearForm}>Cancel edit</button><button className="button button-outline" disabled={Boolean(busy)} type="button" onClick={() => remove(editing)}><Trash2 size={15} /> Delete occurrence</button></>}</div>
      </form>
    </section>}
  </div>

  return <div className="my-church-layout"><section className="directory-card my-card"><div className="my-card-heading"><span className="stat-icon mint"><Icon size={20} /></span><div><h2>{current.title}</h2><p>{owner ? 'Support view across churches. Showing up to 100 records.' : 'Showing up to 100 records available to your account.'}</p></div></div>
    {owner && <label>Filter by church<select value={filter} onChange={(event) => setFilter(event.target.value)}><option value="">All churches</option>{organizations.map((org) => <option key={org.id} value={org.id}>{org.name}</option>)}</select></label>}
    {page === 'calendar' && <label className="calendar-filter">Events<select value={eventFilter} onChange={(event) => setEventFilter(event.target.value)}><option value="upcoming">Ongoing and upcoming</option><option value="all">All events (earliest first)</option></select></label>}
    <label>Search loaded {page === 'calendar' ? 'events' : 'announcements'}<input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search title or details" /></label>
    {loadError && <div className="notice notice-error" role="alert">{loadError}</div>}{error && <div className="notice notice-error" role="alert">{error}</div>}{message && <div className="notice" role="status">{message}</div>}
    {loading ? <p>Loading…</p> : loadError ? null : !visibleItems.length ? <p>{items.length ? 'No matching records in the loaded list.' : 'Nothing here yet.'}</p> : <div className="my-list">{visibleItems.map((item) => <article className="my-list-item" key={item.id}><div><h3>{item.title}</h3>{owner && <small>{organizations.find((org) => org.id === item.organization_id)?.name || 'Church unavailable'}</small>}<p>{page === 'calendar' ? item.description : item.content}</p>{page === 'calendar' && <p>{dateTime(item.starts_at)} – {dateTime(item.ends_at)}{item.location && ` · ${item.location}`}</p>}<small>{page === 'announcements' ? `Published ${dateTime(item.created_at)}` : ''}{(owner || canAdmin) && ` · Audience: ${item.audience_everyone ? 'Everyone' : 'Selected groups'}`}</small></div>{(owner || canAdmin) && <div className="my-item-actions"><button className="text-button" disabled={Boolean(busy)} onClick={() => edit(item)}>Edit</button><button className="text-button" disabled={Boolean(busy)} onClick={() => remove(item)}><ActionLabel busy={busy === item.id} pending="Deleting…">Delete</ActionLabel></button></div>}</article>)}</div>}
  </section>{(owner || canAdmin) && <section className="directory-card my-card"><h2>{editing ? 'Edit' : page === 'calendar' ? 'Add an event' : 'Publish an announcement'}</h2><p>Choose everyone or combine selected roles, ministries and departments.</p>{optionsError && <div className="notice notice-error" role="alert">{optionsError}</div>}<form className="my-form" onSubmit={save}>{owner && <label>Church<select value={targetOrg} onChange={(event) => { setTargetOrg(event.target.value); setAudience({ everyone: true, roles: [], teams: [] }) }} disabled={Boolean(editing)} required><option value="">Select a church</option>{organizations.map((org) => <option key={org.id} value={org.id}>{org.name}</option>)}</select></label>}<label>Title<input maxLength={200} required value={form.title} onChange={update('title')} /></label><label>{page === 'calendar' ? 'Description' : 'Message'}<textarea maxLength={10000} required={page === 'announcements'} value={form.content} onChange={update('content')} /></label>{page === 'calendar' && <><label>Starts<input type="datetime-local" required value={form.starts_at} onChange={update('starts_at')} /></label><label>Ends<input type="datetime-local" required value={form.ends_at} onChange={update('ends_at')} /></label><label>Location<input maxLength={255} value={form.location} onChange={update('location')} /></label></>}{optionsLoading ? <p>Loading audience options…</p> : <AudiencePicker options={audienceOptions} audience={audience} onChange={setAudience} disabled={Boolean(busy) || Boolean(optionsError) || !targetOrg} />}<div className="my-item-actions"><button className="button button-dark" disabled={Boolean(busy) || optionsLoading || Boolean(optionsError)} aria-busy={busy === 'save'}><ActionLabel busy={busy === 'save'} pending="Saving…">{editing ? 'Save changes' : page === 'calendar' ? 'Create event' : 'Publish announcement'}</ActionLabel></button>{editing && <button className="button button-outline" disabled={Boolean(busy)} type="button" onClick={clearForm}>Cancel edit</button>}</div></form></section>}</div>
}
