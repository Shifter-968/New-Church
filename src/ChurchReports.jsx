import React, { useEffect, useState } from 'react'
import Papa from 'papaparse'
import { supabase } from './supabase'
import { downloadCsv } from './MemberImport'
import ActionLabel from './ActionLabel'

export default function ChurchReports({ orgId, canAdmin }) {
  const [features, setFeatures] = useState(null)
  const [analytics, setAnalytics] = useState(null)
  const [branches, setBranches] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [revision, setRevision] = useState(0)
  useEffect(() => {
    let active = true
    if (!canAdmin) { setLoading(false); return () => { active = false } }
    async function load() {
      const { data, error: featureError } = await supabase.rpc('organization_plan_features', { target_org: orgId })
      if (featureError) throw featureError
      const current = data[0] || null
      const requests = []
      if (current?.analytics) requests.push(supabase.rpc('church_analytics', { target_org: orgId }))
      if (current?.advanced_reporting) requests.push(supabase.rpc('church_branch_report', { target_org: orgId }))
      const results = await Promise.all(requests)
      const failure = results.find((result) => result.error)
      if (failure) throw failure.error
      if (active) {
        setFeatures(current)
        setAnalytics(current?.analytics ? results[0].data[0] : null)
        setBranches(current?.advanced_reporting ? results[current.analytics ? 1 : 0].data : [])
      }
    }
    setLoading(true); setError(''); setFeatures(null); setAnalytics(null); setBranches([])
    load().catch((err) => { if (active) setError(`Unable to load reports: ${err.message}`) }).finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [orgId, canAdmin, revision])
  if (!canAdmin) return <div className="notice notice-error" role="alert">Reports currently require organization administrator or platform owner access.</div>
  function exportReport() {
    const data = branches.map((branch) => ({ branch: branch.branch_name, active_members: branch.active_members, visitors: branch.visitors, checkins_last_30_days: branch.checkins_last_30_days }))
    downloadCsv('branch-report.csv', '\uFEFF' + Papa.unparse(data, { escapeFormulae: /^[\t\r\n ]*[=+\-@]|^[\t\r\n]/ }))
  }
  return <section className="directory-card my-card"><div className="my-card-heading"><div><h2>Reports & analytics</h2><p>Church-wide totals use database records, not just the loaded directory. Check-ins count attendance records from the last 30 days, not unique people.</p></div><button className="button button-outline" disabled={loading} onClick={() => setRevision((value) => value + 1)}><ActionLabel busy={loading} pending="Loading…">Refresh</ActionLabel></button></div>
    {error && <div className="notice notice-error" role="alert">{error}</div>}
    {loading ? <p>Loading reports…</p> : error ? null : !features ? <p>No plan is assigned to this church. A platform owner must assign one before plan features are available.</p> : <>
      <p>Assigned plan: <strong>{features.plan_name}</strong>{!features.plan_active && ' (inactive)'}. Plan assignment is manual and does not verify payment.</p>
      {features.analytics ? <><h3>Analytics</h3><div className="my-list">{[['Active members', analytics.active_members], ['Visitors', analytics.visitors], ['Branches', analytics.branches], ['Check-ins in the last 30 days', analytics.checkins_last_30_days]].map(([label, count]) => <article className="my-list-item" key={label}><strong>{label}</strong><span>{count}</span></article>)}</div></> : <p>Analytics is not included in this active plan.</p>}
      {features.advanced_reporting ? <><h3>Branch report</h3><p>Shows up to 1,000 branches, subject to the API row limit. Members and visitors with no branch are excluded from this breakdown. Export includes only displayed branches.</p><button className="button button-outline" disabled={!branches.length} onClick={exportReport}>Export branch report CSV</button>{!branches.length ? <p>No branches available.</p> : <div className="table-scroll"><table><thead><tr><th>BRANCH</th><th>ACTIVE MEMBERS</th><th>VISITORS</th><th>CHECK-INS (30 DAYS)</th></tr></thead><tbody>{branches.map((branch) => <tr key={branch.branch_id}><td>{branch.branch_name}</td><td>{branch.active_members}</td><td>{branch.visitors}</td><td>{branch.checkins_last_30_days}</td></tr>)}</tbody></table></div>}</> : <p>Advanced reporting is not included in this active plan.</p>}
    </>}
  </section>
}
