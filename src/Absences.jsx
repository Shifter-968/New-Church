import React, { useEffect, useMemo, useState } from 'react'
import Papa from 'papaparse'
import { supabase } from './supabase'
import { downloadCsv } from './MemberImport'
import ActionLabel from './ActionLabel'

export function MyAbsences({ orgId }) {
  const [events, setEvents] = useState([])
  const [selected, setSelected] = useState('')
  const [reason, setReason] = useState('')
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [revision, setRevision] = useState(0)
  useEffect(() => {
    let active = true
    setLoading(true); setError('')
    supabase.rpc('my_absence_events', { target_org: orgId }).then(({ data, error: resultError }) => {
      if (!active) return
      if (resultError) setError(`Unable to load events: ${resultError.message}`)
      else setEvents(data)
      setLoading(false)
    }).catch((err) => { if (active) { setError(`Unable to load events: ${err.message}`); setLoading(false) } })
    return () => { active = false }
  }, [orgId, revision])
  async function save(event) {
    event.preventDefault()
    if (busy) return
    setBusy('save'); setError(''); setMessage('')
    try {
      const { error: rpcError } = await supabase.rpc('report_my_absence', { target_event: selected, report_reason: reason })
      if (rpcError) throw rpcError
      setMessage('Your absence notice was saved. It does not notify leaders automatically.')
      setSelected(''); setReason(''); setRevision((value) => value + 1)
    } catch (err) { setError(`${err.message || 'Unable to save the notice.'} Refresh before retrying if the connection was interrupted.`) }
    finally { setBusy('') }
  }
  async function withdraw(item) {
    if (busy || !window.confirm(`Withdraw your absence notice for ${item.title}?`)) return
    setBusy(item.event_id); setError(''); setMessage('')
    try {
      const { error: rpcError } = await supabase.rpc('withdraw_my_absence', { target_event: item.event_id })
      if (rpcError) throw rpcError
      setMessage('Absence notice withdrawn.'); setRevision((value) => value + 1)
      if (selected === item.event_id) { setSelected(''); setReason('') }
    } catch (err) { setError(`${err.message || 'Unable to withdraw the notice.'} Refresh before retrying if the connection was interrupted.`) }
    finally { setBusy('') }
  }
  const selectedEvent = events.find((item) => item.event_id === selected)
  const isPast = (item) => new Date(item.ends_at).getTime() < Date.now()
  return <section className="directory-card my-card"><div className="my-card-heading"><div><h2>Let your church know</h2><p>Report an absence for an upcoming or ongoing event. Your notice is separate from attendance and does not send an automatic notification.</p></div><button className="button button-outline" disabled={loading || Boolean(busy)} onClick={() => setRevision((value) => value + 1)}>Refresh</button></div>
    {error && <div className="notice notice-error" role="alert">{error}</div>}{message && <div className="notice" role="status">{message}</div>}
    {loading ? <p>Loading events…</p> : error ? null : events.length === 0 ? <p>No eligible upcoming or ongoing events. You need a linked record and an active branch assignment.</p> : <>
      <form className="my-form" onSubmit={save}><label>Event<select value={selected} required onChange={(event) => {
        const id = event.target.value
        setSelected(id); setReason(events.find((item) => item.event_id === id)?.reason || '')
      }}><option value="">Select an event</option>{events.filter((item) => !isPast(item)).map((item) => <option key={item.event_id} value={item.event_id} disabled={item.present}>{item.title} · {new Date(item.starts_at).toLocaleString()}{item.present ? ' · Present' : item.reported ? ' · Reported' : ''}</option>)}</select></label>
        <label>Reason <span className="optional">Optional</span><textarea value={reason} onChange={(event) => setReason(event.target.value)} maxLength={500} rows={3} placeholder="Share only what you are comfortable sharing" /></label>
        <p>Authorized church staff can see your reason. Avoid sensitive details you do not want to share.</p>
        <button className="button button-dark" disabled={Boolean(busy) || !selected || selectedEvent?.present}><ActionLabel busy={busy === 'save'} pending="Saving…">{selectedEvent?.reported ? 'Update notice' : 'Report absence'}</ActionLabel></button></form>
      {events.some((item) => item.reported) && <><h3>Your notices</h3><div className="my-list">{events.filter((item) => item.reported).map((item) => <article className="my-list-item" key={item.event_id}><div><strong>{item.title}</strong><p>{new Date(item.starts_at).toLocaleString()} · {item.branch_name}</p><small>{item.present ? 'Now marked present; this notice remains until withdrawn.' : 'Absence reported'}{item.reason ? ` · ${item.reason}` : ''}</small></div><button className="text-button" disabled={Boolean(busy)} onClick={() => withdraw(item)}><ActionLabel busy={busy === item.event_id} pending="Withdrawing…">Withdraw</ActionLabel></button></article>)}</div></>}
    </>}
  </section>
}

export function ReportedAbsences({ orgId, branches }) {
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [revision, setRevision] = useState(0)
  const [search, setSearch] = useState('')
  const [branch, setBranch] = useState('all')
  const [kind, setKind] = useState('all')
  useEffect(() => {
    let active = true
    setLoading(true); setError('')
    supabase.rpc('list_reported_absences', { target_org: orgId }).then(({ data, error: resultError }) => {
      if (!active) return
      if (resultError) setError(`Unable to load absence notices: ${resultError.message}`)
      else setItems(data)
      setLoading(false)
    }).catch((err) => { if (active) { setError(`Unable to load absence notices: ${err.message}`); setLoading(false) } })
    return () => { active = false }
  }, [orgId, revision])
  const visible = useMemo(() => {
    const term = search.trim().toLowerCase()
    return items.filter((item) => (branch === 'all' || item.branch_id === branch)
      && (kind === 'all' || item.person_kind === kind)
      && `${item.person_name} ${item.title} ${item.phone || ''}`.toLowerCase().includes(term))
  }, [items, branch, kind, search])
  function exportRows() {
    const data = visible.map((item) => ({ name: item.person_name, type: item.person_kind, phone: item.phone || '', event: item.title,
      event_start: item.starts_at, branch: item.branch_name, reason: item.reason, reported_at: item.updated_at,
      status: item.present ? 'Present after notice' : 'Absence reported' }))
    downloadCsv('reported-absences.csv', '\uFEFF' + Papa.unparse(data, { escapeFormulae: /^[\t\r\n ]*[=+\-@]|^[\t\r\n]/ }))
  }
  return <section className="directory-card my-card"><div className="my-card-heading"><div><h2>Reported absences</h2><p>Latest 1,000 notices in your permitted branches. A notice is not an attendance record; a later check-in is shown as present.</p></div><button className="button button-outline" disabled={loading} onClick={() => setRevision((value) => value + 1)}>Refresh</button></div>
    {error && <div className="notice notice-error" role="alert">{error}</div>}
    <div className="member-tools"><label>Search loaded notices<input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Name, event or phone" /></label>
      <label>Branch<select value={branch} onChange={(event) => setBranch(event.target.value)}><option value="all">All accessible branches</option>{branches.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
      <label>Person type<select value={kind} onChange={(event) => setKind(event.target.value)}><option value="all">Everyone</option><option value="member">Members</option><option value="visitor">Visitors</option></select></label>
      <button className="button button-outline" disabled={loading || Boolean(error) || !visible.length} onClick={exportRows}>Export shown CSV</button></div>
    <p>Reasons may be private. Handle exported files carefully. No automatic notifications are sent.</p>
    {loading ? <p>Loading notices…</p> : error ? null : !visible.length ? <p>No matching notices.</p> : <div className="my-list">{visible.map((item) => <article className="my-list-item" key={item.id}><div><strong>{item.person_name}</strong><p>{item.person_kind === 'member' ? 'Member' : 'Visitor'} · {item.branch_name} · {item.phone || 'No phone'}</p><p>{item.title} · {new Date(item.starts_at).toLocaleString()}</p><small>{item.present ? 'Present after notice' : 'Absence reported'} · Updated {new Date(item.updated_at).toLocaleString()}{item.reason ? ` · ${item.reason}` : ''}</small></div></article>)}</div>}
  </section>
}
