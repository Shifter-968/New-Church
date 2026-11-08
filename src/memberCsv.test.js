import test from 'node:test'
import assert from 'node:assert/strict'
import Papa from 'papaparse'
import { filterMembers, memberCsv, parseMemberCsv, templateCsv } from './memberCsv.js'

test('parses quoted CSV, optional fields and second phone', () => {
  const rows = parseMemberCsv('\ufefffirst_name,last_name,phone_2,date_of_birth,status\r\n"Mary, Jane",Doe,123,1992-02-29,ACTIVE\r\n')
  assert.deepEqual(rows[0], { first_name: 'Mary, Jane', last_name: 'Doe', email: null, phone: null, phone_2: '123', date_of_birth: '1992-02-29', status: 'active' })
})

test('rejects invalid CSV, dates, duplicates, unknown columns and excessive rows', () => {
  for (const text of ['first_name,last_name\n"bad,Doe', 'first_name,last_name,date_of_birth\nA,B,2025-02-29', 'first_name,last_name\nA,B\nA,B', 'first_name,last_name,branch\nA,B,X', 'first_name,last_name\nA,B,C']) assert.throws(() => parseMemberCsv(text))
  assert.throws(() => parseMemberCsv(`first_name,last_name\n${Array.from({ length: 501 }, (_, i) => `A${i},B`).join('\n')}`), /500/)
})

test('exports filtered data with spreadsheet formula protection', () => {
  const csv = memberCsv([{ first_name: '=2+2', last_name: 'Doe', phone: '  @cmd', status: 'active', branch_id: 'a' }], [{ id: 'a', name: 'Main' }])
  const rows = Papa.parse(csv.replace(/^\uFEFF/, ''), { header: true }).data
  assert.equal(rows[0].first_name, "'=2+2")
  assert.equal(rows[0].phone, "'  @cmd")
  assert.equal(rows[0].branch, 'Main')
  assert.match(templateCsv(), /first_name,last_name/)
})

test('handles embedded newlines and quotes in CSV fields', () => {
  const [row] = parseMemberCsv('first_name,last_name\n"Mary ""May""\nAnne",Doe')
  assert.equal(row.first_name, 'Mary "May"\nAnne')
})

test('visitor template and parsing use only supported visitor fields', () => {
  assert.deepEqual(parseMemberCsv('first_name,last_name,email,phone\nJane,Doe,,', 'visitors'), [{ first_name: 'Jane', last_name: 'Doe', email: null, phone: null }])
  assert.throws(() => parseMemberCsv('first_name,last_name,status\nJane,Doe,active', 'visitors'), /Unsupported columns/)
  assert.equal(templateCsv('visitors').trim(), 'first_name,last_name,email,phone')
  assert.doesNotMatch(memberCsv([{ first_name: 'Jane', last_name: 'Doe' }], [], 'visitors'), /status/)
})

test('filters full names, both phones, branch and status together', () => {
  const list = [{ first_name: 'Jane', last_name: 'Doe', phone_2: '555', branch_id: 'a', status: 'active' }, { first_name: 'John', last_name: 'Doe', branch_id: null, status: 'inactive' }]
  assert.equal(filterMembers(list, 'jane doe', 'a', 'active').length, 1)
  assert.equal(filterMembers(list, '555', 'all', 'all').length, 1)
  assert.equal(filterMembers(list, '', 'unassigned', 'inactive').length, 1)
  assert.equal(filterMembers(list, 'jane', 'unassigned', 'all').length, 0)
})
