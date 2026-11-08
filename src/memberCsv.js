import Papa from 'papaparse'

export const columns = ['first_name', 'last_name', 'email', 'phone', 'phone_2', 'date_of_birth', 'status']
export const maxImportRows = 500
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

export function possibleDuplicateRows(people) {
  const seen = new Map()
  const duplicates = new Set()
  people.forEach((person, index) => {
    const first = person.first_name.trim().toLowerCase()
    const last = person.last_name.trim().toLowerCase()
    const email = (person.email || '').trim().toLowerCase()
    const phone = (person.phone || '').replace(/[^0-9]/g, '')
    const keys = [`name:${first}\u0000${last}`, ...(email ? [`email:${email}`] : []), ...(phone ? [`phone:${phone}`] : [])]
    for (const key of keys) {
      if (seen.has(key)) { duplicates.add(seen.get(key)); duplicates.add(index + 2) }
      else seen.set(key, index + 2)
    }
  })
  return [...duplicates].sort((a, b) => a - b)
}

function validDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false
  const date = new Date(`${value}T00:00:00Z`)
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value
}

export function parseMemberCsv(text, kind = 'members') {
  const allowedColumns = kind === 'visitors' ? ['first_name', 'last_name', 'email', 'phone'] : columns
  const parsed = Papa.parse(text.replace(/^\uFEFF/, ''), { skipEmptyLines: 'greedy' })
  if (parsed.errors.length) throw new Error(`CSV error: ${parsed.errors[0].message}`)
  if (!parsed.data.length) throw new Error('The CSV file is empty.')
  const headers = parsed.data[0].map((header) => header.trim().toLowerCase())
  if (new Set(headers).size !== headers.length) throw new Error('Column names must be unique.')
  const unsupported = headers.filter((header) => !allowedColumns.includes(header))
  if (unsupported.length) throw new Error(`Unsupported columns: ${unsupported.join(', ')}. Use the template.`)
  if (!headers.includes('first_name') || !headers.includes('last_name')) throw new Error('The first_name and last_name columns are required.')
  const records = parsed.data.slice(1)
  if (!records.length) throw new Error('Add at least one member below the header.')
  if (records.length > maxImportRows) throw new Error(`Import at most ${maxImportRows} members at a time.`)
  const seen = new Set()
  return records.map((values, index) => {
    const row = index + 2
    if (values.length !== headers.length) throw new Error(`Row ${row}: the number of fields does not match the header.`)
    const fields = Object.fromEntries(headers.map((header, i) => [header, values[i].trim()]))
    if (!fields.first_name || fields.first_name.length > 100 || !fields.last_name || fields.last_name.length > 100) throw new Error(`Row ${row}: first and last names are required and must be at most 100 characters.`)
    if (fields.email && (fields.email.length > 320 || !emailPattern.test(fields.email))) throw new Error(`Row ${row}: enter a valid email address.`)
    if ((fields.phone || '').length > 40 || (fields.phone_2 || '').length > 40) throw new Error(`Row ${row}: phone numbers cannot exceed 40 characters.`)
    if (fields.date_of_birth && !validDate(fields.date_of_birth)) throw new Error(`Row ${row}: date of birth must be a valid YYYY-MM-DD date.`)
    const status = (fields.status || 'active').toLowerCase()
    if (!['active', 'inactive'].includes(status)) throw new Error(`Row ${row}: status must be active or inactive.`)
    const key = [fields.first_name.toLowerCase(), fields.last_name.toLowerCase(), (fields.email || '').toLowerCase(), fields.date_of_birth || '', fields.phone || '', fields.phone_2 || ''].join('\u0000')
    if (seen.has(key)) throw new Error(`Row ${row}: duplicate ${kind === 'visitors' ? 'visitor' : 'member'} details in this file.`)
    seen.add(key)
    const person = { first_name: fields.first_name, last_name: fields.last_name, email: fields.email || null, phone: fields.phone || null }
    return kind === 'visitors' ? person : { ...person, phone_2: fields.phone_2 || null, date_of_birth: fields.date_of_birth || null, status }
  })
}

export function memberCsv(members, branches, kind = 'members') {
  const branchNames = new Map(branches.map((branch) => [branch.id, branch.name]))
  const rows = members.map((member) => ({
    first_name: member.first_name, last_name: member.last_name, email: member.email || '',
    phone: member.phone || '', phone_2: member.phone_2 || '', date_of_birth: member.date_of_birth || '',
    status: member.status, branch: branchNames.get(member.branch_id) || (member.branch_id ? 'Branch unavailable' : ''),
  }))
  const exportColumns = kind === 'visitors' ? ['first_name', 'last_name', 'email', 'phone'] : columns
  return '\uFEFF' + Papa.unparse({ fields: [...exportColumns, 'branch'], data: rows }, { escapeFormulae: /^[\t\r\n ]*[=+\-@]|^[\t\r\n]/ })
}

export function templateCsv(kind = 'members') {
  return '\uFEFF' + Papa.unparse({ fields: kind === 'visitors' ? ['first_name', 'last_name', 'email', 'phone'] : columns, data: [] })
}

export function filterMembers(members, query, branch, status) {
  const needle = query.trim().toLowerCase()
  return members.filter((member) => {
    const matchesText = [member.first_name, member.last_name, `${member.first_name} ${member.last_name}`, member.email, member.phone, member.phone_2]
      .some((value) => value?.toLowerCase().includes(needle))
    return matchesText && (branch === 'all' || (branch === 'unassigned' ? !member.branch_id : member.branch_id === branch))
      && (status === 'all' || member.status === status)
  })
}
