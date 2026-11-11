import Papa from 'papaparse'

export const childColumns = ['first_name', 'last_name', 'date_of_birth', 'parent_contact', 'residence']
export const maxChildImportRows = 1500

const ignoredColumns = new Set(['id', 'childid', 'familyid', 'memberid', 'visitorid', 'eventid', 'organizationid', 'orgid', 'branchid', 'branch', 'createdat', 'updatedat', 'userid', 'createdby', 'updatedby', 'checkedinat', 'checkedinby'])
const aliases = new Map([
  ['firstname', 'first_name'], ['firstnames', 'first_name'], ['givenname', 'first_name'],
  ['lastname', 'last_name'], ['surname', 'last_name'], ['familyname', 'last_name'],
  ['dob', 'date_of_birth'], ['dateofbirth', 'date_of_birth'], ['birthdate', 'date_of_birth'],
  ['parentcontact', 'parent_contact'], ['parentguardiancontact', 'parent_contact'],
  ['guardiancontact', 'parent_contact'], ['contact', 'parent_contact'],
  ['address', 'residence'], ['homeaddress', 'residence'], ['residentialarea', 'residence'],
])

function mapHeader(header) {
  const key = header.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]/g, '')
  if (ignoredColumns.has(key)) return null
  if (aliases.has(key)) return aliases.get(key)
  return childColumns.includes(header.trim().toLowerCase()) ? header.trim().toLowerCase() : undefined
}

function normalizeDate(value, row) {
  if (!value) return null
  let date = value
  const parts = value.match(/^(\d{1,2})[/. -](\d{1,2})[/. -](\d{4})$/)
  if (parts) date = `${parts[3]}-${parts[2].padStart(2, '0')}-${parts[1].padStart(2, '0')}`
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error(`Row ${row}: date of birth must use YYYY-MM-DD or DD/MM/YYYY.`)
  const parsed = new Date(`${date}T00:00:00Z`)
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== date || date > new Date().toISOString().slice(0, 10)) {
    throw new Error(`Row ${row}: enter a valid date of birth that is not in the future.`)
  }
  return date
}

export function parseChildrenCsv(text) {
  const parsed = Papa.parse(text.replace(/^\uFEFF/, ''), { skipEmptyLines: 'greedy' })
  if (parsed.errors.length) throw new Error(`CSV error: ${parsed.errors[0].message}`)
  if (!parsed.data.length) throw new Error('The CSV file is empty.')
  const rawHeaders = parsed.data[0].map((header) => header.trim())
  const mappedHeaders = rawHeaders.map(mapHeader)
  const unsupported = rawHeaders.filter((header, index) => mappedHeaders[index] === undefined)
  if (unsupported.length) throw new Error(`Unrecognized column${unsupported.length === 1 ? '' : 's'}: ${unsupported.join(', ')}.`)
  const headers = mappedHeaders.filter((header) => header !== null)
  if (new Set(headers).size !== headers.length) throw new Error('Two or more column headings map to the same field.')
  if (!headers.includes('first_name') || !headers.includes('last_name') || !headers.includes('parent_contact')) {
    throw new Error('The first_name, last_name and parent_contact columns are required.')
  }
  const rows = parsed.data.slice(1)
  if (!rows.length) throw new Error('Add at least one child below the header.')
  if (rows.length > maxChildImportRows) throw new Error(`Import at most ${maxChildImportRows} children at a time.`)
  return rows.map((values, index) => {
    const row = index + 2
    if (values.length !== rawHeaders.length) throw new Error(`Row ${row}: the number of fields does not match the header.`)
    const fields = Object.fromEntries(mappedHeaders.map((header, i) => [header, values[i].trim()]).filter(([header]) => header !== null))
    if (!fields.first_name || fields.first_name.length > 100 || !fields.last_name || fields.last_name.length > 100) {
      throw new Error(`Row ${row}: first and last names are required and must be at most 100 characters.`)
    }
    if (!fields.parent_contact || fields.parent_contact.length > 120) {
      throw new Error(`Row ${row}: parent or guardian contact is required and must be at most 120 characters.`)
    }
    if ((fields.residence || '').length > 255) throw new Error(`Row ${row}: residence cannot exceed 255 characters.`)
    return {
      first_name: fields.first_name,
      last_name: fields.last_name,
      date_of_birth: normalizeDate(fields.date_of_birth || '', row),
      parent_contact: fields.parent_contact,
      residence: fields.residence || '',
    }
  })
}

export function childrenTemplateCsv() {
  return '\uFEFF' + Papa.unparse({ fields: childColumns, data: [] })
}
