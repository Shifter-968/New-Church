export function filterAttendance(records, kind, branch, search) {
  const term = search.trim().toLowerCase()
  return records.filter((row) => (kind === 'all' || row.person_kind === kind)
    && (branch === 'all' || row.branch_id === branch)
    && `${row.first_name} ${row.last_name}`.toLowerCase().includes(term))
}
