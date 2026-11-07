export function canManageMembers(isOwner, assignments, action, branchId = null) {
  if (isOwner) return true
  return assignments.some((assignment) => {
    const role = assignment.roles
    const inScope = !assignment.branch_id || assignment.branch_id === branchId
    return inScope && ((!assignment.branch_id && role?.is_org_admin) || role?.permissions?.includes(`members.${action}`))
  })
}
