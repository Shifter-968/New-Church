import React, { useEffect, useState } from 'react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'

export default function VisitorRegistrationReviews({ orgId, branches }) {
  const [rows, setRows] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState('')
  const [revision, setRevision] = useState(0)
  useEffect(() => {
    let active = true
    setLoading(true); setError('')
    supabase.rpc('list_visitor_registration_reviews', { target_org: orgId })
      .then(({ data, error: resultError }) => {
        if (!active) return
        if (resultError) setError(`Unable to load visitor requests: ${resultError.message}`)
        else setRows(data)
        setLoading(false)
      }).catch((err) => { if (active) { setError(`Unable to load visitor requests: ${err.message}`); setLoading(false) } })
    return () => { active = false }
  }, [orgId, revision])
  async function review(row, decision) {
    const text = decision === 'approved'
      ? 'Link this account to the selected visitor record? Verify their identity independently before approving.'
      : decision === 'new'
        ? 'Confirm this is a different person and approve a new visitor record?'
        : 'Reject this visitor registration request?'
    if (busy || !window.confirm(text)) return
    setBusy(row.applicant_id); setError(''); setMessage('')
    try {
      const { error: resultError } = await supabase.rpc('review_visitor_registration', {
        applicant_id: row.applicant_id, target_visitor: decision === 'approved' ? row.visitor_id : null, decision,
      })
      if (resultError) throw resultError
      setMessage(decision === 'rejected' ? 'Visitor registration rejected.' : 'Approved. Ask the visitor to sign in and check registration status.')
      setRevision((value) => value + 1)
    } catch (err) { setError(err.message || 'Unable to review the request.') }
    finally { setBusy('') }
  }
  return <section className="directory-card my-card"><div className="my-card-heading"><div><h2>Visitor registration reviews</h2><p>Possible matches need review. Verify identity independently before linking; a name or phone match alone is not proof.</p></div><button className="button button-outline" disabled={loading || Boolean(busy)} onClick={() => setRevision((value) => value + 1)}>Refresh</button></div>
    {error && <div className="notice notice-error" role="alert">{error}</div>}{message && <div className="notice" role="status">{message}</div>}
    {loading ? <p>Loading visitor requests…</p> : error ? null : rows.length === 0 ? <p>No pending visitor requests in your access scope.</p> : <div className="my-list">{rows.map((row, index) => <article className="my-list-item" key={`${row.applicant_id}-${row.visitor_id || index}`}><div>
      <h3>Applicant: {row.submitted.first_name} {row.submitted.last_name}</h3>
      <p>Email: {row.applicant_email} · Phone: {row.submitted.phone || '—'}{row.submitted.phone_2 ? ` / ${row.submitted.phone_2}` : ''} · Birth date: {row.submitted.birth_date || '—'}</p>
      {row.visitor_id ? <><p>Possible record: <strong>{row.visitor_first_name} {row.visitor_last_name}</strong> · {branches.find((branch) => branch.id === row.branch_id)?.name || 'No branch or unavailable'}</p><small>Email: {row.visitor_email || 'Not recorded'} · Phone: {row.visitor_phone || 'Not recorded'}</small></> : <p>A suggested record is no longer available for linking.</p>}
    </div><div className="my-item-actions">{row.visitor_id && <button className="button button-dark" disabled={Boolean(busy)} onClick={() => review(row, 'approved')}><ActionLabel busy={busy === row.applicant_id} pending="Reviewing…">Approve this match</ActionLabel></button>}<button className="button button-outline" disabled={Boolean(busy)} onClick={() => review(row, 'new')}>Different person: create new</button><button className="button button-outline" disabled={Boolean(busy)} onClick={() => review(row, 'rejected')}>Reject request</button></div></article>)}</div>}
  </section>
}
