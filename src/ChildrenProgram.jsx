import React, { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from './supabase'
import { canManageDirectory, canManageMembers } from './access'
import ActionLabel from './ActionLabel'
import { downloadCsv } from './MemberImport'
import { childrenTemplateCsv, parseChildrenCsv } from './childrenCsv'

const emptyChild = { branch_id: '', first_name: '', last_name: '', date_of_birth: '', residence: '', parent_contact: '' }
const emptyEvent = { branch_id: '', title: '', description: '', starts_at: '', ends_at: '' }

function localDateTime(value) {
  const date = new Date(value)
  const pad = (part) => String(part).padStart(2, '0')
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`
}

function eventOngoing(event) {
  const now = Date.now()
  return new Date(event.starts_at).getTime() <= now && new Date(event.ends_at).getTime() >= now
}

export default function ChildrenProgram({ orgId, branches, owner, assignments }) {
  const [children, setChildren] = useState([])
  const [events, setEvents] = useState([])
  const [attendance, setAttendance] = useState([])
  const [eventId, setEventId] = useState('')
  const [childForm, setChildForm] = useState(emptyChild)
  const [eventForm, setEventForm] = useState(emptyEvent)
  const [editingChild, setEditingChild] = useState('')
  const [editingEvent, setEditingEvent] = useState('')
  const [search, setSearch] = useState('')
  const [attendanceSearch, setAttendanceSearch] = useState('')
  const [importBranch, setImportBranch] = useState('')
  const [importRows, setImportRows] = useState(null)
  const [importFileName, setImportFileName] = useState('')
  const [loading, setLoading] = useState(true)
  const [attendanceLoading, setAttendanceLoading] = useState(false)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const can = (action, branchId) => canManageDirectory(owner, assignments, 'children', action, branchId)
    || canManageMembers(owner, assignments, action, branchId)

  const load = useCallback(async () => {
    const [childrenResult, eventsResult] = await Promise.all([
      supabase.from('church_children').select('*').eq('organization_id', orgId).order('last_name').limit(1000),
      supabase.from('church_children_events').select('*').eq('organization_id', orgId).order('starts_at', { ascending: false }).limit(1000),
    ])
    if (childrenResult.error || eventsResult.error) throw childrenResult.error || eventsResult.error
    setChildren(childrenResult.data)
    setEvents(eventsResult.data)
  }, [orgId])

  useEffect(() => {
    let active = true
    setLoading(true); setError('')
    load().catch((err) => { if (active) setError(`Unable to load children: ${err.message}`) })
      .finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [load])

  useEffect(() => {
    let active = true
    setAttendance([]); setAttendanceLoading(Boolean(eventId))
    if (!eventId) return () => { active = false }
    supabase.from('church_children_event_attendance').select('*').eq('event_id', eventId)
      .then(({ data, error: resultError }) => {
        if (!active) return
        if (resultError) setError(`Unable to load attendance: ${resultError.message}`)
        else setAttendance(data)
        setAttendanceLoading(false)
      }).catch((err) => {
        if (active) { setError(`Unable to load attendance: ${err.message}`); setAttendanceLoading(false) }
      })
    return () => { active = false }
  }, [eventId])

  const filteredChildren = useMemo(() => {
    const term = search.trim().toLowerCase()
    return children.filter((child) => `${child.first_name} ${child.last_name} ${child.parent_contact} ${child.residence}`.toLowerCase().includes(term))
  }, [children, search])
  const selectedEvent = events.find((item) => item.id === eventId)
  const presentIds = useMemo(() => new Set(attendance.map((item) => item.child_id)), [attendance])
  const eligibleChildren = useMemo(() => {
    if (!selectedEvent) return []
    const term = attendanceSearch.trim().toLowerCase()
    return children.filter((child) => child.branch_id === selectedEvent.branch_id
      && can('create', child.branch_id)
      && (!term || `${child.first_name} ${child.last_name} ${child.parent_contact}`.toLowerCase().includes(term)))
  }, [children, selectedEvent, attendanceSearch, owner, assignments])
  const editableBranches = branches.filter((branch) => can(editingChild ? 'update' : 'create', branch.id))
  const eventBranches = branches.filter((branch) => can(editingEvent ? 'update' : 'create', branch.id))
  const importBranches = branches.filter((branch) => can('create', branch.id))

  async function run(key, operation, success) {
    if (busy) return
    setBusy(key); setError(''); setMessage('')
    try {
      await operation()
      setMessage(success)
      try { await load() } catch (err) { setError(`Saved, but the children list could not be refreshed: ${err.message}`) }
    } catch (err) {
      setError(err.message || 'Unable to save. Please try again.')
    } finally { setBusy('') }
  }

  async function saveChild(event) {
    event.preventDefault()
    const values = {
      first_name: childForm.first_name.trim(),
      last_name: childForm.last_name.trim(),
      date_of_birth: childForm.date_of_birth || null,
      residence: childForm.residence.trim(),
      parent_contact: childForm.parent_contact.trim(),
    }
    await run('child', async () => {
      const request = editingChild
        ? supabase.from('church_children').update(values).eq('id', editingChild).eq('organization_id', orgId)
        : supabase.from('church_children').insert({ ...values, organization_id: orgId, branch_id: childForm.branch_id })
      const { data, error: saveError } = await request.select('id')
      if (saveError) throw saveError
      if (!data?.length) throw new Error('No child record was saved. Check your permissions.')
      setEditingChild(''); setChildForm(emptyChild)
    }, editingChild ? 'Child updated.' : 'Child added.')
  }

  async function deleteChild(child) {
    if (!window.confirm(`Delete ${child.first_name} ${child.last_name}? Children linked to families or attendance records cannot be deleted.`)) return
    await run(child.id, async () => {
      const { data, error: deleteError } = await supabase.from('church_children').delete().eq('id', child.id).eq('organization_id', orgId).select('id')
      if (deleteError) throw deleteError
      if (!data?.length) throw new Error('No child record was deleted. Check your permissions.')
      if (editingChild === child.id) { setEditingChild(''); setChildForm(emptyChild) }
    }, 'Child deleted.')
  }

  async function saveEvent(event) {
    event.preventDefault()
    const startsAt = new Date(eventForm.starts_at)
    const endsAt = new Date(eventForm.ends_at)
    if (!Number.isFinite(startsAt.getTime()) || !Number.isFinite(endsAt.getTime()) || endsAt <= startsAt) {
      setError('Enter an end time after the event start time.')
      return
    }
    const values = {
      title: eventForm.title.trim(),
      description: eventForm.description.trim(),
      starts_at: startsAt.toISOString(),
      ends_at: endsAt.toISOString(),
    }
    await run('event', async () => {
      const request = editingEvent
        ? supabase.from('church_children_events').update(values).eq('id', editingEvent).eq('organization_id', orgId)
        : supabase.from('church_children_events').insert({ ...values, organization_id: orgId, branch_id: eventForm.branch_id })
      const { data, error: saveError } = await request.select('id')
      if (saveError) throw saveError
      if (!data?.length) throw new Error('No children event was saved. Check your permissions.')
      setEditingEvent(''); setEventForm(emptyEvent)
    }, editingEvent ? 'Children event updated.' : 'Children event created.')
  }

  async function deleteEvent(item) {
    if (!window.confirm(`Delete "${item.title}"? Events with attendance records cannot be deleted.`)) return
    await run(item.id, async () => {
      const { data, error: deleteError } = await supabase.from('church_children_events').delete().eq('id', item.id).eq('organization_id', orgId).select('id')
      if (deleteError) throw deleteError
      if (!data?.length) throw new Error('No event was deleted. Check your permissions.')
      if (eventId === item.id) { setEventId(''); setAttendance([]) }
      if (editingEvent === item.id) { setEditingEvent(''); setEventForm(emptyEvent) }
    }, 'Children event deleted.')
  }

  async function recordAttendance(child) {
    if (!selectedEvent || busy || !eventOngoing(selectedEvent)) return
    await run(`attendance-${child.id}`, async () => {
      const { error: saveError } = await supabase.rpc('mark_child_event_attendance', { target_event: selectedEvent.id, target_child: child.id })
      if (saveError) throw saveError
      const { data, error: listError } = await supabase.from('church_children_event_attendance').select('*').eq('event_id', selectedEvent.id)
      if (listError) throw listError
      setAttendance(data)
    }, `${child.first_name} ${child.last_name} marked present.`)
  }

  async function removeAttendance(item) {
    if (!window.confirm('Remove this child attendance record?')) return
    await run(`remove-${item.id}`, async () => {
      const { error: saveError } = await supabase.rpc('remove_child_event_attendance', { target_attendance: item.id })
      if (saveError) throw saveError
      setAttendance((current) => current.filter((entry) => entry.id !== item.id))
    }, 'Attendance record removed.')
  }

  async function chooseImport(event) {
    setImportRows(null); setImportFileName(''); setError('')
    const file = event.target.files?.[0]
    if (!file) return
    try {
      if (file.size > 2 * 1024 * 1024) throw new Error('The CSV file must be 2 MB or smaller.')
      setImportRows(parseChildrenCsv(await file.text()))
      setImportFileName(file.name)
    } catch (err) {
      setError(err.message || 'Unable to read this CSV file.')
    }
  }

  async function importChildren() {
    if (busy || !importRows || !importBranches.some((branch) => branch.id === importBranch)) return
    if (!window.confirm(`Import ${importRows.length} child records into the selected branch?`)) return
    await run('import', async () => {
      const { error: importError } = await supabase.from('church_children').insert(importRows.map((row) => ({
        ...row, organization_id: orgId, branch_id: importBranch,
      })))
      if (importError) throw importError
      setImportRows(null); setImportFileName(''); setImportBranch('')
    }, `${importRows.length} children imported.`)
  }

  return <div className="my-church-layout">
    <section className="directory-card my-card">
      <h2>Children</h2>
      <p>Manage child records separately from member accounts. Link children to families under Families. Up to 1,000 records are shown.</p>
      {error && <div className="notice notice-error" role="alert">{error}</div>}
      {message && <div className="notice" role="status">{message}</div>}
      {(editingChild || editableBranches.length > 0) && <form className="my-form" onSubmit={saveChild}>
        <h3>{editingChild ? 'Edit child' : 'Add a child'}</h3>
        <label>Branch<select required value={childForm.branch_id} disabled={Boolean(editingChild) || Boolean(busy)} onChange={(event) => setChildForm({ ...childForm, branch_id: event.target.value })}><option value="">Select a branch</option>{editableBranches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}</select></label>
        <label>First name<input required maxLength={100} value={childForm.first_name} onChange={(event) => setChildForm({ ...childForm, first_name: event.target.value })} /></label>
        <label>Surname<input required maxLength={100} value={childForm.last_name} onChange={(event) => setChildForm({ ...childForm, last_name: event.target.value })} /></label>
        <label>Date of birth<input type="date" value={childForm.date_of_birth || ''} onChange={(event) => setChildForm({ ...childForm, date_of_birth: event.target.value })} /></label>
        <label>Parent or guardian contact<input required maxLength={120} value={childForm.parent_contact} onChange={(event) => setChildForm({ ...childForm, parent_contact: event.target.value })} /></label>
        <label>Residence<input maxLength={255} value={childForm.residence} onChange={(event) => setChildForm({ ...childForm, residence: event.target.value })} /></label>
        <div className="my-item-actions"><button className="button button-dark" disabled={Boolean(busy)}><ActionLabel busy={busy === 'child'} pending="Saving…">{editingChild ? 'Save child' : 'Add child'}</ActionLabel></button>{editingChild && <button type="button" className="button button-outline" disabled={Boolean(busy)} onClick={() => { setEditingChild(''); setChildForm(emptyChild) }}>Cancel</button>}</div>
      </form>}
      <label>Search children<input value={search} onChange={(event) => setSearch(event.target.value)} /></label>
      {loading ? <p>Loading children…</p> : !filteredChildren.length ? <p>No children found.</p> : <div className="my-list">{filteredChildren.map((child) => <article className="my-list-item" key={child.id}><div><strong>{child.first_name} {child.last_name}</strong><p>{branches.find((branch) => branch.id === child.branch_id)?.name || 'Branch unavailable'} · Guardian: {child.parent_contact}</p>{child.date_of_birth && <small>Date of birth: {child.date_of_birth}</small>}{child.residence && <small> · Residence: {child.residence}</small>}</div><div className="my-item-actions">{can('update', child.branch_id) && <button className="text-button" disabled={Boolean(busy)} onClick={() => { setEditingChild(child.id); setChildForm(child) }}>Edit</button>}{can('delete', child.branch_id) && <button className="text-button" disabled={Boolean(busy)} onClick={() => deleteChild(child)}><ActionLabel busy={busy === child.id} pending="Deleting…">Delete</ActionLabel></button>}</div></article>)}</div>}
    </section>

    <section className="directory-card my-card">
      <h2>Import children from CSV</h2>
      <p>CSV fields match the child form. Organization and branch IDs in uploaded files are ignored; select the destination branch here. Up to 1,500 rows and 2 MB per file.</p>
      <button type="button" className="text-button" onClick={() => downloadCsv('children-import-template.csv', childrenTemplateCsv())}>Download children CSV template</button>
      <label>Branch<select value={importBranch} onChange={(event) => setImportBranch(event.target.value)} disabled={Boolean(busy)}><option value="">Select a branch</option>{importBranches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}</select></label>
      <label>CSV file<input type="file" accept=".csv,text/csv" onChange={chooseImport} disabled={Boolean(busy)} /></label>
      {importRows && <p>{importFileName}: {importRows.length} valid child {importRows.length === 1 ? 'row' : 'rows'} ready to import.</p>}
      {importBranches.length === 0 && <p>You need child creation permission on a branch to import children.</p>}
      <button type="button" className="button button-dark" disabled={Boolean(busy) || !importRows || !importBranch} onClick={importChildren}><ActionLabel busy={busy === 'import'} pending="Importing…">Import children</ActionLabel></button>
    </section>

    <section className="directory-card my-card">
      <h2>Children’s events</h2>
      <p>Create events for children by branch. Children’s attendance is recorded manually by an authorized church user; there is no child self check-in.</p>
      {(editingEvent || eventBranches.length > 0) && <form className="my-form" onSubmit={saveEvent}>
        <h3>{editingEvent ? 'Edit children’s event' : 'Create children’s event'}</h3>
        <label>Branch<select required value={eventForm.branch_id} disabled={Boolean(editingEvent) || Boolean(busy)} onChange={(event) => setEventForm({ ...eventForm, branch_id: event.target.value })}><option value="">Select a branch</option>{eventBranches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}</select></label>
        <label>Event title<input required maxLength={200} value={eventForm.title} onChange={(event) => setEventForm({ ...eventForm, title: event.target.value })} /></label>
        <label>Description<textarea maxLength={5000} value={eventForm.description} onChange={(event) => setEventForm({ ...eventForm, description: event.target.value })} /></label>
        <div className="form-grid"><label>Starts<input type="datetime-local" required value={eventForm.starts_at} onChange={(event) => setEventForm({ ...eventForm, starts_at: event.target.value })} /></label><label>Ends<input type="datetime-local" required value={eventForm.ends_at} onChange={(event) => setEventForm({ ...eventForm, ends_at: event.target.value })} /></label></div>
        <div className="my-item-actions"><button className="button button-dark" disabled={Boolean(busy)}><ActionLabel busy={busy === 'event'} pending="Saving…">{editingEvent ? 'Save event' : 'Create event'}</ActionLabel></button>{editingEvent && <button type="button" className="button button-outline" disabled={Boolean(busy)} onClick={() => { setEditingEvent(''); setEventForm(emptyEvent) }}>Cancel</button>}</div>
      </form>}
      {loading ? <p>Loading events…</p> : !events.length ? <p>No children’s events have been created.</p> : <div className="my-list">{events.map((item) => <article className="my-list-item" key={item.id}><div><strong>{item.title}</strong><p>{branches.find((branch) => branch.id === item.branch_id)?.name || 'Branch unavailable'} · {new Date(item.starts_at).toLocaleString()} – {new Date(item.ends_at).toLocaleString()}</p>{item.description && <small>{item.description}</small>}</div><div className="my-item-actions"><button className="text-button" onClick={() => setEventId(item.id)}>{eventId === item.id ? 'Selected' : 'Take attendance'}</button>{can('update', item.branch_id) && <button className="text-button" disabled={Boolean(busy)} onClick={() => { setEditingEvent(item.id); setEventForm({ ...item, starts_at: localDateTime(item.starts_at), ends_at: localDateTime(item.ends_at) }) }}>Edit</button>}{can('delete', item.branch_id) && <button className="text-button" disabled={Boolean(busy)} onClick={() => deleteEvent(item)}>Delete</button>}</div></article>)}</div>}
    </section>

    <section className="directory-card my-card">
      <h2>Manual children’s attendance</h2>
      <label>Children’s event<select value={eventId} onChange={(event) => setEventId(event.target.value)} disabled={Boolean(busy)}><option value="">Select an event</option>{events.map((item) => <option key={item.id} value={item.id}>{item.title} · {new Date(item.starts_at).toLocaleString()}</option>)}</select></label>
      {!selectedEvent ? <p>Select an event to record attendance.</p> : <>
        <p>{selectedEvent.title} · {branches.find((branch) => branch.id === selectedEvent.branch_id)?.name || 'Branch unavailable'} · {eventOngoing(selectedEvent) ? 'Ongoing' : 'Attendance is only available while the event is ongoing.'}</p>
        <label>Search children<input value={attendanceSearch} onChange={(event) => setAttendanceSearch(event.target.value)} placeholder="Name or guardian contact" disabled={!eventOngoing(selectedEvent)} /></label>
        {attendanceLoading ? <p>Loading attendance…</p> : eligibleChildren.length === 0 ? <p>No children are available in this event’s branch.</p> : <div className="my-list">{eligibleChildren.map((child) => <article className="my-list-item" key={child.id}><div><strong>{child.first_name} {child.last_name}</strong><p>Guardian: {child.parent_contact}{presentIds.has(child.id) ? ' · Present' : ' · Not marked present'}</p></div><button className="button button-outline" disabled={Boolean(busy) || attendanceLoading || !eventOngoing(selectedEvent) || presentIds.has(child.id)} onClick={() => recordAttendance(child)}><ActionLabel busy={busy === `attendance-${child.id}`} pending="Recording…">{presentIds.has(child.id) ? 'Present' : 'Mark present'}</ActionLabel></button></article>)}</div>}
        {attendance.length > 0 && <><h3>Attendance records ({attendance.length})</h3><div className="my-list">{attendance.map((item) => { const child = children.find((entry) => entry.id === item.child_id); return <article className="my-list-item" key={item.id}><div><strong>{child ? `${child.first_name} ${child.last_name}` : 'Child unavailable'}</strong><p>Recorded {new Date(item.checked_in_at).toLocaleString()}</p></div>{can('update', item.branch_id) && <button className="text-button" disabled={Boolean(busy)} onClick={() => removeAttendance(item)}>Remove record</button>}</article> })}</div></>}
      </>}
    </section>
  </div>
}
