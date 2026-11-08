import React, { useCallback, useEffect, useMemo, useState } from 'react'
import {
  ArrowDownRight, ArrowRight, ArrowUpRight, Building2, CalendarDays, Check,
  ChevronDown, Church, CircleHelp, ClipboardList, HeartHandshake, LayoutDashboard,
  LogOut, Menu, Plus, Search, ShieldCheck, Sparkles, Users, X,
} from 'lucide-react'
import { supabase } from './supabase'
import { canManageMembers } from './access'
import PublicApp from './PublicApp'
import BranchAdministration from './BranchAdministration'
import Applications from './Applications'
import Plans from './Plans.jsx'
import ActionLabel from './ActionLabel'
import MyChurch from './MyChurch.jsx'
import SupportActivity from './SupportActivity.jsx'
import ConnectGroups from './ConnectGroups.jsx'
import MembershipReviews from './MembershipReviews.jsx'
import MemberImport, { downloadCsv } from './MemberImport.jsx'
import Visitors from './Visitors.jsx'
import { AttendanceManagement, SelfAttendance } from './Attendance.jsx'
import { filterMembers, memberCsv } from './memberCsv'
import { isOrganizationAdmin, personalNavigation, visibleManagementNavigation } from './navigation'

const emptyMember = { first_name: '', last_name: '', email: '', phone: '', phone_2: '', date_of_birth: '', branch_id: '', status: 'active' }
function Brand({ light = false }) {
  return <div className={`brand ${light ? 'brand-light' : ''}`}><span className="brand-mark"><Church size={19} strokeWidth={2.2} /></span><span>afri<span className="brand-accent">church</span><small>CHURCH MANAGEMENT</small></span></div>
}

function Notice({ children, error = false }) {
  return <div className={`notice ${error ? 'notice-error' : ''}`} role={error ? 'alert' : 'status'}>{children}</div>
}

function AuthScreen({ configured, onHome, onRegister, churchName }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  async function signIn(event) {
    event.preventDefault()
    setError('')
    setBusy(true)
    try {
      const { error: authError } = await supabase.auth.signInWithPassword({ email: email.trim(), password })
      if (authError) setError(authError.message)
    } catch (authError) {
      setError(authError.message || 'Unable to sign in. Please try again.')
    } finally {
      setBusy(false)
    }
  }

  return <div className="auth-page">
    <div className="auth-main">
      <header className="auth-header"><button className="auth-home" onClick={onHome}><Brand /></button><button className="auth-back" onClick={onHome}>← Back to home</button></header>
      <main className="auth-content">
        <div className="eyebrow"><span className="eyebrow-dot" /> A BETTER WAY TO DO CHURCH</div>
        <h1>People first.<br /><em>Everything</em> else<br />follows.</h1>
        <p className="auth-description">A thoughtful space to care for your people, stay connected, and grow your church community together.</p>
        <div className="auth-card">
          <div className="card-heading"><div><h2>Welcome back</h2><p>{churchName ? `Sign in to ${churchName}.` : 'Sign in to your church workspace.'}</p></div><span className="lock-icon"><ShieldCheck size={21} /></span></div>
          {!configured && <Notice error>Supabase is not configured yet. Follow the setup instructions in the project README to connect your new database.</Notice>}
          {error && <Notice error>{error}</Notice>}
          <form onSubmit={signIn}>
            <label>Email address<input type="email" placeholder="you@yourchurch.org" value={email} onChange={(e) => setEmail(e.target.value)} required autoComplete="email" /></label>
            <label>Password<input type="password" placeholder="Enter your password" value={password} onChange={(e) => setPassword(e.target.value)} required autoComplete="current-password" /></label>
            <button className="button button-dark sign-in" disabled={!configured || busy} aria-busy={busy}><ActionLabel busy={busy} pending="Signing in…">Sign in to your workspace</ActionLabel>{!busy && <ArrowRight size={17} />}</button>
          </form>
          <p className="auth-help"><CircleHelp size={15} /> Need access? Contact your platform administrator.</p>
          <p className="auth-help">New here? <button className="auth-register" onClick={onRegister}>Register</button></p>
        </div>
      </main>
      <footer className="auth-footer"><span>© {new Date().getFullYear()} AfriChurch</span><span>Made for the work that matters.</span></footer>
    </div>
    <aside className="auth-aside">
      <div className="aside-top"><span>YOUR COMMUNITY, CONNECTED</span><Sparkles size={18} /></div>
      <div className="aside-art"><div className="art-ring ring-one" /><div className="art-ring ring-two" /><div className="art-ring ring-three" /><div className="art-center"><Church size={52} strokeWidth={1.1} /></div><div className="art-label art-label-one"><span className="art-icon"><Users size={17} /></span><span>People matter<small>Every story, in one place</small></span></div><div className="art-label art-label-two"><span className="art-icon gold"><HeartHandshake size={17} /></span><span>Stronger together<small>Built around community</small></span></div></div>
      <div className="aside-bottom"><div className="quote-mark">“</div><h2>More connection.<br />More purpose.<br /><span>More room to grow.</span></h2><p>Because behind every great church is a community worth caring for.</p><div className="aside-line" /><small>WELCOME TO AFRICHURCH &nbsp; / &nbsp; YOUR WORKSPACE</small></div>
    </aside>
  </div>
}

function Modal({ title, description, onClose, children, busy = false }) {
  useEffect(() => {
    function onKey(event) { if (event.key === 'Escape' && !busy) onClose() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose, busy])
  return <div className="modal-backdrop" onMouseDown={(e) => { if (!busy && e.target === e.currentTarget) onClose() }}>
    <section className="modal" role="dialog" aria-modal="true" aria-labelledby="modal-title">
      <div className="modal-heading"><div><h2 id="modal-title">{title}</h2><p>{description}</p></div><button className="icon-button" aria-label="Close dialog" disabled={busy} onClick={onClose}><X size={20} /></button></div>
      {children}
    </section>
  </div>
}

function MemberForm({ member, branches, canSaveBranch, onSave, onClose }) {
  const [form, setForm] = useState(member ? { ...member, branch_id: member.branch_id || '' } : emptyMember)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const change = (key) => (event) => setForm({ ...form, [key]: event.target.value })
  async function submit(event) {
    event.preventDefault()
    setError('')
    setBusy(true)
    const payload = {
      first_name: form.first_name.trim(), last_name: form.last_name.trim(),
      email: form.email?.trim() || null, phone: form.phone?.trim() || null,
      phone_2: form.phone_2?.trim() || null,
      date_of_birth: form.date_of_birth || null,
      branch_id: form.branch_id || null, status: form.status,
    }
    if (!payload.first_name || !payload.last_name) {
      setError('First and last names cannot be blank.')
      setBusy(false)
      return
    }
    try {
      const result = await onSave(payload, member?.id)
      if (result) setError(result)
    } catch (saveError) {
      setError(saveError.message || 'Unable to save the member. Please try again.')
    } finally {
      setBusy(false)
    }
  }
  return <Modal title={member ? 'Edit member' : 'Add a member'} description="Keep your community connected, one person at a time." onClose={onClose} busy={busy}>
    {error && <Notice error>{error}</Notice>}
    <form onSubmit={submit} className="member-form">
      <div className="form-grid"><label>First name<input value={form.first_name} onChange={change('first_name')} maxLength={100} required autoFocus /></label><label>Last name<input value={form.last_name} onChange={change('last_name')} maxLength={100} required /></label></div>
      <div className="form-grid"><label>Email address <span className="optional">Optional</span><input type="email" value={form.email || ''} onChange={change('email')} /></label><label>Phone number <span className="optional">Optional</span><input type="tel" value={form.phone || ''} onChange={change('phone')} /></label></div>
      <div className="form-grid"><label>Second phone number <span className="optional">Optional</span><input type="tel" maxLength={40} value={form.phone_2 || ''} onChange={change('phone_2')} /></label><label>Date of birth <span className="optional">Optional</span><input type="date" value={form.date_of_birth || ''} onChange={change('date_of_birth')} /></label></div>
      {member?.user_id && <Notice>Branch, status and deletion are unavailable for linked accounts until account access management is implemented.</Notice>}
      <div className="form-grid"><label>Branch<select value={form.branch_id} onChange={change('branch_id')} required={!canSaveBranch(null)} disabled={Boolean(member?.user_id)}><option value="" disabled={!canSaveBranch(null)}>No branch</option>{branches.filter((branch) => canSaveBranch(branch.id)).map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}</select></label><label>Status<select value={form.status} onChange={change('status')} disabled={Boolean(member?.user_id)}><option value="active">Active</option><option value="inactive">Inactive</option></select></label></div>
      <div className="modal-actions"><button type="button" className="button button-outline" disabled={busy} onClick={onClose}>Cancel</button><button className="button button-dark" disabled={busy} aria-busy={busy}><ActionLabel busy={busy} pending="Saving…">Save member</ActionLabel>{!busy && <ArrowRight size={16} />}</button></div>
    </form>
  </Modal>
}

function Workspace({ session }) {
  const [organizations, setOrganizations] = useState([])
  const [orgId, setOrgId] = useState('')
  const [owner, setOwner] = useState(false)
  const [assignments, setAssignments] = useState([])
  const [branches, setBranches] = useState([])
  const [members, setMembers] = useState([])
  const [page, setPage] = useState('dashboard')
  const [query, setQuery] = useState('')
  const [branchFilter, setBranchFilter] = useState('all')
  const [statusFilter, setStatusFilter] = useState('all')
  const [modal, setModal] = useState(null)
  const [newOrg, setNewOrg] = useState('')
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [loading, setLoading] = useState(true)
  const [orgLoading, setOrgLoading] = useState(false)
  const [busy, setBusy] = useState(false)
  const [menuOpen, setMenuOpen] = useState(false)
  const [signingOut, setSigningOut] = useState(false)
  const [deletingId, setDeletingId] = useState('')
  const [registrationError, setRegistrationError] = useState('')
  const [registrationStatus, setRegistrationStatus] = useState('')
  const [registrationBusy, setRegistrationBusy] = useState(false)

  const loadOrganizations = useCallback(async () => {
    const [ownerResult, orgResult] = await Promise.all([
      supabase.rpc('is_platform_owner'),
      supabase.from('organizations').select('id, name').order('name'),
    ])
    if (ownerResult.error || orgResult.error) throw new Error((ownerResult.error || orgResult.error).message)
    setOwner(ownerResult.data)
    setOrganizations(orgResult.data)
    setOrgId((current) => {
      const requested = new URLSearchParams(window.location.search).get('organization_id')
      return orgResult.data.some((org) => org.id === current) ? current : (orgResult.data.find((org) => org.id === requested)?.id || orgResult.data[0]?.id || '')
    })
  }, [])

  useEffect(() => {
    let active = true
    async function initialize() {
      if (session.user.user_metadata?.individual_registration) {
        const { data: status, error: completionError } = await supabase.rpc('complete_individual_registration')
        if (active && completionError) setRegistrationError(completionError.message)
        else if (active) setRegistrationStatus(status)
      }
      await loadOrganizations()
    }
    initialize().catch((err) => { if (active) setError(err.message) }).finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [loadOrganizations, session.user.user_metadata])

  async function retryRegistration() {
    setRegistrationError(''); setRegistrationBusy(true)
    try {
      const { data: status, error: completionError } = await supabase.rpc('complete_individual_registration')
      if (completionError) throw completionError
      setRegistrationStatus(status)
      await loadOrganizations()
      if (status === 'completed') setNotice('Your registration is complete.')
    } catch (err) { setRegistrationError(err.message || 'Unable to complete your registration.') }
    finally { setRegistrationBusy(false) }
  }

  const loadOrgData = useCallback(async (id) => {
    const [memberResult, branchResult, assignmentResult] = await Promise.all([
      supabase.from('members').select('*').eq('organization_id', id).order('created_at', { ascending: false }).limit(1000),
      supabase.from('branches').select('id, name').eq('organization_id', id).order('name'),
      supabase.from('assignments').select('branch_id, roles(name, is_org_admin, permissions)').eq('organization_id', id).eq('active', true),
    ])
    const resultError = memberResult.error || branchResult.error || assignmentResult.error
    if (resultError) throw new Error(resultError.message)
    return { members: memberResult.data, branches: branchResult.data, assignments: assignmentResult.data }
  }, [])

  useEffect(() => {
    let active = true
    setMembers([]); setBranches([]); setAssignments([]); setQuery(''); setBranchFilter('all'); setStatusFilter('all')
    if (!orgId) { setOrgLoading(false); return () => { active = false } }
    setOrgLoading(true)
    setError('')
    loadOrgData(orgId).then((data) => {
      if (active) { setMembers(data.members); setBranches(data.branches); setAssignments(data.assignments) }
    }).catch((err) => { if (active) setError(err.message) }).finally(() => { if (active) setOrgLoading(false) })
    return () => { active = false }
  }, [orgId, loadOrgData])

  async function refreshMembers() {
    const { data, error: loadError } = await supabase.from('members').select('*').eq('organization_id', orgId).order('created_at', { ascending: false }).limit(1000)
    if (loadError) throw new Error(loadError.message)
    setMembers(data)
  }

  async function saveMember(payload, id) {
    const request = id
      ? supabase.from('members').update(payload).eq('id', id).eq('organization_id', orgId)
      : supabase.from('members').insert({ ...payload, organization_id: orgId })
    const { data, error: saveError } = await request.select('id')
    if (saveError) return saveError.message
    if (!data.length) return 'The member was not saved. Check your permissions and try again.'
    setModal(null)
    setNotice(id ? 'Member updated successfully.' : 'Member added successfully.')
    try { await refreshMembers() } catch (err) { setError(`Saved, but the list could not be refreshed: ${err.message}`) }
    return null
  }

  async function deleteMember(member) {
    if (!window.confirm(`Remove ${member.first_name} ${member.last_name} from this directory? This cannot be undone.`)) return
    setError('')
    setDeletingId(member.id)
    try {
      const { data, error: deleteError } = await supabase.from('members').delete().eq('id', member.id).eq('organization_id', orgId).select('id')
      if (deleteError || !data?.length) { setError(deleteError?.message || 'The member could not be removed. Check your permissions.'); return }
      setNotice('Member removed.')
      try { await refreshMembers() } catch (err) { setError(`Removed, but the list could not be refreshed: ${err.message}`) }
    } catch (err) {
      setError(err.message || 'Unable to remove the member. Please try again.')
    } finally {
      setDeletingId('')
    }
  }

  async function createOrg(event) {
    event.preventDefault()
    setError('')
    if (newOrg.trim().length < 2) { setError('Church name must contain at least two characters.'); return }
    setBusy(true)
    try {
      const { data, error: createError } = await supabase.from('organizations').insert({ name: newOrg.trim() }).select('id').single()
      if (createError) { setError(createError.message); return }
      try {
        await loadOrganizations()
        setOrgId(data.id); setNewOrg(''); setModal(null); setNotice('Church workspace created.')
      } catch (err) { setError(`Church created, but the list could not be refreshed: ${err.message}`) }
    } catch (err) {
      setError(err.message || 'Unable to create the church. Please try again.')
    } finally {
      setBusy(false)
    }
  }

  async function signOut() {
    if (signingOut) return
    setError('')
    setSigningOut(true)
    try {
      const { error: signOutError } = await supabase.auth.signOut()
      if (signOutError) setError(signOutError.message)
    } catch (signOutError) {
      setError(signOutError.message || 'Unable to sign out. Please try again.')
    } finally {
      setSigningOut(false)
    }
  }

  const org = organizations.find((item) => item.id === orgId)
  const can = (action, branchId) => canManageMembers(owner, assignments, action, branchId)
  const canCreate = can('create', null) || branches.some((branch) => can('create', branch.id))
  const managementNav = visibleManagementNavigation(owner, assignments)
  const orgAdmin = isOrganizationAdmin(owner, assignments)
  const canViewMembers = managementNav.some((item) => item.id === 'members')
  const currentPage = [...personalNavigation, ...managementNav].find((item) => item.id === page)
  const pageAvailable = page === 'dashboard' || (['applications', 'plans'].includes(page) && owner) || Boolean(currentPage)
  const pageTitle = page === 'dashboard' ? 'Overview' : page === 'applications' && owner ? 'Church applications' : page === 'plans' && owner ? 'Plans & billing' : currentPage?.label || 'Access changed'
  const filtered = useMemo(() => filterMembers(members, query, branchFilter, statusFilter), [members, query, branchFilter, statusFilter])
  const activeCount = members.filter((member) => member.status === 'active').length
  const firstName = session.user.user_metadata?.full_name?.split(' ')[0] || session.user.email?.split('@')[0] || 'there'
  const navigate = (next) => { setPage(next); setMenuOpen(false); setNotice(''); if (next === 'dashboard') { setBranchFilter('all'); setStatusFilter('all') } }
  async function refreshBranches() {
    const { data, error: loadError } = await supabase.from('branches').select('id, name').eq('organization_id', orgId).order('name')
    if (loadError) throw new Error(loadError.message)
    setBranches(data)
  }

  return <div className="app-shell">
    <button className="mobile-menu icon-button" aria-label="Open menu" onClick={() => setMenuOpen(!menuOpen)}><Menu size={21} /></button>
    <aside className={`sidebar ${menuOpen ? 'sidebar-open' : ''}`}>
      <div className="sidebar-brand"><Brand /></div>
      <div className="workspace-picker"><div className="workspace-icon"><Church size={19} /></div><div className="workspace-name"><small>YOUR WORKSPACE</small><span>{org?.name || 'Select a church'}</span></div><ChevronDown size={16} /></div>
      <div className="nav-label">WORKSPACE</div>
      <nav className="workspace-nav" aria-label="Main navigation">
        <button className={`nav-item ${page === 'dashboard' ? 'selected' : ''}`} onClick={() => navigate('dashboard')}><LayoutDashboard size={18} /> Overview</button>
        {owner && <button className={`nav-item ${page === 'applications' ? 'selected' : ''}`} onClick={() => navigate('applications')}><ClipboardList size={18} /> Church applications</button>}
        {owner && <button className={`nav-item ${page === 'plans' ? 'selected' : ''}`} onClick={() => navigate('plans')}><Building2 size={18} /> Plans & billing</button>}
        <div className="nav-label nav-label-spaced">MY CHURCH</div>
        {personalNavigation.map((item) => <button key={item.id} className={`nav-item ${page === item.id ? 'selected' : ''}`} onClick={() => navigate(item.id)}><HeartHandshake size={18} /> {item.label}</button>)}
        {managementNav.length > 0 && <div className="nav-label nav-label-spaced">MANAGEMENT</div>}
        {managementNav.map((item) => <button key={item.id} className={`nav-item ${page === item.id ? 'selected' : ''}`} onClick={() => navigate(item.id)}><Users size={18} /> {item.label}{!['members', 'visitors', 'branches', 'membership-requests', 'attendance'].includes(item.id) && !(owner && item.id === 'audit') && <span className="nav-soon">Soon</span>}</button>)}
      </nav>
      <div className="sidebar-bottom"><div className="sidebar-note"><Sparkles size={17} /><strong>Built for belonging.</strong><p>A little more space for the things that matter.</p></div><button className="user-button" onClick={signOut} disabled={signingOut} aria-busy={signingOut}><span className="avatar">{firstName[0].toUpperCase()}</span><span className="user-info"><strong>{firstName}</strong><small><ActionLabel busy={signingOut} pending="Signing out…">Sign out</ActionLabel></small></span>{!signingOut && <LogOut size={17} />}</button></div>
    </aside>
    <div className="workspace">
      <header className="topbar"><div className="breadcrumb">Workspace <span>/</span> <strong>{pageTitle}</strong></div><div className="topbar-right">{owner && <span className="owner-badge"><ShieldCheck size={14} /> Platform owner</span>}{!owner && orgAdmin && <span className="owner-badge"><ShieldCheck size={14} /> Organization admin</span>}<span className="top-avatar">{firstName[0].toUpperCase()}</span></div></header>
      <main className="main-content">
        {error && <Notice error>{error}</Notice>}{registrationError && <div className="notice notice-error" role="alert">Registration is not complete: {registrationError} <button className="text-button" disabled={registrationBusy} onClick={retryRegistration}><ActionLabel busy={registrationBusy} pending="Retrying…">Retry registration</ActionLabel></button></div>}{registrationStatus === 'pending' && <div className="notice" role="status">Your registration needs church administrator review. After approval, sign in and retry. <button className="text-button" disabled={registrationBusy} onClick={retryRegistration}><ActionLabel busy={registrationBusy} pending="Checking…">Check status</ActionLabel></button></div>}{registrationStatus === 'rejected' && <Notice error>Your registration was not approved. Please contact your church administrator.</Notice>}{notice && <Notice><Check size={16} /> {notice}</Notice>}
        <div className="page-heading"><div><div className="eyebrow"><span className="eyebrow-dot" /> {page === 'dashboard' ? 'YOUR CHURCH, CONNECTED' : 'YOUR WORKSPACE'}</div><h1>{page === 'dashboard' ? `Welcome back, ${firstName}.` : pageTitle}</h1><p>{page === 'dashboard' ? 'Here’s a little overview of your community.' : page === 'members' ? 'A thoughtful home for the people who make your church.' : 'Your church community, in one place.'}</p></div>
          <div className="heading-actions">{organizations.length > 0 && <label className="select-wrap"><span className="sr-only">Choose church</span><Building2 size={16} /><select value={orgId} onChange={(e) => { setOrgId(e.target.value); setNotice('') }}>{organizations.map((item) => <option value={item.id} key={item.id}>{item.name}</option>)}</select></label>}{owner && <button className="button button-outline" onClick={() => { setError(''); setModal('organization') }}><Plus size={16} /> New church</button>}{org && canCreate && <button className="button button-dark" onClick={() => setModal('add')}><Plus size={17} /> Add member</button>}</div>
        </div>
        {loading ? <div className="loading">Loading your workspace…</div> : owner && page === 'applications' ? <Applications onApproved={loadOrganizations} /> : owner && page === 'plans' ? <Plans /> : owner && page === 'audit' ? <SupportActivity organizations={organizations} /> : page === 'community' && (owner || org) ? (orgLoading ? <div className="loading">Loading church workspace…</div> : <ConnectGroups key={orgId} orgId={orgId} organizations={organizations} owner={owner} canAdmin={orgAdmin} userId={session.user.id} />) : page === 'my-attendance' ? (!org ? <section className="empty-workspace"><h2>No church selected</h2><p>Check-in requires a linked church record.</p></section> : orgLoading ? <div className="loading">Loading church workspace…</div> : <SelfAttendance key={orgId} orgId={orgId} />) : personalNavigation.some((item) => item.id === page) && page !== 'community' ? (orgLoading ? <div className="loading">Loading church workspace…</div> : <MyChurch key={`${page}-${orgId}`} page={page} user={session.user} orgId={orgId} organization={org} organizations={organizations} owner={owner} assignments={assignments} canAdmin={orgAdmin} />) : !org ? <section className="empty-workspace"><span className="empty-icon"><Church size={27} /></span><h2>Let’s make room for community.</h2><p>{owner ? 'Review church applications, or create a church workspace directly.' : 'You don’t have a church assignment yet. If you registered a church, confirm your email and wait for platform owner approval.'}</p>{owner && <button className="button button-dark" onClick={() => navigate('applications')}>Review applications <ArrowRight size={17} /></button>}</section> : orgLoading ? <div className="loading">Loading church workspace…</div> : <>
          {page === 'dashboard' && <>
            <div className="welcome-banner"><div className="banner-copy"><span className="banner-tag"><Sparkles size={13} /> A SPACE TO BELONG</span><h2>Good things happen<br />when we <em>come together.</em></h2><p>Your people are at the heart of everything. Let’s keep them close.</p>{canViewMembers && <button onClick={() => navigate('members')}>Explore your directory <ArrowRight size={16} /></button>}</div><div className="banner-art"><div className="banner-circle circle-a" /><div className="banner-circle circle-b" /><div className="banner-church"><Church size={58} strokeWidth={1.1} /></div><span className="banner-sparkle">✳</span></div></div>
            {canViewMembers && <><div className="section-title"><div><span className="section-kicker">AT A GLANCE</span><h2>Your community overview</h2></div><span className="section-caption">Based on members you can access</span></div>
            <div className="stats-grid"><div className="stat-card"><div className="stat-top"><span className="stat-icon mint"><Users size={19} /></span><ArrowUpRight size={17} /></div><div className="stat-value">{members.length}</div><div className="stat-label">Members shown</div><p>People in your directory</p></div><div className="stat-card"><div className="stat-top"><span className="stat-icon peach"><Check size={19} /></span><ArrowUpRight size={17} /></div><div className="stat-value">{activeCount}</div><div className="stat-label">Active members</div><p>From the members shown</p></div><div className="stat-card"><div className="stat-top"><span className="stat-icon lilac"><Building2 size={19} /></span><ArrowDownRight size={17} /></div><div className="stat-value">{branches.length}</div><div className="stat-label">Branches visible</div><p>Across your access scope</p></div></div></>}
          </>}
          {pageAvailable && (page === 'dashboard' || page === 'members') && canViewMembers && <section className="directory">
            <div className="section-title directory-heading"><div><span className="section-kicker">PEOPLE & COMMUNITY</span><h2>{page === 'dashboard' ? 'Your church family' : 'Member directory'}</h2><p>Every name has a story. Keep yours connected.</p></div>{page === 'dashboard' && <button className="text-button" onClick={() => navigate('members')}>View all members <ArrowRight size={16} /></button>}</div>
            <div className="directory-card"><div className="directory-toolbar"><div><strong>Members shown</strong><span className="count-pill">{filtered.length}</span></div><label className="search"><Search size={17} /><span className="sr-only">Search members</span><input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search people..." /></label></div>
              {page === 'members' && <div className="member-tools"><label>Branch<select value={branchFilter} onChange={(e) => setBranchFilter(e.target.value)}><option value="all">All branches</option><option value="unassigned">No branch</option>{branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}</select></label><label>Status<select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}><option value="all">All statuses</option><option value="active">Active</option><option value="inactive">Inactive</option></select></label><button className="button button-outline" disabled={!filtered.length} onClick={() => downloadCsv('members.csv', memberCsv(filtered, branches))}>Export shown CSV</button>{canCreate && <button className="button button-outline" onClick={() => setModal('import')}>Import CSV</button>}</div>}
              <Notice>Directory loads at most 1,000 accessible members. Search, filters and export only cover the loaded records.</Notice>
              {filtered.length === 0 ? <div className="empty-members"><div className="empty-icon"><Users size={24} /></div><h3>{query || branchFilter !== 'all' || statusFilter !== 'all' ? 'No people found' : 'Your directory starts here'}</h3><p>{query || branchFilter !== 'all' || statusFilter !== 'all' ? 'Try another search or filter.' : 'Members you have permission to see will appear here.'}</p>{!query && branchFilter === 'all' && statusFilter === 'all' && canCreate && <button className="text-button" onClick={() => setModal('add')}>Add your first member <ArrowRight size={15} /></button>}</div> :
                <div className="table-scroll"><table><thead><tr><th>MEMBER</th><th>CONTACT</th><th>BRANCH</th><th>STATUS</th><th><span className="sr-only">Actions</span></th></tr></thead><tbody>{(page === 'dashboard' ? filtered.slice(0, 5) : filtered).map((member) => <tr key={member.id}><td><div className="member-name"><span className="member-avatar">{member.first_name[0]}{member.last_name[0]}</span><strong>{member.first_name} {member.last_name}</strong></div></td><td><span>{member.email || '—'}</span><small>{member.phone || ''}</small></td><td>{branches.find((branch) => branch.id === member.branch_id)?.name || '—'}</td><td><span className={`status ${member.status}`}><span />{member.status}</span></td><td><div className="row-actions">{can('update', member.branch_id) && <button disabled={Boolean(deletingId)} onClick={() => setModal(member)}>Edit</button>}{can('delete', member.branch_id) && <button disabled={Boolean(deletingId)} aria-busy={deletingId === member.id} onClick={() => deleteMember(member)}><ActionLabel busy={deletingId === member.id} pending="Removing…">Remove</ActionLabel></button>}</div></td></tr>)}</tbody></table></div>}
            </div>
          </section>}
          {pageAvailable && page === 'branches' && <BranchAdministration key={orgId} orgId={orgId} branches={branches} canAdmin={orgAdmin} onRefresh={refreshBranches} />}
          {pageAvailable && page === 'membership-requests' && <MembershipReviews key={orgId} orgId={orgId} branches={branches} />}
          {pageAvailable && page === 'visitors' && <Visitors key={orgId} orgId={orgId} branches={branches} owner={owner} assignments={assignments} Modal={Modal} Notice={Notice} />}
          {pageAvailable && page === 'attendance' && <AttendanceManagement key={orgId} orgId={orgId} branches={branches} owner={owner} assignments={assignments} />}
          {page !== 'dashboard' && page !== 'members' && page !== 'branches' && !(pageAvailable && ['membership-requests', 'visitors', 'attendance'].includes(page)) && <section className="empty-workspace"><span className="empty-icon"><Sparkles size={24} /></span><h2>{pageTitle}</h2><p>{pageAvailable ? 'This workspace area is not implemented yet. Its navigation is shown according to your permissions.' : 'Your current assignments do not grant access to this area.'}</p></section>}
        </>}
        <footer className="content-footer"><span>Made for the work that matters <span>✳</span></span><span>AFRICHURCH / YOUR COMMUNITY</span></footer>
      </main>
    </div>
    {modal === 'organization' && <Modal title="Create a church" description="Start a fresh workspace for your church community." onClose={() => setModal(null)} busy={busy}>{error && <Notice error>{error}</Notice>}<form onSubmit={createOrg} className="member-form"><label>Church name<input autoFocus maxLength={120} required value={newOrg} onChange={(e) => setNewOrg(e.target.value)} placeholder="e.g. Grace Community Church" /></label><div className="modal-actions"><button type="button" className="button button-outline" disabled={busy} onClick={() => setModal(null)}>Cancel</button><button className="button button-dark" disabled={busy} aria-busy={busy}><ActionLabel busy={busy} pending="Creating…">Create workspace</ActionLabel>{!busy && <ArrowRight size={16} />}</button></div></form></Modal>}
    {modal === 'import' && <MemberImport key={orgId} orgId={orgId} branches={branches} canCreate={(branchId) => can('create', branchId)} Modal={Modal} Notice={Notice} onClose={() => setModal(null)} onImported={async (count) => { setModal(null); setNotice(`${count} members imported.`); try { await refreshMembers() } catch (err) { setError(`Import completed, but the list could not be refreshed: ${err.message}`) } }} />}
    {modal && modal !== 'organization' && modal !== 'import' && <MemberForm member={modal === 'add' ? null : modal} branches={branches} canSaveBranch={(branchId) => can(modal === 'add' ? 'create' : 'update', branchId)} onSave={saveMember} onClose={() => setModal(null)} />}
  </div>
}

export default function App() {
  const [session, setSession] = useState(null)
  const [loading, setLoading] = useState(Boolean(supabase))
  const [error, setError] = useState('')
  useEffect(() => {
    if (!supabase) return
    let active = true
    supabase.auth.getSession().then(({ data, error: sessionError }) => {
      if (active) { if (sessionError) setError(sessionError.message); else setSession(data.session); setLoading(false) }
    })
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, nextSession) => { if (active) setSession(nextSession) })
    return () => { active = false; subscription.unsubscribe() }
  }, [])
  if (loading) return <div className="app-loading">Preparing your workspace…</div>
  if (error) return <div className="app-loading"><Notice error>{error} Please refresh and try again.</Notice></div>
  return session ? <Workspace key={session.user.id} session={session} /> : <PublicApp AuthScreen={(props) => <AuthScreen {...props} configured={Boolean(supabase)} />} />
}
