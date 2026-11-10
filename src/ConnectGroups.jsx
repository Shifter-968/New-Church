import React, { useEffect, useState } from 'react'
import { HeartHandshake } from 'lucide-react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'
import ConnectConversation from './ConnectConversation.jsx'

const initialForm = { name: '', description: '', branch: '', ownerEmail: '', status: 'ACTIVE' }

export default function ConnectGroups({ orgId, organizations, owner, canAdmin, userId }) {
  const [filter, setFilter] = useState(owner ? '' : orgId)
  const [targetOrg, setTargetOrg] = useState(orgId || '')
  const [branches, setBranches] = useState([])
  const [items, setItems] = useState([])
  const [form, setForm] = useState(initialForm)
  const [editing, setEditing] = useState(null)
  const [selectedId, setSelectedId] = useState(null)
  const [code, setCode] = useState('')
  const [loading, setLoading] = useState(true)
  const [branchLoading, setBranchLoading] = useState(false)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [loadError, setLoadError] = useState('')
  const [branchError, setBranchError] = useState('')
  const [message, setMessage] = useState('')
  const [reload, setReload] = useState(0)
  const administrator = owner || canAdmin

  useEffect(() => {
    let active = true
    setLoading(true); setLoadError('')
    supabase.rpc('list_connect_groups', { target_org: filter || null }).then(({ data, error: resultError }) => {
      if (!active) return
      if (resultError) { setItems([]); setLoadError(`Unable to load Connects: ${resultError.message}`) }
      else setItems(data)
      setLoading(false)
    }).catch((err) => {
      if (active) { setItems([]); setLoadError(`Unable to load Connects: ${err.message || 'Please try again.'}`); setLoading(false) }
    })
    return () => { active = false }
  }, [filter, reload])

  useEffect(() => {
    let active = true
    setBranches([]); setBranchError('')
    if (!targetOrg) { setBranchLoading(false); return () => { active = false } }
    setBranchLoading(true)
    supabase.from('branches').select('id,name').eq('organization_id', targetOrg).order('name').then(({ data, error: resultError }) => {
      if (!active) return
      if (resultError) setBranchError(`Unable to load branches: ${resultError.message}`)
      else setBranches(data)
      setBranchLoading(false)
    })
    return () => { active = false }
  }, [targetOrg])

  function reset() { setEditing(null); setForm(initialForm); setTargetOrg(orgId || '') }
  function edit(item) {
    setError(''); setMessage(''); setEditing(item); setTargetOrg(item.organization_id)
    setForm({ name: item.name, description: item.description, branch: item.branch_id || '', ownerEmail: item.owner_email || '', status: item.status })
  }
  function update(key) { return (event) => setForm((value) => ({ ...value, [key]: event.target.value })) }
  async function save(event) {
    event.preventDefault(); setError(''); setMessage('')
    if (!form.name.trim()) { setError('Enter a Connect name.'); return }
    setBusy('save')
    try {
      const { error: saveError } = await supabase.rpc('save_connect_group', {
        target_id: editing?.id || null, target_org: targetOrg, target_branch: form.branch || null,
        group_name: form.name, group_description: form.description, group_status: form.status,
        owner_email: administrator ? form.ownerEmail.trim() : '',
      })
      if (saveError) throw saveError
      reset(); setMessage(editing ? 'Connect updated.' : 'Connect created.'); setReload((value) => value + 1)
    } catch (saveError) { setError(saveError.message || 'Unable to save the Connect.') } finally { setBusy('') }
  }
  async function join(event) {
    event.preventDefault(); setError(''); setMessage(''); setBusy('join')
    try {
      const { error: joinError } = await supabase.rpc('join_connect_group', { target_org: orgId, code })
      if (joinError) throw joinError
      setCode(''); setMessage('You joined the Connect.'); setReload((value) => value + 1)
    } catch (joinError) { setError(joinError.message || 'Unable to join the Connect.') } finally { setBusy('') }
  }
  async function remove(item) {
    if (!window.confirm(`Permanently delete "${item.name}", its memberships, announcements and all messages?`)) return
    setError(''); setMessage(''); setBusy(item.id)
    try {
      const { error: deleteError } = await supabase.rpc('delete_connect_group', { target_id: item.id })
      if (deleteError) throw deleteError
      if (editing?.id === item.id) reset()
      if (selectedId === item.id) setSelectedId(null)
      setMessage('Connect deleted.'); setReload((value) => value + 1)
    } catch (deleteError) { setError(deleteError.message || 'Unable to delete the Connect.') } finally { setBusy('') }
  }
  async function leave(item) {
    if (busy || !window.confirm(`Leave "${item.name}"? You will lose access to its conversation. You can rejoin with a code if eligible.`)) return
    setError(''); setMessage(''); setBusy(`leave:${item.id}`)
    try {
      const { error: leaveError } = await supabase.rpc('leave_connect_group', { target_id: item.id })
      if (leaveError) throw leaveError
      if (selectedId === item.id) setSelectedId(null)
      setMessage('You left the Connect.'); setReload((value) => value + 1)
    } catch (leaveError) { setError(leaveError.message || 'Unable to leave the Connect.') } finally { setBusy('') }
  }
  const selected = items.find((item) => item.id === selectedId)
  return <><div className="my-church-layout"><section className="directory-card my-card">
    <div className="my-card-heading"><span className="stat-icon mint"><HeartHandshake size={20} /></span><div><h2>{owner ? 'Connect support' : 'Your Connects'}</h2><p>{owner ? 'Manage Connect groups across churches without joining them.' : 'Your groups and, for church administrators, groups in your church.'} Showing up to 100.</p></div></div>
    <p>Manage members and exchange text messages. Media and direct chats are not available yet.</p>
    {owner && <label>Filter by church<select value={filter} onChange={(event) => setFilter(event.target.value)}><option value="">All churches</option>{organizations.map((org) => <option key={org.id} value={org.id}>{org.name}</option>)}</select></label>}
    {loadError && <div className="notice notice-error" role="alert">{loadError}</div>}{branchError && <div className="notice notice-error" role="alert">{branchError}</div>}{error && <div className="notice notice-error" role="alert">{error}</div>}{message && <div className="notice" role="status">{message}</div>}
    {loading ? <p>Loading Connects…</p> : loadError ? null : !items.length ? <p>No Connects available yet.</p> : <div className="my-list">{items.map((item) => <article className="my-list-item" key={item.id}><div><h3>{item.name}</h3><small>{organizations.find((org) => org.id === item.organization_id)?.name || 'Church unavailable'} · {item.branch_name || 'Entire church'} · {item.status.toLowerCase()} · {item.member_count} members</small><p>{item.description}</p>{item.owner_email && <small>Owner: {item.owner_email}</small>}{item.join_code && <small>Join code: {item.join_code}</small>}{item.my_role === 'CREATOR' && <small>Transfer ownership through a church administrator before leaving.</small>}</div><div className="my-item-actions"><button className="text-button" disabled={Boolean(busy)} onClick={() => setSelectedId(item.id)}>Open</button>{item.my_role && item.my_role !== 'CREATOR' && <button className="text-button" disabled={Boolean(busy)} onClick={() => leave(item)}><ActionLabel busy={busy === `leave:${item.id}`} pending="Leaving…">Leave</ActionLabel></button>}{(administrator || item.my_role === 'CREATOR') && <><button className="text-button" disabled={Boolean(busy)} onClick={() => edit(item)}>Edit</button><button className="text-button" disabled={Boolean(busy)} onClick={() => remove(item)}><ActionLabel busy={busy === item.id} pending="Deleting…">Delete</ActionLabel></button></>}</div></article>)}</div>}
    {!owner && <form className="my-form" onSubmit={join}><label>Join with a code<input value={code} onChange={(event) => setCode(event.target.value)} required maxLength={10} /></label><button className="button button-outline" disabled={Boolean(busy)} aria-busy={busy === 'join'}><ActionLabel busy={busy === 'join'} pending="Joining…">Join Connect</ActionLabel></button></form>}
  </section><section className="directory-card my-card"><h2>{editing ? 'Edit Connect' : 'Create a Connect'}</h2><p>{administrator ? 'Choose an existing, confirmed church account as the Connect owner. The platform owner is not automatically added.' : 'You will be the Connect owner.'}</p>
    <form className="my-form" onSubmit={save}>{owner && <label>Church<select required disabled={Boolean(editing)} value={targetOrg} onChange={(event) => { setTargetOrg(event.target.value); setForm((value) => ({ ...value, branch: '' })) }}><option value="">Select a church</option>{organizations.map((org) => <option value={org.id} key={org.id}>{org.name}</option>)}</select></label>}
      <label>Name<input value={form.name} onChange={update('name')} maxLength={255} required /></label><label>Description<textarea value={form.description} onChange={update('description')} maxLength={10000} /></label>
      <label>Branch<select value={form.branch} onChange={update('branch')} disabled={branchLoading || Boolean(branchError) || (Boolean(editing) && !administrator)}><option value="">Entire church</option>{branches.map((branch) => <option value={branch.id} key={branch.id}>{branch.name}</option>)}</select></label>
      {administrator && <><label>Connect owner email<input type="email" required value={form.ownerEmail} onChange={update('ownerEmail')} /></label><label>Status<select value={form.status} onChange={update('status')}><option value="ACTIVE">Active</option><option value="ARCHIVED">Archived</option><option value="SUSPENDED">Suspended</option></select></label></>}
      <div className="my-item-actions"><button className="button button-dark" disabled={Boolean(busy) || !targetOrg || branchLoading || Boolean(branchError)} aria-busy={busy === 'save'}><ActionLabel busy={busy === 'save'} pending="Saving…">{editing ? 'Save changes' : 'Create Connect'}</ActionLabel></button>{editing && <button className="button button-outline" type="button" disabled={Boolean(busy)} onClick={reset}>Cancel edit</button>}</div>
    </form>
  </section></div>{selected && <ConnectConversation key={selected.id} group={selected} userId={userId} support={administrator} onChanged={() => setReload((value) => value + 1)} onClose={() => setSelectedId(null)} />}</>
}
