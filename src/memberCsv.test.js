import test from 'node:test'
import assert from 'node:assert/strict'
import Papa from 'papaparse'
import { filterMembers, memberCsv, parseMemberCsv, possibleDuplicateRows, templateCsv } from './memberCsv.js'

test('maps familiar headers and parses member profile fields', () => {
  const rows = parseMemberCsv('\ufeffFirst Name,Surname,Sex,Phone 2,DOB,Residence,Baptised,Marital Status,Branch ID,Created At\r\n"Mary, Jane",Doe,Female,123,1992-02-29,Manzini,yes,Married,ignored,ignored\r\n')
  assert.deepEqual(rows[0], { first_name: 'Mary, Jane', last_name: 'Doe', email: null, phone: null, gender: 'FEMALE', phone_2: '123', date_of_birth: '1992-02-29', residence: 'Manzini', baptized: true, marital_status: 'MARRIED', status: 'active' })
})

test('rejects missing required fields, invalid data and excessive rows with clear errors', () => {
  const valid = 'first_name,last_name,gender,date_of_birth\n'
  for (const text of ['first_name,last_name\n"bad,Doe', `${valid}A,B,Female,2025-02-29`, `${valid}A,B,,2000-01-01`, `${valid}A,B,Female,`, `${valid}A,B,Female,2000-01-01\nA,B,Female,2000-01-01`, `${valid}A,B,Female,2000-01-01,extra`]) assert.throws(() => parseMemberCsv(text))
  assert.throws(() => parseMemberCsv(`first_name,last_name,gender,date_of_birth\n${Array.from({ length: 1501 }, (_, i) => `A${i},B,Female,2000-01-01`).join('\n')}`), /1500/)
  assert.throws(() => parseMemberCsv('first_name,last_name,gender\nA,B,Female'), /date_of_birth/)
  assert.throws(() => parseMemberCsv('first_name,last_name,gender,date_of_birth,marital_status\nA,B,Female,2000-01-01,complicated'), /marital status/)
})

test('defaults omitted marital status to single and supports common Excel date formats', () => {
  const [row] = parseMemberCsv('First Name,Last Name,Gender,Date of Birth,ID\nJane,Doe,Female,15/12/1990,ignored')
  assert.equal(row.date_of_birth, '1990-12-15')
  assert.equal(row.marital_status, 'SINGLE')
})

test('exports filtered data with spreadsheet formula protection', () => {
  const csv = memberCsv([{ first_name: '=2+2', last_name: 'Doe', phone: '  @cmd', status: 'active', branch_id: 'a' }], [{ id: 'a', name: 'Main' }])
  const rows = Papa.parse(csv.replace(/^\uFEFF/, ''), { header: true }).data
  assert.equal(rows[0].first_name, "'=2+2")
  assert.equal(rows[0].phone, "'  @cmd")
  assert.equal(rows[0].branch, 'Main')
  assert.match(templateCsv(), /first_name,last_name,gender/)
  assert.match(templateCsv(), /baptised/)
})

test('handles embedded newlines and quotes in CSV fields', () => {
  const [row] = parseMemberCsv('first_name,last_name,gender,date_of_birth\n"Mary ""May""\nAnne",Doe,Female,2000-01-01')
  assert.equal(row.first_name, 'Mary "May"\nAnne')
})

test('visitor template and parsing use only supported visitor fields', () => {
  assert.deepEqual(parseMemberCsv('first_name,last_name,email,phone\nJane,Doe,,', 'visitors'), [{ first_name: 'Jane', last_name: 'Doe', email: null, phone: null }])
  assert.throws(() => parseMemberCsv('first_name,last_name,status\nJane,Doe,active', 'visitors'), /Unsupported visitor/)
  assert.equal(templateCsv('visitors').trim(), 'first_name,last_name,email,phone')
  assert.doesNotMatch(memberCsv([{ first_name: 'Jane', last_name: 'Doe' }], [], 'visitors'), /status/)
})

test('flags possible duplicates within visitor imports by name, email or normalized phone', () => {
  const rows = [
    { first_name: 'Jane', last_name: 'Doe', email: 'A@example.test', phone: '123-45' },
    { first_name: 'jane', last_name: 'DOE', email: 'other@example.test' },
    { first_name: 'Other', last_name: 'Person', phone: '123 45' },
    { first_name: 'Third', last_name: 'Person', email: 'a@EXAMPLE.test' },
    { first_name: 'Fourth', last_name: 'Person' },
  ]
  assert.deepEqual(possibleDuplicateRows(rows), [2, 3, 4, 5])
})

test('flags either member phone across records without flagging one record against itself', () => {
  const rows = [
    { first_name: 'A', last_name: 'One', phone: '123-45', phone_2: '123 45' },
    { first_name: 'B', last_name: 'Two', phone_2: '12345' },
    { first_name: 'C', last_name: 'Three', phone: '555', phone_2: '555' },
  ]
  assert.deepEqual(possibleDuplicateRows(rows), [2, 3])
  assert.deepEqual(possibleDuplicateRows(rows.slice(2)), [])
})

test('filters full names, both phones, branch and status together', () => {
  const list = [{ first_name: 'Jane', last_name: 'Doe', phone_2: '555', branch_id: 'a', status: 'active' }, { first_name: 'John', last_name: 'Doe', branch_id: null, status: 'inactive' }]
  assert.equal(filterMembers(list, 'jane doe', 'a', 'active').length, 1)
  assert.equal(filterMembers(list, '555', 'all', 'all').length, 1)
  assert.equal(filterMembers(list, '', 'unassigned', 'inactive').length, 1)
  assert.equal(filterMembers(list, 'jane', 'unassigned', 'all').length, 0)
})
