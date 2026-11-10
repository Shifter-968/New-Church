import React, { useRef, useState } from 'react'
import { supabase } from './supabase'
import ActionLabel from './ActionLabel'
import { parseMemberCsv, possibleDuplicateRows, templateCsv } from './memberCsv'
import { findVisitorDuplicates } from './visitorDuplicates'
import { findMemberImportDuplicates } from './memberDuplicates'

export function downloadCsv(name, text) {
  const url = URL.createObjectURL(new Blob([text], { type: 'text/csv;charset=utf-8' }))
  const link = document.createElement('a')
  link.href = url
  link.download = name
  link.click()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

export default function MemberImport({ orgId, branches, canCreate, onImported, onClose, Modal, Notice, kind = 'members' }) {
  const singular = kind === 'visitors' ? 'visitor' : 'member'
  const allowedBranches = branches.filter((branch) => canCreate(branch.id))
  const [branchId, setBranchId] = useState(allowedBranches.length === 1 ? allowedBranches[0].id : '')
  const [members, setMembers] = useState(null)
  const [fileName, setFileName] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [locked, setLocked] = useState(false)
  const fileVersion = useRef(0)

  async function chooseFile(event) {
    const version = ++fileVersion.current
    const file = event.target.files?.[0]
    setMembers(null); setFileName(''); setError('')
    if (!file) return
    try {
      if (file.size > 2 * 1024 * 1024) throw new Error('The CSV file must be 2 MB or smaller.')
      const rows = parseMemberCsv(await file.text(), kind)
      if (version === fileVersion.current) { setMembers(rows); setFileName(file.name) }
    } catch (err) {
      if (version === fileVersion.current) setError(err.message || 'Unable to read this CSV file.')
    }
  }

  async function submit(event) {
    event.preventDefault()
    if (busy || locked || !members || !allowedBranches.some((branch) => branch.id === branchId)) return
    setError(''); setBusy(true)
    let submitted = false
    try {
      const matches = kind === 'visitors'
        ? await findVisitorDuplicates(orgId, members)
        : await findMemberImportDuplicates(orgId, branchId, members)
      const rowsInFile = possibleDuplicateRows(members)
      if (matches.length || rowsInFile.length) {
        const rowsInDatabase = [...new Set(matches.map((item) => item.row_number + 1))]
        setError(`Possible duplicates found${rowsInDatabase.length ? ` in the directory for CSV record numbers ${rowsInDatabase.join(', ')}` : ''}${rowsInFile.length ? ` within the CSV at record numbers ${rowsInFile.join(', ')}` : ''}. Record numbers count the header as 1 and ignore blank records. Names, email or phone can match different people; review the directory, remove or correct affected records and reselect the file.`)
        return
      }
      if (!window.confirm(`Add ${members.length} new ${singular} records to this branch? Existing records will not be updated.`)) return
      setLocked(true); submitted = true
      const { error: importError } = await supabase.from(kind).insert(members.map((member) => ({ ...member, organization_id: orgId, branch_id: branchId })))
      if (importError) throw importError
      await onImported(members.length)
    } catch (err) {
      setError(submitted ? `Import could not be confirmed: ${err.message || 'connection error'}. Check the directory before trying again; the request may have completed.` : (err.message || 'Unable to check this import.'))
    } finally { setBusy(false) }
  }

  return <Modal title={`Import ${kind}`} description="Add new records from a CSV file to one branch." onClose={onClose} busy={busy}>
    {error && <Notice error>{error}</Notice>}
    <div className="notice">Possible duplicate names, emails or phone numbers in your visible directory or file must be reviewed before import. Matching cannot see branches outside your view permissions, prevent concurrent duplicates, or guarantee uniqueness. This adds records only; it does not update existing records.</div>
    <form className="member-form" onSubmit={submit}>
      <button type="button" className="text-button" onClick={() => downloadCsv(`${singular}-import-template.csv`, templateCsv(kind))}>Download CSV template</button>
      <label>Branch<select value={branchId} onChange={(event) => setBranchId(event.target.value)} required disabled={busy || locked}><option value="">Select a branch</option>{allowedBranches.map((branch) => <option value={branch.id} key={branch.id}>{branch.name}</option>)}</select></label>
      {allowedBranches.length === 0 && <Notice error>No branch is available with member creation permission.</Notice>}
      <label>CSV file <span className="optional">Up to 1,500 records, 2 MB</span><input type="file" accept=".csv,text/csv" onChange={chooseFile} disabled={busy || locked} required /></label>
      {members && <p>{fileName}: {members.length} valid {singular} {members.length === 1 ? 'row' : 'rows'} ready to add.</p>}
      {locked && !busy && <p>Close this window and check the directory before attempting another import.</p>}
      <div className="modal-actions"><button type="button" className="button button-outline" disabled={busy} onClick={onClose}>Close</button><button className="button button-dark" disabled={busy || locked || !members || !branchId} aria-busy={busy} aria-label={busy ? `Importing ${kind}` : `Import ${kind}`}><ActionLabel busy={busy} pending="Importing…">Import {kind}</ActionLabel></button></div>
    </form>
  </Modal>
}
