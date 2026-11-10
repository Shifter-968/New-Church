import React, { useEffect, useState } from 'react'
import { Check, X } from 'lucide-react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'

export default function Applications({ onApproved }) {
  const [applications, setApplications] = useState([])
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(null)
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
    }).catch((loadError) => { if (active) { setError(loadError.message || 'Unable to load applications.'); setLoading(false) } })
    return () => { active = false }
  }, [])
  async function downloadReceipt(application) {
    if (busy) return
    setError(''); setMessage(''); setBusy({ id: application.id, decision: 'download' })
    try {
      const { data, error: downloadError } = await supabase.storage.from('registration-payment-proofs').download(`${application.applicant_user_id}/receipt`)
      if (downloadError) throw downloadError
      const extension = { 'application/pdf': 'pdf', 'image/jpeg': 'jpg', 'image/png': 'png' }[data.type] || 'bin'
      const url = URL.createObjectURL(new Blob([data], { type: 'application/octet-stream' }))
      const link = document.createElement('a')
      link.href = url; link.download = `payment-proof-${application.id}.${extension}`; link.click()
      setTimeout(() => URL.revokeObjectURL(url), 1000)
    } catch (downloadError) { setError(downloadError.message || 'Unable to download the payment proof.') }
    finally { setBusy(null) }
  }
  async function review(application, decision) {
    const confirmation = decision === 'approved' && application.requested_plan_id
      ? `Approve ${application.organization_name} and assign the requested plan? Independently verify the payment first; the receipt and reference do not prove payment.`
      : `${decision === 'approved' ? 'Approve' : 'Reject'} the application for ${application.organization_name}?`
    if (!window.confirm(confirmation)) return
    setError(''); setMessage(''); setBusy({ id: application.id, decision })
    try {
      const { error: reviewError } = await supabase.rpc('review_organization_application', { application_id: application.id, decision })
      if (reviewError) setError(reviewError.message)
      else {
        setMessage(`Application ${decision}.`)
        try { await Promise.all([load(), onApproved()]) } catch (refreshError) { setError(`Decision saved, but refresh failed: ${refreshError.message}`) }
      }
    } catch (reviewError) {
      setError(reviewError.message || 'Unable to review the application. Please try again.')
    } finally {
      setBusy(null)
    }
  }
  return <section className="directory-card branch-card">
    {error && <div className="notice notice-error" role="alert">{error}</div>}
    {message && <div className="notice" role="status">{message}</div>}
    <h2>Church applications</h2><p>Confirm the applicant's email and independently verify payment before approval. A reference or receipt is not proof of payment. Treat downloaded files as untrusted.</p>
    {loading ? <p>Loading applications…</p> : applications.length === 0 ? <p>No applications yet.</p> : <div className="application-list">{applications.map((application) => <article className="application-card" key={application.id}><div><span className={`status ${application.status === 'approved' ? 'active' : 'inactive'}`}><span />{application.status}</span><h3>{application.organization_name}</h3><p>{application.first_name} {application.last_name} · {application.account_role === 'FOUNDING_PASTOR' ? 'Founding pastor' : 'Church administrator'}</p><p>{application.applicant_email} · {application.phone}</p><p>{application.address}, {application.city}, {application.country}</p><p>Submitted {new Date(application.created_at).toLocaleDateString()}</p>{application.requested_plan_id && <><p>Requested plan: {application.requested_plan_name} · {application.requested_plan_currency} {Number(application.requested_plan_price).toFixed(2)} / {application.requested_plan_period === 'MONTHLY' ? 'month' : 'year'}</p>{application.payment_method && <p>Payment method: {application.payment_method} · Reference: {application.transaction_reference}</p>}<p>{application.payment_submitted_at ? `Payment details submitted ${new Date(application.payment_submitted_at).toLocaleString()}${application.receipt_submitted ? ' with a receipt.' : ' without a receipt.'}` : 'Waiting for the applicant to submit payment details.'}</p>{application.receipt_submitted && <button className="text-button" disabled={Boolean(busy)} onClick={() => downloadReceipt(application)}><ActionLabel busy={busy?.id === application.id && busy.decision === 'download'} pending="Downloading…">Download receipt</ActionLabel></button>}</>}</div>{application.status === 'pending' && <div className="application-actions"><button className="button button-outline" disabled={Boolean(busy)} aria-busy={busy?.id === application.id && busy.decision === 'rejected'} onClick={() => review(application, 'rejected')}>{!(busy?.id === application.id && busy.decision === 'rejected') && <X size={15} />}<ActionLabel busy={busy?.id === application.id && busy.decision === 'rejected'} pending="Rejecting…">Reject</ActionLabel></button><button className="button button-dark" disabled={Boolean(busy) || Boolean(application.requested_plan_id && !application.payment_submitted_at)} aria-busy={busy?.id === application.id && busy.decision === 'approved'} onClick={() => review(application, 'approved')}>{!(busy?.id === application.id && busy.decision === 'approved') && <Check size={15} />}<ActionLabel busy={busy?.id === application.id && busy.decision === 'approved'} pending="Approving…">Approve</ActionLabel></button></div>}</article>)}</div>}
  </section>
}
