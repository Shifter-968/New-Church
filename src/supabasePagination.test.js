import test from 'node:test'
import assert from 'node:assert/strict'
import { fetchAllPages } from './supabasePagination.js'

test('fetches all pages until the last partial page', async () => {
  const rows = Array.from({ length: 5 }, (_, id) => ({ id }))
  const ranges = []
  const result = await fetchAllPages(async (from, to) => {
    ranges.push([from, to])
    return { data: rows.slice(from, to + 1), error: null }
  }, 2)
  assert.deepEqual(result, rows)
  assert.deepEqual(ranges, [[0, 1], [2, 3], [4, 5]])
})

test('surfaces pagination query errors', async () => {
  await assert.rejects(fetchAllPages(async () => ({ data: null, error: new Error('query failed') })), /query failed/)
})
