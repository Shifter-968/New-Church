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
  const [searchApplicant, setSearchApplicant] = useState('')
  const [search, setSearch] = useState('')
  const [searchResults, setSearchResults] = useState(null)
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
      setSearchApplicant(''); setSearch(''); setSearchResults(null)
      setReload((value) => value + 1)
    } catch (resultError) { setError(resultError.message || 'Unable to review the request.') }
    finally { setBusy('') }
  }
  async function searchMembers(event, row) {
    event.preventDefault()
    if (busy) return
    setError(''); setSearchResults(null); setBusy(`search:${row.applicant_id}`)
    try {
      const { data, error: resultError } = await supabase.rpc('search_member_registration_candidates', {
        applicant_id: row.applicant_id, search_text: search.trim(),
      })
      if (resultError) throw resultError
      setSearchResults(data)
    } catch (resultError) { setError(resultError.message || 'Unable to search members.') }
    finally { setBusy('') }
  }
  return <section className="directory-card my-card"><h2>Member registration reviews</h2><p>Possible matches require a decision. Confirm identity independently before approving; a matching name alone is not proof of identity.</p>
    {error && <div className="notice notice-error" role="alert">{error}</div>}{message && <div className="notice" role="status">{message}</div>}
    {loading ? <p>Loading reviews…</p> : error && rows.length === 0 ? null : rows.length === 0 ? <p>No pending matches in your access scope.</p> : <div className="my-list">{rows.map((row, index) => <article className="my-list-item" key={`${row.applicant_id}-${row.member_id || index}`}><div>
      <h3>Applicant: {row.submitted.first_name} {row.submitted.last_name}</h3>
      <p>Email: {row.applicant_email} · Phone: {row.submitted.phone || '—'}{row.submitted.phone_2 ? ` / ${row.submitted.phone_2}` : ''} · Birth date: {row.submitted.birth_date || '—'}</p>
      {row.member_id ? <><p>Possible record: <strong>{row.member_first_name} {row.member_last_name}</strong> · {branches.find((branch) => branch.id === row.branch_id)?.name || 'No branch'}</p>
        <small>Email: {row.member_email || 'Not recorded'} · Phone: {row.member_phone || 'Not recorded'}{row.member_phone_2 ? ` / ${row.member_phone_2}` : ''} · Birth date: {row.member_birth_date || 'Not recorded'}</small></> : <p>No available suggested record. Search the selected branch or contact the applicant.</p>}
      {searchApplicant === row.applicant_id && rows.findIndex((item) => item.applicant_id === row.applicant_id) === index && <div>
        <form onSubmit={(event) => searchMembers(event, row)}><label>Search member name or phone<input minLength={2} maxLength={100} required value={search} onChange={(event) => setSearch(event.target.value)} /></label><button className="button button-outline" disabled={Boolean(busy)} aria-label="Search members"><ActionLabel busy={busy === `search:${row.applicant_id}`} pending="Searching…">Search</ActionLabel></button></form>
        {searchResults && (searchResults.length ? searchResults.map((member) => <div key={member.member_id}><p>{member.first_name} {member.last_name} · {member.phone || 'No phone'}{member.phone_2 ? ` / ${member.phone_2}` : ''} · {member.email || 'No email'} · {member.date_of_birth || 'No birth date'}</p><button className="text-button" disabled={Boolean(busy)} onClick={() => review({ ...row, member_id: member.member_id }, 'approved')}>Approve this record</button></div>) : <p>No available members matched this search.</p>)}
      </div>}
    </div><div className="my-item-actions">{row.member_id && <button className="button button-dark" disabled={Boolean(busy)} onClick={() => review(row, 'approved')}><ActionLabel busy={busy === row.applicant_id} pending="Reviewing…">Approve this match</ActionLabel></button>}{rows.findIndex((item) => item.applicant_id === row.applicant_id) === index && <button className="button button-outline" disabled={Boolean(busy)} onClick={() => { setSearchApplicant(searchApplicant === row.applicant_id ? '' : row.applicant_id); setSearch(''); setSearchResults(null) }}>Search records</button>}<button className="button button-outline" disabled={Boolean(busy)} onClick={() => review(row, 'rejected')}>Reject request</button></div></article>)}</div>}
  </section>
}
