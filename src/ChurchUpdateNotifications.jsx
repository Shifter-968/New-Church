import React, { useEffect, useState } from 'react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'

export default function ChurchUpdateNotifications({ userId }) {
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [revision, setRevision] = useState(0)
  useEffect(() => {
    let active = true
    setLoading(true); setError('')
    supabase.rpc('my_church_update_notices').then(({ data, error: loadError }) => {
      if (!active) return
      if (loadError) setError(`Unable to load church updates: ${loadError.message}`)
      else setItems(data)
      setLoading(false)
    }).catch((err) => { if (active) { setError(`Unable to load church updates: ${err.message}`); setLoading(false) } })
    return () => { active = false }
  }, [revision, userId])
  async function markRead(ids, key) {
    if (busy || !ids.length) return
    setBusy(key); setError('')
    try {
      const { error: saveError } = await supabase.rpc('mark_church_update_notices_read', { notice_ids: ids })
      if (saveError) throw saveError
      setRevision((value) => value + 1)
    } catch (err) { setError(`${err.message || 'Unable to mark updates read.'} Refresh and try again.`) }
    finally { setBusy('') }
  }
  const unread = items.filter((item) => !item.read_at)
  return <section className="directory-card my-card"><div className="my-card-heading"><div><h2>Church updates</h2><p>Latest 100 visible new announcements and events across your churches. Access changes may add or remove updates.</p></div><button className="button button-outline" disabled={loading || Boolean(busy)} onClick={() => setRevision((value) => value + 1)}>Refresh</button><button className="button button-outline" disabled={loading || Boolean(busy) || !unread.length} onClick={() => markRead(unread.map((item) => item.notice_id), 'all')}><ActionLabel busy={busy === 'all'} pending="Updating…">Mark shown read</ActionLabel></button></div>
    {error && <div className="notice notice-error" role="alert">{error}</div>}
    {loading ? <p>Loading church updates…</p> : error ? null : !items.length ? <p>No church updates available.</p> : <div className="my-list">{items.map((item) => <article className="my-list-item" key={item.notice_id}><div><h3>{item.title} {!item.read_at && <span className="unread-dot" aria-label="Unread" />}</h3><p>{item.kind === 'event' ? 'New event' : 'New announcement'} · {item.organization_name}</p><small>{new Date(item.created_at).toLocaleString()} · Open {item.kind === 'event' ? 'My calendar' : 'Announcements'} for details.</small></div>{!item.read_at && <button className="text-button" disabled={Boolean(busy)} onClick={() => markRead([item.notice_id], item.notice_id)}><ActionLabel busy={busy === item.notice_id} pending="Updating…">Mark read</ActionLabel></button>}</article>)}</div>}
  </section>
}
