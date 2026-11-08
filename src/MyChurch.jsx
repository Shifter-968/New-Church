import React, { useEffect, useState } from 'react'
import { ArrowRight, Bell, Check, UserRound } from 'lucide-react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'
import ChurchFeed from './ChurchFeed.jsx'
import './my-church.css'

const blankProfile = { first_name: '', last_name: '', middle_name: '', phone: '', phone_2: '', date_of_birth: '', gender: '', marital_status: '', address: '', city: '', country: '', baptized: false }
const dateTime = (value) => new Date(value).toLocaleString()

function Feedback({ error, message }) {
  return <>{error && <div className="notice notice-error" role="alert">{error}</div>}{message && <div className="notice" role="status">{message}</div>}</>
}

function Profile({ user, organization, assignments }) {
  const [form, setForm] = useState(blankProfile)
  const [loading, setLoading] = useState(true)
  const [loadFailed, setLoadFailed] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  useEffect(() => {
    let active = true
    supabase.from('profiles').select('*').eq('user_id', user.id).maybeSingle().then(({ data, error: loadError }) => {
      if (!active) return
      if (loadError) { setLoadFailed(true); setError(`Unable to load your profile: ${loadError.message}`) }
      else if (data) setForm({ ...blankProfile, ...Object.fromEntries(Object.keys(blankProfile).map((key) => [key, data[key] ?? blankProfile[key]])) })
      setLoading(false)
    })
    return () => { active = false }
  }, [user.id])
  const update = (key) => (event) => setForm((current) => ({ ...current, [key]: event.target.type === 'checkbox' ? event.target.checked : event.target.value }))
  async function save(event) {
    event.preventDefault()
    setError(''); setMessage(''); setBusy(true)
    try {
      const { error: saveError } = await supabase.from('profiles').upsert({ ...form, date_of_birth: form.date_of_birth || null, user_id: user.id })
      if (saveError) throw saveError
      setMessage('Your profile has been saved.')
    } catch (saveError) { setError(saveError.message || 'Unable to save your profile.') } finally { setBusy(false) }
  }
  if (loading) return <p className="loading">Loading your profile…</p>
  return <div className="my-church-layout"><section className="directory-card my-card"><div className="my-card-heading"><span className="stat-icon mint"><UserRound size={20} /></span><div><h2>Personal details</h2><p>Keep your account information up to date.</p></div></div><Feedback error={error} message={message} /><form className="my-form" onSubmit={save}><div className="form-grid">{[['first_name','First name'],['last_name','Last name'],['middle_name','Middle name'],['phone','Phone number'],['phone_2','Second phone number'],['address','Address'],['city','City'],['country','Country']].map(([key,label]) => <label key={key}>{label}<input value={form[key]} onChange={update(key)} maxLength={key.includes('phone') ? 40 : key === 'address' ? 255 : key === 'city' || key === 'country' ? 120 : 100} /></label>)}<label>Date of birth<input type="date" value={form.date_of_birth} onChange={update('date_of_birth')} /></label><label>Gender<select value={form.gender} onChange={update('gender')}><option value="">Not specified</option><option value="MALE">Male</option><option value="FEMALE">Female</option><option value="OTHER">Other</option></select></label><label>Marital status<select value={form.marital_status} onChange={update('marital_status')}><option value="">Not specified</option><option value="SINGLE">Single</option><option value="MARRIED">Married</option><option value="ENGAGED">Engaged</option><option value="DIVORCED">Divorced</option><option value="UNOFFICIAL_RELATIONSHIP">Unofficial relationship</option></select></label><label className="my-check"><input type="checkbox" checked={form.baptized} onChange={update('baptized')} /> Baptized</label></div><button className="button button-dark" disabled={busy || loadFailed} aria-busy={busy}><ActionLabel busy={busy} pending="Saving…">Save profile</ActionLabel>{!busy && <ArrowRight size={16} />}</button></form></section><aside className="directory-card my-card"><h2>Account & access</h2><p>Email</p><strong>{user.email}</strong><p>Church workspace</p><strong>{organization?.name || 'No church selected'}</strong><p>Assigned roles</p><strong>{assignments.map((assignment) => assignment.roles?.name).filter(Boolean).join(', ') || 'No church role assigned'}</strong><p>Profile information is private to your account. It is not yet linked to the church member directory.</p></aside></div>
}

function PasswordSettings() {
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  async function save(event) {
    event.preventDefault(); setError(''); setMessage('')
    if (password !== confirm) { setError('Passwords do not match.'); return }
    setBusy(true)
    try {
      const { error: saveError } = await supabase.auth.updateUser({ password })
      if (saveError) throw saveError
      setPassword(''); setConfirm(''); setMessage('Password updated.')
    } catch (saveError) { setError(saveError.message || 'Unable to update your password.') } finally { setBusy(false) }
  }
  return <section className="directory-card my-card my-narrow"><h2>Account security</h2><p>Change your account password. Your existing session may require recent authentication.</p><Feedback error={error} message={message} /><form className="my-form" onSubmit={save}><label>New password<input type="password" autoComplete="new-password" value={password} onChange={(e) => setPassword(e.target.value)} required minLength={6} /></label><label>Confirm new password<input type="password" autoComplete="new-password" value={confirm} onChange={(e) => setConfirm(e.target.value)} required /></label><button className="button button-dark" disabled={busy} aria-busy={busy}><ActionLabel busy={busy} pending="Updating…">Update password</ActionLabel></button></form></section>
}

function Notifications({ userId }) {
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  useEffect(() => {
    let active = true
    supabase.from('notifications').select('id,title,message,created_at,read_at').eq('user_id', userId).order('created_at', { ascending: false }).limit(100).then(({ data, error: loadError }) => {
      if (active) { if (loadError) setError(loadError.message); else setItems(data); setLoading(false) }
    })
    return () => { active = false }
  }, [userId])
  async function markRead(id) {
    setBusy(true); setError('')
    const now = new Date().toISOString()
    try {
      let request = supabase.from('notifications').update({ read_at: now }).eq('user_id', userId).is('read_at', null)
      if (id) request = request.eq('id', id)
      const { data, error: saveError } = await request.select('id,read_at')
      if (saveError) throw saveError
      const updated = new Map(data.map((item) => [item.id, item.read_at]))
      setItems((current) => current.map((item) => updated.has(item.id) ? { ...item, read_at: updated.get(item.id) } : item))
    } catch (saveError) { setError(saveError.message || 'Unable to mark notifications as read.') } finally { setBusy(false) }
  }
  return <section className="directory-card my-card"><div className="my-card-heading"><span className="stat-icon peach"><Bell size={20} /></span><div><h2>Your notifications</h2><p>Showing your latest 100 notifications. Automatic notifications are not yet generated by the app.</p></div><button className="button button-outline" disabled={busy || !items.some((item) => !item.read_at)} onClick={() => markRead()}><ActionLabel busy={busy} pending="Updating…">Mark all read</ActionLabel></button></div><Feedback error={error} />{loading ? <p>Loading notifications…</p> : items.length === 0 ? <p>You’re all caught up.</p> : <div className="my-list">{items.map((item) => <article key={item.id} className="my-list-item"><div><h3>{item.title} {!item.read_at && <span className="unread-dot" aria-label="Unread" />}</h3><p>{item.message}</p><small>{dateTime(item.created_at)}</small></div>{!item.read_at && <button className="text-button" disabled={busy} onClick={() => markRead(item.id)}>Mark read <Check size={15} /></button>}</article>)}</div>}</section>
}

export default function MyChurch({ page, user, orgId, organization, organizations, assignments, canAdmin, owner }) {
  if (page === 'profile') return <Profile user={user} organization={organization} assignments={assignments} />
  if (page === 'personal-settings') return <PasswordSettings />
  if (page === 'notifications') return <Notifications userId={user.id} />
  if (page === 'announcements' || page === 'calendar') {
    if (!orgId && !owner) return <section className="empty-workspace"><h2>No church selected</h2><p>These updates require a church workspace.</p></section>
    return <ChurchFeed key={`${page}-${orgId}`} page={page} orgId={orgId} organizations={organizations} owner={owner} canAdmin={canAdmin} />
  }
  return null
}
