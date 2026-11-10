import React, { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'
import { fetchAllPages } from './supabasePagination'

const emptyCriteria = { gender: [], marital_status: [], min_age: '', max_age: '', baptized: '', residence: '' }

function criteriaFormFromTeam(team) {
  return {
    ...emptyCriteria,
    gender: team.criteria?.gender || [],
    marital_status: team.criteria?.marital_status || [],
    min_age: team.criteria?.min_age ?? '',
    max_age: team.criteria?.max_age ?? '',
    baptized: team.criteria && Object.hasOwn(team.criteria, 'baptized') ? String(team.criteria.baptized) : '',
    residence: team.criteria?.residence || '',
  }
}

function criteriaFromForm(form) {
  const criteria = {}
  if (form.gender.length) criteria.gender = form.gender
  if (form.marital_status.length) criteria.marital_status = form.marital_status
  if (form.min_age !== '') criteria.min_age = Number(form.min_age)
  if (form.max_age !== '') criteria.max_age = Number(form.max_age)
  if (form.baptized !== '') criteria.baptized = form.baptized === 'true'
  if (form.residence.trim()) criteria.residence = form.residence.trim()
  return Object.keys(criteria).length ? criteria : null
}

export default function ChurchTeams({ orgId, kind, branches, canAdmin }) {
  const [teams, setTeams] = useState([])
  const [people, setPeople] = useState([])
  const [memberships, setMemberships] = useState([])
  const [selected, setSelected] = useState('')
  const [name, setName] = useState('')
  const [editing, setEditing] = useState('')
  const [criteria, setCriteria] = useState(emptyCriteria)
  const [search, setSearch] = useState('')
  const [busy, setBusy] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const label = kind === 'ministry' ? 'ministry' : 'department'

  const load = useCallback(async () => {
    const results = await Promise.all([
      fetchAllPages((from, to) => supabase.from('church_teams').select('*').eq('organization_id', orgId).eq('kind', kind).order('name').range(from, to)),
      fetchAllPages((from, to) => supabase.from('church_team_members').select('*').eq('organization_id', orgId).range(from, to)),
      fetchAllPages((from, to) => supabase.from('members').select('id,first_name,last_name,email,phone,branch_id,user_id,status,gender,date_of_birth,marital_status,baptized,residence').eq('organization_id', orgId).order('first_name').range(from, to)),
      fetchAllPages((from, to) => supabase.from('visitors').select('id,first_name,last_name,email,phone,branch_id,user_id').eq('organization_id', orgId).order('first_name').range(from, to)),
    ])
    return { teams: results[0], memberships: results[1], people: [...results[2].filter((p) => p.status === 'active').map((p) => ({ ...p, kind: 'member' })), ...results[3].map((p) => ({ ...p, kind: 'visitor' }))] }
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
    const savedCriteria = kind === 'ministry' ? criteriaFromForm(criteria) : null
    await run('save', async () => {
      const request = editing
        ? supabase.from('church_teams').update({ name: name.trim(), criteria: savedCriteria }).eq('organization_id', orgId).eq('id', editing)
        : supabase.from('church_teams').insert({ organization_id: orgId, kind, name: name.trim(), criteria: savedCriteria })
      const { data, error: saveError } = await request.select('id')
      if (saveError) throw saveError
      if (!data?.length) throw new Error('No team saved. Check your permissions.')
      setName(''); setEditing(''); setCriteria(emptyCriteria)
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
  function changeCriteriaList(field, value) {
    setCriteria((current) => ({ ...current, [field]: current[field].includes(value) ? current[field].filter((item) => item !== value) : [...current[field], value] }))
  }
  const criteriaDescription = (team) => {
    const items = team.criteria || {}
    if (!Object.keys(items).length) return 'Manual membership'
    const parts = []
    if (items.gender?.length) parts.push(items.gender.join(' or ').toLowerCase())
    if (items.min_age != null || items.max_age != null) parts.push(`${items.min_age ?? 0}–${items.max_age ?? 'any'} years`)
    if (items.marital_status?.length) parts.push(items.marital_status.join(' or ').toLowerCase().replaceAll('_', ' '))
    if (Object.hasOwn(items, 'baptized')) parts.push(items.baptized ? 'baptized' : 'not baptized')
    if (items.residence) parts.push(`residence includes “${items.residence}”`)
    return `Auto-assign when all match: ${parts.join(', ')}`
  }
  return <div className="my-church-layout"><section className="directory-card my-card"><h2>{kind === 'ministry' ? 'Ministries' : 'Departments'}</h2><p>Create teams and manage their people. Ministries can automatically include active members when all selected criteria match; departments remain manually managed.</p>
    {error && <div className="notice notice-error" role="alert">{error}</div>}{message && <div className="notice" role="status">{message}</div>}
    <form className="my-form" onSubmit={save}><label>{editing ? `Edit ${label}` : `New ${label}`}<input value={name} onChange={(event) => setName(event.target.value)} maxLength={120} required /></label>
      {kind === 'ministry' && <fieldset className="team-criteria"><legend>Automatic member criteria <span className="optional">Optional; all chosen criteria must match</span></legend>
        <div className="form-grid">{[['gender', 'Gender', [['MALE', 'Male'], ['FEMALE', 'Female'], ['OTHER', 'Other']]], ['marital_status', 'Marital status', [['SINGLE', 'Single'], ['COURTSHIP', 'Courtship'], ['ENGAGED', 'Engaged'], ['MARRIED', 'Married'], ['DIVORCED', 'Divorced'], ['WIDOWED', 'Widowed']]]].map(([field, title, options]) => <fieldset key={field}><legend>{title} <span className="optional">Any selected</span></legend>{options.map(([value, optionLabel]) => <label key={value}><input type="checkbox" checked={criteria[field].includes(value)} onChange={() => changeCriteriaList(field, value)} /> {optionLabel}</label>)}</fieldset>)}
          <label>Minimum age <span className="optional">Optional</span><input type="number" min="0" max="130" value={criteria.min_age} onChange={(event) => setCriteria((current) => ({ ...current, min_age: event.target.value }))} /></label>
          <label>Maximum age <span className="optional">Optional</span><input type="number" min="0" max="130" value={criteria.max_age} onChange={(event) => setCriteria((current) => ({ ...current, max_age: event.target.value }))} /></label>
          <label>Baptism <select value={criteria.baptized} onChange={(event) => setCriteria((current) => ({ ...current, baptized: event.target.value }))}><option value="">Any</option><option value="true">Baptized</option><option value="false">Not baptized</option></select></label>
          <label>Residence contains <span className="optional">Optional</span><input maxLength={100} value={criteria.residence} onChange={(event) => setCriteria((current) => ({ ...current, residence: event.target.value }))} /></label>
        </div>
      </fieldset>}
      <div className="my-item-actions"><button className="button button-dark" disabled={Boolean(busy)} aria-label={busy === 'save' ? 'Saving team' : 'Save team'}><ActionLabel busy={busy === 'save'} pending="Saving…">{editing ? 'Save changes' : `Create ${label}`}</ActionLabel></button>{editing && <button type="button" className="button button-outline" disabled={Boolean(busy)} onClick={() => { setEditing(''); setName(''); setCriteria(emptyCriteria) }}>Cancel</button>}</div></form>
    {loading ? <p>Loading…</p> : <div className="my-list">{teams.map((team) => <article className="my-list-item" key={team.id}><div><button className="text-button" onClick={() => { setSelected(team.id); setSearch('') }}>{team.name}{selected === team.id ? ' (selected)' : ''}</button><p>{criteriaDescription(team)}</p></div><div className="my-item-actions"><button className="text-button" disabled={Boolean(busy)} onClick={() => { setEditing(team.id); setName(team.name); setCriteria(criteriaFormFromTeam(team)) }}>Edit</button><button className="text-button" disabled={Boolean(busy)} onClick={() => removeTeam(team)} aria-label={`Delete ${team.name}`}><ActionLabel busy={busy === team.id} pending="Deleting…">Delete</ActionLabel></button></div></article>)}</div>}
  </section><section className="directory-card my-card"><h2>{current ? `${current.name} people` : 'Select a team'}</h2><p>Member criteria are evaluated against the current profile, and matching active members are assigned automatically. Visitors and departments are managed manually. All accessible people and assignments are loaded.</p>
    {current && <><h3>Current people</h3>{!currentMemberships.length ? <p>No people assigned.</p> : <div className="my-list">{currentMemberships.map((membership) => {
      const person = people.find((item) => item.id === (membership.member_id || membership.visitor_id) && item.kind === (membership.member_id ? 'member' : 'visitor'))
      return <article className="my-list-item" key={membership.id}><div><strong>{person ? `${person.first_name} ${person.last_name}` : 'Person not in loaded records'}</strong>{person && <p>{person.kind} · {branches.find((branch) => branch.id === person.branch_id)?.name || 'No branch'} · {person.email || person.phone || 'No contact'} · {person.user_id ? 'Linked' : 'Not linked'}{membership.auto_assigned ? ' · Automatically assigned' : ''}</p>}</div><button className="text-button" disabled={Boolean(busy) || membership.auto_assigned} title={membership.auto_assigned ? 'This person matches the ministry criteria; change the criteria or profile to remove them.' : undefined} onClick={() => togglePerson(person || { id: membership.member_id || membership.visitor_id }, membership)}><ActionLabel busy={busy === (membership.member_id || membership.visitor_id)} pending="Removing…">Remove</ActionLabel></button></article>
    })}</div>}
      <label>Find a person<input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Name, email or phone" /></label><div className="my-list">{matches.map((person) => {
        const membership = currentMemberships.find((item) => person.kind === 'member' ? item.member_id === person.id : item.visitor_id === person.id)
        return <article className="my-list-item" key={`${person.kind}-${person.id}`}><div><strong>{person.first_name} {person.last_name}</strong><p>{person.kind} · {branches.find((branch) => branch.id === person.branch_id)?.name || 'No branch'} · {person.email || person.phone || 'No contact'}</p></div><button className="button button-outline" disabled={Boolean(busy) || Boolean(membership)} aria-label={`Add ${person.first_name} ${person.last_name} to ${current.name}`} onClick={() => togglePerson(person, null)}><ActionLabel busy={busy === person.id} pending="Adding…">{membership ? 'Added' : 'Add'}</ActionLabel></button></article>
      })}</div></>}
  </section></div>
}
