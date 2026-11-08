export function canManageMembers(isOwner, assignments, action, branchId = null) {
  return canManageDirectory(isOwner, assignments, 'members', action, branchId)
}

export function canManageDirectory(isOwner, assignments, resource, action, branchId = null) {
  if (isOwner) return true
  return assignments.some((assignment) => {
    const role = assignment.roles
    const inScope = !assignment.branch_id || assignment.branch_id === branchId
    return inScope && ((!assignment.branch_id && role?.is_org_admin) || role?.permissions?.includes(`${resource}.${action}`))
  })
}
