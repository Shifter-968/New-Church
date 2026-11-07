import React, { useEffect, useState } from 'react'
import { Check, X } from 'lucide-react'
import { supabase } from './supabase'

export default function Applications({ onApproved }) {
  const [applications, setApplications] = useState([])
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')

  async function load() {
    const { data, error: loadError } = await supabase.from('organization_applications').select('*').order('created_at', { ascending: false })
    if (loadError) throw new Error(loadError.message)
    setApplications(data)
  }
  useEffect(() => {
    let active = true
    supabase.from('organization_applications').select('*').order('created_at', { ascending: false }).then(({ data, error: loadError }) => {
      if (!active) return
      if (loadError) setError(loadError.message)
      else setApplications(data)
      setLoading(false)
    })
    return () => { active = false }
  }, [])
  async function review(application, decision) {
    if (!window.confirm(`${decision === 'approved' ? 'Approve' : 'Reject'} the application for ${application.organization_name}?`)) return
    setError(''); setMessage(''); setBusy(application.id)
    const { error: reviewError } = await supabase.rpc('review_organization_application', { application_id: application.id, decision })
    if (reviewError) setError(reviewError.message)
    else {
      setMessage(`Application ${decision}.`)
      try { await Promise.all([load(), onApproved()]) } catch (refreshError) { setError(`Decision saved, but refresh failed: ${refreshError.message}`) }
    }
    setBusy('')
  }
  return <section className="directory-card branch-card">
    {error && <div className="notice notice-error" role="alert">{error}</div>}
    {message && <div className="notice" role="status">{message}</div>}
    <h2>Church applications</h2><p>Review applications before granting an organisation administrator access. The applicant must confirm their email before approval.</p>
    {loading ? <p>Loading applications…</p> : applications.length === 0 ? <p>No applications yet.</p> : <div className="application-list">{applications.map((application) => <article className="application-card" key={application.id}><div><span className={`status ${application.status === 'approved' ? 'active' : 'inactive'}`}><span />{application.status}</span><h3>{application.organization_name}</h3><p>{application.first_name} {application.last_name} · {application.account_role === 'FOUNDING_PASTOR' ? 'Founding pastor' : 'Church administrator'}</p><p>{application.applicant_email} · {application.phone}</p><p>{application.address}, {application.city}, {application.country}</p><p>Submitted {new Date(application.created_at).toLocaleDateString()}</p></div>{application.status === 'pending' && <div className="application-actions"><button className="button button-outline" disabled={Boolean(busy)} onClick={() => review(application, 'rejected')}><X size={15} /> Reject</button><button className="button button-dark" disabled={Boolean(busy)} onClick={() => review(application, 'approved')}><Check size={15} /> Approve</button></div>}</article>)}</div>}
  </section>
}
