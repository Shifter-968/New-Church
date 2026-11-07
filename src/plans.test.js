import test from 'node:test'
import assert from 'node:assert/strict'
import { planDefaults, planToForm, preparePlan } from './plans.js'

test('plan form prepares nullable limits, decimal prices and features', () => {
  const plan = preparePlan({ ...planDefaults, name: ' Starter ', price: '1400.00', currency: 'szl', max_members: '500', features: ' One \n\nTwo ' })
  assert.equal(plan.name, 'Starter')
  assert.equal(plan.currency, 'SZL')
  assert.equal(plan.price, '1400.00')
  assert.equal(plan.max_members, 500)
  assert.equal(plan.max_branches, null)
  assert.deepEqual(plan.features, ['One', 'Two'])
  assert.equal(planToForm(plan).features, 'One\nTwo')
})

test('invalid plans cannot be submitted', () => {
  const form = { ...planDefaults, name: 'Starter', price: '12' }
  for (const invalid of [{ price: '-1' }, { price: '0.001' }, { max_users: '0' }, { max_members: '2.5' }, { free_trial_days: '' }, { currency: 'SZ' }]) {
    assert.throws(() => preparePlan({ ...form, ...invalid }))
  }
})
