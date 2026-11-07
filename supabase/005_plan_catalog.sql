-- Apply once after 004_branch_admin_by_email.sql.
begin;

create table public.plans (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 120),
  description text not null default '' check (length(description) <= 2000),
  price numeric(12,2) not null check (price >= 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  billing_period text not null check (billing_period in ('MONTHLY', 'ANNUALLY')),
  free_trial_days integer not null default 0 check (free_trial_days between 0 and 3650),
  grace_period_days integer not null default 0 check (grace_period_days between 0 and 3650),
  max_branches integer check (max_branches > 0),
  max_members integer check (max_members > 0),
  max_visitors integer check (max_visitors > 0),
  max_users integer check (max_users > 0),
  max_storage_gb integer check (max_storage_gb > 0),
  max_api_calls_per_month integer check (max_api_calls_per_month > 0),
  max_api_calls_per_minute integer check (max_api_calls_per_minute > 0),
  include_support boolean not null default false,
  include_analytics boolean not null default false,
  include_advanced_reporting boolean not null default false,
  include_integrations boolean not null default false,
  features text[] not null default '{}',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create unique index plans_name_unique on public.plans (lower(trim(name)));
alter table public.plans enable row level security;
create policy "public can view active plans" on public.plans for select to anon, authenticated using (is_active);
create policy "owners can view all plans" on public.plans for select to authenticated using (public.is_platform_owner());
create policy "owners can create plans" on public.plans for insert to authenticated with check (public.is_platform_owner());
create policy "owners can update plans" on public.plans for update to authenticated using (public.is_platform_owner()) with check (public.is_platform_owner());
grant select on public.plans to anon, authenticated;
grant insert, update on public.plans to authenticated;
commit;
