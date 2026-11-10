import React, { useEffect, useState } from 'react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'

const resourceNames = {
  announcements: 'announcement', church_events: 'event', connect_groups: 'Connect',
  connect_members: 'Connect membership', connect_messages: 'Connect message', connect_announcements: 'Connect announcement',
  members: 'member', visitors: 'visitor', branches: 'branch', roles: 'role',
  assignments: 'role assignment', church_teams: 'ministry or department',
  church_team_members: 'team membership', event_attendance: 'attendance record',
  church_families: 'family', church_children: 'child', church_family_people: 'family link',
  organization_plan_assignments: 'plan assignment',
}
const actionNames = { INSERT: 'Created', UPDATE: 'Updated', DELETE: 'Deleted' }

export default function SupportActivity({ organizations, orgId, owner = false }) {
  const [filter, setFilter] = useState(owner ? '' : orgId)
  const [items, setItems] = useState([])
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)
  const [revision, setRevision] = useState(0)
  const [search, setSearch] = useState('')
  useEffect(() => {
    let active = true
    setLoading(true); setError(''); setItems([])
    let request = supabase.from('support_activity').select('id,organization_id,actor_id,resource_type,resource_id,action,created_at')
      .order('created_at', { ascending: false }).order('id', { ascending: false }).limit(100)
    if (filter) request = request.eq('organization_id', filter)
    request.then(({ data, error: loadError }) => {
      if (!active) return
      if (loadError) setError(`Unable to load activity: ${loadError.message}`)
      else setItems(data)
      setLoading(false)
    }).catch((err) => { if (active) { setError(`Unable to load activity: ${err.message}`); setLoading(false) } })
    return () => { active = false }
  }, [filter, revision])
  const query = search.trim().toLowerCase()
  const visible = items.filter((item) => `${actionNames[item.action] || item.action} ${resourceNames[item.resource_type] || item.resource_type} ${item.actor_id || ''} ${item.resource_id} ${organizations.find((org) => org.id === item.organization_id)?.name || ''}`.toLowerCase().includes(query))
  return <section className="directory-card my-card"><div className="my-card-heading"><div><h2>{owner ? 'Support activity' : 'Church audit trail'}</h2><p>Latest 100 recorded changes for this selection. Search applies to the loaded list. This is not a complete audit trail; messages and personal details are not included.</p></div><button className="button button-outline" disabled={loading} onClick={() => setRevision((value) => value + 1)}><ActionLabel busy={loading} pending="Loading…">Refresh</ActionLabel></button></div>
    {owner && <label>Filter by church<select value={filter} onChange={(event) => setFilter(event.target.value)}><option value="">All churches</option>{organizations.map((org) => <option key={org.id} value={org.id}>{org.name}</option>)}</select></label>}
    <label>Search loaded activity<input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Action, type, church or ID" /></label>
    {error && <div className="notice notice-error" role="alert">{error}</div>}
    {loading ? <p>Loading activity…</p> : error ? null : !visible.length ? <p>{items.length ? 'No matching activity in the loaded list.' : 'No recorded activity yet.'}</p> : <div className="my-list">{visible.map((item) => <article className="my-list-item" key={item.id}><div><h3>{actionNames[item.action] || item.action} {resourceNames[item.resource_type] || item.resource_type}</h3>{owner && <p>{organizations.find((org) => org.id === item.organization_id)?.name || 'Church unavailable'}</p>}<small>{new Date(item.created_at).toLocaleString()} · Actor ID: {item.actor_id || 'System'} · {item.resource_type === 'connect_members' ? 'Connect' : 'Record'} ID: {item.resource_id}</small></div></article>)}</div>}
  </section>
}
