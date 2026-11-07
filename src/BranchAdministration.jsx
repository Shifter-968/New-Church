import React, { useState } from 'react'
import { ArrowRight, Building2, ShieldCheck } from 'lucide-react'
import { supabase } from './supabase'

export default function BranchAdministration({ orgId, branches, canAdmin, onRefresh }) {
  const [name, setName] = useState('')
  const [branchId, setBranchId] = useState('')
  const [email, setEmail] = useState('')
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')

  async function createBranch(event) {
    event.preventDefault()
    setError(''); setMessage('')
    if (name.trim().length < 2) { setError('Branch name must have at least two characters.'); return }
    setBusy(true)
    const { error: saveError } = await supabase.from('branches').insert({ organization_id: orgId, name: name.trim() })
    if (saveError) { setError(saveError.message); setBusy(false); return }
    setName('')
    try { await onRefresh(); setMessage('Branch created.') } catch (refreshError) { setError(`Branch created, but the list could not be refreshed: ${refreshError.message}`) }
    setBusy(false)
  }

  async function assignAdmin(event) {
    event.preventDefault()
    setError(''); setMessage(''); setBusy(true)
    const { error: saveError } = await supabase.rpc('assign_branch_administrator_by_email', { org_id: orgId, target_branch_id: branchId, account_email: email.trim() })
    if (saveError) setError(saveError.message)
    else { setEmail(''); setMessage('Branch administrator assigned to the existing account.') }
    setBusy(false)
  }

  return <section className="branch-admin">
    {error && <div className="notice notice-error" role="alert">{error}</div>}
    {message && <div className="notice" role="status">{message}</div>}
    <div className="branch-admin-grid"><section className="directory-card branch-card"><span className="stat-icon mint"><Building2 size={19} /></span><h2>Church branches</h2><p>Branches visible in your current access scope.</p>{branches.length ? <ul>{branches.map((branch) => <li key={branch.id}>{branch.name}</li>)}</ul> : <p>No branches available.</p>}
      {canAdmin && <form onSubmit={createBranch} className="branch-form"><label>New branch name<input value={name} onChange={(event) => setName(event.target.value)} maxLength={120} required /></label><button className="button button-dark" disabled={busy}>Create branch <ArrowRight size={15} /></button></form>}
    </section>
    {canAdmin && <section className="directory-card branch-card"><span className="stat-icon peach"><ShieldCheck size={19} /></span><h2>Assign a branch administrator</h2><p>Grant an existing confirmed account member-management access limited to one branch. Account invitations are not yet available here.</p><form onSubmit={assignAdmin} className="branch-form"><label>Branch<select value={branchId} onChange={(event) => setBranchId(event.target.value)} required><option value="">Select a branch</option>{branches.map((branch) => <option value={branch.id} key={branch.id}>{branch.name}</option>)}</select></label><label>Administrator's email<input type="email" value={email} onChange={(event) => setEmail(event.target.value)} required placeholder="person@example.com" /></label><button className="button button-dark" disabled={busy || !branches.length}>Assign administrator <ArrowRight size={15} /></button></form></section>}</div>
  </section>
}
