import React, { useEffect, useRef, useState } from 'react'
import { MapPin } from 'lucide-react'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
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
  const [search, setSearch] = useState('')
  const [searchResults, setSearchResults] = useState([])
  const mapElement = useRef(null)
  const map = useRef(null)
  const marker = useRef(null)
  const lastSearchAt = useRef(0)

  useEffect(() => {
    if (!branchId || !mapElement.current || map.current) return undefined
    const mapInstance = L.map(mapElement.current).setView([0, 20], 3)
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    }).addTo(mapInstance)
    mapInstance.on('click', ({ latlng }) => {
      setForm((value) => ({ ...value, latitude: latlng.lat.toFixed(6), longitude: latlng.lng.toFixed(6) }))
      setError('')
    })
    map.current = mapInstance
    return () => {
      mapInstance.remove()
      map.current = null
      marker.current = null
    }
  }, [branchId])

  useEffect(() => {
    if (!map.current || form.latitude === '' || form.longitude === '') return
    const point = [Number(form.latitude), Number(form.longitude)]
    if (!point.every(Number.isFinite)) return
    map.current.setView(point, Math.max(map.current.getZoom(), 15))
    if (!marker.current) marker.current = L.circleMarker(point, { radius: 9, color: '#294e3e', fillColor: '#d3a64b', fillOpacity: 0.9 }).addTo(map.current)
    else marker.current.setLatLng(point)
  }, [form.latitude, form.longitude])

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
  async function searchPlace() {
    if (!search.trim() || busy) return
    const wait = 1000 - (Date.now() - lastSearchAt.current)
    if (wait > 0) { setError('Please wait a moment before searching again.'); return }
    lastSearchAt.current = Date.now()
    setBusy('search'); setError(''); setSearchResults([])
    try {
      const url = new URL('https://nominatim.openstreetmap.org/search')
      url.search = new URLSearchParams({ q: search.trim(), format: 'jsonv2', limit: '5' }).toString()
      const response = await fetch(url)
      if (!response.ok) throw new Error(`Map search failed (${response.status}).`)
      const results = await response.json()
      setSearchResults(results)
      if (!results.length) setError('No matching places found. Try a nearby town or address.')
    } catch (err) {
      setError(err.message || 'Unable to search for that place. You can still select a point on the map.')
    } finally { setBusy('') }
  }
  function choosePlace(place) {
    const latitude = Number(place.lat); const longitude = Number(place.lon)
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) { setError('This search result did not contain valid coordinates.'); return }
    const label = (place.name || place.display_name || '').slice(0, 255)
    setForm((value) => ({ ...value, latitude: latitude.toFixed(6), longitude: longitude.toFixed(6), location_label: label || value.location_label }))
    setSearchResults([])
    setSearch(place.display_name || place.name || '')
  }
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
  return <section className="directory-card branch-card"><span className="stat-icon mint"><MapPin size={19} /></span><h2>Attendance location</h2><p>Search for the city or address, then select the church location on the map. The map uses OpenStreetMap; searching uses Nominatim.</p>
    {error && <div className="notice notice-error" role="alert">{error}</div>}{message && <div className="notice" role="status">{message}</div>}
    <form className="branch-form" onSubmit={save}>
      <label>Branch<select value={branchId} onChange={(event) => chooseBranch(event.target.value)} disabled={loading || Boolean(busy)} required><option value="">Select a branch</option>{branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}</select></label>
      {branchId && <><label>Location label <span className="optional">Optional</span><input maxLength={255} value={form.location_label} onChange={change('location_label')} disabled={Boolean(busy)} /></label>
        <div className="branch-map-search"><label>Search a city or address<input value={search} onChange={(event) => setSearch(event.target.value)} onKeyDown={(event) => { if (event.key === 'Enter') { event.preventDefault(); searchPlace() } }} maxLength={200} disabled={Boolean(busy)} placeholder="e.g. Manzini, Eswatini" /></label><button type="button" className="button button-outline" onClick={searchPlace} disabled={Boolean(busy) || !search.trim()}><ActionLabel busy={busy === 'search'} pending="Searching…">Search map</ActionLabel></button></div>
        {searchResults.length > 0 && <div className="branch-map-results" aria-label="Map search results">{searchResults.map((place) => <button key={place.place_id} type="button" className="text-button" disabled={Boolean(busy)} onClick={() => choosePlace(place)}>{place.display_name}</button>)}</div>}
        <div ref={mapElement} className="branch-map" role="application" aria-label="Select the church location on the map" />
        <p>Click the map to set the pin. You can also adjust the coordinates below.</p>
        <div className="form-grid"><label>Latitude<input type="number" step="any" min="-90" max="90" value={form.latitude} onChange={change('latitude')} disabled={Boolean(busy)} required /></label><label>Longitude<input type="number" step="any" min="-180" max="180" value={form.longitude} onChange={change('longitude')} disabled={Boolean(busy)} required /></label></div>
        <label>Allowed radius in metres<input type="number" min="20" max="2000" step="1" value={form.radius_meters} onChange={change('radius_meters')} disabled={Boolean(busy)} required /></label>
        <button type="button" className="button button-outline" disabled={Boolean(busy)} aria-label={busy === 'location' ? 'Finding location' : 'Use current device location'} onClick={useLocation}><ActionLabel busy={busy === 'location'} pending="Finding location…">Use current device location</ActionLabel></button>
        <button className="button button-dark" disabled={Boolean(busy)} aria-label={busy === 'save' ? 'Saving location' : 'Save location'}><ActionLabel busy={busy === 'save'} pending="Saving…">Save location</ActionLabel></button></>}
    </form>
  </section>
}
