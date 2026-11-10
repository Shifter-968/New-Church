import test from 'node:test'
import assert from 'node:assert/strict'
import { isOrganizationAdmin, visibleManagementNavigation, managementNavigation } from './navigation.js'

test('organization administrator sees all management navigation', () => {
  const assignments = [{ branch_id: null, roles: { is_org_admin: true, permissions: [] } }]
  assert.equal(visibleManagementNavigation(false, assignments).length, managementNavigation.length)
})

test('branch administrator and member see only granted management modules', () => {
  const assignments = [{ branch_id: 'a', roles: { is_org_admin: true, permissions: ['members.view'] } }]
  assert.equal(isOrganizationAdmin(false, assignments), false)
  const ids = visibleManagementNavigation(false, assignments).map((item) => item.id)
  assert.ok(ids.includes('members'))
  assert.ok(!ids.includes('users'))
  assert.ok(!ids.includes('audit'))
  assert.deepEqual(visibleManagementNavigation(false, []), [])
})

test('absence notices require their own permission in navigation', () => {
  const assignments = [{ branch_id: 'a', roles: { is_org_admin: false, permissions: ['attendance.absences.view'] } }]
  const ids = visibleManagementNavigation(false, assignments).map((item) => item.id)
  assert.ok(ids.includes('absences'))
  assert.ok(!ids.includes('attendance'))
  assert.ok(!visibleManagementNavigation(false, [{ branch_id: 'a', roles: { permissions: ['attendance.view'] } }]).some((item) => item.id === 'absences'))
})
