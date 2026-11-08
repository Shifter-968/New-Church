import React, { useEffect, useState } from 'react'
import { CalendarDays, Megaphone } from 'lucide-react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'

const config = {
  announcements: { table: 'announcements', title: 'Church announcements', icon: Megaphone, sort: 'created_at' },
  calendar: { table: 'church_events', title: 'Church calendar', icon: CalendarDays, sort: 'starts_at' },
}
const blank = { title: '', content: '', starts_at: '', ends_at: '', location: '' }
const dateTime = (value) => new Date(value).toLocaleString()
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
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState('')
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [editing, setEditing] = useState(null)
  const [form, setForm] = useState(blank)
  const [reload, setReload] = useState(0)

  useEffect(() => {
    let active = true
    setLoading(true); setLoadError(''); setError(''); setItems([])
    let request = supabase.from(current.table).select('*').order(current.sort, { ascending: page === 'calendar' }).limit(100)
    if (filter) request = request.eq('organization_id', filter)
    if (page === 'calendar' && eventFilter === 'upcoming') request = request.gte('ends_at', new Date().toISOString())
    request.then(({ data, error: requestError }) => {
      if (!active) return
      if (requestError) setLoadError(`Unable to load records: ${requestError.message}`)
      else setItems(data)
      setLoading(false)
    })
    return () => { active = false }
  }, [page, filter, eventFilter, reload, current.table, current.sort])

  const update = (key) => (event) => setForm((value) => ({ ...value, [key]: event.target.value }))
  function edit(item) {
    setError(''); setMessage(''); setEditing(item); setTargetOrg(item.organization_id)
    setForm({ title: item.title, content: page === 'calendar' ? item.description : item.content, starts_at: page === 'calendar' ? localDateTime(item.starts_at) : '', ends_at: page === 'calendar' ? localDateTime(item.ends_at) : '', location: item.location || '' })
  }
  function clearForm() { setEditing(null); setForm(blank); setTargetOrg(orgId || '') }
  async function save(event) {
    event.preventDefault(); setError(''); setMessage('')
    if (!targetOrg) { setError('Select a church.'); return }
    if (!form.title.trim() || (page === 'announcements' && !form.content.trim())) { setError('Enter a title and message.'); return }
    const start = new Date(form.starts_at)
    const end = new Date(form.ends_at)
    if (page === 'calendar' && (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime()) || end < start)) { setError('Enter valid start and end times. The end must not be before the start.'); return }
    const fields = page === 'calendar' ? { title: form.title.trim(), description: form.content.trim(), starts_at: start.toISOString(), ends_at: end.toISOString(), location: form.location.trim() } : { title: form.title.trim(), content: form.content.trim() }
    setBusy('save')
    try {
      const request = editing ? supabase.from(current.table).update(fields).eq('id', editing.id).eq('organization_id', editing.organization_id) : supabase.from(current.table).insert({ ...fields, organization_id: targetOrg })
      const { data, error: saveError } = await request.select('id')
      if (saveError) throw saveError
      if (!data?.length) throw new Error('No record was saved. Check your permissions.')
      setMessage(editing ? 'Changes saved.' : page === 'calendar' ? 'Event created.' : 'Announcement published.')
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
  return <div className="my-church-layout"><section className="directory-card my-card"><div className="my-card-heading"><span className="stat-icon mint"><Icon size={20} /></span><div><h2>{current.title}</h2><p>{owner ? 'Support view across churches. Showing up to 100 records.' : 'Visible to everyone assigned to this church. Showing up to 100 records.'}</p></div></div>
    {owner && <label>Filter by church<select value={filter} onChange={(event) => setFilter(event.target.value)}><option value="">All churches</option>{organizations.map((org) => <option key={org.id} value={org.id}>{org.name}</option>)}</select></label>}
    {page === 'calendar' && <label className="calendar-filter">Events<select value={eventFilter} onChange={(event) => setEventFilter(event.target.value)}><option value="upcoming">Ongoing and upcoming</option><option value="all">All events (earliest first)</option></select></label>}
    {loadError && <div className="notice notice-error" role="alert">{loadError}</div>}{error && <div className="notice notice-error" role="alert">{error}</div>}{message && <div className="notice" role="status">{message}</div>}
    {loading ? <p>Loading…</p> : loadError ? null : !items.length ? <p>Nothing here yet.</p> : <div className="my-list">{items.map((item) => <article className="my-list-item" key={item.id}><div><h3>{item.title}</h3>{owner && <small>{organizations.find((org) => org.id === item.organization_id)?.name || 'Church unavailable'}</small>}<p>{page === 'calendar' ? item.description : item.content}</p>{page === 'calendar' && <p>{dateTime(item.starts_at)} – {dateTime(item.ends_at)}{item.location && ` · ${item.location}`}</p>}<small>{page === 'announcements' ? `Published ${dateTime(item.created_at)}` : ''}</small></div>{(owner || canAdmin) && <div className="my-item-actions"><button className="text-button" disabled={Boolean(busy)} onClick={() => edit(item)}>Edit</button><button className="text-button" disabled={Boolean(busy)} onClick={() => remove(item)}><ActionLabel busy={busy === item.id} pending="Deleting…">Delete</ActionLabel></button></div>}</article>)}</div>}
  </section>{(owner || canAdmin) && <section className="directory-card my-card"><h2>{editing ? 'Edit' : page === 'calendar' ? 'Add an event' : 'Publish an announcement'}</h2><p>This is shared with the entire church. Targeted audiences are not available yet.</p><form className="my-form" onSubmit={save}>{owner && <label>Church<select value={targetOrg} onChange={(event) => setTargetOrg(event.target.value)} disabled={Boolean(editing)} required><option value="">Select a church</option>{organizations.map((org) => <option key={org.id} value={org.id}>{org.name}</option>)}</select></label>}<label>Title<input maxLength={200} required value={form.title} onChange={update('title')} /></label><label>{page === 'calendar' ? 'Description' : 'Message'}<textarea maxLength={10000} required={page === 'announcements'} value={form.content} onChange={update('content')} /></label>{page === 'calendar' && <><label>Starts<input type="datetime-local" required value={form.starts_at} onChange={update('starts_at')} /></label><label>Ends<input type="datetime-local" required value={form.ends_at} onChange={update('ends_at')} /></label><label>Location<input maxLength={255} value={form.location} onChange={update('location')} /></label></>}<div className="my-item-actions"><button className="button button-dark" disabled={Boolean(busy)} aria-busy={busy === 'save'}><ActionLabel busy={busy === 'save'} pending="Saving…">{editing ? 'Save changes' : page === 'calendar' ? 'Create event' : 'Publish announcement'}</ActionLabel></button>{editing && <button className="button button-outline" disabled={Boolean(busy)} type="button" onClick={clearForm}>Cancel edit</button>}</div></form></section>}</div>
}
