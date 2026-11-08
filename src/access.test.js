import test from 'node:test'
import assert from 'node:assert/strict'
import { canManageDirectory, canManageMembers } from './access.js'

test('owner can manage members', () => {
  assert.equal(canManageMembers(true, [], 'delete', 'branch'), true)
})

test('organization admin covers every branch', () => {
  const assignments = [{ branch_id: null, roles: { is_org_admin: true, permissions: [] } }]
  assert.equal(canManageMembers(false, assignments, 'create', 'branch'), true)
})

test('branch grants do not extend to other branches or unassigned members', () => {
  const assignments = [{ branch_id: 'a', roles: { is_org_admin: false, permissions: ['members.update'] } }]
  assert.equal(canManageMembers(false, assignments, 'update', 'a'), true)
  assert.equal(canManageMembers(false, assignments, 'update', 'b'), false)
  assert.equal(canManageMembers(false, assignments, 'update', null), false)
  assert.equal(canManageMembers(false, assignments, 'delete', 'a'), false)
})

test('a branch assignment does not turn an organization administrator into a branch superuser', () => {
  const assignments = [{ branch_id: 'a', roles: { is_org_admin: true, permissions: [] } }]
  assert.equal(canManageMembers(false, assignments, 'update', 'a'), false)
})

test('visitor permissions are separate and branch scoped', () => {
  const assignments = [{ branch_id: 'a', roles: { permissions: ['visitors.view', 'members.create'] } }]
  assert.equal(canManageDirectory(false, assignments, 'visitors', 'view', 'a'), true)
  assert.equal(canManageDirectory(false, assignments, 'visitors', 'view', 'b'), false)
  assert.equal(canManageDirectory(false, assignments, 'visitors', 'create', 'a'), false)
})
