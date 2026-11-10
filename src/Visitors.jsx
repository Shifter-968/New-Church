import React, { useCallback, useEffect, useMemo, useState } from 'react'
import { Plus, Search, Users } from 'lucide-react'
import { supabase } from './supabase'
import { canManageDirectory } from './access'
import ActionLabel from './ActionLabel'
import MemberImport, { downloadCsv } from './MemberImport'
import { filterMembers, memberCsv } from './memberCsv'
import { findVisitorDuplicates } from './visitorDuplicates'
import VisitorRegistrationReviews from './VisitorRegistrationReviews'

const emptyVisitor = { first_name: '', last_name: '', email: '', phone: '', branch_id: '' }

function VisitorForm({ visitor, branches, can, onClose, onSaved, Modal, Notice, orgId }) {
  const [form, setForm] = useState(visitor ? { ...visitor, branch_id: visitor.branch_id || '' } : emptyVisitor)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [matches, setMatches] = useState([])
  const [checked, setChecked] = useState(false)
  const action = visitor ? 'update' : 'create'
  const change = (field) => (event) => { setChecked(false); setMatches([]); setForm((previous) => ({ ...previous, [field]: event.target.value })) }

  async function submit(event) {
    event.preventDefault()
    if (busy) return
    const branch = form.branch_id || null
    if (!can(action, branch) || (visitor && !can('update', visitor.branch_id))) {
      setError('You do not have permission to save this visitor in that branch.')
      return
    }
    const payload = { first_name: form.first_name.trim(), last_name: form.last_name.trim(), email: form.email?.trim() || null, phone: form.phone?.trim() || null, branch_id: branch }
    if (!payload.first_name || !payload.last_name) { setError('First and last names cannot be blank.'); return }
    setError(''); setBusy(true)
    try {
      if (!visitor && !checked) {
        const found = await findVisitorDuplicates(orgId, [payload])
        if (found.length) { setMatches(found); setChecked(true); return }
      }
      const request = visitor
        ? supabase.from('visitors').update(payload).eq('id', visitor.id).eq('organization_id', orgId)
        : supabase.from('visitors').insert({ ...payload, organization_id: orgId })
      const { data, error: saveError } = await request.select('id')
      if (saveError) throw saveError
      if (!data?.length) throw new Error('The visitor was not saved. Check your permissions.')
      await onSaved(visitor ? 'Visitor updated.' : 'Visitor added.')
    } catch (err) { setError(err.message || 'Unable to save the visitor.') }
    finally { setBusy(false) }
  }

  return <Modal title={visitor ? 'Edit visitor' : 'Add a visitor'} description="Keep a record of the people visiting your church." onClose={onClose} busy={busy}>
    {error && <Notice error>{error}</Notice>}
    {matches.length > 0 && <div className="notice notice-error" role="alert"><div><strong>Possible existing visitor found.</strong> Check the directory and use Attendance to mark the existing person present instead of adding them again. Matching does not prove identity.<ul>{matches.map((match) => <li key={match.id}>{match.first_name} {match.last_name} · {match.email || 'No email'} · {match.phone || 'No phone'} · {branches.find((branch) => branch.id === match.branch_id)?.name || 'No branch or unavailable'}</li>)}</ul>Only up to five matches are shown. If these are different people, you can choose Create anyway.</div></div>}
    {visitor?.user_id && <Notice>This visitor has an account. Their branch cannot be changed and this record cannot be deleted until account access management is available. Contact changes here do not update their account.</Notice>}
    <form className="member-form" onSubmit={submit}>
      <div className="form-grid"><label>First name<input value={form.first_name} onChange={change('first_name')} maxLength={100} required autoFocus /></label><label>Last name<input value={form.last_name} onChange={change('last_name')} maxLength={100} required /></label></div>
      <div className="form-grid"><label>Email <span className="optional">Optional</span><input type="email" maxLength={320} value={form.email || ''} onChange={change('email')} /></label><label>Phone <span className="optional">Optional</span><input type="tel" maxLength={40} value={form.phone || ''} onChange={change('phone')} /></label></div>
      <label>Branch<select value={form.branch_id} onChange={change('branch_id')} required={!can(action, null)} disabled={Boolean(visitor?.user_id)}><option value="" disabled={!can(action, null)}>No branch</option>{branches.filter((branch) => can(action, branch.id)).map((branch) => <option value={branch.id} key={branch.id}>{branch.name}</option>)}</select></label>
      <div className="modal-actions"><button type="button" className="button button-outline" disabled={busy} onClick={onClose}>Cancel</button><button className="button button-dark" disabled={busy} aria-busy={busy} aria-label={busy ? 'Saving visitor' : checked ? 'Create anyway' : 'Save visitor'}><ActionLabel busy={busy} pending="Checking and saving…">{checked ? 'Create anyway' : 'Save visitor'}</ActionLabel></button></div>
    </form>
  </Modal>
}

export default function Visitors({ orgId, branches, owner, assignments, Modal, Notice }) {
  const [visitors, setVisitors] = useState([])
  const [query, setQuery] = useState('')
  const [branch, setBranch] = useState('all')
  const [modal, setModal] = useState(null)
  const [loading, setLoading] = useState(true)
  const [deleting, setDeleting] = useState('')
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const can = (action, branchId) => canManageDirectory(owner, assignments, 'visitors', action, branchId)
  const canCreate = can('create', null) || branches.some((item) => can('create', item.id))
  const filtered = useMemo(() => filterMembers(visitors, query, branch, 'all'), [visitors, query, branch])

  const fetchVisitors = useCallback(async () => {
    const { data, error: loadError } = await supabase.from('visitors').select('*').eq('organization_id', orgId).order('created_at', { ascending: false }).limit(1000)
    if (loadError) throw loadError
    return data
  }, [orgId])

  useEffect(() => {
    let active = true
    fetchVisitors().then((data) => { if (active) setVisitors(data) }).catch((err) => { if (active) setError(err.message || 'Unable to load visitors.') }).finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [fetchVisitors])

  async function saved(message) {
    setModal(null); setNotice(message); setError('')
    try { setVisitors(await fetchVisitors()) } catch (err) { setError(`Saved, but the list could not be refreshed: ${err.message}`) }
  }

  async function remove(visitor) {
    if (deleting || !window.confirm(`Remove ${visitor.first_name} ${visitor.last_name}? This cannot be undone.`)) return
    setDeleting(visitor.id); setError(''); setNotice('')
    try {
      const { data, error: deleteError } = await supabase.from('visitors').delete().eq('id', visitor.id).eq('organization_id', orgId).select('id')
      if (deleteError) throw deleteError
      if (!data?.length) throw new Error('The visitor was not removed. Check your permissions.')
      await saved('Visitor removed.')
    } catch (err) { setError(err.message || 'Unable to remove the visitor.') }
    finally { setDeleting('') }
  }

  const canReview = can('update', null) || branches.some((item) => can('update', item.id))
  return <section className="directory">
    {error && <Notice error>{error}</Notice>}{notice && <Notice>{notice}</Notice>}
    {canReview && <VisitorRegistrationReviews orgId={orgId} branches={branches} />}
    <div className="section-title directory-heading"><div><span className="section-kicker">PEOPLE & COMMUNITY</span><h2>Visitor directory</h2><p>Welcome and stay connected with your visitors.</p></div>{canCreate && <button className="button button-dark" onClick={() => setModal('add')}><Plus size={16} /> Add visitor</button>}</div>
    <div className="directory-card"><div className="directory-toolbar"><div><strong>Visitors shown</strong><span className="count-pill">{filtered.length}</span></div><label className="search"><Search size={17} /><span className="sr-only">Search visitors</span><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search people..." /></label></div>
      <div className="member-tools"><label>Branch<select value={branch} onChange={(event) => setBranch(event.target.value)}><option value="all">All branches</option><option value="unassigned">No branch</option>{branches.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label><button className="button button-outline" disabled={!filtered.length} onClick={() => downloadCsv('visitors.csv', memberCsv(filtered, branches, 'visitors'))}>Export shown CSV</button>{canCreate && <button className="button button-outline" onClick={() => setModal('import')}>Import CSV</button>}</div>
      <Notice>Directory loads at most 1,000 accessible visitors. Search, filters and export only cover the loaded records.</Notice>
      {loading ? <div className="loading">Loading visitors…</div> : !filtered.length ? <div className="empty-members"><div className="empty-icon"><Users size={24} /></div><h3>No visitors found</h3><p>Visitors you have permission to see will appear here. Try another search or branch.</p></div> : <div className="table-scroll"><table><thead><tr><th>VISITOR</th><th>CONTACT</th><th>BRANCH</th><th><span className="sr-only">Actions</span></th></tr></thead><tbody>{filtered.map((visitor) => <tr key={visitor.id}><td><div className="member-name"><span className="member-avatar">{visitor.first_name[0]}{visitor.last_name[0]}</span><strong>{visitor.first_name} {visitor.last_name}</strong></div></td><td><span>{visitor.email || '—'}</span><small>{visitor.phone || ''}</small></td><td>{branches.find((item) => item.id === visitor.branch_id)?.name || '—'}</td><td><div className="row-actions">{can('update', visitor.branch_id) && <button disabled={Boolean(deleting)} onClick={() => setModal(visitor)}>Edit</button>}{can('delete', visitor.branch_id) && !visitor.user_id && <button disabled={Boolean(deleting)} aria-busy={deleting === visitor.id} aria-label={`${deleting === visitor.id ? 'Removing' : 'Remove'} ${visitor.first_name} ${visitor.last_name}`} onClick={() => remove(visitor)}><ActionLabel busy={deleting === visitor.id} pending="Removing…">Remove</ActionLabel></button>}</div></td></tr>)}</tbody></table></div>}
    </div>
    {modal === 'import' && <MemberImport kind="visitors" orgId={orgId} branches={branches} canCreate={(branchId) => can('create', branchId)} Modal={Modal} Notice={Notice} onClose={() => setModal(null)} onImported={(count) => saved(`${count} visitors imported.`)} />}
    {modal && modal !== 'import' && <VisitorForm visitor={modal === 'add' ? null : modal} orgId={orgId} branches={branches} can={can} Modal={Modal} Notice={Notice} onClose={() => setModal(null)} onSaved={saved} />}
  </section>
}
