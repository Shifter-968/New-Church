import { supabase } from './supabase'

export async function findMemberImportDuplicates(orgId, branchId, candidates) {
  const results = []
  for (let offset = 0; offset < candidates.length; offset += 500) {
    const batch = candidates.slice(offset, offset + 500)
    const { data, error } = await supabase.rpc('find_member_import_duplicates', {
      target_org: orgId,
      target_branch: branchId,
      candidates: batch.map(({ first_name, last_name, email, phone, phone_2 }) => ({ first_name, last_name, email, phone, phone_2 })),
    })
    if (error) throw new Error(`Could not check for existing members: ${error.message}`)
    results.push(...data.flatMap((row) => row.matches.map((match) => ({ ...match, row_number: row.row_number + offset }))))
  }
  return results
}
