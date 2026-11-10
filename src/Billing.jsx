import React, { useEffect, useState } from 'react'
import { CalendarDays, Check, Clock3, CreditCard, ShieldCheck } from 'lucide-react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'

function localDateInput() {
  const now = new Date()
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`
}

function displayDate(value) {
  if (!value) return '—'
  const [year, month, day] = value.split('-').map(Number)
  return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(new Date(year, month - 1, day))
}

function price(plan) {
  return `${plan.currency} ${Number(plan.price).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

function Usage({ label, used, limit }) {
  const percentage = limit == null ? 0 : Math.min(100, Math.round(used / limit * 100))
  return <div className="billing-usage">
    <div><strong>{label}</strong><span>{used.toLocaleString()} used {limit == null ? '· Unlimited' : `of ${Number(limit).toLocaleString()}`}</span></div>
    {limit != null && <div className="billing-progress" role="progressbar" aria-valuenow={percentage} aria-valuemin="0" aria-valuemax="100"><span style={{ width: `${percentage}%` }} /></div>}
  </div>
}

export default function Billing({ orgId, owner = false }) {
  const [summary, setSummary] = useState(null)
  const [plans, setPlans] = useState([])
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [revision, setRevision] = useState(0)
  const [paidOn, setPaidOn] = useState(localDateInput)
  const [amount, setAmount] = useState('')
  const [reference, setReference] = useState('')

  useEffect(() => {
    let active = true
    async function load() {
      setLoading(true)
      setError('')
      const [billingResult, plansResult] = await Promise.all([
        supabase.rpc('church_plan_billing_summary', { target_org: orgId }),
        supabase.from('plans').select('id,name,description,price,currency,billing_period,free_trial_days,grace_period_days,max_branches,max_members,max_visitors,max_users,features,include_support,include_analytics,include_advanced_reporting,include_integrations').eq('is_active', true).order('price'),
      ])
      if (!active) return
      if (billingResult.error || plansResult.error) {
        setError(`Unable to load billing details: ${(billingResult.error || plansResult.error).message}`)
      } else {
        const current = billingResult.data?.[0] || null
        setSummary(current)
        setPlans(plansResult.data.filter((plan) => plan.id !== current?.plan_id))
        setAmount(current ? String(current.price) : '')
      }
      setLoading(false)
    }
    load().catch((err) => { if (active) { setError(`Unable to load billing details: ${err.message}`); setLoading(false) } })
    return () => { active = false }
  }, [orgId, revision])

  async function recordPayment(event) {
    event.preventDefault()
    if (busy || !summary) return
    setBusy(true); setError(''); setNotice('')
    try {
      const { error: saveError } = await supabase.rpc('record_organization_plan_payment', {
        target_org: orgId, paid_on: paidOn, amount: Number(amount), reference: reference.trim(),
      })
      if (saveError) throw saveError
      setRevision((value) => value + 1)
      setReference('')
      setNotice('Payment recorded and the next due date updated.')
    } catch (err) {
      setError(err.message || 'Unable to record the payment.')
    } finally { setBusy(false) }
  }

  const status = summary ? (summary.plan_active ? summary.billing_status : 'inactive') : ''
  return <section className="billing-screen">
    {error && <div className="notice notice-error" role="alert">{error}</div>}
    {notice && <div className="notice" role="status"><Check size={16} /> {notice}</div>}
    {loading ? <p className="loading">Loading billing information…</p> : <>
      {summary ? <article className="directory-card billing-current">
        <div className="billing-heading"><div><span className="section-kicker">CURRENT SUBSCRIPTION</span><h2>{summary.plan_name}</h2><p>{price(summary)} / {summary.billing_period === 'MONTHLY' ? 'month' : 'year'}</p></div><span className={`billing-status ${status}`}><span />{status === 'trial' ? 'Free trial' : status === 'grace' ? 'Grace period' : status === 'expired' ? 'Expired' : status === 'inactive' ? 'Inactive plan' : 'Active'}</span></div>
        <div className="billing-dates">
          {status === 'trial' ? <div><Clock3 size={18} /><span><strong>{Math.max(0, summary.trial_end_date ? Math.ceil((new Date(`${summary.trial_end_date}T00:00:00Z`) - new Date(`${localDateInput()}T00:00:00Z`)) / 86400000) : 0)} days</strong><small>left in trial</small></span></div>
            : <div><CalendarDays size={18} /><span><strong>{summary.days_to_due} days</strong><small>until payment is due</small></span></div>}
          <div><CalendarDays size={18} /><span><strong>{displayDate(summary.next_payment_due_date)}</strong><small>next payment due</small></span></div>
          <div><Clock3 size={18} /><span><strong>{summary.grace_days_remaining} days</strong><small>{status === 'grace' ? `grace ends ${displayDate(summary.grace_period_end_date)}` : status === 'expired' ? `grace ended ${displayDate(summary.grace_period_end_date)}` : `grace period: ${summary.grace_period_days} days`}</small></span></div>
        </div>
        <div className="billing-usage-grid">
          <Usage label="Active members" used={summary.active_members} limit={summary.max_members} />
          <Usage label="Visitors" used={summary.visitors} limit={summary.max_visitors} />
          <Usage label="Branches" used={summary.branches} limit={summary.max_branches} />
          <Usage label="Active accounts" used={summary.active_users} limit={summary.max_users} />
        </div>
        <p className="billing-footnote">Included features: {[summary.include_support && 'Support', summary.include_analytics && 'Analytics', summary.include_advanced_reporting && 'Advanced reporting', summary.include_integrations && 'Integrations', ...(summary.features || [])].filter(Boolean).join(' · ') || 'Standard plan features'}</p>
        {(summary.max_storage_gb != null || summary.max_api_calls_per_month != null || summary.max_api_calls_per_minute != null) && <p className="billing-footnote">Storage and API usage are not currently measured in the dashboard.</p>}
        <p className="billing-footnote">Usage is shown for reference. Plan limits are not yet enforced. Grace begins after the payment due date and ends on the displayed grace-period date.</p>
        {summary.last_payment_at && <p className="billing-last-payment">Last payment: {displayDate(summary.last_payment_at)} · {summary.currency} {Number(summary.last_payment_amount).toFixed(2)} · Reference: {summary.last_payment_reference}</p>}
        {owner && <form className="billing-payment-form" onSubmit={recordPayment}>
          <h3><CreditCard size={18} /> Record a manually verified payment</h3>
          <p>Only record a payment after verifying it outside AfriChurch. This does not charge the church.</p>
          <div className="form-grid"><label>Payment date<input type="date" max={localDateInput()} value={paidOn} onChange={(event) => setPaidOn(event.target.value)} required /></label><label>Amount ({summary.currency})<input type="number" min="0" step="0.01" value={amount} onChange={(event) => setAmount(event.target.value)} required /></label></div>
          <label>Payment reference<input maxLength={200} value={reference} onChange={(event) => setReference(event.target.value)} required /></label>
          <button className="button button-dark" disabled={busy} aria-busy={busy}><ActionLabel busy={busy} pending="Recording…">Record payment</ActionLabel></button>
        </form>}
      </article> : <div className="directory-card billing-current"><span className="stat-icon mint"><ShieldCheck size={19} /></span><h2>No plan is assigned</h2><p>Contact the platform owner to assign a plan to this church.</p></div>}

      <div className="billing-plans-heading"><div><h2>Other available plans</h2><p>Compare the current catalogue. Plans shown here are read-only; contact the platform owner to change your assignment.</p></div></div>
      {plans.length ? <div className="plan-list">{plans.map((plan) => <article className="directory-card plan-card" key={plan.id}><h3>{plan.name}</h3><p>{plan.description || 'No description provided.'}</p><div className="plan-price">{price(plan)} <small>/ {plan.billing_period === 'MONTHLY' ? 'month' : 'year'}</small></div><div className="plan-limits">{[['max_branches', 'branches'], ['max_members', 'members'], ['max_visitors', 'visitors'], ['max_users', 'accounts']].map(([key, label]) => <span key={key}>{plan[key] == null ? 'Unlimited' : Number(plan[key]).toLocaleString()} {label}</span>)}</div><p>Included features: {[plan.include_support && 'Support', plan.include_analytics && 'Analytics', plan.include_advanced_reporting && 'Advanced reporting', plan.include_integrations && 'Integrations', ...(plan.features || [])].filter(Boolean).join(' · ') || 'Standard plan features'}</p></article>)}</div> : <p>No other active plans are available.</p>}
    </>}
  </section>
}
