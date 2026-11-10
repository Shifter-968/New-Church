import React, { useCallback, useEffect, useState } from 'react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'
import ConnectAnnouncements from './ConnectAnnouncements'
import './connect.css'

export default function ConnectConversation({ group, userId, support, onChanged, onClose }) {
  const [members, setMembers] = useState([])
  const [messages, setMessages] = useState([])
  const [email, setEmail] = useState('')
  const [draft, setDraft] = useState('')
  const [editing, setEditing] = useState(null)
  const [loading, setLoading] = useState(true)
  const [loadFailed, setLoadFailed] = useState(false)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [refresh, setRefresh] = useState(0)
  const isMember = Boolean(group.my_role)
  const creator = group.my_role === 'CREATOR'
  const canManage = creator || support

  const load = useCallback(async () => {
    const [membership, conversation] = await Promise.all([
      supabase.rpc('list_connect_members', { target_id: group.id }),
      isMember && group.status === 'ACTIVE'
        ? supabase.rpc('list_connect_messages', { target_id: group.id })
        : Promise.resolve({ data: [], error: null }),
    ])
    if (membership.error) throw new Error(membership.error.message)
    if (conversation.error) throw new Error(conversation.error.message)
    return { members: membership.data, messages: conversation.data }
  }, [group.id, group.status, isMember])

  useEffect(() => {
    let active = true
    setLoading(true); setLoadFailed(false); setError('')
    load().then((data) => { if (active) { setMembers(data.members); setMessages(data.messages) } })
      .catch((err) => { if (active) { setLoadFailed(true); setError(`Unable to load Connect: ${err.message}`) } })
      .finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [load, refresh])

  async function perform(action, request, success, updateGroup = false) {
    setError(''); setNotice(''); setBusy(action)
    try {
      const { error: requestError } = await request()
      if (requestError) throw requestError
      setNotice(success); setRefresh((value) => value + 1)
      if (updateGroup) onChanged()
      return true
    } catch (requestError) { setError(requestError.message || 'The operation failed. Please try again.'); return false }
    finally { setBusy('') }
  }
  async function add(event) {
    event.preventDefault()
    if (await perform('add', () => supabase.rpc('add_connect_member', { target_id: group.id, account_email: email.trim() }), 'Member added.', true)) setEmail('')
  }
  async function changeMember(member, role, status) {
    const removal = status !== 'ACTIVE'
    if (removal && !window.confirm(`${status === 'BANNED' ? 'Ban' : 'Remove'} this member from the Connect?`)) return
    await perform(member.user_id, () => supabase.rpc('manage_connect_member', {
      target_id: group.id, target_user: member.user_id, new_role: role, new_status: status,
    }), 'Membership updated.', true)
  }
  async function send(event) {
    event.preventDefault()
    if (!draft.trim()) { setError('Enter a message.'); return }
    const request = editing
      ? () => supabase.rpc('edit_connect_message', { target_id: group.id, message_id: editing, message_text: draft })
      : () => supabase.rpc('send_connect_message', { target_id: group.id, message_text: draft })
    if (await perform('send', request, editing ? 'Message updated.' : 'Message sent.')) { setDraft(''); setEditing(null) }
  }
  async function removeMessage(item) {
    if (!window.confirm('Delete this message for everyone in the Connect?')) return
    const deleted = await perform(item.id, () => supabase.rpc('delete_connect_message', { target_id: group.id, message_id: item.id }), 'Message deleted for everyone.')
    if (deleted && editing === item.id) { setEditing(null); setDraft('') }
  }

  return <section className="directory-card my-card connect-detail">
    <div className="connect-detail-heading"><div><h2>{group.name}</h2><p>Connect members and conversation</p></div><div className="my-item-actions"><button className="button button-outline" disabled={Boolean(busy)} onClick={() => setRefresh((value) => value + 1)}>Refresh</button><button className="button button-outline" disabled={Boolean(busy)} onClick={onClose}>Close</button></div></div>
    {error && <div className="notice notice-error" role="alert">{error}</div>}{notice && <div className="notice" role="status">{notice}</div>}
    <ConnectAnnouncements group={group} />
    {loading ? <p>Loading Connect…</p> : loadFailed ? null : <div className="connect-columns">
      <section><h3>Members</h3><p className="connect-hint">Only the creator can promote or demote group admins. Church administrators can help manage membership.</p>
        <div className="my-list">{members.map((member) => <article className="my-list-item" key={member.user_id}><div><h3>{member.display_name}</h3>{member.email && <small>{member.email}</small>}<small>{member.role.toLowerCase()} · {member.status.toLowerCase()}</small></div>
          {canManage && member.role !== 'CREATOR' && <div className="connect-member-actions">
            {creator && member.status === 'ACTIVE' && <button className="text-button" disabled={Boolean(busy)} onClick={() => changeMember(member, member.role === 'ADMIN' ? 'MEMBER' : 'ADMIN', 'ACTIVE')}>{member.role === 'ADMIN' ? 'Remove admin' : 'Make admin'}</button>}
            {member.status === 'ACTIVE' ? <><button className="text-button" disabled={Boolean(busy)} onClick={() => changeMember(member, member.role, 'INACTIVE')}><ActionLabel busy={busy === member.user_id} pending="Updating…">Remove</ActionLabel></button><button className="text-button" disabled={Boolean(busy)} onClick={() => changeMember(member, member.role, 'BANNED')}>Ban</button></> : <button className="text-button" disabled={Boolean(busy)} onClick={() => changeMember(member, 'MEMBER', 'ACTIVE')}><ActionLabel busy={busy === member.user_id} pending="Updating…">Restore</ActionLabel></button>}
          </div>}
        </article>)}</div>
        {canManage && group.status === 'ACTIVE' && <form className="my-form" onSubmit={add}><label>Add member by email<input type="email" required value={email} onChange={(event) => setEmail(event.target.value)} placeholder="person@example.com" /></label><small>They must have a confirmed account and an eligible church assignment.</small><button className="button button-dark" disabled={Boolean(busy)} aria-busy={busy === 'add'}><ActionLabel busy={busy === 'add'} pending="Adding…">Add member</ActionLabel></button></form>}
      </section>
      <section><h3>Messages</h3>{!isMember ? <p className="connect-hint">Support can manage membership without joining. Only active group members can read or send messages.</p> : group.status !== 'ACTIVE' ? <p className="connect-hint">This Connect is not active; its conversation is unavailable.</p> : <>
        <p className="connect-hint">Latest 100 messages. Use Refresh to check for new messages. Deleting a message removes its content for everyone.</p>
        <div className="connect-messages">{messages.length === 0 ? <p>No messages yet.</p> : messages.map((item) => <article className={`connect-message ${item.sender_id === userId ? 'connect-message-own' : ''}`} key={item.id}><strong>{item.sender_id === userId ? 'You' : item.sender_name}</strong><p>{item.deleted_at ? <em>Message deleted</em> : item.content}</p><small>{new Date(item.created_at).toLocaleString()}{item.edited_at && !item.deleted_at ? ' · edited' : ''}</small>{!item.deleted_at && <div className="my-item-actions">{item.sender_id === userId && <button className="text-button" disabled={Boolean(busy)} onClick={() => { setEditing(item.id); setDraft(item.content) }}>Edit</button>}{(item.sender_id === userId || ['CREATOR', 'ADMIN'].includes(group.my_role)) && <button className="text-button" disabled={Boolean(busy)} onClick={() => removeMessage(item)}><ActionLabel busy={busy === item.id} pending="Deleting…">Delete for everyone</ActionLabel></button>}</div>}</article>)}</div>
        <form className="my-form" onSubmit={send}><label>{editing ? 'Edit message' : 'Your message'}<textarea value={draft} onChange={(event) => setDraft(event.target.value)} required maxLength={10000} /></label><div className="my-item-actions"><button className="button button-dark" disabled={Boolean(busy)} aria-busy={busy === 'send'}><ActionLabel busy={busy === 'send'} pending={editing ? 'Saving…' : 'Sending…'}>{editing ? 'Save message' : 'Send message'}</ActionLabel></button>{editing && <button type="button" className="button button-outline" disabled={Boolean(busy)} onClick={() => { setEditing(null); setDraft('') }}>Cancel edit</button>}</div></form>
      </>}</section>
    </div>}
  </section>
}
