-- Apply once after 020_families_and_children.sql.
begin;

create table public.organization_plan_assignments (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null unique references public.organizations(id),
 plan_id uuid not null references public.plans(id),
 assigned_by uuid not null references auth.users(id),
 assigned_at timestamptz not null default now()
);
alter table public.organization_plan_assignments enable row level security;
revoke all on public.organization_plan_assignments from public, anon, authenticated;
create trigger organization_plan_activity after insert or update or delete on public.organization_plan_assignments
 for each row execute function public.record_support_activity();

create function public.set_organization_plan(target_org uuid, target_plan uuid)
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
   insert into public.organization_plan_assignments(organization_id,plan_id,assigned_by)
   values(target_org,target_plan,auth.uid())
   on conflict(organization_id) do update set plan_id=excluded.plan_id,assigned_by=excluded.assigned_by,assigned_at=now();
 end if;
end
$$;

create function public.organization_plan_features(target_org uuid)
returns table(plan_id uuid, plan_name text, plan_active boolean, analytics boolean, advanced_reporting boolean)
language plpgsql stable security definer set search_path = ''
as $$
begin
 if not public.is_org_administrator(target_org) then raise exception 'Only a church administrator or platform owner can view plan features.'; end if;
 return query select p.id,p.name,p.is_active,p.is_active and p.include_analytics,p.is_active and p.include_advanced_reporting
 from public.organization_plan_assignments a join public.plans p on p.id=a.plan_id where a.organization_id=target_org;
end
$$;

create function public.church_analytics(target_org uuid)
returns table(active_members bigint, visitors bigint, branches bigint, checkins_last_30_days bigint)
language plpgsql stable security definer set search_path = ''
as $$
begin
 if not public.is_org_administrator(target_org) then raise exception 'Only a church administrator or platform owner can view analytics.'; end if;
 if not exists(select 1 from public.organization_plan_assignments a join public.plans p on p.id=a.plan_id
   where a.organization_id=target_org and p.is_active and p.include_analytics) then
   raise exception 'Analytics is not included in the currently assigned active plan.';
 end if;
 return query select
   (select count(*) from public.members m where m.organization_id=target_org and m.status='active'),
   (select count(*) from public.visitors v where v.organization_id=target_org),
   (select count(*) from public.branches b where b.organization_id=target_org),
   (select count(*) from public.event_attendance a where a.organization_id=target_org and a.checked_in_at >= now()-interval '30 days');
end
$$;

create function public.church_branch_report(target_org uuid)
returns table(branch_id uuid, branch_name text, active_members bigint, visitors bigint, checkins_last_30_days bigint)
language plpgsql stable security definer set search_path = ''
as $$
begin
 if not public.is_org_administrator(target_org) then raise exception 'Only a church administrator or platform owner can view reports.'; end if;
 if not exists(select 1 from public.organization_plan_assignments a join public.plans p on p.id=a.plan_id
   where a.organization_id=target_org and p.is_active and p.include_advanced_reporting) then
   raise exception 'Advanced reporting is not included in the currently assigned active plan.';
 end if;
 return query select b.id,b.name,
   (select count(*) from public.members m where m.organization_id=target_org and m.branch_id=b.id and m.status='active'),
   (select count(*) from public.visitors v where v.organization_id=target_org and v.branch_id=b.id),
   (select count(*) from public.event_attendance a where a.organization_id=target_org and a.branch_id=b.id and a.checked_in_at >= now()-interval '30 days')
 from public.branches b where b.organization_id=target_org order by b.name,b.id limit 1000;
end
$$;
revoke all on function public.set_organization_plan(uuid,uuid),public.organization_plan_features(uuid),
 public.church_analytics(uuid),public.church_branch_report(uuid) from public, anon;
grant execute on function public.set_organization_plan(uuid,uuid),public.organization_plan_features(uuid),
 public.church_analytics(uuid),public.church_branch_report(uuid) to authenticated;
commit;
