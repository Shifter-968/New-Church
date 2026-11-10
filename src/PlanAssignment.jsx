import React, { useEffect, useState } from 'react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'

export default function PlanAssignment({ organizations }) {
  const [orgId, setOrgId] = useState('')
  const [planId, setPlanId] = useState('')
  const [plans, setPlans] = useState([])
  const [current, setCurrent] = useState(null)
  const [loading, setLoading] = useState(false)
  const [plansError, setPlansError] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  const [revision, setRevision] = useState(0)
  useEffect(() => {
    let active = true
    supabase.from('plans').select('id,name,is_active').eq('is_active', true).order('name').then(({ data, error: err }) => {
      if (!active) return
      if (err) setPlansError(`Unable to load active plans: ${err.message}`)
      else setPlans(data)
    }).catch((err) => { if (active) setPlansError(`Unable to load active plans: ${err.message}`) })
    return () => { active = false }
  }, [revision])
  useEffect(() => {
    let active = true
    setCurrent(null); setPlanId(''); setError('')
    if (!orgId) { setLoading(false); return () => { active = false } }
    setLoading(true)
    supabase.rpc('organization_plan_features', { target_org: orgId }).then(({ data, error: err }) => {
      if (!active) return
      if (err) setError(`Unable to load assigned plan: ${err.message}`)
      else { setCurrent(data[0] || null); if (data[0]?.plan_active) setPlanId(data[0].plan_id) }
      setLoading(false)
    }).catch((err) => { if (active) { setError(`Unable to load assigned plan: ${err.message}`); setLoading(false) } })
    return () => { active = false }
  }, [orgId, revision])
  async function save(remove) {
    if (busy || !orgId || (!remove && !planId)) return
    const action = remove ? 'Remove the assigned plan' : `Assign ${plans.find((p) => p.id === planId)?.name || 'the selected plan'}`
    if (!window.confirm(`${action} for ${organizations.find((org) => org.id === orgId)?.name}? This changes access immediately and does not verify payment.`)) return
    setBusy(true); setError(''); setMessage('')
    try {
      const { error: saveError } = await supabase.rpc('set_organization_plan', { target_org: orgId, target_plan: remove ? null : planId })
      if (saveError) throw saveError
      setRevision((value) => value + 1)
      setMessage('Plan assignment saved.')
    } catch (err) { setError(err.message || 'Unable to save plan assignment.') }
    finally { setBusy(false) }
  }
  return <section className="directory-card my-card"><h2>Assign a church plan</h2><p>Assigning a plan starts its billing schedule and controls included reporting features. It does not collect or verify payment; record verified payments from the church’s Billing tab. Usage limits are not enforced.</p>
    {plansError && <div className="notice notice-error" role="alert">{plansError}</div>}{error && <div className="notice notice-error" role="alert">{error}</div>}{message && <div className="notice" role="status">{message}</div>}
    <div className="my-form"><label>Church<select value={orgId} disabled={busy} onChange={(event) => { setOrgId(event.target.value); setMessage('') }}><option value="">Select a church</option>{organizations.map((org) => <option value={org.id} key={org.id}>{org.name}</option>)}</select></label>
      {orgId && (loading ? <p>Loading assigned plan…</p> : <p>Currently assigned: {current ? `${current.plan_name}${current.plan_active ? '' : ' (inactive)'}` : 'None'}</p>)}
      <label>Active plan<select value={planId} disabled={!orgId || loading || busy || Boolean(plansError)} onChange={(event) => setPlanId(event.target.value)}><option value="">Select a plan</option>{plans.map((plan) => <option value={plan.id} key={plan.id}>{plan.name}</option>)}</select></label>
      <div className="my-item-actions"><button className="button button-dark" disabled={!orgId || !planId || loading || busy || Boolean(error) || Boolean(plansError)} onClick={() => save(false)}><ActionLabel busy={busy} pending="Saving…">Assign plan</ActionLabel></button><button className="button button-outline" disabled={!orgId || !current || loading || busy || Boolean(error)} onClick={() => save(true)}>Remove assignment</button></div>
    </div>
  </section>
}
