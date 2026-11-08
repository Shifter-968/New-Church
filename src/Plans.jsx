import React, { useEffect, useState } from 'react'
import { ArrowRight, Plus, Tag, X } from 'lucide-react'
import { supabase } from './supabase'
import { inclusions, limits, planToForm, preparePlan } from './plans.js'
import ActionLabel from './ActionLabel'

export default function Plans() {
  const [plans, setPlans] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [editing, setEditing] = useState(null)
  const [form, setForm] = useState(null)
  const [busy, setBusy] = useState(false)

  async function load() {
    const { data, error: loadError } = await supabase.from('plans').select('*').order('created_at', { ascending: false })
    if (loadError) throw new Error(loadError.message)
    setPlans(data)
  }
  useEffect(() => {
    let active = true
    supabase.from('plans').select('*').order('created_at', { ascending: false }).then(({ data, error: loadError }) => {
      if (!active) return
      if (loadError) setError(`Unable to load plans: ${loadError.message}`)
      else setPlans(data)
      setLoading(false)
    })
    return () => { active = false }
  }, [])
  function open(plan = null) { setEditing(plan); setForm(planToForm(plan)); setError(''); setNotice('') }
  function update(key, value) { setForm((current) => ({ ...current, [key]: value })) }
  async function save(event) {
    event.preventDefault()
    setError(''); setNotice('')
    let payload
    try { payload = preparePlan(form) } catch (validationError) { setError(validationError.message); return }
    setBusy(true)
    try {
      const request = editing ? supabase.from('plans').update(payload).eq('id', editing.id) : supabase.from('plans').insert(payload)
      const { data, error: saveError } = await request.select('id')
      if (saveError || !data?.length) { setError(saveError?.message || 'The plan was not saved. Check your permissions.'); return }
      setForm(null)
      setNotice(editing ? 'Plan updated.' : 'Plan created.')
      try { await load() } catch (refreshError) { setError(`Saved, but the list could not be refreshed: ${refreshError.message}`) }
    } catch (saveError) {
      setError(saveError.message || 'Unable to save the plan. Please try again.')
    } finally { setBusy(false) }
  }
  return <section className="plans-screen">
    {notice && <div className="notice" role="status">{notice}</div>}
    {error && !form && <div className="notice notice-error" role="alert">{error}</div>}
    <div className="plans-heading"><div><h2>Plan catalogue</h2><p>Create and update the packages your church organisations will eventually choose.</p></div><button className="button button-dark" disabled={busy} onClick={() => open()}><Plus size={16} /> Create plan</button></div>
    <div className="notice">Plans are saved as a catalogue only. Registration, subscriptions, payments, and usage limits are not connected or enforced yet.</div>
    {loading ? <p className="loading">Loading plans…</p> : !plans.length ? <div className="empty-workspace"><span className="empty-icon"><Tag size={24} /></span><h2>No plans yet</h2><p>Create your first plan to start your catalogue.</p></div> : <div className="plan-list">{plans.map((plan) => <article className="directory-card plan-card" key={plan.id}><div className="plan-card-top"><span className="stat-icon mint"><Tag size={19} /></span><span className={`status ${plan.is_active ? 'active' : 'inactive'}`}><span />{plan.is_active ? 'Active' : 'Inactive'}</span></div><h3>{plan.name}</h3><p>{plan.description || 'No description provided.'}</p><div className="plan-price">{plan.currency} {Number(plan.price).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} <small>/ {plan.billing_period === 'MONTHLY' ? 'month' : 'year'}</small></div><div className="plan-limits">{limits.slice(0, 3).map(([key, label]) => <span key={key}>{plan[key] == null ? 'Unlimited' : plan[key]} {label.toLowerCase()}</span>)}</div><button className="text-button" onClick={() => open(plan)}>Edit plan <ArrowRight size={15} /></button></article>)}</div>}
    {form && <div className="modal-backdrop" onMouseDown={(event) => { if (!busy && event.target === event.currentTarget) setForm(null) }}><section className="modal plan-modal" role="dialog" aria-modal="true" aria-labelledby="plan-title"><div className="modal-heading"><div><h2 id="plan-title">{editing ? 'Edit plan' : 'Create a plan'}</h2><p>Set the package details and optional limits.</p></div><button className="icon-button" disabled={busy} onClick={() => setForm(null)} aria-label="Close dialog"><X size={20} /></button></div>
      {error && <div className="notice notice-error" role="alert">{error}</div>}
      <form className="member-form" onSubmit={save}><div className="form-grid"><label>Plan name<input value={form.name} onChange={(e) => update('name', e.target.value)} maxLength={120} required autoFocus /></label><label>Currency code<input value={form.currency} onChange={(e) => update('currency', e.target.value)} maxLength={3} required /></label><label>Price<input type="number" min="0" max="9999999999.99" step="0.01" value={form.price} onChange={(e) => update('price', e.target.value)} required /></label><label>Billing period<select value={form.billing_period} onChange={(e) => update('billing_period', e.target.value)}><option value="MONTHLY">Monthly</option><option value="ANNUALLY">Annually</option></select></label><label>Free trial days<input type="number" min="0" max="3650" step="1" value={form.free_trial_days} onChange={(e) => update('free_trial_days', e.target.value)} required /></label><label>Grace period days<input type="number" min="0" max="3650" step="1" value={form.grace_period_days} onChange={(e) => update('grace_period_days', e.target.value)} required /></label></div>
      <label>Description<textarea value={form.description} maxLength={2000} onChange={(e) => update('description', e.target.value)} /></label>
      <div><h3 className="plan-form-title">Limits</h3><p className="plan-form-hint">Leave blank for unlimited. Limits are not enforced yet.</p></div><div className="form-grid">{limits.map(([key, label]) => <label key={key}>{label}<input type="number" min="1" max="2147483647" step="1" value={form[key]} onChange={(e) => update(key, e.target.value)} placeholder="Unlimited" /></label>)}</div>
      <div><h3 className="plan-form-title">Included features</h3><div className="plan-checks">{inclusions.map(([key, label]) => <label key={key}><input type="checkbox" checked={form[key]} onChange={(e) => update(key, e.target.checked)} />{label}</label>)}<label><input type="checkbox" checked={form.is_active} onChange={(e) => update('is_active', e.target.checked)} />Available in catalogue</label></div></div><label>Additional features <span className="optional">One per line</span><textarea value={form.features} onChange={(e) => update('features', e.target.value)} /></label>
      <div className="modal-actions"><button type="button" className="button button-outline" disabled={busy} onClick={() => setForm(null)}>Cancel</button><button className="button button-dark" disabled={busy} aria-busy={busy}><ActionLabel busy={busy} pending="Saving…">Save plan</ActionLabel>{!busy && <ArrowRight size={15} />}</button></div></form></section></div>}
  </section>
}
