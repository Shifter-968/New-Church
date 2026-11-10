-- Apply once after 036_member_profiles_and_ministry_criteria.sql.
begin;

alter table public.organization_plan_assignments
  add column trial_end_date date,
  add column next_payment_due_date date,
  add column grace_period_end_date date,
  add column renewal_count integer not null default 0,
  add column last_payment_at date,
  add column last_payment_amount numeric(12, 2),
  add column last_payment_reference text;

create table public.organization_plan_payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plan_id uuid not null references public.plans(id),
  paid_on date not null,
  amount numeric(12, 2) not null check (amount >= 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  reference text not null check (length(trim(reference)) between 1 and 200),
  recorded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
create index organization_plan_payments_org_idx on public.organization_plan_payments (organization_id, paid_on desc, created_at desc);
alter table public.organization_plan_payments enable row level security;
revoke all on public.organization_plan_payments from public, anon, authenticated;

create function public.initialize_organization_plan_dates()
returns trigger language plpgsql set search_path = ''
as $$
declare trial_days integer; grace_days integer; period text; start_date date;
begin
  if tg_op = 'UPDATE' and new.plan_id is not distinct from old.plan_id
    and new.assigned_at is not distinct from old.assigned_at then
    return new;
  end if;
  select p.free_trial_days, p.grace_period_days, p.billing_period
    into trial_days, grace_days, period from public.plans p where p.id = new.plan_id;
  if not found then raise exception 'Plan not found.'; end if;
  start_date := coalesce(new.assigned_at::date, current_date);
  new.trial_end_date := case when trial_days > 0 then start_date + trial_days else null end;
  new.next_payment_due_date := case
    when trial_days > 0 then start_date + trial_days
    when period = 'MONTHLY' then (start_date + interval '1 month')::date
    else (start_date + interval '1 year')::date
  end;
  new.grace_period_end_date := new.next_payment_due_date + grace_days;
  new.renewal_count := 0;
  new.last_payment_at := null;
  new.last_payment_amount := null;
  new.last_payment_reference := null;
  return new;
end
$$;
revoke all on function public.initialize_organization_plan_dates() from public, anon, authenticated;
create trigger initialize_organization_plan_dates before insert or update of plan_id, assigned_at
  on public.organization_plan_assignments for each row execute function public.initialize_organization_plan_dates();

create or replace function public.set_organization_plan(target_org uuid, target_plan uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_platform_owner() then raise exception 'Only a platform owner can assign plans.'; end if;
  if not exists(select 1 from public.organizations where id=target_org) then raise exception 'Church not found.'; end if;
  if target_plan is null then
    delete from public.organization_plan_assignments where organization_id=target_org;
  else
    if not exists(select 1 from public.plans where id=target_plan and is_active) then
      raise exception 'Select an active plan.';
    end if;
    insert into public.organization_plan_assignments as current_assignment (organization_id,plan_id,assigned_by)
    values(target_org,target_plan,auth.uid())
    on conflict(organization_id) do update set
      plan_id=excluded.plan_id,
      assigned_by=excluded.assigned_by,
      assigned_at=case when current_assignment.plan_id is distinct from excluded.plan_id
        then now() else current_assignment.assigned_at end;
  end if;
end
$$;

update public.organization_plan_assignments a
set trial_end_date = case when p.free_trial_days > 0 then a.assigned_at::date + p.free_trial_days else null end,
    next_payment_due_date = case
      when p.free_trial_days > 0 then a.assigned_at::date + p.free_trial_days
      when p.billing_period = 'MONTHLY' then (a.assigned_at::date + interval '1 month')::date
      else (a.assigned_at::date + interval '1 year')::date
    end,
    grace_period_end_date = case
      when p.free_trial_days > 0 then a.assigned_at::date + p.free_trial_days + p.grace_period_days
      when p.billing_period = 'MONTHLY' then (a.assigned_at::date + interval '1 month')::date + p.grace_period_days
      else (a.assigned_at::date + interval '1 year')::date + p.grace_period_days
    end
from public.plans p where p.id = a.plan_id;

create function public.church_plan_billing_summary(target_org uuid)
returns table (
  plan_id uuid, plan_name text, plan_active boolean, price numeric, currency text, billing_period text,
  free_trial_days integer, grace_period_days integer, trial_end_date date, next_payment_due_date date,
  grace_period_end_date date, renewal_count integer, last_payment_at date, last_payment_amount numeric,
  last_payment_reference text, billing_status text, days_to_due integer, grace_days_remaining integer,
  active_members bigint, visitors bigint, branches bigint, active_users bigint,
  max_branches integer, max_members integer, max_visitors integer, max_users integer,
  max_storage_gb integer, max_api_calls_per_month integer, max_api_calls_per_minute integer,
  features text[], include_support boolean, include_analytics boolean,
  include_advanced_reporting boolean, include_integrations boolean
)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_org_administrator(target_org) then
    raise exception 'Only a church administrator or platform owner can view billing details.';
  end if;
  return query
  select p.id, p.name, p.is_active, p.price, p.currency, p.billing_period,
    p.free_trial_days, p.grace_period_days, a.trial_end_date, a.next_payment_due_date,
    a.grace_period_end_date, a.renewal_count, a.last_payment_at, a.last_payment_amount,
    a.last_payment_reference,
    case
      when a.trial_end_date is not null and current_date < a.trial_end_date then 'trial'
      when current_date <= a.next_payment_due_date then 'active'
      when current_date <= a.grace_period_end_date then 'grace'
      else 'expired'
    end,
    greatest(a.next_payment_due_date - current_date, 0),
    case when current_date > a.next_payment_due_date and current_date <= a.grace_period_end_date
      then a.grace_period_end_date - current_date + 1 else 0 end,
    (select count(*) from public.members m where m.organization_id = target_org and m.status = 'active'),
    (select count(*) from public.visitors v where v.organization_id = target_org),
    (select count(*) from public.branches b where b.organization_id = target_org),
    (select count(distinct x.user_id) from public.assignments x where x.organization_id = target_org and x.active),
    p.max_branches, p.max_members, p.max_visitors, p.max_users, p.max_storage_gb,
    p.max_api_calls_per_month, p.max_api_calls_per_minute, p.features, p.include_support,
    p.include_analytics, p.include_advanced_reporting, p.include_integrations
  from public.organization_plan_assignments a
  join public.plans p on p.id = a.plan_id
  where a.organization_id = target_org;
end
$$;

create function public.record_organization_plan_payment(
  target_org uuid, paid_on date, amount numeric, reference text
)
returns void language plpgsql security definer set search_path = ''
as $$
declare assigned public.organization_plan_assignments%rowtype;
  selected_period text; selected_currency text; grace_days integer; next_due date;
begin
  if not public.is_platform_owner() then raise exception 'Only a platform owner can record a church payment.'; end if;
  if paid_on is null or paid_on > current_date or amount is null or amount < 0
    or reference is null or length(trim(reference)) not between 1 and 200 then
    raise exception 'Enter a valid payment date, non-negative amount and reference.';
  end if;
  select * into assigned from public.organization_plan_assignments a
    where a.organization_id = target_org for update;
  if not found then raise exception 'Assign a plan before recording payment.'; end if;
  select p.billing_period, p.currency, p.grace_period_days
    into selected_period, selected_currency, grace_days
    from public.plans p where p.id = assigned.plan_id;
  insert into public.organization_plan_payments
    (organization_id, plan_id, paid_on, amount, currency, reference, recorded_by)
  values (target_org, assigned.plan_id, paid_on, amount, selected_currency, trim(reference), auth.uid());
  next_due := (greatest(paid_on, assigned.next_payment_due_date) +
    case when selected_period = 'MONTHLY' then interval '1 month' else interval '1 year' end)::date;
  update public.organization_plan_assignments
  set trial_end_date = null, next_payment_due_date = next_due,
    grace_period_end_date = next_due + grace_days, renewal_count = renewal_count + 1,
    last_payment_at = paid_on, last_payment_amount = amount, last_payment_reference = trim(reference)
  where organization_id = target_org;
end
$$;

revoke all on function public.church_plan_billing_summary(uuid),
  public.record_organization_plan_payment(uuid, date, numeric, text) from public, anon;
grant execute on function public.church_plan_billing_summary(uuid),
  public.record_organization_plan_payment(uuid, date, numeric, text) to authenticated;

commit;
