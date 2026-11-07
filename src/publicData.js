import { supabase } from './supabase'

function client() {
  if (!supabase) throw new Error('Church search is unavailable until Supabase is configured.')
  return supabase
}

export async function searchChurches(query) {
  if (query.trim().length < 2) return []
  const { data, error } = await client().rpc('search_public_churches', { search_term: query.trim() })
  if (error) throw new Error(`Could not search churches: ${error.message}`)
  return data
}

export async function getPublicBranches(churchId) {
  const { data, error } = await client().rpc('public_church_branches', { church_id: churchId })
  if (error) throw new Error(`Could not load branches: ${error.message}`)
  return data
}
