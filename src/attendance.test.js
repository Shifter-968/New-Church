import test from 'node:test'
import assert from 'node:assert/strict'
import { filterAttendance } from './attendance.js'

test('attendance filters members and visitors without separating records', () => {
  const rows = [
    { first_name: 'Jane', last_name: 'Doe', person_kind: 'member', branch_id: 'a' },
    { first_name: 'Jane', last_name: 'Doe', person_kind: 'visitor', branch_id: 'a' },
    { first_name: 'Jane', last_name: 'Doe', person_kind: 'visitor', branch_id: 'b' },
  ]
  assert.equal(filterAttendance(rows, 'all', 'all', '').length, 3)
  assert.equal(filterAttendance(rows, 'visitor', 'all', 'jane doe').length, 2)
  assert.deepEqual(filterAttendance(rows, 'visitor', 'a', 'JANE'), [rows[1]])
  assert.equal(filterAttendance(rows, 'member', 'b', '').length, 0)
})
