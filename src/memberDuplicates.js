import { supabase } from './supabase'

export async function findMemberImportDuplicates(orgId, branchId, candidates) {
  const { data, error } = await supabase.rpc('find_member_import_duplicates', {
    target_org: orgId,
    target_branch: branchId,
    candidates: candidates.map(({ first_name, last_name, email, phone, phone_2 }) => ({ first_name, last_name, email, phone, phone_2 })),
  })
  if (error) throw new Error(`Could not check for existing members: ${error.message}`)
  return data.flatMap((row) => row.matches.map((match) => ({ ...match, row_number: row.row_number })))
}
