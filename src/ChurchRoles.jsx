import React, { useCallback, useEffect, useState } from 'react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'

const permissions = [
  ['members.view', 'View members'], ['members.create', 'Add members'], ['members.update', 'Edit members'], ['members.delete', 'Delete members'],
  ['visitors.view', 'View visitors'], ['visitors.create', 'Add visitors'], ['visitors.update', 'Edit visitors'], ['visitors.delete', 'Delete visitors'],
  ['attendance.view', 'View attendance'], ['attendance.create', 'Mark attendance'], ['attendance.absences.view', 'View reported absences and reasons'],
]

export default function ChurchRoles({ orgId, branches, canAdmin, onAccessChanged }) {
  const [roles, setRoles] = useState([])
  const [assignments, setAssignments] = useState([])
  const [name, setName] = useState('')
  const [selectedPermissions, setSelectedPermissions] = useState([])
  const [editing, setEditing] = useState('')
  const [roleId, setRoleId] = useState('')
  const [email, setEmail] = useState('')
  const [branch, setBranch] = useState('')
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')

  const load = useCallback(async () => {
    const [roleResult, assignmentResult] = await Promise.all([
      supabase.rpc('manageable_church_roles', { target_org: orgId }),
      supabase.rpc('custom_role_assignments', { target_org: orgId }),
    ])
    if (roleResult.error || assignmentResult.error) throw roleResult.error || assignmentResult.error
    setRoles(roleResult.data); setAssignments(assignmentResult.data)
  }, [orgId])

  useEffect(() => {
    if (!canAdmin) { setLoading(false); return }
    let active = true
    setLoading(true)
    load().catch((err) => { if (active) setError(`Unable to load roles: ${err.message}`) }).finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [load, canAdmin])

  async function run(key, operation, success) {
    if (busy) return
    setBusy(key); setError(''); setMessage('')
    try {
      await operation()
      setMessage(success)
      try { await Promise.all([load(), onAccessChanged()]) } catch (err) { setError(`Saved, but the workspace could not be refreshed: ${err.message}`) }
    } catch (err) { setError(err.message || 'Unable to save. Please try again.') }
    finally { setBusy('') }
  }
  function togglePermission(value) {
    setSelectedPermissions((current) => current.includes(value) ? current.filter((item) => item !== value) : [...current, value])
  }
  function clearForm() { setEditing(''); setName(''); setSelectedPermissions([]) }
  async function save(event) {
    event.preventDefault()
    await run('save', async () => {
      const { error: rpcError } = await supabase.rpc('save_custom_church_role', { target_org: orgId, target_role: editing || null, role_name: name, role_permissions: selectedPermissions })
      if (rpcError) throw rpcError
      clearForm()
    }, 'Role saved.')
  }
  async function assign(event) {
    event.preventDefault()
    await run('assign', async () => {
      const { error: rpcError } = await supabase.rpc('assign_custom_church_role', { target_org: orgId, target_role: roleId, account_email: email, target_branch: branch === 'all' ? null : branch })
      if (rpcError) throw rpcError
      setEmail('')
    }, 'Role assigned.')
  }
  async function removeRole(role) {
    if (!window.confirm(`Delete "${role.name}"? Roles in use or selected in an audience cannot be deleted.`)) return
    await run(role.id, async () => {
      const { error: rpcError } = await supabase.rpc('delete_custom_church_role', { target_org: orgId, target_role: role.id })
      if (rpcError) throw rpcError
      if (editing === role.id) clearForm()
      if (roleId === role.id) setRoleId('')
    }, 'Role deleted.')
  }
  async function removeAssignment(assignment) {
    if (!window.confirm(`Remove this role from ${assignment.email}?`)) return
    await run(assignment.id, async () => {
      const { error: rpcError } = await supabase.rpc('remove_custom_role_assignment', { target_org: orgId, target_assignment: assignment.id })
      if (rpcError) throw rpcError
    }, 'Role assignment removed.')
  }
  if (!canAdmin) return <div className="notice notice-error" role="alert">Role management requires organization administrator or platform owner access.</div>
  return <div className="my-church-layout"><section className="directory-card my-card"><h2>Roles & permissions</h2>
    <p>Create custom roles for event audiences and the supported permissions below. Built-in roles are protected and are not edited here. Changes affect every account assigned to the role.</p>
    {error && <div className="notice notice-error" role="alert">{error}</div>}{message && <div className="notice" role="status">{message}</div>}
    <form className="my-form" onSubmit={save}><label>Role name<input value={name} onChange={(event) => setName(event.target.value)} minLength={2} maxLength={120} required /></label>
      <fieldset className="audience-picker"><legend>Permissions</legend><p>Select view access for each area before granting its other permissions. An empty role can be used for audiences only.</p>
        {permissions.map(([value, label]) => <label className="audience-choice" key={value}><input type="checkbox" checked={selectedPermissions.includes(value)} onChange={() => togglePermission(value)} /> {label}</label>)}
      </fieldset><div className="my-item-actions"><button className="button button-dark" disabled={Boolean(busy) || loading}><ActionLabel busy={busy === 'save'} pending="Saving…">{editing ? 'Save changes' : 'Create role'}</ActionLabel></button>{editing && <button className="button button-outline" type="button" disabled={Boolean(busy)} onClick={clearForm}>Cancel</button>}</div>
    </form>
    {loading ? <p>Loading roles…</p> : roles.length === 0 ? <p>No custom roles yet.</p> : <div className="my-list">{roles.map((role) => <article className="my-list-item" key={role.id}><div><strong>{role.name}</strong><p>{role.permissions.length ? role.permissions.join(', ') : 'Audience only'}</p></div><div className="my-item-actions"><button className="text-button" disabled={Boolean(busy)} onClick={() => { setEditing(role.id); setName(role.name); setSelectedPermissions(role.permissions) }}>Edit</button><button className="text-button" disabled={Boolean(busy)} onClick={() => removeRole(role)}><ActionLabel busy={busy === role.id} pending="Deleting…">Delete</ActionLabel></button></div></article>)}</div>}
  </section><section className="directory-card my-card"><h2>Assign a custom role</h2><p>The person must have a confirmed account and an existing active assignment in this church. Church-wide access covers all branches; branch access is limited to the selected branch. The role adds privileges and does not replace existing roles.</p>
    <form className="my-form" onSubmit={assign}><label>Custom role<select required value={roleId} onChange={(event) => setRoleId(event.target.value)}><option value="">Select a role</option>{roles.map((role) => <option value={role.id} key={role.id}>{role.name}</option>)}</select></label>
      <label>Confirmed account email<input type="email" required value={email} onChange={(event) => setEmail(event.target.value)} /></label>
      <label>Permission scope<select required value={branch} onChange={(event) => setBranch(event.target.value)}><option value="">Select a scope</option><option value="all">Entire church (all branches)</option>{branches.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
      <button className="button button-dark" disabled={Boolean(busy) || loading}><ActionLabel busy={busy === 'assign'} pending="Assigning…">Assign role</ActionLabel></button></form>
    <h3>Custom role assignments</h3><p>Showing up to 1,000 active assignments. Users should reload their workspace after access changes.</p>
    {!loading && assignments.length === 0 ? <p>No custom role assignments yet.</p> : <div className="my-list">{assignments.map((item) => <article className="my-list-item" key={item.id}><div><strong>{item.email}</strong><p>{roles.find((role) => role.id === item.role_id)?.name || 'Role unavailable'} · {item.branch_id ? branches.find((b) => b.id === item.branch_id)?.name || 'Branch unavailable' : 'Entire church'}</p></div><button className="text-button" disabled={Boolean(busy)} onClick={() => removeAssignment(item)}><ActionLabel busy={busy === item.id} pending="Removing…">Remove</ActionLabel></button></article>)}</div>}
  </section></div>
}
