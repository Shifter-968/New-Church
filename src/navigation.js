export const personalNavigation = [
  { id: 'profile', label: 'My profile' },
  { id: 'announcements', label: 'Announcements' },
  { id: 'calendar', label: 'My calendar' },
  { id: 'community', label: 'Community' },
  { id: 'notifications', label: 'Notifications' },
  { id: 'personal-settings', label: 'Settings' },
]

export const managementNavigation = [
  { id: 'members', label: 'Members', permission: 'members.view' },
  { id: 'membership-requests', label: 'Membership requests', permission: 'members.create' },
  { id: 'children', label: 'Children', permission: 'members.view' },
  { id: 'families', label: 'Families', permission: 'members.view' },
  { id: 'visitors', label: 'Visitors', permission: 'visitors.view' },
  { id: 'branches', label: 'Branches', permission: 'org.branches.view' },
  { id: 'users', label: 'Users & access', permission: 'org.users.view' },
  { id: 'roles', label: 'Roles & permissions', permission: 'roles.manage' },
  { id: 'ministries', label: 'Ministries', permission: 'ministries.view' },
  { id: 'departments', label: 'Departments', permission: 'departments.view' },
  { id: 'attendance', label: 'Attendance', permission: 'attendance.view' },
  { id: 'absences', label: 'Reported absences', permission: 'attendance.absences.view' },
  { id: 'events', label: 'Events', permission: 'events.view' },
  { id: 'reports', label: 'Reports', permission: 'reports.view' },
  { id: 'org-settings', label: 'Organization settings', permission: 'org.settings.manage' },
  { id: 'billing', label: 'Billing', permission: 'org.settings.manage' },
  { id: 'audit', label: 'Audit trail', orgAdminOnly: true },
]

export function isOrganizationAdmin(owner, assignments) {
  return owner || assignments.some((assignment) => !assignment.branch_id && assignment.roles?.is_org_admin)
}

export function visibleManagementNavigation(owner, assignments) {
  const admin = isOrganizationAdmin(owner, assignments)
  return managementNavigation.filter((item) => admin || (!item.orgAdminOnly && assignments.some((assignment) => assignment.roles?.permissions?.includes(item.permission))))
}
