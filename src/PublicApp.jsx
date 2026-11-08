import React, { useEffect, useState } from 'react'
import { ArrowLeft, ArrowRight, Building2, CalendarDays, Check, Church, ClipboardList, HeartHandshake, LockKeyhole, Search, ShieldCheck, Sparkles, Users, X } from 'lucide-react'
import { getPublicBranches, searchChurches } from './publicData'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'
import './public.css'

function Logo({ navigate }) {
  return <button className="public-logo" onClick={() => navigate('/')} aria-label="AfriChurch home"><span><Church size={20} /></span><strong>afri<span>church</span><small>CHURCH MANAGEMENT</small></strong></button>
}

function PublicHeader({ navigate, onSearch }) {
  return <header className="public-header"><Logo navigate={navigate} /><nav aria-label="Public navigation"><a href="/#platform" onClick={(event) => { if (location.pathname !== '/') { event.preventDefault(); navigate('/'); setTimeout(() => document.getElementById('platform')?.scrollIntoView(), 0) } }}>The platform</a><a href="/#features" onClick={(event) => { if (location.pathname !== '/') { event.preventDefault(); navigate('/'); setTimeout(() => document.getElementById('features')?.scrollIntoView(), 0) } }}>Features</a><button onClick={onSearch}>Visit your church</button></nav><button className="public-header-button" onClick={() => navigate('/register')}>Register <ArrowRight size={15} /></button></header>
}

function useChurchSearch(query) {
  const [state, setState] = useState({ results: [], loading: false, error: '' })
  useEffect(() => {
    let active = true
    if (query.trim().length < 2) {
      setState({ results: [], loading: false, error: '' })
      return () => { active = false }
    }
    setState({ results: [], loading: true, error: '' })
    const timer = setTimeout(() => {
      searchChurches(query).then((results) => {
        if (active) setState({ results, loading: false, error: '' })
      }).catch((error) => {
        if (active) setState({ results: [], loading: false, error: error.message })
      })
    }, 350)
    return () => { active = false; clearTimeout(timer) }
  }, [query])
  return state
}

function SearchResults({ query, state, onSelect }) {
  return <div className="public-search-status" aria-live="polite">
    {query.trim().length < 2 ? 'Enter at least 2 characters to search.' : state.loading ? 'Searching churches…' : state.error || (state.results.length === 0 ? 'No churches matched that name.' : `${state.results.length} churches found.`)}
    {state.results.map((church) => <button className="church-result" type="button" key={church.id} onClick={() => onSelect(church)}><span className="public-icon"><Church size={18} /></span><strong>{church.name}</strong><ArrowRight size={16} /></button>)}
  </div>
}

function ChurchSearch({ onClose, navigate }) {
  const [query, setQuery] = useState('')
  const search = useChurchSearch(query)
  useEffect(() => {
    function onKey(event) { if (event.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])
  return <div className="public-overlay" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose() }}><section className="public-dialog" role="dialog" aria-modal="true" aria-labelledby="church-search-title">
    <div className="public-dialog-heading"><span className="public-icon"><Church size={22} /></span><button className="public-close" onClick={onClose} aria-label="Close church search"><X size={20} /></button></div>
    <span className="public-kicker">FIND YOUR COMMUNITY</span><h2 id="church-search-title">Visit your church.</h2><p>Start typing your church’s name to find your community and sign in to your church workspace.</p>
    <label className="public-search"><Search size={19} /><span className="sr-only">Search for your church</span><input autoFocus value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search for your church..." /></label>
    <SearchResults query={query} state={search} onSelect={(church) => navigate(`/login?organization_id=${encodeURIComponent(church.id)}&church_name=${encodeURIComponent(church.name)}`)} />
  </section></div>
}

const features = [
  { icon: Users, name: 'People & community', text: 'Keep members and visitors connected with a home for every story.' },
  { icon: Building2, name: 'Churches & branches', text: 'Bring your church, branches and teams together in one place.' },
  { icon: CalendarDays, name: 'Events & attendance', text: 'Make space for meaningful gatherings and keep track of participation.' },
  { icon: HeartHandshake, name: 'Ministries & teams', text: 'Help the people who serve your community stay connected.' },
  { icon: ClipboardList, name: 'Reports & insights', text: 'See the bigger picture and make informed decisions for your church.' },
  { icon: ShieldCheck, name: 'Roles & permissions', text: 'Give each person access appropriate to their role and scope.' },
]

function Landing({ navigate, onSearch }) {
  return <>
    <section className="public-hero" id="platform"><div className="public-hero-copy"><span className="public-kicker"><span className="public-dot" /> MADE FOR YOUR CHURCH COMMUNITY</span><h1>A little more<br /><em>connected.</em><br />A lot more church.</h1><p>One thoughtful place for your church, your people, and all the meaningful work you do together.</p><div className="public-actions"><button className="public-primary" onClick={() => navigate('/register')}>Register <ArrowRight size={17} /></button><button className="public-secondary" onClick={onSearch}><Search size={16} /> Visit your church</button></div><div className="public-hero-note"><span className="tiny-people"><i>♥</i><i>✳</i><i>✦</i></span><span>Made for people.<br /><strong>Built for belonging.</strong></span></div></div>
      <div className="public-hero-visual"><div className="hero-visual-inner"><div className="hero-orbit orbit-1" /><div className="hero-orbit orbit-2" /><div className="hero-church"><Church size={77} strokeWidth={1} /></div><div className="floating-card float-one"><span className="public-icon"><Users size={20} /></span><span><strong>Your people</strong><small>At the heart of it all</small></span></div><div className="floating-card float-two"><span className="public-icon gold-icon"><HeartHandshake size={20} /></span><span><strong>Better together</strong><small>Connected in community</small></span></div><span className="public-sparkle">✳</span></div><div className="visual-caption">A HOME FOR EVERY COMMUNITY <span>✦</span></div></div>
    </section>
    <section className="public-intro" id="features"><div><span className="public-kicker"><span className="public-dot" /> A MORE CONNECTED CHURCH</span><h2>More room for what <em>matters.</em></h2></div><p>From the first hello to the everyday details, bring your church community closer together.</p></section>
    <section className="feature-grid" aria-label="Platform features">{features.map(({ icon: Icon, name, text }, index) => <article className="feature-card" key={name}><span className={`public-icon ${index % 2 ? 'gold-icon' : ''}`}><Icon size={20} /></span><h3>{name}</h3><p>{text}</p></article>)}</section>
    <section className="public-bottom-cta"><div><span className="public-kicker">LET’S GROW TOGETHER</span><h2>Every community has a story.<br /><em>Let’s make room for yours.</em></h2></div><button className="public-primary" onClick={() => navigate('/register')}>Register with AfriChurch <ArrowRight size={16} /></button></section>
    <footer className="public-footer"><Logo navigate={navigate} /><span>Made for the work that matters.</span><button onClick={() => navigate('/login')}>Platform administrator or support? Sign in <ArrowRight size={14} /></button></footer>
  </>
}

const initialForm = { organization_name: '', account_role: '', address: '', city: '', country: '', person_type: 'MEMBER', national_id: '', first_name: '', last_name: '', email: '', phone: '', contact_number_2: '', birth_date: '', gender: '', residence: '', marital_status: 'SINGLE', baptized: false, password: '', confirm_password: '', purchase_authorized: false }

function Register({ navigate }) {
  const [type, setType] = useState(null)
  const [form, setForm] = useState(initialForm)
  const [churchQuery, setChurchQuery] = useState('')
  const [previewDetails, setPreviewDetails] = useState(false)
  const [registrationError, setRegistrationError] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [submitted, setSubmitted] = useState(false)
  const [church, setChurch] = useState(null)
  const [branchId, setBranchId] = useState('')
  const [branchState, setBranchState] = useState({ results: [], loading: false, error: '' })
  const search = useChurchSearch(churchQuery)
  useEffect(() => {
    let active = true
    setBranchId('')
    if (!church) { setBranchState({ results: [], loading: false, error: '' }); return () => { active = false } }
    setBranchState({ results: [], loading: true, error: '' })
    getPublicBranches(church.id).then((results) => {
      if (active) {
        setBranchState({ results, loading: false, error: '' })
        if (results.length === 1) setBranchId(results[0].id)
      }
    }).catch((error) => { if (active) setBranchState({ results: [], loading: false, error: error.message }) })
    return () => { active = false }
  }, [church])
  const update = (key) => (event) => setForm((current) => ({ ...current, [key]: event.target.type === 'checkbox' ? event.target.checked : event.target.value }))
  const changeType = () => { setType(null); setPreviewDetails(false); setChurch(null); setChurchQuery('') }
  const yesterday = new Date(Date.now() - 86400000).toISOString().slice(0, 10)
  async function submitOrganization(event) {
    event.preventDefault()
    setRegistrationError('')
    if (!supabase) { setRegistrationError('Supabase is not configured.'); return }
    if (!form.purchase_authorized) { setRegistrationError('Please confirm that you are authorized to manage this church account.'); return }
    if (form.password !== form.confirm_password) { setRegistrationError('Passwords do not match.'); return }
    setSubmitting(true)
    try {
      const readiness = await supabase.rpc('organization_registration_ready')
      if (readiness.error || !readiness.data) {
        setRegistrationError('Church registration is not ready. An administrator must apply the organisation applications database migration before registration.')
        return
      }
      const application = {
        organization_name: form.organization_name.trim(), account_role: form.account_role,
        address: form.address.trim(), city: form.city.trim(), country: form.country.trim(),
        first_name: form.first_name.trim(), last_name: form.last_name.trim(),
        phone: form.phone.trim(), birth_date: form.birth_date, gender: form.gender || null,
        purchase_authorized: form.purchase_authorized,
      }
      const { data, error } = await supabase.auth.signUp({
        email: form.email.trim(), password: form.password,
        options: { data: { full_name: `${application.first_name} ${application.last_name}`, organization_application: application }, emailRedirectTo: `${window.location.origin}/login` },
      })
      if (error) setRegistrationError(error.message)
      else if (!data.user || (Array.isArray(data.user.identities) && data.user.identities.length === 0)) setRegistrationError('Unable to create an account with those details. If you already have an account, sign in instead.')
      else setSubmitted(true)
    } catch (error) {
      setRegistrationError(error.message || 'Unable to submit your application. Please try again.')
    } finally {
      setSubmitting(false)
    }
  }
  if (submitted) return <main className="registration-page registration-narrow"><section className="registration-card"><span className="public-icon"><Check size={22} /></span><div className="registration-heading"><h1>Application <em>received.</em></h1><p>Confirm your email if requested, then sign in. A platform owner must review your application before your church workspace is available.</p></div><button className="public-primary" onClick={() => navigate('/login')}>Go to sign in <ArrowRight size={16} /></button></section></main>
  if (!type) return <main className="registration-page"><button className="back-link" onClick={() => navigate('/')}><ArrowLeft size={16} /> Back to home</button><div className="registration-heading centered"><span className="public-kicker"><span className="public-dot" /> GET STARTED</span><h1>There’s a place for <em>you.</em></h1><p>Let’s find the right way to bring you into the community.</p></div><div className="gateway-grid">
    <button className="gateway-card" onClick={() => setType('organization')}><span className="gateway-top"><span className="public-icon"><Building2 size={23} /></span><span>01 / ORGANISATION</span></span><h2>Church or organisation</h2><p>Create a church workspace, choose a plan, and manage your people, branches and ministries.</p><span className="gateway-action">Register your church <ArrowRight size={16} /></span></button>
    <button className="gateway-card" onClick={() => setType('individual')}><span className="gateway-top"><span className="public-icon gold-icon"><Users size={23} /></span><span>02 / INDIVIDUAL</span></span><h2>Member or visitor</h2><p>Join your church as a member or visitor using your personal details. No church plan required.</p><span className="gateway-action">Register as an individual <ArrowRight size={16} /></span></button>
  </div><p className="registration-footnote">Already have an account? <button onClick={() => navigate('/login')}>Sign in <ArrowRight size={14} /></button></p></main>

  if (type === 'individual' && !previewDetails) return <main className="registration-page registration-narrow"><button className="back-link" onClick={changeType}><ArrowLeft size={16} /> Change registration type</button><div className="registration-heading"><span className="public-kicker"><span className="public-dot" /> INDIVIDUAL REGISTRATION</span><h1>Find your <em>church.</em></h1><p>Choose the church where your member or visitor record is registered.</p></div><section className="registration-card"><h2>Choose your church</h2><p>Search by your church’s name to get started.</p><label className="field-label">Search for your church <span>*</span><div className="field-search"><Search size={17} /><input value={churchQuery} onChange={(event) => { setChurchQuery(event.target.value); setChurch(null) }} placeholder="e.g. Grace Community Church" /></div></label>{!church && <SearchResults query={churchQuery} state={search} onSelect={(selected) => { setChurch(selected); setChurchQuery(selected.name) }} />}{church && <div className="selected-church"><strong>{church.name}</strong><button type="button" onClick={() => setChurch(null)}>Change church</button></div>}{church && branchState.loading && <div className="offline-message">Loading branches…</div>}{church && branchState.error && <div className="notice notice-error" role="alert">{branchState.error}</div>}{church && !branchState.loading && !branchState.error && branchState.results.length > 0 && <label className="field-label">Branch <span>*</span><select value={branchId} onChange={(event) => setBranchId(event.target.value)}><option value="">Select your branch</option>{branchState.results.map((branch) => <option value={branch.id} key={branch.id}>{branch.name}</option>)}</select></label>}<button className="public-primary full-width church-continue" type="button" disabled={!church || branchState.loading || Boolean(branchState.error) || (branchState.results.length > 0 && !branchId)} onClick={() => setPreviewDetails(true)}>Continue to personal details <ArrowRight size={16} /></button><button className="preview-link" onClick={() => setPreviewDetails(true)}>Preview the personal details form <ArrowRight size={14} /></button></section></main>

  const org = type === 'organization'
  return <main className="registration-page registration-wide"><button className="back-link" onClick={changeType}><ArrowLeft size={16} /> Change registration type</button><div className="registration-heading"><span className="public-kicker"><span className="public-dot" /> {org ? 'CHURCH ACCOUNT SETUP' : 'INDIVIDUAL ACCOUNT SETUP'}</span><h1>{org ? <>A home for your <em>church.</em></> : <>Let’s get to know <em>you.</em></>}</h1><p>{org ? 'Create a workspace for your church and the people who make it special.' : 'Create your personal member or visitor profile.'}</p></div>
    <div className="registration-layout"><form id="registration-form" className="registration-card registration-form" onSubmit={org ? submitOrganization : (event) => event.preventDefault()}><div className="form-section-heading"><div><span className="section-kicker">THE DETAILS</span><h2>{org ? 'Your church and account' : 'Your personal details'}</h2></div><span className="public-icon"><Sparkles size={19} /></span></div>
      {registrationError && <div className="notice notice-error" role="alert">{registrationError}</div>}
      {!org && <div className="offline-message">{church ? `Selected church: ${church.name}${branchId ? ` · ${branchState.results.find((branch) => branch.id === branchId)?.name || ''}` : ''}. ` : 'Preview only: choose a church and branch before registration. '}Registration is not connected and nothing entered here is saved.</div>}
      {org && <><div className="fields-grid"><label className="field-label wide">Church or organisation name <span>*</span><input value={form.organization_name} onChange={update('organization_name')} placeholder="Grace Community Church" required /></label><label className="field-label wide">Your responsibility <span>*</span><select value={form.account_role} onChange={update('account_role')} required><option value="">Choose your responsibility</option><option value="FOUNDING_PASTOR">Founding pastor</option><option value="CHURCH_ADMIN">Authorized church administrator</option></select></label><label className="field-label wide">Church address <span>*</span><input value={form.address} onChange={update('address')} placeholder="Street address" required /></label><label className="field-label">City <span>*</span><input value={form.city} onChange={update('city')} required /></label><label className="field-label">Country <span>*</span><input value={form.country} onChange={update('country')} required /></label></div><div className="plan-placeholder"><div><strong>Plans and billing</strong><p>Not connected yet. Applications can be reviewed without payment during this initial testing phase.</p></div></div></>}
      {!org && <div className="fields-grid"><label className="field-label wide">I am registering as <span>*</span><select value={form.person_type} onChange={update('person_type')}><option value="MEMBER">Member</option><option value="VISITOR">Visitor</option></select></label>{form.person_type === 'MEMBER' && <><div className="field-hint wide">Members must already be registered by their church administrator. Your name and email, either phone number or national ID will be checked against the church register. Otherwise, register as a visitor.</div><label className="field-label wide">National ID number <small>Optional, helps verification</small><input value={form.national_id} onChange={update('national_id')} /></label></>}</div>}
      <div className="form-divider"><span>YOUR DETAILS</span></div><div className="google-placeholder"><button type="button" disabled>Continue with Google</button><small>Google sign-in will be connected later. Or use email and password below.</small></div>
      <div className="fields-grid"><label className="field-label">First name <span>*</span><input value={form.first_name} onChange={update('first_name')} autoComplete="given-name" required /></label><label className="field-label">Last name <span>*</span><input value={form.last_name} onChange={update('last_name')} autoComplete="family-name" required /></label><label className="field-label wide">Email address <span>*</span><input type="email" value={form.email} onChange={update('email')} autoComplete="email" required /></label><label className="field-label">Phone number <span>*</span><input type="tel" value={form.phone} onChange={update('phone')} autoComplete="tel" required /></label>{!org && <label className="field-label">Second phone number <small>Optional</small><input type="tel" value={form.contact_number_2} onChange={update('contact_number_2')} /></label>}<label className="field-label">Date of birth <span>*</span><input type="date" max={yesterday} value={form.birth_date} onChange={update('birth_date')} required /></label><label className="field-label">Gender <small>Optional</small><select value={form.gender} onChange={update('gender')}><option value="">Select gender</option><option value="MALE">Male</option><option value="FEMALE">Female</option><option value="OTHER">Other</option></select></label>{!org && <><label className="field-label wide">Residence <small>Optional</small><input value={form.residence} onChange={update('residence')} placeholder="Home address or area" /></label><label className="field-label">Marital status<select value={form.marital_status} onChange={update('marital_status')}><option value="SINGLE">Single</option><option value="MARRIED">Married</option><option value="ENGAGED">Engaged</option><option value="DIVORCED">Divorced</option><option value="UNOFFICIAL_RELATIONSHIP">Unofficial relationship</option></select></label><label className="check-label"><input type="checkbox" checked={form.baptized} onChange={update('baptized')} /> Baptized</label></>}<label className="field-label">Password <span>*</span><input type="password" value={form.password} onChange={update('password')} autoComplete="new-password" required /></label><label className="field-label">Confirm password <span>*</span><input type="password" value={form.confirm_password} onChange={update('confirm_password')} autoComplete="new-password" required /></label></div>
    </form><aside className="registration-summary"><span className="summary-icon"><Church size={24} /></span><span className="public-kicker">YOUR NEXT CHAPTER</span><h2>{org ? <>A stronger church <em>starts here.</em></> : <>It’s good to <em>belong.</em></>}</h2><p>{org ? 'Everything your church needs, in a space made for people.' : 'Your church community, a little closer to home.'}</p><div className="summary-line" /><ul><li><Check size={16} /> {org ? 'Submit a church application' : 'Connect with your church'}</li><li><Check size={16} /> {org ? 'Confirm your email address' : 'Join as a member or visitor'}</li><li><Check size={16} /> {org ? 'Activate after platform owner approval' : 'No church plan required'}</li></ul>{org && <label className="summary-check"><input type="checkbox" checked={form.purchase_authorized} onChange={update('purchase_authorized')} /> I confirm that I am authorized to manage this church account.</label>}<div className="summary-note"><LockKeyhole size={16} /> {org ? 'No payment is collected yet. The platform owner reviews each application.' : 'Individual registration is not connected yet. This form is a preview and does not create an account.'}</div><button className="public-primary full-width" type="submit" form="registration-form" disabled={!org || submitting} aria-busy={submitting}><ActionLabel busy={submitting} pending="Submitting…">{org ? 'Submit application' : 'Create account'}</ActionLabel>{!submitting && <ArrowRight size={16} />}</button></aside></div>
  </main>
}

export default function PublicApp({ AuthScreen }) {
  const [path, setPath] = useState(window.location.pathname)
  const [showSearch, setShowSearch] = useState(false)
  useEffect(() => {
    const onPopState = () => setPath(window.location.pathname)
    window.addEventListener('popstate', onPopState)
    return () => window.removeEventListener('popstate', onPopState)
  }, [])
  function navigate(next) {
    window.history.pushState(null, '', next)
    setPath(window.location.pathname)
    setShowSearch(false)
    window.scrollTo(0, 0)
  }
  if (path === '/login') return <AuthScreen churchName={new URLSearchParams(window.location.search).get('church_name')} onHome={() => navigate('/')} onRegister={() => navigate('/register')} />
  return <div className="public-app"><PublicHeader navigate={navigate} onSearch={() => setShowSearch(true)} />{path === '/register' ? <Register navigate={navigate} /> : <Landing navigate={navigate} onSearch={() => setShowSearch(true)} />}{showSearch && <ChurchSearch navigate={navigate} onClose={() => setShowSearch(false)} />}</div>
}
