import React, { useEffect, useState } from 'react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'

export default function ChurchUsers({ orgId, canAdmin, onAccessChanged, navigate }) {
  const [items, setItems] = useState([])
  const [search, setSearch] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState('')
  const [revision, setRevision] = useState(0)
  useEffect(() => {
    let active = true
    setItems([]); setError('')
    if (!canAdmin) { setLoading(false); return () => { active = false } }
    setLoading(true)
    supabase.rpc('list_church_access', { target_org: orgId }).then(({ data, error: loadError }) => {
      if (!active) return
      if (loadError) setError(`Unable to load church access: ${loadError.message}`)
      else setItems(data)
      setLoading(false)
    }).catch((err) => { if (active) { setError(`Unable to load church access: ${err.message}`); setLoading(false) } })
    return () => { active = false }
  }, [orgId, canAdmin, revision])
  async function remove(item) {
    if (busy || !window.confirm(`Remove ${item.role_name} access for ${item.email} (${item.scope_name})? Their other assignments remain active.`)) return
    setBusy(item.assignment_id); setError(''); setMessage('')
    try {
      const rpc = item.assignment_kind === 'custom' ? 'remove_custom_role_assignment' : 'remove_branch_administrator_assignment'
      const { error: saveError } = await supabase.rpc(rpc, { target_org: orgId, target_assignment: item.assignment_id })
      if (saveError) throw saveError
      setMessage('Assignment removed. The user should reload their workspace.')
      setRevision((value) => value + 1)
      try { await onAccessChanged() } catch (err) { setError(`Removed, but workspace access could not be refreshed: ${err.message}`) }
    } catch (err) { setError(`${err.message || 'Unable to remove the assignment.'} If the connection was interrupted, refresh before retrying.`) }
    finally { setBusy('') }
  }
  if (!canAdmin) return <div className="notice notice-error" role="alert">Users & access currently requires organization administrator or platform owner access.</div>
  const term = search.trim().toLowerCase()
  const visible = items.filter((item) => `${item.email || ''} ${item.role_name} ${item.scope_name || ''}`.toLowerCase().includes(term))
  return <section className="directory-card my-card"><div className="my-card-heading"><div><h2>Users & access</h2><p>Active account assignments for the selected church. One person may appear more than once. Search covers only the first 1,000 assignments.</p></div><button className="button button-outline" disabled={loading || Boolean(busy)} onClick={() => { setMessage(''); setRevision((value) => value + 1) }}><ActionLabel busy={loading} pending="Loading…">Refresh</ActionLabel></button></div>
    <p>Custom roles and branch administrator assignments can be removed here, provided another active church assignment remains. Organization administrator, member, visitor and other built-in assignments remain protected. Removing one role does not revoke a user’s other roles or their account.</p>
    <div className="my-item-actions"><button className="button button-outline" onClick={() => navigate('roles')}>Manage custom roles</button><button className="button button-outline" onClick={() => navigate('branches')}>Assign branch administrator</button></div>
    {error && <div className="notice notice-error" role="alert">{error}</div>}{message && <div className="notice" role="status">{message}</div>}
    <label>Search loaded assignments<input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Email, role or branch" /></label>
    {loading ? <p>Loading users…</p> : error && !items.length ? null : !visible.length ? <p>{items.length ? 'No matching assignments in the loaded list.' : 'No active assignments found.'}</p> : <div className="my-list">{visible.map((item) => <article className="my-list-item" key={item.assignment_id}><div><strong>{item.email || 'Email unavailable'}</strong><p>{item.role_name} · {item.scope_name || 'Branch unavailable'}</p><small>{item.assignment_kind === 'custom' ? 'Custom role' : item.assignment_kind === 'branch_admin' ? 'Branch administrator' : 'Protected assignment'}</small></div>{['custom', 'branch_admin'].includes(item.assignment_kind) && <button className="text-button" disabled={Boolean(busy)} onClick={() => remove(item)}><ActionLabel busy={busy === item.assignment_id} pending="Removing…">Remove assignment</ActionLabel></button>}</article>)}</div>}
  </section>
}
