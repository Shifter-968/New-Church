import React, { useCallback, useEffect, useMemo, useState } from 'react'
import Papa from 'papaparse'
import { supabase } from './supabase'
import { canManageDirectory } from './access'
import { downloadCsv } from './MemberImport'
import ActionLabel from './ActionLabel'
import { filterAttendance } from './attendance'
import { isOrganizationAdmin } from './navigation'
import { MyAbsences } from './Absences'

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
  const [history, setHistory] = useState([])
  const [historyLoading, setHistoryLoading] = useState(true)
  const [historyError, setHistoryError] = useState('')
  const [historyRevision, setHistoryRevision] = useState(0)
  const load = useCallback(async () => {
    const { data, error: loadError } = await supabase.rpc('current_checkin_events', { target_org: orgId })
    if (loadError) throw loadError
    setEvents(data)
  }, [orgId])
  useEffect(() => {
    let active = true
    setHistoryLoading(true); setHistoryError('')
    supabase.rpc('my_attendance_history', { target_org: orgId }).then(({ data, error: loadError }) => {
      if (!active) return
      if (loadError) setHistoryError(`Unable to load attendance history: ${loadError.message}`)
      else setHistory(data)
      setHistoryLoading(false)
    }).catch((err) => { if (active) { setHistoryError(`Unable to load attendance history: ${err.message}`); setHistoryLoading(false) } })
    return () => { active = false }
  }, [orgId, historyRevision])
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
      const event = events.find((item) => item.event_id === id)
      if (!event) throw new Error('This event is no longer available. Refresh and try again.')
      if (event.event_format === 'physical' && !event.location_configured) throw new Error('This physical event has no map pin. Ask your church administrator to update the event location.')
      const position = event.event_format === 'physical' ? await deviceLocation() : null
      const { error: checkError } = await supabase.rpc('self_check_in', { target_event: id, device_latitude: position?.coords.latitude ?? null, device_longitude: position?.coords.longitude ?? null })
      if (checkError) throw checkError
      setMessage('You are checked in.')
      setHistoryRevision((value) => value + 1)
      try { await load() } catch (err) { setError(`Checked in, but events could not be refreshed: ${err.message}`) }
    } catch (err) { setError(`${err.message || 'Check-in could not be confirmed.'} If the connection was interrupted, refresh before retrying.`) }
    finally { setBusy('') }
  }
  async function refresh() {
    setBusy('refresh'); setError('')
    setHistoryRevision((value) => value + 1)
    try { await load() } catch (err) { setError(err.message || 'Unable to refresh events.') }
    finally { setBusy('') }
  }
  return <div className="my-church-layout"><section className="directory-card my-card"><div className="my-card-heading"><div><h2>Check in to an event</h2><p>Ongoing events for your linked member or visitor record. Virtual services allow check-in anywhere; physical events require your device to be within 100 m of the event pin.</p></div><button className="button button-outline" disabled={Boolean(busy)} onClick={refresh} aria-label="Refresh ongoing events and history"><ActionLabel busy={busy === 'refresh'} pending="Refreshing…">Refresh</ActionLabel></button></div>
    <Feedback error={error} message={message} />
    {loading ? <p>Loading events…</p> : !events.length ? <p>No ongoing events available. A linked record and active branch assignment are required; ask your church administrator if you need help.</p> : <div className="my-list">{events.map((event) => <article className="my-list-item" key={event.event_id}><div><h3>{event.title}</h3><p>{new Date(event.starts_at).toLocaleString()} – {new Date(event.ends_at).toLocaleString()} · {event.branch_name}</p><small>{event.event_format === 'virtual' ? `Virtual${event.location ? ` · ${event.location}` : ''}` : `Physical${event.location ? ` · ${event.location}` : ''}${!event.location_configured ? ' · Location pin required; contact your administrator' : ''}`}</small></div><button className="button button-dark" disabled={Boolean(busy) || event.already_checked_in || (event.event_format === 'physical' && !event.location_configured)} aria-label={event.already_checked_in ? 'Already checked in' : `Check in to ${event.title}`} onClick={() => checkIn(event.event_id)}><ActionLabel busy={busy === event.event_id} pending="Checking in…">{event.already_checked_in ? 'Checked in' : 'Mark me present'}</ActionLabel></button></article>)}</div>}
    <p>Physical check-ins use device location at the event pin; location can be inaccurate or spoofed, and is not stored with attendance records. Virtual check-ins do not request device location.</p>
  </section><MyAbsences orgId={orgId} /><section className="directory-card my-card"><h2>My attendance history</h2><p>Your latest 100 visible event check-ins, including those marked by an administrator. Events you no longer have permission to see are hidden.</p>
    {historyError && <div className="notice notice-error" role="alert">{historyError}</div>}
    {historyLoading ? <p>Loading attendance history…</p> : historyError ? null : !history.length ? <p>No attendance records available.</p> : <div className="my-list">{history.map((item) => <article className="my-list-item" key={item.event_id}><div><h3>{item.title}</h3><p>{new Date(item.starts_at).toLocaleString()} · {item.branch_name}</p><small>Checked in {new Date(item.checked_in_at).toLocaleString()} · {item.method === 'self' ? 'Self check-in' : 'Marked by an administrator'}</small></div></article>)}</div>}
  </section></div>
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
  const canCorrect = isOrganizationAdmin(owner, assignments)
  const [selectedCorrection, setSelectedCorrection] = useState(null)
  const [reason, setReason] = useState('')
  const [corrections, setCorrections] = useState([])
  const [correctionsLoading, setCorrectionsLoading] = useState(false)
  const [correctionsError, setCorrectionsError] = useState('')
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
  useEffect(() => {
    let active = true
    setCorrections([]); setCorrectionsError(''); setCorrectionsLoading(Boolean(eventId && canCorrect))
    if (eventId && canCorrect) supabase.rpc('list_attendance_corrections', { target_org: orgId, target_event: eventId }).then(({ data, error: loadError }) => {
      if (!active) return
      if (loadError) setCorrectionsError(`Unable to load corrections: ${loadError.message}`)
      else setCorrections(data)
      setCorrectionsLoading(false)
    }).catch((err) => { if (active) { setCorrectionsError(`Unable to load corrections: ${err.message}`); setCorrectionsLoading(false) } })
    return () => { active = false }
  }, [eventId, orgId, canCorrect, revision])
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
  async function correct(event) {
    event.preventDefault()
    if (busy || !selectedCorrection || !eventId) return
    if (reason.trim().length < 3) { setError('Enter at least 3 characters explaining the correction.'); return }
    setBusy('correct'); setError(''); setMessage('')
    try {
      const { error: saveError } = await supabase.rpc('correct_attendance', { target_org: orgId, target_event: eventId, target_attendance: selectedCorrection.id, correction_reason: reason })
      if (saveError) throw saveError
      setSelectedCorrection(null); setReason(''); setMessage('Attendance removed and the correction recorded.')
      setRevision((value) => value + 1)
    } catch (err) { setError(`${err.message || 'Unable to confirm the correction.'} If the connection was interrupted, refresh before retrying.`) }
    finally { setBusy('') }
  }
  function exportRecords() {
    const data = filtered.map((row) => ({ first_name: row.first_name, last_name: row.last_name, type: row.person_kind, branch: branches.find((item) => item.id === row.branch_id)?.name || 'Unavailable', checked_in_at: row.checked_in_at, method: row.method }))
    downloadCsv('attendance.csv', '\uFEFF' + Papa.unparse(data, { escapeFormulae: /^[\t\r\n ]*[=+\-@]|^[\t\r\n]/ }))
  }
  return <div className="my-church-layout"><section className="directory-card my-card"><h2>Event attendance</h2><p>Members and visitors share the same attendance list. Showing up to 100 events and 1,000 records per event.</p><Feedback error={error} message={message} />
    {loading ? <p>Loading attendance…</p> : <><label>Event<select value={eventId} disabled={Boolean(busy)} onChange={(event) => { setEventId(event.target.value); setSelectedCorrection(null); setReason(''); setError(''); setMessage('') }}><option value="">Select an event</option>{events.map((event) => <option key={event.id} value={event.id}>{event.title} · {new Date(event.starts_at).toLocaleString()}</option>)}</select></label>
      {eventId && <><div className="member-tools"><label>Type<select value={kind} onChange={(event) => setKind(event.target.value)}><option value="all">Everyone</option><option value="member">Members</option><option value="visitor">Visitors</option></select></label><label>Branch<select value={branch} onChange={(event) => setBranch(event.target.value)}><option value="all">All branches</option>{branches.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label>Search attendees<input value={search} onChange={(event) => setSearch(event.target.value)} /></label><button className="button button-outline" disabled={!filtered.length || recordsLoading} onClick={exportRecords}>Export shown CSV</button><button className="button button-outline" disabled={recordsLoading || Boolean(busy)} onClick={() => { setError(''); setRevision((value) => value + 1) }}>Refresh records</button></div>
        {recordsLoading ? <p>Loading attendance records…</p> : <><p>{filtered.length} records shown.</p>{filtered.length ? <div className="table-scroll"><table><thead><tr><th>PERSON</th><th>TYPE</th><th>BRANCH</th><th>CHECKED IN</th><th>METHOD</th>{canCorrect && <th>ACTION</th>}</tr></thead><tbody>{filtered.map((row) => <tr key={row.id}><td>{row.first_name} {row.last_name}</td><td>{row.person_kind}</td><td>{branches.find((item) => item.id === row.branch_id)?.name || 'Unavailable'}</td><td>{new Date(row.checked_in_at).toLocaleString()}</td><td>{row.method}</td>{canCorrect && <td><button className="text-button" disabled={Boolean(busy)} onClick={() => { setSelectedCorrection(row); setReason(''); setError(''); setMessage('') }}>Correct</button></td>}</tr>)}</tbody></table></div> : <p>No matching attendance records.</p>}</>}
        {canCorrect && selectedCorrection && <form className="my-form" onSubmit={correct}><h3>Remove mistaken check-in</h3><p>{selectedCorrection.first_name} {selectedCorrection.last_name} will no longer count as present for this event. The person may be checked in again. The original check-in, your account and the reason will be retained in correction history.</p><label>Reason<textarea required minLength={3} maxLength={500} value={reason} onChange={(event) => setReason(event.target.value)} /></label><div className="my-item-actions"><button className="button button-dark" disabled={Boolean(busy) || recordsLoading}><ActionLabel busy={busy === 'correct'} pending="Correcting…">Confirm correction</ActionLabel></button><button type="button" className="button button-outline" disabled={Boolean(busy)} onClick={() => { setSelectedCorrection(null); setReason('') }}>Cancel</button></div></form>}
        {canCorrect && <><h3>Correction history</h3><p>Latest 100 corrections for this event. Reasons are visible to church administrators and platform support.</p>{correctionsError && <div className="notice notice-error" role="alert">{correctionsError}</div>}{correctionsLoading ? <p>Loading corrections…</p> : correctionsError ? null : !corrections.length ? <p>No corrections for this event.</p> : <div className="my-list">{corrections.map((item) => <article className="my-list-item" key={item.id}><div><strong>{item.first_name} {item.last_name} · {item.person_kind}</strong><p>{branches.find((b) => b.id === item.branch_id)?.name || 'Branch unavailable'} · {item.reason}</p><small>Corrected {new Date(item.corrected_at).toLocaleString()} · Actor ID: {item.corrected_by} · Original check-in {new Date(item.checked_in_at).toLocaleString()} ({item.method})</small></div></article>)}</div>}</>}
      </>}
    </>}
  </section><section className="directory-card my-card"><h2>Mark someone present</h2><p>Choose an event, then search existing members or visitors. Only the first 1,000 accessible records of each type are searchable here. People must have a branch.</p>
    <label>Search people<input value={personSearch} onChange={(event) => setPersonSearch(event.target.value)} placeholder="Name, email or phone (at least two characters)" disabled={!eventId} /></label>
    {personSearch.trim().length >= 2 && !matchingPeople.length && <p>No eligible people found in the loaded records.</p>}
    <div className="my-list">{matchingPeople.map((person) => <article className="my-list-item" key={`${person.kind}-${person.id}`}><div><h3>{person.first_name} {person.last_name}</h3><p>{person.kind} · {branches.find((item) => item.id === person.branch_id)?.name || 'Branch unavailable'} · {person.email || 'No email'} · {person.phone || 'No phone'}{person.phone_2 && ` · ${person.phone_2}`}</p></div><button className="button button-outline" disabled={Boolean(busy) || recordsLoading} aria-label={`Mark ${person.first_name} ${person.last_name} present`} onClick={() => checkIn(person)}><ActionLabel busy={busy === person.id} pending="Marking…">Mark present</ActionLabel></button></article>)}</div>
  </section></div>
}
