import React, { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'

export default function ChurchTeams({ orgId, kind, branches, canAdmin }) {
  const [teams, setTeams] = useState([])
  const [people, setPeople] = useState([])
  const [memberships, setMemberships] = useState([])
  const [selected, setSelected] = useState('')
  const [name, setName] = useState('')
  const [editing, setEditing] = useState('')
  const [search, setSearch] = useState('')
  const [busy, setBusy] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const label = kind === 'ministry' ? 'ministry' : 'department'

  const load = useCallback(async () => {
    const results = await Promise.all([
      supabase.from('church_teams').select('*').eq('organization_id', orgId).eq('kind', kind).order('name').limit(1000),
      supabase.from('church_team_members').select('*').eq('organization_id', orgId).limit(1000),
      supabase.from('members').select('id,first_name,last_name,email,phone,branch_id,user_id,status').eq('organization_id', orgId).order('first_name').limit(1000),
      supabase.from('visitors').select('id,first_name,last_name,email,phone,branch_id,user_id').eq('organization_id', orgId).order('first_name').limit(1000),
    ])
    const failure = results.find((result) => result.error)
    if (failure) throw failure.error
    return { teams: results[0].data, memberships: results[1].data, people: [...results[2].data.filter((p) => p.status === 'active').map((p) => ({ ...p, kind: 'member' })), ...results[3].data.map((p) => ({ ...p, kind: 'visitor' }))] }
  }, [orgId, kind])
  const apply = (data) => { setTeams(data.teams); setMemberships(data.memberships); setPeople(data.people) }
  useEffect(() => {
    if (!canAdmin) { setLoading(false); return }
    let active = true
    load().then((data) => { if (active) apply(data) }).catch((err) => { if (active) setError(`Unable to load ${label} data: ${err.message}`) }).finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [load, canAdmin, label])
  const current = teams.find((team) => team.id === selected)
  const currentMemberships = memberships.filter((item) => item.team_id === selected)
  const matches = useMemo(() => {
    const needle = search.trim().toLowerCase()
    if (needle.length < 2) return []
    return people.filter((p) => [`${p.first_name} ${p.last_name}`, p.email, p.phone].some((value) => value?.toLowerCase().includes(needle))).slice(0, 30)
  }, [people, search])

  async function run(key, operation, success) {
    if (busy) return
    setError(''); setMessage(''); setBusy(key)
    try {
      await operation()
      setMessage(success)
      try { apply(await load()) } catch (err) { setError(`Saved, but the list could not be refreshed: ${err.message}`) }
    } catch (err) { setError(err.message || 'Unable to save. Please try again.') }
    finally { setBusy('') }
  }
  async function save(event) {
    event.preventDefault()
    if (!name.trim()) { setError('Enter a name.'); return }
    await run('save', async () => {
      const request = editing ? supabase.from('church_teams').update({ name: name.trim() }).eq('organization_id', orgId).eq('id', editing) : supabase.from('church_teams').insert({ organization_id: orgId, kind, name: name.trim() })
      const { data, error: saveError } = await request.select('id')
      if (saveError) throw saveError
      if (!data?.length) throw new Error('No team saved. Check your permissions.')
      setName(''); setEditing('')
    }, `${label === 'ministry' ? 'Ministry' : 'Department'} saved.`)
  }
  async function removeTeam(team) {
    if (!window.confirm(`Delete ${team.name} and its membership list? This cannot be undone.`)) return
    await run(team.id, async () => {
      const { data, error: deleteError } = await supabase.from('church_teams').delete().eq('id', team.id).eq('organization_id', orgId).select('id')
      if (deleteError) throw deleteError
      if (!data?.length) throw new Error('No team deleted. Check your permissions.')
      setSelected('')
    }, 'Team deleted.')
  }
  async function togglePerson(person, membership) {
    await run(person.id, async () => {
      const request = membership ? supabase.from('church_team_members').delete().eq('id', membership.id).eq('organization_id', orgId)
        : supabase.from('church_team_members').insert({ organization_id: orgId, team_id: selected, member_id: person.kind === 'member' ? person.id : null, visitor_id: person.kind === 'visitor' ? person.id : null })
      const { data, error: saveError } = await request.select('id')
      if (saveError) throw saveError
      if (!data?.length) throw new Error('Membership was not changed. Check your permissions.')
    }, membership ? 'Person removed from team.' : 'Person added to team.')
  }
  if (!canAdmin) return <div className="notice notice-error" role="alert">Team setup currently requires organization administrator or platform owner access.</div>
  return <div className="my-church-layout"><section className="directory-card my-card"><h2>{kind === 'ministry' ? 'Ministries' : 'Departments'}</h2><p>Create teams and manage their people. These teams become available as audiences for events and announcements.</p>
    {error && <div className="notice notice-error" role="alert">{error}</div>}{message && <div className="notice" role="status">{message}</div>}
    <form className="my-form" onSubmit={save}><label>{editing ? `Rename ${label}` : `New ${label}`}<input value={name} onChange={(event) => setName(event.target.value)} maxLength={120} required /></label><div className="my-item-actions"><button className="button button-dark" disabled={Boolean(busy)} aria-label={busy === 'save' ? 'Saving team' : 'Save team'}><ActionLabel busy={busy === 'save'} pending="Saving…">{editing ? 'Save changes' : `Create ${label}`}</ActionLabel></button>{editing && <button type="button" className="button button-outline" disabled={Boolean(busy)} onClick={() => { setEditing(''); setName('') }}>Cancel</button>}</div></form>
    {loading ? <p>Loading…</p> : <div className="my-list">{teams.map((team) => <article className="my-list-item" key={team.id}><button className="text-button" onClick={() => { setSelected(team.id); setSearch('') }}>{team.name}{selected === team.id ? ' (selected)' : ''}</button><div className="my-item-actions"><button className="text-button" disabled={Boolean(busy)} onClick={() => { setEditing(team.id); setName(team.name) }}>Rename</button><button className="text-button" disabled={Boolean(busy)} onClick={() => removeTeam(team)} aria-label={`Delete ${team.name}`}><ActionLabel busy={busy === team.id} pending="Deleting…">Delete</ActionLabel></button></div></article>)}</div>}
  </section><section className="directory-card my-card"><h2>{current ? `${current.name} people` : 'Select a team'}</h2><p>Members and visitors with linked accounts receive targeted content; unlinked records are included in the team but cannot sign in until linked. Up to 1,000 people of each type and 1,000 team assignments are loaded.</p>
    {current && <><h3>Current people</h3>{!currentMemberships.length ? <p>No people assigned.</p> : <div className="my-list">{currentMemberships.map((membership) => {
      const person = people.find((item) => item.id === (membership.member_id || membership.visitor_id) && item.kind === (membership.member_id ? 'member' : 'visitor'))
      return <article className="my-list-item" key={membership.id}><div><strong>{person ? `${person.first_name} ${person.last_name}` : 'Person not in loaded records'}</strong>{person && <p>{person.kind} · {branches.find((branch) => branch.id === person.branch_id)?.name || 'No branch'} · {person.email || person.phone || 'No contact'} · {person.user_id ? 'Linked' : 'Not linked'}</p>}</div><button className="text-button" disabled={Boolean(busy)} onClick={() => togglePerson(person || { id: membership.member_id || membership.visitor_id }, membership)}><ActionLabel busy={busy === (membership.member_id || membership.visitor_id)} pending="Removing…">Remove</ActionLabel></button></article>
    })}</div>}
      <label>Find a person<input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Name, email or phone" /></label><div className="my-list">{matches.map((person) => {
        const membership = currentMemberships.find((item) => person.kind === 'member' ? item.member_id === person.id : item.visitor_id === person.id)
        return <article className="my-list-item" key={`${person.kind}-${person.id}`}><div><strong>{person.first_name} {person.last_name}</strong><p>{person.kind} · {branches.find((branch) => branch.id === person.branch_id)?.name || 'No branch'} · {person.email || person.phone || 'No contact'}</p></div><button className="button button-outline" disabled={Boolean(busy) || Boolean(membership)} aria-label={`Add ${person.first_name} ${person.last_name} to ${current.name}`} onClick={() => togglePerson(person, null)}><ActionLabel busy={busy === person.id} pending="Adding…">{membership ? 'Added' : 'Add'}</ActionLabel></button></article>
      })}</div></>}
  </section></div>
}
