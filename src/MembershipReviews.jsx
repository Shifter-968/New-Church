import React, { useEffect, useState } from 'react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'

export default function MembershipReviews({ orgId, branches }) {
  const [rows, setRows] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState('')
  const [reload, setReload] = useState(0)
  useEffect(() => {
    let active = true
    setLoading(true); setError('')
    supabase.rpc('list_member_registration_reviews', { target_org: orgId }).then(({ data, error: resultError }) => {
      if (!active) return
      if (resultError) setError(`Unable to load reviews: ${resultError.message}`)
      else setRows(data)
      setLoading(false)
    })
    return () => { active = false }
  }, [orgId, reload])
  async function review(row, decision) {
    const text = decision === 'approved'
      ? 'Approve this applicant for the selected member record? Verify their identity independently before approving.'
      : 'Reject this registration request?'
    if (!window.confirm(text)) return
    setError(''); setMessage(''); setBusy(row.applicant_id)
    try {
      const { error: resultError } = await supabase.rpc('review_member_registration', {
        applicant_id: row.applicant_id, target_member: decision === 'approved' ? row.member_id : null, decision,
      })
      if (resultError) throw resultError
      setMessage(decision === 'approved' ? 'Approved. Ask the applicant to sign in and retry registration.' : 'Registration request rejected.')
      setReload((value) => value + 1)
    } catch (resultError) { setError(resultError.message || 'Unable to review the request.') }
    finally { setBusy('') }
  }
  return <section className="directory-card my-card"><h2>Member registration reviews</h2><p>Possible matches require a decision. Confirm identity independently before approving; a matching name alone is not proof of identity.</p>
    {error && <div className="notice notice-error" role="alert">{error}</div>}{message && <div className="notice" role="status">{message}</div>}
    {loading ? <p>Loading reviews…</p> : error ? null : rows.length === 0 ? <p>No pending matches in your access scope.</p> : <div className="my-list">{rows.map((row, index) => <article className="my-list-item" key={`${row.applicant_id}-${row.member_id || index}`}><div>
      <h3>Applicant: {row.submitted.first_name} {row.submitted.last_name}</h3>
      <p>Email: {row.applicant_email} · Phone: {row.submitted.phone || '—'}{row.submitted.phone_2 ? ` / ${row.submitted.phone_2}` : ''} · Birth date: {row.submitted.birth_date || '—'}</p>
      {row.member_id ? <><p>Possible record: <strong>{row.member_first_name} {row.member_last_name}</strong> · {branches.find((branch) => branch.id === row.branch_id)?.name || 'No branch'}</p>
        <small>Email: {row.member_email || 'Not recorded'} · Phone: {row.member_phone || 'Not recorded'}{row.member_phone_2 ? ` / ${row.member_phone_2}` : ''} · Birth date: {row.member_birth_date || 'Not recorded'}</small></> : <p>A previously suggested record is no longer available. Reject this request and contact the applicant.</p>}
    </div><div className="my-item-actions">{row.member_id && <button className="button button-dark" disabled={Boolean(busy)} onClick={() => review(row, 'approved')}><ActionLabel busy={busy === row.applicant_id} pending="Reviewing…">Approve this match</ActionLabel></button>}<button className="button button-outline" disabled={Boolean(busy)} onClick={() => review(row, 'rejected')}>Reject request</button></div></article>)}</div>}
  </section>
}
