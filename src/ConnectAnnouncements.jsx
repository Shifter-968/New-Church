import React, { useEffect, useState } from 'react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'

export default function ConnectAnnouncements({ group }) {
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [busy, setBusy] = useState('')
  const [revision, setRevision] = useState(0)
  const [editing, setEditing] = useState(null)
  const [title, setTitle] = useState('')
  const [content, setContent] = useState('')
  const [status, setStatus] = useState('DRAFT')
  const [priority, setPriority] = useState('0')
  const [pinned, setPinned] = useState(false)
  const available = Boolean(group.my_role) && group.status === 'ACTIVE'
  const canManage = available && ['CREATOR', 'ADMIN'].includes(group.my_role)

  useEffect(() => {
    let active = true
    if (!available) { setItems([]); setLoading(false); return () => { active = false } }
    setLoading(true); setError('')
    supabase.rpc('my_connect_announcement_board', { target_id: group.id })
      .then(({ data, error: loadError }) => {
        if (!active) return
        if (loadError) { setItems([]); setError(`Unable to load announcements: ${loadError.message}`) }
        else setItems(data)
        setLoading(false)
      }).catch((err) => {
        if (active) { setItems([]); setError(`Unable to load announcements: ${err.message || 'Please try again.'}`); setLoading(false) }
      })
    return () => { active = false }
  }, [group.id, available, canManage, revision])

  function reset() { setEditing(null); setTitle(''); setContent(''); setStatus('DRAFT'); setPriority('0'); setPinned(false) }
  async function save(event) {
    event.preventDefault()
    if (busy) return
    if (!title.trim() || !content.trim()) { setError('Enter a title and announcement.'); return }
    setBusy('save'); setError(''); setNotice('')
    try {
      const { error: saveError } = await supabase.rpc('save_connect_announcement_workflow', {
        target_id: group.id, announcement_id: editing, announcement_title: title, announcement_content: content,
        new_status: status, new_priority: Number(priority), new_pinned: pinned,
      })
      if (saveError) throw saveError
      setNotice(status === 'PUBLISHED' ? 'Announcement published or updated.' : status === 'DRAFT' ? 'Draft saved for group leaders.' : 'Announcement archived.')
      reset(); setRevision((value) => value + 1)
    } catch (err) { setError(err.message || 'Unable to save the announcement.') }
    finally { setBusy('') }
  }
  async function remove(item) {
    if (busy || !window.confirm(`Permanently delete "${item.title}" from this Connect?`)) return
    setBusy(item.id); setError(''); setNotice('')
    try {
      const { error: deleteError } = await supabase.rpc('delete_connect_announcement', { target_id: group.id, announcement_id: item.id })
      if (deleteError) throw deleteError
      if (editing === item.id) reset()
      setNotice('Announcement deleted.'); setRevision((value) => value + 1)
    } catch (err) { setError(err.message || 'Unable to delete the announcement.') }
    finally { setBusy('') }
  }
  async function markRead(item) {
    if (busy) return
    setBusy(`read:${item.id}`); setError(''); setNotice('')
    try {
      const { error: readError } = await supabase.rpc('mark_connect_announcement_read', {
        target_id: group.id, announcement_id: item.id, expected_revision: item.revision,
      })
      if (readError) throw readError
      setRevision((value) => value + 1)
    } catch (err) { setError(err.message || 'Unable to mark the announcement read. Refresh and try again.') }
    finally { setBusy('') }
  }
  if (!available) return <section className="connect-announcements"><h3>Connect announcements</h3><p className="connect-hint">Only active group members can access announcements while the Connect is active.</p></section>
  return <section className="connect-announcements">
    <div className="connect-detail-heading"><div><h3>Connect announcements</h3><p className="connect-hint">Showing up to 100, pinned and highest priority first. {canManage ? 'Only group leaders can see drafts and archived items.' : 'Only published announcements are visible.'} Mark items read for yourself; content changes make them unread again. Refresh to check for updates.</p></div><button className="button button-outline" disabled={loading || Boolean(busy)} onClick={() => setRevision((value) => value + 1)}>Refresh announcements</button></div>
    {error && <div className="notice notice-error" role="alert">{error}</div>}{notice && <div className="notice" role="status">{notice}</div>}
    {loading ? <p>Loading announcements…</p> : error && !items.length ? null : !items.length ? <p>No announcements yet.</p> : <div className="my-list">{items.filter((item) => canManage || item.status === 'PUBLISHED').map((item) => <article className="my-list-item connect-announcement" key={item.id}><div><h3>{item.title} {!item.read_at && <span className="unread-dot" aria-label="Unread" />}</h3><p>{item.content}</p><small>{item.read_at ? 'Read' : 'Unread'} · {item.pinned ? 'Pinned · ' : ''}{['Normal', 'Important', 'Urgent'][item.priority]}{canManage ? ` · ${item.status.toLowerCase()}` : ''} · {item.author_name} · {new Date(item.created_at).toLocaleString()}{item.edited_at ? ' · edited' : ''}</small></div><div className="my-item-actions">{!item.read_at && <button className="text-button" disabled={Boolean(busy)} onClick={() => markRead(item)}><ActionLabel busy={busy === `read:${item.id}`} pending="Updating…">Mark read</ActionLabel></button>}{canManage && <><button className="text-button" disabled={Boolean(busy)} onClick={() => { setEditing(item.id); setTitle(item.title); setContent(item.content); setStatus(item.status); setPriority(String(item.priority)); setPinned(item.pinned); setError(''); setNotice('') }}>Edit</button><button className="text-button" disabled={Boolean(busy)} onClick={() => remove(item)}><ActionLabel busy={busy === item.id} pending="Deleting…">Delete</ActionLabel></button></>}</div></article>)}</div>}
    {canManage && <form className="my-form" onSubmit={save}><h3>{editing ? 'Edit announcement' : 'Create announcement'}</h3><label>Title<input required maxLength={200} value={title} onChange={(event) => setTitle(event.target.value)} /></label><label>Message<textarea required maxLength={10000} value={content} onChange={(event) => setContent(event.target.value)} /></label><label>Status<select value={status} onChange={(event) => setStatus(event.target.value)}><option value="DRAFT">Draft — leaders only</option><option value="PUBLISHED">Published — all group members</option><option value="ARCHIVED">Archived — leaders only</option></select></label><label>Priority<select value={priority} onChange={(event) => setPriority(event.target.value)}><option value="0">Normal</option><option value="1">Important</option><option value="2">Urgent</option></select></label><label className="connect-pin"><input type="checkbox" checked={pinned} onChange={(event) => setPinned(event.target.checked)} /> Pin to top</label><div className="my-item-actions"><button className="button button-dark" disabled={Boolean(busy)} aria-busy={busy === 'save'}><ActionLabel busy={busy === 'save'} pending="Saving…">Save announcement</ActionLabel></button>{editing && <button type="button" className="button button-outline" disabled={Boolean(busy)} onClick={reset}>Cancel edit</button>}</div></form>}
  </section>
}
