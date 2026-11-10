-- Apply once after 021_plan_reporting.sql.
begin;

create function public.list_church_access(target_org uuid)
returns table (assignment_id uuid, user_id uuid, email text, role_name text,
 branch_id uuid, scope_name text, assignment_kind text)
language plpgsql stable security definer set search_path = ''
as $$
begin
 if not public.is_org_administrator(target_org) then
   raise exception 'Only an organization administrator or platform owner can view users and access.';
 end if;
 return query
 select a.id, a.user_id, u.email::text, r.name, a.branch_id,
   case when a.branch_id is null then 'Entire church' else b.name end,
   case when r.is_org_admin then 'organization_admin'
     when c.role_id is not null then 'custom'
     when r.name='Branch Administrator' and a.branch_id is not null then 'branch_admin'
     else 'protected' end
 from public.assignments a
 join auth.users u on u.id=a.user_id
 join public.roles r on r.id=a.role_id and r.organization_id=a.organization_id
 left join public.branches b on b.id=a.branch_id and b.organization_id=a.organization_id
 left join public.custom_church_roles c on c.role_id=r.id and c.organization_id=r.organization_id
 where a.organization_id=target_org and a.active
 order by lower(u.email), u.id, r.name, a.id limit 1000;
end
$$;

create function public.remove_branch_administrator_assignment(target_org uuid, target_assignment uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare target_user uuid;
begin
 if not public.is_org_administrator(target_org) then
   raise exception 'Only an organization administrator or platform owner can remove branch administrators.';
 end if;
 select a.user_id into target_user
 from public.assignments a join public.roles r on r.id=a.role_id and r.organization_id=a.organization_id
 where a.id=target_assignment and a.organization_id=target_org and a.active and a.branch_id is not null
   and r.name='Branch Administrator' and not r.is_org_admin
   and not exists(select 1 from public.custom_church_roles c where c.role_id=r.id);
 if target_user is null then raise exception 'Branch administrator assignment not found.'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(target_org::text || target_user::text,0));
 if not exists(select 1 from public.assignments a where a.user_id=target_user and a.organization_id=target_org
   and a.active and a.id<>target_assignment) then
   raise exception 'Cannot remove the account’s last active church assignment.';
 end if;
 delete from public.assignments a using public.roles r
 where a.id=target_assignment and a.organization_id=target_org and a.active and a.branch_id is not null
   and r.id=a.role_id and r.organization_id=a.organization_id and r.name='Branch Administrator' and not r.is_org_admin
   and not exists(select 1 from public.custom_church_roles c where c.role_id=r.id);
 if not found then raise exception 'Branch administrator assignment not found.'; end if;
end
$$;

revoke all on function public.list_church_access(uuid), public.remove_branch_administrator_assignment(uuid,uuid) from public, anon;
grant execute on function public.list_church_access(uuid), public.remove_branch_administrator_assignment(uuid,uuid) to authenticated;
commit;
