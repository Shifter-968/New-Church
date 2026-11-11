import React, { useEffect, useRef, useState } from 'react'
import { MapPin, Search, X } from 'lucide-react'
import L from 'leaflet'

export default function EventLocationPicker({ eventFormat, location, latitude, longitude, onChange, disabled }) {
    const mapElement = useRef(null)
    const map = useRef(null)
    const marker = useRef(null)
    const lastSearchAt = useRef(0)
    const disabledRef = useRef(disabled)
    const [search, setSearch] = useState('')
    const [results, setResults] = useState([])
    const [busy, setBusy] = useState(false)
    const [error, setError] = useState('')

    useEffect(() => { disabledRef.current = disabled }, [disabled])

    useEffect(() => {
        if (!mapElement.current || map.current) return undefined
        const hasCoordinates = latitude !== '' && longitude !== ''
        const center = hasCoordinates ? [Number(latitude), Number(longitude)] : [0, 20]
        const mapInstance = L.map(mapElement.current).setView(center, hasCoordinates ? 15 : 2)
        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
            maxZoom: 19,
            attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
        }).addTo(mapInstance)
        mapInstance.on('click', ({ latlng }) => { if (!disabledRef.current) onChange({ latitude: latlng.lat.toFixed(6), longitude: latlng.lng.toFixed(6) }) })
        map.current = mapInstance
        return () => { mapInstance.remove(); map.current = null; marker.current = null }
    }, [])

    useEffect(() => {
        if (!map.current) return
        if (latitude === '' || longitude === '') {
            if (marker.current) { marker.current.remove(); marker.current = null }
            return
        }
        const point = [Number(latitude), Number(longitude)]
        if (!point.every(Number.isFinite)) return
        map.current.setView(point, Math.max(map.current.getZoom(), 15))
        if (!marker.current) marker.current = L.circleMarker(point, { radius: 9, color: '#294e3e', fillColor: '#d3a64b', fillOpacity: 0.9 }).addTo(map.current)
        else marker.current.setLatLng(point)
    }, [latitude, longitude])

    async function searchPlace(event) {
        event.preventDefault()
        if (!search.trim() || busy) return
        const wait = 1000 - (Date.now() - lastSearchAt.current)
        if (wait > 0) { setError('Please wait a moment before searching again.'); return }
        lastSearchAt.current = Date.now(); setBusy(true); setError(''); setResults([])
        try {
            const url = new URL('https://nominatim.openstreetmap.org/search')
            url.search = new URLSearchParams({ q: search.trim(), format: 'jsonv2', limit: '5' }).toString()
            const response = await fetch(url)
            if (!response.ok) throw new Error(`Map search failed (${response.status}).`)
            const places = await response.json()
            setResults(places)
            if (!places.length) setError('No matching places found. Try a nearby town or address.')
        } catch (requestError) { setError(requestError.message || 'Unable to search the map. You can still select a point directly.') }
        finally { setBusy(false) }
    }

    function choosePlace(place) {
        const selectedLatitude = Number(place.lat)
        const selectedLongitude = Number(place.lon)
        if (!Number.isFinite(selectedLatitude) || !Number.isFinite(selectedLongitude)) { setError('This search result did not contain valid coordinates.'); return }
        const label = (place.display_name || place.name || '').slice(0, 255)
        onChange({ latitude: selectedLatitude.toFixed(6), longitude: selectedLongitude.toFixed(6), location: label || location })
        setSearch(label); setResults([]); setError('')
    }

    function clearPin() {
        onChange({ latitude: '', longitude: '' })
        setSearch(''); setResults([])
    }

    return <div className="event-location">
        <label>{eventFormat === 'virtual' ? 'Online location or meeting link' : 'Venue name'} <span className="optional">Optional</span><input maxLength={255} value={location} onChange={(event) => onChange({ location: event.target.value })} disabled={disabled} /></label>
        {eventFormat === 'physical' && <details className="event-map" open>
            <summary><MapPin size={15} /> Physical event location <span className="optional">Required for check-in</span></summary>
            <p>Search for the venue or select its point on the map. Attendees must be within 100 m of this pin to check in.</p>
            {error && <div className="notice notice-error" role="alert">{error}</div>}
            <form className="branch-map-search" onSubmit={searchPlace}>
                <label>Search a city or address<input value={search} onChange={(event) => setSearch(event.target.value)} maxLength={200} disabled={disabled || busy} placeholder="e.g. Manzini, Eswatini" /></label>
                <button type="submit" className="button button-outline" disabled={disabled || busy || !search.trim()} aria-label="Search map"><Search size={15} />{busy ? 'Searching…' : 'Search map'}</button>
            </form>
            {results.length > 0 && <div className="branch-map-results" aria-label="Map search results">{results.map((place) => <button key={place.place_id} type="button" className="text-button" disabled={disabled} onClick={() => choosePlace(place)}>{place.display_name}</button>)}</div>}
            <div ref={mapElement} className="branch-map event-map-canvas" role="application" aria-label="Choose an event location on the map" />
            <div className="event-map-footer"><small>{latitude && longitude ? `Pinned at ${latitude}, ${longitude}` : 'No map pin selected'}</small>{latitude && longitude && <button type="button" className="text-button" onClick={clearPin} disabled={disabled}><X size={14} /> Clear pin</button>}</div>
        </details>}
    </div>
}