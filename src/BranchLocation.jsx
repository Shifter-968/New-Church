import React, { useEffect, useState } from 'react'
import { MapPin } from 'lucide-react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'

const empty = { latitude: '', longitude: '', radius_meters: '100', location_label: '' }

export default function BranchLocation({ orgId, branches }) {
  const [branchId, setBranchId] = useState('')
  const [locations, setLocations] = useState([])
  const [form, setForm] = useState(empty)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')

  useEffect(() => {
    let active = true
    setLoading(true); setError('')
    supabase.from('branches').select('id,latitude,longitude,radius_meters,location_label').eq('organization_id', orgId).then(({ data, error: loadError }) => {
      if (!active) return
      if (loadError) setError(`Unable to load locations: ${loadError.message}`)
      else setLocations(data)
      setLoading(false)
    }).catch((err) => { if (active) { setError(`Unable to load locations: ${err.message}`); setLoading(false) } })
    return () => { active = false }
  }, [orgId, branches])

  function chooseBranch(id) {
    const location = locations.find((item) => item.id === id)
    setBranchId(id); setMessage(''); setError('')
    setForm(location ? { latitude: location.latitude ?? '', longitude: location.longitude ?? '', radius_meters: String(location.radius_meters), location_label: location.location_label || '' } : empty)
  }
  function change(field) { return (event) => setForm((value) => ({ ...value, [field]: event.target.value })) }
  function useLocation() {
    if (!navigator.geolocation) { setError('Location is unavailable in this browser. Enter coordinates manually.'); return }
    setError(''); setMessage(''); setBusy('location')
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => { setForm((value) => ({ ...value, latitude: coords.latitude.toFixed(6), longitude: coords.longitude.toFixed(6) })); setBusy('') },
      (err) => { setError(`Could not get device location: ${err.message}. Allow location access or enter coordinates manually.`); setBusy('') },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
    )
  }
  async function save(event) {
    event.preventDefault()
    if (busy) return
    const latitude = Number(form.latitude); const longitude = Number(form.longitude); const radius = Number(form.radius_meters)
    if (!branchId || String(form.latitude).trim() === '' || String(form.longitude).trim() === '' || !Number.isFinite(latitude) || !Number.isFinite(longitude) || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180 || !Number.isInteger(radius) || radius < 20 || radius > 2000) {
      setError('Select a branch and enter valid coordinates and a radius from 20 to 2000 metres.'); return
    }
    setBusy('save'); setError(''); setMessage('')
    try {
      const { error: saveError } = await supabase.rpc('save_branch_location', { target_org: orgId, target_branch: branchId, new_latitude: latitude, new_longitude: longitude, new_radius: radius, new_label: form.location_label })
      if (saveError) throw saveError
      setLocations((items) => items.map((item) => item.id === branchId ? { ...item, latitude, longitude, radius_meters: radius, location_label: form.location_label.trim() } : item))
      setMessage('Branch location saved.')
    } catch (err) { setError(err.message || 'Unable to save location.') }
    finally { setBusy('') }
  }
  return <section className="directory-card branch-card"><span className="stat-icon mint"><MapPin size={19} /></span><h2>Attendance location</h2><p>Set the church coordinates and permitted radius for self check-in at each branch.</p>
    {error && <div className="notice notice-error" role="alert">{error}</div>}{message && <div className="notice" role="status">{message}</div>}
    <form className="branch-form" onSubmit={save}>
      <label>Branch<select value={branchId} onChange={(event) => chooseBranch(event.target.value)} disabled={loading || Boolean(busy)} required><option value="">Select a branch</option>{branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}</select></label>
      {branchId && <><label>Location label <span className="optional">Optional</span><input maxLength={255} value={form.location_label} onChange={change('location_label')} disabled={Boolean(busy)} /></label>
        <div className="form-grid"><label>Latitude<input type="number" step="any" min="-90" max="90" value={form.latitude} onChange={change('latitude')} disabled={Boolean(busy)} required /></label><label>Longitude<input type="number" step="any" min="-180" max="180" value={form.longitude} onChange={change('longitude')} disabled={Boolean(busy)} required /></label></div>
        <label>Allowed radius in metres<input type="number" min="20" max="2000" step="1" value={form.radius_meters} onChange={change('radius_meters')} disabled={Boolean(busy)} required /></label>
        <button type="button" className="button button-outline" disabled={Boolean(busy)} aria-label={busy === 'location' ? 'Finding location' : 'Use current device location'} onClick={useLocation}><ActionLabel busy={busy === 'location'} pending="Finding location…">Use current device location</ActionLabel></button>
        <button className="button button-dark" disabled={Boolean(busy)} aria-label={busy === 'save' ? 'Saving location' : 'Save location'}><ActionLabel busy={busy === 'save'} pending="Saving…">Save location</ActionLabel></button></>}
    </form>
  </section>
}
