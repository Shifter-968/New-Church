export const planDefaults = {
  name: '', description: '', price: '', currency: 'SZL', billing_period: 'MONTHLY',
  free_trial_days: '0', grace_period_days: '0', max_branches: '', max_members: '',
  max_visitors: '', max_users: '', max_storage_gb: '', max_api_calls_per_month: '',
  max_api_calls_per_minute: '', include_support: false, include_analytics: false,
  include_advanced_reporting: false, include_integrations: false, features: '', is_active: true,
}

export const limits = [
  ['max_branches', 'Branches'],
  ['max_members', 'Members'],
  ['max_visitors', 'Visitors'],
  ['max_users', 'Users'],
  ['max_storage_gb', 'Storage (GB)'],
  ['max_api_calls_per_month', 'API calls per month'],
  ['max_api_calls_per_minute', 'API calls per minute'],
]

export const inclusions = [
  ['include_support', 'Platform support'],
  ['include_analytics', 'Analytics'],
  ['include_advanced_reporting', 'Advanced reporting'],
  ['include_integrations', 'Integrations'],
]

export function planToForm(plan) {
  if (!plan) return { ...planDefaults }
  const form = Object.fromEntries(Object.keys(planDefaults).map((key) => [key, plan[key] ?? '']))
  form.features = plan.features.join('\n')
  return form
}

export function preparePlan(form) {
  const name = form.name.trim()
  const currency = form.currency.trim().toUpperCase()
  const price = String(form.price).trim()
  if (name.length < 2 || name.length > 120) throw new Error('Plan name must be between 2 and 120 characters.')
  if (!/^[A-Z]{3}$/.test(currency)) throw new Error('Use a three-letter currency code, such as SZL.')
  if (!/^\d{1,10}(\.\d{1,2})?$/.test(price)) throw new Error('Enter a non-negative price with at most two decimal places.')
  if (!['MONTHLY', 'ANNUALLY'].includes(form.billing_period)) throw new Error('Select a valid billing period.')
  if (form.description.length > 2000) throw new Error('Description cannot exceed 2,000 characters.')
  const result = {
    name, description: form.description.trim(), price, currency, billing_period: form.billing_period,
    include_support: form.include_support, include_analytics: form.include_analytics,
    include_advanced_reporting: form.include_advanced_reporting, include_integrations: form.include_integrations,
    features: form.features.split('\n').map((feature) => feature.trim()).filter(Boolean), is_active: form.is_active,
  }
  for (const [key, label] of limits) {
    const value = String(form[key]).trim()
    if (value && (!/^\d+$/.test(value) || Number(value) < 1 || Number(value) > 2147483647)) throw new Error(`${label} must be a positive whole number, or blank for unlimited.`)
    result[key] = value ? Number(value) : null
  }
  for (const [key, label] of [['free_trial_days', 'Trial days'], ['grace_period_days', 'Grace days']]) {
    const value = String(form[key]).trim()
    if (!/^\d+$/.test(value) || Number(value) > 3650) throw new Error(`${label} must be a whole number from 0 to 3650.`)
    result[key] = Number(value)
  }
  return result
}
