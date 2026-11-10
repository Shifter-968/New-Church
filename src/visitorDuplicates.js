import { supabase } from './supabase'

export async function findVisitorDuplicates(orgId, candidates) {
  const results = []
  for (let offset = 0; offset < candidates.length; offset += 500) {
    const batch = candidates.slice(offset, offset + 500)
    const { data, error } = await supabase.rpc('find_visitor_duplicates', {
      target_org: orgId,
      candidates: batch.map(({ first_name, last_name, email, phone }) => ({ first_name, last_name, email, phone })),
    })
    if (error) throw new Error(`Could not check for existing visitors: ${error.message}`)
    results.push(...data.flatMap((row) => row.matches.map((match) => ({ ...match, row_number: row.row_number + offset }))))
  }
  return results
}
