import React, { useCallback, useEffect, useMemo, useState } from 'react'
import Papa from 'papaparse'
import { supabase } from './supabase'
import { canManageDirectory } from './access'
import { downloadCsv } from './MemberImport'
import ActionLabel from './ActionLabel'
import { filterAttendance } from './attendance'

function Feedback({ error, message }) {
  return <>{error && <div className="notice notice-error" role="alert">{error}</div>}{message && <div className="notice" role="status">{message}</div>}</>
}

function deviceLocation() {
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) { reject(new Error('Location is unavailable. Use a secure browser connection and allow location access.')); return }
    navigator.geolocation.getCurrentPosition(resolve, (err) => reject(new Error(`Unable to get your location: ${err.message}`)), { enableHighAccuracy: true, timeout: 20000, maximumAge: 0 })
  })
}

export function SelfAttendance({ orgId }) {
  const [events, setEvents] = useState([])
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const load = useCallback(async () => {
    const { data, error: loadError } = await supabase.rpc('current_checkin_events', { target_org: orgId })
    if (loadError) throw loadError
    setEvents(data)
  }, [orgId])
  useEffect(() => {
    let active = true
    supabase.rpc('current_checkin_events', { target_org: orgId }).then(({ data, error: loadError }) => {
      if (!active) return
      if (loadError) setError(`Unable to load events: ${loadError.message}`)
      else setEvents(data)
      setLoading(false)
    }).catch((err) => { if (active) { setError(err.message || 'Unable to load events.'); setLoading(false) } })
    return () => { active = false }
  }, [orgId])
  async function checkIn(id) {
    if (busy) return
    setBusy(id); setError(''); setMessage('')
    try {
      const position = await deviceLocation()
      const { error: checkError } = await supabase.rpc('self_check_in', { target_event: id, device_latitude: position.coords.latitude, device_longitude: position.coords.longitude })
      if (checkError) throw checkError
      setMessage('You are checked in.')
      try { await load() } catch (err) { setError(`Checked in, but events could not be refreshed: ${err.message}`) }
    } catch (err) { setError(`${err.message || 'Check-in could not be confirmed.'} If the connection was interrupted, refresh before retrying.`) }
    finally { setBusy('') }
  }
  async function refresh() {
    setBusy('refresh'); setError('')
    try { await load() } catch (err) { setError(err.message || 'Unable to refresh events.') }
    finally { setBusy('') }
  }
  return <section className="directory-card my-card"><div className="my-card-heading"><div><h2>Check in to an event</h2><p>Ongoing church events for your linked member or visitor record. You must be within your registered branch's configured location.</p></div><button className="button button-outline" disabled={Boolean(busy)} onClick={refresh} aria-label="Refresh ongoing events"><ActionLabel busy={busy === 'refresh'} pending="Refreshing…">Refresh</ActionLabel></button></div>
    <Feedback error={error} message={message} />
    {loading ? <p>Loading events…</p> : !events.length ? <p>No ongoing events available. A linked record and active branch assignment are required; ask your church administrator if you need help.</p> : <div className="my-list">{events.map((event) => <article className="my-list-item" key={event.event_id}><div><h3>{event.title}</h3><p>{new Date(event.starts_at).toLocaleString()} – {new Date(event.ends_at).toLocaleString()} · {event.branch_name}</p></div><button className="button button-dark" disabled={Boolean(busy) || event.already_checked_in} aria-label={event.already_checked_in ? 'Already checked in' : `Check in to ${event.title}`} onClick={() => checkIn(event.event_id)}><ActionLabel busy={busy === event.event_id} pending="Checking in…">{event.already_checked_in ? 'Checked in' : 'Mark me present'}</ActionLabel></button></article>)}</div>}
    <p>Device location is checked when you tap the button. Location can be inaccurate or spoofed; it is not stored with the attendance record.</p>
  </section>
}

export function AttendanceManagement({ orgId, branches, owner, assignments }) {
  const [events, setEvents] = useState([])
  const [people, setPeople] = useState([])
  const [records, setRecords] = useState([])
  const [eventId, setEventId] = useState('')
  const [kind, setKind] = useState('all')
  const [branch, setBranch] = useState('all')
  const [search, setSearch] = useState('')
  const [personSearch, setPersonSearch] = useState('')
  const [loading, setLoading] = useState(true)
  const [recordsLoading, setRecordsLoading] = useState(false)
  const [revision, setRevision] = useState(0)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const can = (action, branchId) => canManageDirectory(owner, assignments, 'attendance', action, branchId)
  const loadRecords = useCallback(async (id) => {
    const { data, error: loadError } = await supabase.rpc('list_event_attendance', { target_org: orgId, target_event: id })
    if (loadError) throw loadError
    return data
  }, [orgId])
  useEffect(() => {
    let active = true
    async function load() {
      const results = await Promise.all([
        supabase.from('church_events').select('id,title,starts_at,ends_at').eq('organization_id', orgId).order('starts_at', { ascending: false }).limit(100),
        supabase.from('members').select('id,first_name,last_name,email,phone,phone_2,branch_id,status').eq('organization_id', orgId).order('first_name').limit(1000),
        supabase.from('visitors').select('id,first_name,last_name,email,phone,branch_id').eq('organization_id', orgId).order('first_name').limit(1000),
      ])
      const failure = results.find((result) => result.error)
      if (failure) throw failure.error
      if (active) { setEvents(results[0].data); setPeople([...results[1].data.filter((item) => item.status === 'active').map((item) => ({ ...item, kind: 'member' })), ...results[2].data.map((item) => ({ ...item, kind: 'visitor' }))]) }
    }
    load().catch((err) => { if (active) setError(`Unable to load attendance: ${err.message}`) }).finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [orgId])
  useEffect(() => {
    let active = true
    setRecords([]); setRecordsLoading(Boolean(eventId))
    if (eventId) loadRecords(eventId).then((data) => { if (active) setRecords(data) }).catch((err) => { if (active) setError(`Unable to load records: ${err.message}`) }).finally(() => { if (active) setRecordsLoading(false) })
    return () => { active = false }
  }, [eventId, loadRecords, revision])
  const filtered = useMemo(() => filterAttendance(records, kind, branch, search), [records, kind, branch, search])
  const matchingPeople = useMemo(() => {
    const term = personSearch.trim().toLowerCase()
    if (term.length < 2) return []
    return people.filter((p) => p.branch_id && can('create', p.branch_id) && [`${p.first_name} ${p.last_name}`, p.email, p.phone, p.phone_2].some((value) => value?.toLowerCase().includes(term))).slice(0, 30)
  }, [people, personSearch, owner, assignments])
  async function checkIn(person) {
    if (busy || recordsLoading || !eventId) return
    setBusy(person.id); setError(''); setMessage('')
    try {
      const { error: saveError } = await supabase.rpc('admin_check_in', { target_event: eventId, person_kind: person.kind, person_id: person.id })
      if (saveError) throw saveError
      setMessage(`${person.first_name} ${person.last_name} marked present.`)
      try { setRecords(await loadRecords(eventId)) } catch (err) { setError(`Saved, but the attendance list could not be refreshed: ${err.message}`) }
    } catch (err) { setError(`${err.message || 'Unable to confirm attendance.'} If the connection was interrupted, refresh before retrying.`) }
    finally { setBusy('') }
  }
  function exportRecords() {
    const data = filtered.map((row) => ({ first_name: row.first_name, last_name: row.last_name, type: row.person_kind, branch: branches.find((item) => item.id === row.branch_id)?.name || 'Unavailable', checked_in_at: row.checked_in_at, method: row.method }))
    downloadCsv('attendance.csv', '\uFEFF' + Papa.unparse(data, { escapeFormulae: /^[\t\r\n ]*[=+\-@]|^[\t\r\n]/ }))
  }
  return <div className="my-church-layout"><section className="directory-card my-card"><h2>Event attendance</h2><p>Members and visitors share the same attendance list. Showing up to 100 events and 1,000 records per event.</p><Feedback error={error} message={message} />
    {loading ? <p>Loading attendance…</p> : <><label>Event<select value={eventId} disabled={Boolean(busy)} onChange={(event) => { setEventId(event.target.value); setError(''); setMessage('') }}><option value="">Select an event</option>{events.map((event) => <option key={event.id} value={event.id}>{event.title} · {new Date(event.starts_at).toLocaleString()}</option>)}</select></label>
      {eventId && <><div className="member-tools"><label>Type<select value={kind} onChange={(event) => setKind(event.target.value)}><option value="all">Everyone</option><option value="member">Members</option><option value="visitor">Visitors</option></select></label><label>Branch<select value={branch} onChange={(event) => setBranch(event.target.value)}><option value="all">All branches</option>{branches.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label>Search attendees<input value={search} onChange={(event) => setSearch(event.target.value)} /></label><button className="button button-outline" disabled={!filtered.length || recordsLoading} onClick={exportRecords}>Export shown CSV</button><button className="button button-outline" disabled={recordsLoading || Boolean(busy)} onClick={() => { setError(''); setRevision((value) => value + 1) }}>Refresh records</button></div>
        {recordsLoading ? <p>Loading attendance records…</p> : <><p>{filtered.length} records shown.</p>{filtered.length ? <div className="table-scroll"><table><thead><tr><th>PERSON</th><th>TYPE</th><th>BRANCH</th><th>CHECKED IN</th><th>METHOD</th></tr></thead><tbody>{filtered.map((row) => <tr key={row.id}><td>{row.first_name} {row.last_name}</td><td>{row.person_kind}</td><td>{branches.find((item) => item.id === row.branch_id)?.name || 'Unavailable'}</td><td>{new Date(row.checked_in_at).toLocaleString()}</td><td>{row.method}</td></tr>)}</tbody></table></div> : <p>No matching attendance records.</p>}</>}</>}
    </>}
  </section><section className="directory-card my-card"><h2>Mark someone present</h2><p>Choose an event, then search existing members or visitors. Only the first 1,000 accessible records of each type are searchable here. People must have a branch.</p>
    <label>Search people<input value={personSearch} onChange={(event) => setPersonSearch(event.target.value)} placeholder="Name, email or phone (at least two characters)" disabled={!eventId} /></label>
    {personSearch.trim().length >= 2 && !matchingPeople.length && <p>No eligible people found in the loaded records.</p>}
    <div className="my-list">{matchingPeople.map((person) => <article className="my-list-item" key={`${person.kind}-${person.id}`}><div><h3>{person.first_name} {person.last_name}</h3><p>{person.kind} · {branches.find((item) => item.id === person.branch_id)?.name || 'Branch unavailable'} · {person.email || 'No email'} · {person.phone || 'No phone'}{person.phone_2 && ` · ${person.phone_2}`}</p></div><button className="button button-outline" disabled={Boolean(busy) || recordsLoading} aria-label={`Mark ${person.first_name} ${person.last_name} present`} onClick={() => checkIn(person)}><ActionLabel busy={busy === person.id} pending="Marking…">Mark present</ActionLabel></button></article>)}</div>
  </section></div>
}
