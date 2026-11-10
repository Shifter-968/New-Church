import Papa from 'papaparse'

export const columns = ['first_name', 'last_name', 'gender', 'email', 'phone', 'phone_2', 'date_of_birth', 'residence', 'baptized', 'marital_status', 'status']
export const maxImportRows = 1500
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const maritalStatuses = new Set(['SINGLE', 'COURTSHIP', 'ENGAGED', 'MARRIED', 'DIVORCED', 'WIDOWED'])
const ignoredColumns = new Set(['id', 'memberid', 'organizationid', 'orgid', 'branchid', 'branch', 'createdat', 'updatedat', 'userid'])
const aliases = new Map([
  ['firstname', 'first_name'], ['firstnames', 'first_name'], ['givenname', 'first_name'], ['forename', 'first_name'], ['fname', 'first_name'],
  ['lastname', 'last_name'], ['surname', 'last_name'], ['familyname', 'last_name'],
  ['sex', 'gender'],
  ['emailaddress', 'email'], ['mail', 'email'],
  ['telephone', 'phone'], ['phonenumber', 'phone'], ['mobile', 'phone'], ['primaryphone', 'phone'],
  ['phone2', 'phone_2'], ['secondphone', 'phone_2'], ['alternatephone', 'phone_2'], ['secondaryphone', 'phone_2'], ['mobile2', 'phone_2'],
  ['dob', 'date_of_birth'], ['dateofbirth', 'date_of_birth'], ['birthdate', 'date_of_birth'], ['birth', 'date_of_birth'],
  ['address', 'residence'], ['homeaddress', 'residence'], ['residentialaddress', 'residence'], ['residencearea', 'residence'], ['residentialarea', 'residence'], ['physicaladdress', 'residence'],
  ['baptised', 'baptized'], ['baptism', 'baptized'], ['baptismstatus', 'baptized'], ['isbaptized', 'baptized'], ['isbaptised', 'baptized'],
  ['maritalstatus', 'marital_status'], ['marriage', 'marital_status'],
])

function normalizeHeader(header) {
  const normalized = header.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]/g, '')
  if (ignoredColumns.has(normalized)) return null
  if (aliases.has(normalized)) return aliases.get(normalized)
  return columns.includes(header.trim().toLowerCase()) ? header.trim().toLowerCase() : undefined
}

function normalizeDate(value, row) {
  if (!value) throw new Error(`Row ${row}: date of birth is required.`)
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    if (validDate(value)) return value
    throw new Error(`Row ${row}: "${value}" is not a valid date of birth.`)
  }
  const parts = value.match(/^(\d{1,2})[/. -](\d{1,2})[/. -](\d{4})$/)
  if (parts) {
    const [, day, month, year] = parts
    const normalized = `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`
    if (validDate(normalized)) return normalized
  }
  if (/^\d{1,5}(\.0+)?$/.test(value)) {
    const serial = Number(value)
    if (serial >= 1 && serial <= 2958465) {
      const date = new Date(Date.UTC(1899, 11, 30) + Math.trunc(serial) * 86400000).toISOString().slice(0, 10)
      if (validDate(date)) return date
    }
  }
  throw new Error(`Row ${row}: date of birth "${value}" is invalid. Use YYYY-MM-DD or DD/MM/YYYY.`)
}

function normalizeBoolean(value, row) {
  if (!value) return false
  if (['yes', 'y', 'true', '1', 'baptized', 'baptised'].includes(value.toLowerCase())) return true
  if (['no', 'n', 'false', '0', 'not baptized', 'not baptised'].includes(value.toLowerCase())) return false
  throw new Error(`Row ${row}: baptized must be yes or no.`)
}

export function possibleDuplicateRows(people) {
  const seen = new Map()
  const duplicates = new Set()
  people.forEach((person, index) => {
    const first = person.first_name.trim().toLowerCase()
    const last = person.last_name.trim().toLowerCase()
    const email = (person.email || '').trim().toLowerCase()
    const phones = [person.phone, person.phone_2].map((phone) => (phone || '').replace(/[^0-9]/g, '')).filter(Boolean)
    const keys = new Set([`name:${first}\u0000${last}`, ...(email ? [`email:${email}`] : []), ...phones.map((phone) => `phone:${phone}`)])
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
  const rawHeaders = parsed.data[0].map((header) => header.trim())
  const mappedHeaders = rawHeaders.map(normalizeHeader)
  const unsupported = rawHeaders.filter((header, index) => mappedHeaders[index] === undefined)
  if (unsupported.length) throw new Error(`Unrecognized column${unsupported.length === 1 ? '' : 's'}: ${unsupported.join(', ')}. Rename them to the template field names or remove them.`)
  const headers = mappedHeaders.filter((header) => header !== null)
  if (new Set(headers).size !== headers.length) throw new Error('Two or more column headings map to the same field. Keep only one column for each field.')
  const invalidForKind = headers.filter((header) => !allowedColumns.includes(header))
  if (invalidForKind.length) throw new Error(`Unsupported ${kind === 'visitors' ? 'visitor' : 'member'} column${invalidForKind.length === 1 ? '' : 's'}: ${invalidForKind.join(', ')}.`)
  if (!headers.includes('first_name') || !headers.includes('last_name')) throw new Error('The first_name and last_name columns are required.')
  if (kind !== 'visitors') {
    const missing = ['gender', 'date_of_birth'].filter((header) => !headers.includes(header))
    if (missing.length) throw new Error(`Missing required column${missing.length === 1 ? '' : 's'}: ${missing.join(', ')}.`)
  }
  const records = parsed.data.slice(1)
  if (!records.length) throw new Error('Add at least one member below the header.')
  if (records.length > maxImportRows) throw new Error(`Import at most ${maxImportRows} records at a time.`)
  const seen = new Set()
  return records.map((values, index) => {
    const row = index + 2
    if (values.length !== rawHeaders.length) throw new Error(`Row ${row}: the number of fields does not match the header.`)
    const fields = Object.fromEntries(mappedHeaders.map((header, i) => [header, values[i].trim()]).filter(([header]) => header !== null))
    if (!fields.first_name || fields.first_name.length > 100 || !fields.last_name || fields.last_name.length > 100) throw new Error(`Row ${row}: first and last names are required and must be at most 100 characters.`)
    if (fields.email && (fields.email.length > 320 || !emailPattern.test(fields.email))) throw new Error(`Row ${row}: enter a valid email address.`)
    if ((fields.phone || '').length > 40 || (fields.phone_2 || '').length > 40) throw new Error(`Row ${row}: phone numbers cannot exceed 40 characters.`)
    if (fields.date_of_birth && !validDate(fields.date_of_birth) && kind === 'visitors') throw new Error(`Row ${row}: date of birth must be a valid YYYY-MM-DD date.`)
    const status = (fields.status || 'active').toLowerCase()
    if (!['active', 'inactive'].includes(status)) throw new Error(`Row ${row}: status must be active or inactive.`)
    const key = [fields.first_name.toLowerCase(), fields.last_name.toLowerCase(), (fields.email || '').toLowerCase(), fields.date_of_birth || '', fields.phone || '', fields.phone_2 || ''].join('\u0000')
    if (seen.has(key)) throw new Error(`Row ${row}: duplicate ${kind === 'visitors' ? 'visitor' : 'member'} details in this file.`)
    seen.add(key)
    const person = { first_name: fields.first_name, last_name: fields.last_name, email: fields.email || null, phone: fields.phone || null }
    if (kind === 'visitors') return person
    const genderValue = (fields.gender || '').trim().toUpperCase()
    const gender = ({ M: 'MALE', MAN: 'MALE', F: 'FEMALE', WOMAN: 'FEMALE', NONBINARY: 'OTHER', 'NON-BINARY': 'OTHER' })[genderValue] || genderValue
    if (!['MALE', 'FEMALE', 'OTHER'].includes(gender)) throw new Error(`Row ${row}: gender is required and must be Male, Female or Other.`)
    const date_of_birth = normalizeDate(fields.date_of_birth, row)
    if (date_of_birth >= new Date().toISOString().slice(0, 10)) throw new Error(`Row ${row}: date of birth must be before today.`)
    const marital_status = (fields.marital_status || 'SINGLE').trim().replace(/\s+/g, '_').toUpperCase()
    if (!maritalStatuses.has(marital_status)) throw new Error(`Row ${row}: marital status must be Single, Courtship, Engaged, Married, Divorced or Widowed.`)
    const baptized = normalizeBoolean(fields.baptized || '', row)
    if ((fields.residence || '').length > 255) throw new Error(`Row ${row}: residence cannot exceed 255 characters.`)
    return { ...person, gender, phone_2: fields.phone_2 || null, date_of_birth, residence: fields.residence || '', baptized, marital_status, status }
  })
}

export function memberCsv(members, branches, kind = 'members') {
  const branchNames = new Map(branches.map((branch) => [branch.id, branch.name]))
  const rows = members.map((member) => ({
    first_name: member.first_name, last_name: member.last_name, gender: member.gender || '', email: member.email || '',
    phone: member.phone || '', phone_2: member.phone_2 || '', date_of_birth: member.date_of_birth || '',
    residence: member.residence || '', baptized: member.baptized == null ? '' : member.baptized ? 'yes' : 'no',
    marital_status: member.marital_status || '', status: member.status,
    branch: branchNames.get(member.branch_id) || (member.branch_id ? 'Branch unavailable' : ''),
  }))
  const exportColumns = kind === 'visitors' ? ['first_name', 'last_name', 'email', 'phone'] : columns
  return '\uFEFF' + Papa.unparse({ fields: [...exportColumns, 'branch'], data: rows }, { escapeFormulae: /^[\t\r\n ]*[=+\-@]|^[\t\r\n]/ })
}

export function templateCsv(kind = 'members') {
  const memberColumns = columns.filter((column) => column !== 'email' && column !== 'status').map((column) => column === 'baptized' ? 'baptised' : column)
  return '\uFEFF' + Papa.unparse({ fields: kind === 'visitors' ? ['first_name', 'last_name', 'email', 'phone'] : memberColumns, data: [] })
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
