import React from 'react'

export default function AudiencePicker({ options, audience, onChange, disabled }) {
  function toggle(field, id) {
    const selected = audience[field]
    onChange({ ...audience, [field]: selected.includes(id) ? selected.filter((item) => item !== id) : [...selected, id] })
  }
  return <fieldset className="audience-picker" disabled={disabled}><legend>Who can see this?</legend>
    <label className="audience-choice"><input type="radio" name="audience" checked={audience.everyone} onChange={() => onChange({ everyone: true, roles: [], teams: [] })} /> Everyone in this church</label>
    <label className="audience-choice"><input type="radio" name="audience" checked={!audience.everyone} onChange={() => onChange({ everyone: false, roles: [], teams: [] })} /> Selected roles, ministries or departments</label>
    {!audience.everyone && <><p>Anyone matching at least one selection can see it. Organization administrators and platform support can always manage it.</p>{[['role', 'Roles', 'roles'], ['ministry', 'Ministries', 'teams'], ['department', 'Departments', 'teams']].map(([kind, title, field]) => <div key={kind}><strong>{title}</strong>{options.filter((item) => item.kind === kind).length === 0 ? <p>None available.</p> : options.filter((item) => item.kind === kind).map((item) => <label className="audience-choice" key={item.id}><input type="checkbox" checked={audience[field].includes(item.id)} onChange={() => toggle(field, item.id)} /> {item.name}</label>)}</div>)}</>}
  </fieldset>
}
