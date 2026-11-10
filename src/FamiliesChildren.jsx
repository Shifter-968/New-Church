import React, { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from './supabase'
import { canManageMembers } from './access'
import ActionLabel from './ActionLabel'

const emptyFamily = { branch_id: '', name: '', primary_contact: '', address: '', notes: '' }
const emptyChild = { branch_id: '', first_name: '', last_name: '', date_of_birth: '', residence: '', parent_contact: '' }

export default function FamiliesChildren({ orgId, branches, owner, assignments, page }) {
  const isFamily = page === 'families'
  const [families, setFamilies] = useState([])
  const [children, setChildren] = useState([])
  const [members, setMembers] = useState([])
  const [links, setLinks] = useState([])
  const [selected, setSelected] = useState('')
  const [editing, setEditing] = useState('')
  const [form, setForm] = useState(isFamily ? emptyFamily : emptyChild)
  const [search, setSearch] = useState('')
  const [personSearch, setPersonSearch] = useState('')
  const [relationship, setRelationship] = useState('')
  const [editingLink, setEditingLink] = useState('')
  const [linkRelationship, setLinkRelationship] = useState('')
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState('')
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const can = (action, branch) => canManageMembers(owner, assignments, action, branch)
  const load = useCallback(async () => {
    const results = await Promise.all([
      supabase.from('church_families').select('*').eq('organization_id', orgId).order('name').limit(1000),
      supabase.from('church_children').select('*').eq('organization_id', orgId).order('last_name').limit(1000),
      supabase.from('church_family_people').select('*').eq('organization_id', orgId).limit(1000),
      supabase.from('members').select('id,first_name,last_name,branch_id,status').eq('organization_id', orgId).order('last_name').limit(1000),
    ])
    const failure = results.find((result) => result.error)
    if (failure) throw failure.error
    setFamilies(results[0].data); setChildren(results[1].data); setLinks(results[2].data); setMembers(results[3].data)
  }, [orgId])
  useEffect(() => {
    let active = true
    setLoading(true); setLoadError('')
    load().catch((err) => { if (active) setLoadError(`Unable to load records: ${err.message}`) }).finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [load])
  const current = families.find((item) => item.id === selected)
  const items = (isFamily ? families : children).filter((item) => `${item.name || ''} ${item.first_name || ''} ${item.last_name || ''} ${item.primary_contact || ''} ${item.parent_contact || ''}`.toLowerCase().includes(search.trim().toLowerCase()))
  const people = useMemo(() => [
    ...members.filter((item) => item.status === 'active').map((item) => ({ ...item, kind: 'member' })),
    ...children.map((item) => ({ ...item, kind: 'child' })),
  ], [members, children])
  const currentLinks = links.filter((item) => item.family_id === selected)
  const matches = current && personSearch.trim().length >= 2 ? people.filter((p) => p.branch_id === current.branch_id && `${p.first_name} ${p.last_name}`.toLowerCase().includes(personSearch.trim().toLowerCase())).slice(0, 30) : []
  function reset() { setForm(isFamily ? emptyFamily : emptyChild); setEditing('') }
  async function run(key, operation, success) {
    if (busy) return
    setBusy(key); setError(''); setMessage('')
    try {
      await operation()
      setMessage(success)
      try { await load(); setLoadError('') } catch (err) { setLoadError(`Saved, but records could not be refreshed: ${err.message}`) }
    } catch (err) { setError(err.message || 'Unable to save. Please try again.') }
    finally { setBusy('') }
  }
  async function save(event) {
    event.preventDefault()
    const table = isFamily ? 'church_families' : 'church_children'
    const values = isFamily
      ? { name: form.name.trim(), primary_contact: form.primary_contact.trim(), address: form.address.trim(), notes: form.notes.trim() }
      : { first_name: form.first_name.trim(), last_name: form.last_name.trim(), date_of_birth: form.date_of_birth || null, residence: form.residence.trim(), parent_contact: form.parent_contact.trim() }
    await run('save', async () => {
      const request = editing ? supabase.from(table).update(values).eq('id', editing).eq('organization_id', orgId)
        : supabase.from(table).insert({ ...values, organization_id: orgId, branch_id: form.branch_id })
      const { data, error: saveError } = await request.select('id')
      if (saveError) throw saveError
      if (!data?.length) throw new Error('No record saved. Check your permissions.')
      reset()
    }, isFamily ? 'Family saved.' : 'Child saved.')
  }
  async function remove(item) {
    if (!window.confirm(`Delete this ${isFamily ? 'family and its links' : 'child record'}? This cannot be undone.`)) return
    await run(item.id, async () => {
      const { data, error: deleteError } = await supabase.from(isFamily ? 'church_families' : 'church_children').delete().eq('id', item.id).eq('organization_id', orgId).select('id')
      if (deleteError) throw deleteError
      if (!data?.length) throw new Error('No record deleted. Check your permissions.')
      if (selected === item.id) setSelected('')
      if (editing === item.id) reset()
    }, 'Record deleted.')
  }
  async function changeLink(person, link) {
    await run(link ? link.id : `${person.kind}-${person.id}`, async () => {
      const request = link ? supabase.from('church_family_people').delete().eq('id', link.id).eq('organization_id', orgId)
        : supabase.from('church_family_people').insert({ organization_id: orgId, branch_id: current.branch_id, family_id: current.id, member_id: person.kind === 'member' ? person.id : null, child_id: person.kind === 'child' ? person.id : null, relationship: relationship.trim() })
      const { data, error: saveError } = await request.select('id')
      if (saveError) throw saveError
      if (!data?.length) throw new Error('Family link was not changed. Check your permissions.')
      if (!link) setRelationship('')
    }, link ? 'Person removed from family.' : 'Person linked to family.')
  }
  async function saveRelationship(event) {
    event.preventDefault()
    await run(editingLink, async () => {
      const { data, error: saveError } = await supabase.from('church_family_people').update({ relationship: linkRelationship.trim() }).eq('id', editingLink).eq('organization_id', orgId).select('id')
      if (saveError) throw saveError
      if (!data?.length) throw new Error('Family link was not changed. Check your permissions.')
      setEditingLink(''); setLinkRelationship('')
    }, 'Relationship saved.')
  }
  const editableBranches = branches.filter((branch) => can(editing ? 'update' : 'create', branch.id))
  const disabled = Boolean(busy) || loading || Boolean(loadError)
  return <div className="my-church-layout"><section className="directory-card my-card"><h2>{isFamily ? 'Families' : 'Children'}</h2><p>{isFamily ? 'Manage branch families and link existing members or children.' : 'Manage children separately from member accounts. Link them to a family under Families.'} Lists contain up to 1,000 accessible records.</p><p>These details are visible to users with member-view access in the branch. Collect only information your church needs.</p>
    {error && <div className="notice notice-error" role="alert">{error}</div>}{loadError && <div className="notice notice-error" role="alert">{loadError} <button className="text-button" onClick={() => { setLoadError(''); setLoading(true); load().catch((err) => setLoadError(`Unable to load records: ${err.message}`)).finally(() => setLoading(false)) }}>Retry</button></div>}{message && <div className="notice" role="status">{message}</div>}
    {(editing || editableBranches.length > 0) && <form className="my-form" onSubmit={save}><h3>{editing ? 'Edit' : 'Add'} {isFamily ? 'family' : 'child'}</h3>
      <label>Branch<select required value={form.branch_id} disabled={Boolean(editing) || disabled} onChange={(event) => setForm({ ...form, branch_id: event.target.value })}><option value="">Select a branch</option>{editableBranches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}</select></label>
      {isFamily ? <><label>Family name<input required maxLength={120} value={form.name} onChange={(event) => setForm({ ...form, name: event.target.value })} /></label><label>Primary contact<input required maxLength={120} value={form.primary_contact} onChange={(event) => setForm({ ...form, primary_contact: event.target.value })} /></label><label>Address<input maxLength={255} value={form.address} onChange={(event) => setForm({ ...form, address: event.target.value })} /></label><label>Notes<textarea maxLength={1000} value={form.notes} onChange={(event) => setForm({ ...form, notes: event.target.value })} /></label></>
        : <><label>First name<input required maxLength={100} value={form.first_name} onChange={(event) => setForm({ ...form, first_name: event.target.value })} /></label><label>Surname<input required maxLength={100} value={form.last_name} onChange={(event) => setForm({ ...form, last_name: event.target.value })} /></label><label>Date of birth<input type="date" value={form.date_of_birth || ''} onChange={(event) => setForm({ ...form, date_of_birth: event.target.value })} /></label><label>Parent or guardian contact<input required maxLength={120} value={form.parent_contact} onChange={(event) => setForm({ ...form, parent_contact: event.target.value })} /></label><label>Residence<input maxLength={255} value={form.residence} onChange={(event) => setForm({ ...form, residence: event.target.value })} /></label></>}
      <div className="my-item-actions"><button className="button button-dark" disabled={disabled}><ActionLabel busy={busy === 'save'} pending="Saving…">Save {isFamily ? 'family' : 'child'}</ActionLabel></button>{editing && <button type="button" className="button button-outline" disabled={Boolean(busy)} onClick={reset}>Cancel</button>}</div>
    </form>}
    <label>Search loaded records<input value={search} onChange={(event) => setSearch(event.target.value)} /></label>
    {loading ? <p>Loading…</p> : loadError ? null : !items.length ? <p>No matching records.</p> : <div className="my-list">{items.map((item) => <article className="my-list-item" key={item.id}><div>{isFamily ? <button className="text-button" onClick={() => { setSelected(item.id); setPersonSearch(''); setEditingLink('') }}>{item.name}{selected === item.id ? ' (selected)' : ''}</button> : <strong>{item.first_name} {item.last_name}</strong>}<p>{branches.find((branch) => branch.id === item.branch_id)?.name || 'Branch unavailable'} · {isFamily ? `Contact: ${item.primary_contact}` : `Guardian contact: ${item.parent_contact}`}</p>{isFamily ? <>{item.address && <p>Address: {item.address}</p>}{item.notes && <p>Notes: {item.notes}</p>}</> : <>{item.date_of_birth && <p>Date of birth: {item.date_of_birth}</p>}{item.residence && <p>Residence: {item.residence}</p>}</>}</div><div className="my-item-actions">{can('update', item.branch_id) && <button className="text-button" disabled={disabled} onClick={() => { setEditing(item.id); setForm(item) }}>Edit</button>}{can('delete', item.branch_id) && <button className="text-button" disabled={disabled} onClick={() => remove(item)}><ActionLabel busy={busy === item.id} pending="Deleting…">Delete</ActionLabel></button>}</div></article>)}</div>}
  </section>{isFamily && <section className="directory-card my-card"><h2>{current ? `${current.name} people` : 'Select a family'}</h2><p>Only people in the same branch can be linked. Remove links before deleting or moving a linked child or member. Up to 1,000 links are loaded.</p>
    {current && <><h3>Linked people</h3>{!currentLinks.length ? <p>No linked people in the loaded records.</p> : <div className="my-list">{currentLinks.map((link) => { const person = people.find((p) => p.id === (link.member_id || link.child_id) && p.kind === (link.member_id ? 'member' : 'child')); return <article className="my-list-item" key={link.id}><div><strong>{person ? `${person.first_name} ${person.last_name}` : 'Person outside the loaded records'}</strong><p>{link.member_id ? 'Member' : 'Child'}{link.relationship && ` · ${link.relationship}`}</p></div>{can('update', current.branch_id) && <div className="my-item-actions"><button className="text-button" disabled={disabled} onClick={() => { setEditingLink(link.id); setLinkRelationship(link.relationship) }}>Edit relationship</button><button className="text-button" disabled={disabled} onClick={() => changeLink(null, link)}><ActionLabel busy={busy === link.id && editingLink !== link.id} pending="Removing…">Remove</ActionLabel></button></div>}</article> })}</div>}
      {editingLink && <form className="my-form" onSubmit={saveRelationship}><label>Edit relationship<input maxLength={120} value={linkRelationship} onChange={(event) => setLinkRelationship(event.target.value)} /></label><div className="my-item-actions"><button className="button button-dark" disabled={disabled}><ActionLabel busy={busy === editingLink} pending="Saving…">Save relationship</ActionLabel></button><button className="button button-outline" type="button" disabled={Boolean(busy)} onClick={() => setEditingLink('')}>Cancel</button></div></form>}
      {can('update', current.branch_id) && <><label>Relationship for new link<input maxLength={120} value={relationship} onChange={(event) => setRelationship(event.target.value)} placeholder="e.g. Parent, child" /></label><label>Find a member or child<input value={personSearch} onChange={(event) => setPersonSearch(event.target.value)} placeholder="At least two characters" /></label>{personSearch.trim().length >= 2 && !matches.length && <p>No matches in the loaded branch records.</p>}<div className="my-list">{matches.map((person) => { const linked = currentLinks.some((link) => person.kind === 'member' ? link.member_id === person.id : link.child_id === person.id); return <article className="my-list-item" key={`${person.kind}-${person.id}`}><div><strong>{person.first_name} {person.last_name}</strong><p>{person.kind}</p></div><button className="button button-outline" disabled={disabled || linked} onClick={() => changeLink(person, null)}><ActionLabel busy={busy === `${person.kind}-${person.id}`} pending="Adding…">{linked ? 'Linked' : 'Add'}</ActionLabel></button></article> })}</div></>}
    </>}
  </section>}</div>
}
