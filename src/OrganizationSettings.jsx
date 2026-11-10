import React, { useEffect, useState } from 'react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'

export default function OrganizationSettings({ orgId, canAdmin, onSaved, navigate }) {
  const [form, setForm] = useState(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [revision, setRevision] = useState(0)
  useEffect(() => {
    let active = true
    setForm(null); setError('')
    if (!canAdmin) { setLoading(false); return () => { active = false } }
    setLoading(true)
    supabase.rpc('organization_settings', { target_org: orgId }).single().then(({ data, error: loadError }) => {
      if (!active) return
      if (loadError) setError(`Unable to load settings: ${loadError.message}`)
      else setForm(data)
      setLoading(false)
    }).catch((err) => { if (active) { setError(`Unable to load settings: ${err.message}`); setLoading(false) } })
    return () => { active = false }
  }, [orgId, canAdmin, revision])
  async function save(event) {
    event.preventDefault()
    if (busy) return
    setError(''); setMessage(''); setBusy(true)
    try {
      const { error: saveError } = await supabase.rpc('save_organization_settings', {
        target_org: orgId, church_name: form.name, discoverable: form.is_discoverable,
        member_registration: form.allow_member_registration, visitor_registration: form.allow_visitor_registration,
      })
      if (saveError) throw saveError
      setMessage('Church settings saved.'); setRevision((value) => value + 1)
      try { await onSaved() } catch (err) { setError(`Settings saved, but the workspace could not be refreshed: ${err.message}`) }
    } catch (err) { setError(`${err.message || 'Unable to save settings.'} If the connection was interrupted, refresh before retrying.`) }
    finally { setBusy(false) }
  }
  if (!canAdmin) return <div className="notice notice-error" role="alert">Church settings require organization administrator or platform owner access.</div>
  const update = (field) => (event) => setForm((current) => ({ ...current, [field]: event.target.type === 'checkbox' ? event.target.checked : event.target.value }))
  return <section className="directory-card my-card"><div className="my-card-heading"><div><h2>Church identity & registration</h2><p>Manage how people find and join your church.</p></div><button className="button button-outline" disabled={loading || busy} onClick={() => { setMessage(''); setRevision((value) => value + 1) }}>Reload settings</button></div>
    {error && <div className="notice notice-error" role="alert">{error}</div>}{message && <div className="notice" role="status">{message}</div>}
    {loading ? <p>Loading settings…</p> : form && <form className="my-form" onSubmit={save}>
      <label>Church name<input value={form.name} onChange={update('name')} maxLength={120} required /></label>
      <fieldset className="audience-picker"><legend>Public access</legend>
        <label className="audience-choice"><input type="checkbox" checked={form.is_discoverable} onChange={update('is_discoverable')} /> Show this church in public search</label>
        <label className="audience-choice"><input type="checkbox" checked={form.allow_member_registration} onChange={update('allow_member_registration')} /> Allow member self-registration</label>
        <label className="audience-choice"><input type="checkbox" checked={form.allow_visitor_registration} onChange={update('allow_visitor_registration')} /> Allow visitor self-registration</label>
      </fieldset>
      <p>Hiding the church removes it from public search and pauses incomplete individual registrations. Turning off a registration type also pauses pending or approved-but-incomplete registrations. Existing church accounts and administrator-created records are unaffected.</p>
      <button className="button button-dark" disabled={busy}><ActionLabel busy={busy} pending="Saving…">Save settings</ActionLabel></button>
    </form>}
    <p>Attendance location is configured separately for each branch.</p><button className="button button-outline" onClick={() => navigate('branches')}>Open branch settings</button>
  </section>
}
