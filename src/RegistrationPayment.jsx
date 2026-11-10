import React, { useEffect, useState } from 'react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'

const bucket = 'registration-payment-proofs'
const allowedTypes = ['application/pdf', 'image/jpeg', 'image/png']

export default function RegistrationPayment({ userId }) {
  const [application, setApplication] = useState(null)
  const [hasReceipt, setHasReceipt] = useState(false)
  const [file, setFile] = useState(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [revision, setRevision] = useState(0)

  useEffect(() => {
    let active = true
    async function load() {
      const { data, error: appError } = await supabase.from('organization_applications')
        .select('id,status,requested_plan_id,requested_plan_name,requested_plan_price,requested_plan_currency,requested_plan_period,payment_method,transaction_reference,payment_submitted_at,receipt_submitted')
        .eq('applicant_user_id', userId).maybeSingle()
      if (appError) throw appError
      let receipt = Boolean(data?.receipt_submitted)
      if (data?.status === 'pending' && data.requested_plan_id && !data.payment_submitted_at) {
        const { data: objects, error: storageError } = await supabase.storage.from(bucket).list(userId, { limit: 100 })
        if (storageError) throw storageError
        receipt = objects.some((object) => object.name === 'receipt')
      }
      if (active) { setApplication(data); setHasReceipt(receipt) }
    }
    setLoading(true); setError('')
    load().catch((err) => { if (active) setError(`Unable to load your church application: ${err.message || 'Please try again.'}`) })
      .finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [userId, revision])

  async function upload(event) {
    event.preventDefault()
    if (busy) return
    if (!file || !allowedTypes.includes(file.type) || file.size === 0 || file.size > 8 * 1024 * 1024) {
      setError('Choose a non-empty PDF, JPEG or PNG file no larger than 8 MB.'); return
    }
    setBusy('upload'); setError(''); setNotice('')
    try {
      const { error: uploadError } = await supabase.storage.from(bucket).upload(`${userId}/receipt`, file, { contentType: file.type, upsert: false })
      if (uploadError) throw uploadError
      setFile(null); setNotice('Receipt uploaded privately. Submit your details when ready.')
      setRevision((value) => value + 1)
    } catch (err) { setError(`${err.message || 'Unable to upload the receipt.'} Refresh to check whether it was uploaded before retrying.`) }
    finally { setBusy('') }
  }
  async function remove() {
    if (busy || !window.confirm('Remove the uploaded receipt? You can upload another before submitting.')) return
    setBusy('remove'); setError(''); setNotice('')
    try {
      const { data, error: removeError } = await supabase.storage.from(bucket).remove([`${userId}/receipt`])
      if (removeError) throw removeError
      if (!data?.length) throw new Error('The receipt was not removed. Refresh and check your application.')
      setNotice('Receipt removed.'); setRevision((value) => value + 1)
    } catch (err) { setError(err.message || 'Unable to remove the receipt.') }
    finally { setBusy('') }
  }
  async function submit() {
    if (busy || !window.confirm(`Submit your payment details ${hasReceipt ? 'with the uploaded receipt' : 'without a receipt'}? You cannot change them here afterwards.`)) return
    setBusy('submit'); setError(''); setNotice('')
    try {
      const { error: submitError } = await supabase.rpc('submit_organization_payment_details')
      if (submitError) throw submitError
      setNotice('Payment details submitted for platform-owner review.'); setRevision((value) => value + 1)
    } catch (err) { setError(`${err.message || 'Unable to submit payment details.'} Refresh to check the application status before retrying.`) }
    finally { setBusy('') }
  }
  if (loading) return <section className="directory-card my-card"><p>Loading your church application…</p></section>
  if (error && !application) return <section className="directory-card my-card"><div className="notice notice-error" role="alert">{error}</div><button className="button button-outline" onClick={() => setRevision((value) => value + 1)}>Retry</button></section>
  if (!application) return null
  const pending = application.status === 'pending' && application.requested_plan_id && !application.payment_submitted_at
  return <section className="directory-card my-card"><div className="my-card-heading"><div><h2>Your church application</h2><p>Status: {application.status}. Payment is reviewed manually; submitting a receipt does not verify payment.</p></div><button className="button button-outline" disabled={Boolean(busy)} onClick={() => setRevision((value) => value + 1)}>Refresh</button></div>
    {error && <div className="notice notice-error" role="alert">{error}</div>}{notice && <div className="notice" role="status">{notice}</div>}
    {application.requested_plan_id && <p>Requested plan: <strong>{application.requested_plan_name} · {application.requested_plan_currency} {Number(application.requested_plan_price).toFixed(2)} / {application.requested_plan_period === 'MONTHLY' ? 'month' : 'year'}</strong>{application.payment_method && <> · {application.payment_method} · Reference: {application.transaction_reference}</>}</p>}
    {pending ? <><p>After confirming your email, optionally upload a PDF, JPEG or PNG receipt up to 8 MB. Then submit your details, with or without a receipt, for review. Once submitted, contact the platform owner to correct them.</p>
      {hasReceipt ? <div className="my-item-actions"><span>Receipt uploaded privately.</span><button className="button button-outline" disabled={Boolean(busy)} onClick={remove}><ActionLabel busy={busy === 'remove'} pending="Removing…">Remove receipt</ActionLabel></button></div> : <form className="my-form" onSubmit={upload}><label>Payment receipt <span className="optional">Optional</span><input type="file" accept="application/pdf,image/jpeg,image/png" onChange={(event) => setFile(event.target.files?.[0] || null)} required /></label><button className="button button-outline" disabled={Boolean(busy)}><ActionLabel busy={busy === 'upload'} pending="Uploading…">Upload receipt</ActionLabel></button></form>}
      <div className="modal-actions"><button className="button button-dark" disabled={Boolean(busy)} onClick={submit}><ActionLabel busy={busy === 'submit'} pending="Submitting…">Submit details for review</ActionLabel></button></div></> : <p>{application.payment_submitted_at ? `Payment details submitted${application.receipt_submitted ? ' with a receipt' : ' without a receipt'}.` : 'This application was created before plan and payment details were added.'}</p>}
  </section>
}
