import { supabase } from './supabase'

export async function findVisitorDuplicates(orgId, candidates) {
  const { data, error } = await supabase.rpc('find_visitor_duplicates', {
    target_org: orgId,
    candidates: candidates.map(({ first_name, last_name, email, phone }) => ({ first_name, last_name, email, phone })),
  })
  if (error) throw new Error(`Could not check for existing visitors: ${error.message}`)
  return data.flatMap((row) => row.matches.map((match) => ({ ...match, row_number: row.row_number })))
}
