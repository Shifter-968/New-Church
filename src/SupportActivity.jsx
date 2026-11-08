import React, { useEffect, useState } from 'react'
import { supabase } from './supabase'

export default function SupportActivity({ organizations }) {
  const [items, setItems] = useState([])
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)
  useEffect(() => {
    let active = true
    supabase.from('support_activity').select('id,organization_id,actor_id,resource_type,resource_id,action,created_at').order('created_at', { ascending: false }).limit(100).then(({ data, error: loadError }) => {
      if (!active) return
      if (loadError) setError(loadError.message)
      else setItems(data)
      setLoading(false)
    })
    return () => { active = false }
  }, [])
  return <section className="directory-card my-card"><h2>Support activity</h2><p>Latest 100 announcement, calendar and Connect group changes recorded after their migrations. Membership changes and other modules are not audited here yet.</p>{error && <div className="notice notice-error" role="alert">{error}</div>}{loading ? <p>Loading activity…</p> : items.length === 0 && !error ? <p>No recorded activity yet.</p> : <div className="my-list">{items.map((item) => <article className="my-list-item" key={item.id}><div><h3>{item.action === 'INSERT' ? 'Created' : item.action === 'UPDATE' ? 'Updated' : 'Deleted'} {item.resource_type === 'announcements' ? 'announcement' : item.resource_type === 'church_events' ? 'event' : item.resource_type === 'connect_groups' ? 'Connect' : item.resource_type}</h3><p>{organizations.find((org) => org.id === item.organization_id)?.name || 'Church unavailable'}</p><small>{new Date(item.created_at).toLocaleString()} · Actor: {item.actor_id || 'System'} · Record: {item.resource_id}</small></div></article>)}</div>}</section>
}
