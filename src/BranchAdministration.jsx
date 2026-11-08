import React, { useState } from 'react'
import { ArrowRight, Building2, ShieldCheck } from 'lucide-react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'

export default function BranchAdministration({ orgId, branches, canAdmin, onRefresh }) {
  const [name, setName] = useState('')
  const [branchId, setBranchId] = useState('')
  const [email, setEmail] = useState('')
  const [busy, setBusy] = useState('')
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')

  async function createBranch(event) {
    event.preventDefault()
    setError(''); setMessage('')
    if (name.trim().length < 2) { setError('Branch name must have at least two characters.'); return }
    setBusy('create')
    try {
      const { error: saveError } = await supabase.from('branches').insert({ organization_id: orgId, name: name.trim() })
      if (saveError) { setError(saveError.message); return }
      setName('')
      try { await onRefresh(); setMessage('Branch created.') } catch (refreshError) { setError(`Branch created, but the list could not be refreshed: ${refreshError.message}`) }
    } catch (saveError) {
      setError(saveError.message || 'Unable to create the branch. Please try again.')
    } finally { setBusy('') }
  }

  async function assignAdmin(event) {
    event.preventDefault()
    setError(''); setMessage(''); setBusy('assign')
    try {
      const { error: saveError } = await supabase.rpc('assign_branch_administrator_by_email', { org_id: orgId, target_branch_id: branchId, account_email: email.trim() })
      if (saveError) setError(saveError.message)
      else { setEmail(''); setMessage('Branch administrator assigned to the existing account.') }
    } catch (saveError) {
      setError(saveError.message || 'Unable to assign the administrator. Please try again.')
    } finally { setBusy('') }
  }

  return <section className="branch-admin">
    {error && <div className="notice notice-error" role="alert">{error}</div>}
    {message && <div className="notice" role="status">{message}</div>}
    <div className="branch-admin-grid"><section className="directory-card branch-card"><span className="stat-icon mint"><Building2 size={19} /></span><h2>Church branches</h2><p>Branches visible in your current access scope.</p>{branches.length ? <ul>{branches.map((branch) => <li key={branch.id}>{branch.name}</li>)}</ul> : <p>No branches available.</p>}
      {canAdmin && <form onSubmit={createBranch} className="branch-form"><label>New branch name<input value={name} onChange={(event) => setName(event.target.value)} maxLength={120} required /></label><button className="button button-dark" disabled={Boolean(busy)} aria-busy={busy === 'create'}><ActionLabel busy={busy === 'create'} pending="Creating…">Create branch</ActionLabel>{busy !== 'create' && <ArrowRight size={15} />}</button></form>}
    </section>
    {canAdmin && <section className="directory-card branch-card"><span className="stat-icon peach"><ShieldCheck size={19} /></span><h2>Assign a branch administrator</h2><p>Grant an existing confirmed account member and visitor management access limited to one branch. Account invitations are not yet available here.</p><form onSubmit={assignAdmin} className="branch-form"><label>Branch<select value={branchId} onChange={(event) => setBranchId(event.target.value)} required><option value="">Select a branch</option>{branches.map((branch) => <option value={branch.id} key={branch.id}>{branch.name}</option>)}</select></label><label>Administrator's email<input type="email" value={email} onChange={(event) => setEmail(event.target.value)} required placeholder="person@example.com" /></label><button className="button button-dark" disabled={Boolean(busy) || !branches.length} aria-busy={busy === 'assign'}><ActionLabel busy={busy === 'assign'} pending="Assigning…">Assign administrator</ActionLabel>{busy !== 'assign' && <ArrowRight size={15} />}</button></form></section>}</div>
  </section>
}
