-- Apply once after 015_audiences_and_teams.sql.
begin;

create table public.custom_church_roles (
  role_id uuid primary key,
  organization_id uuid not null,
  foreign key (role_id, organization_id) references public.roles(id, organization_id) on delete cascade
);
alter table public.custom_church_roles enable row level security;
revoke all on public.custom_church_roles from public, anon, authenticated;

create function public.manageable_church_roles(target_org uuid)
returns table (id uuid, name text, permissions text[])
language plpgsql stable security definer set search_path = ''
as $$
begin
 if not public.is_org_administrator(target_org) then raise exception 'Only organization administrators can manage roles.'; end if;
 return query select r.id,r.name,r.permissions from public.roles r
 join public.custom_church_roles c on c.role_id=r.id and c.organization_id=r.organization_id
 where r.organization_id=target_org order by r.name,r.id;
end
$$;

create function public.save_custom_church_role(target_org uuid, target_role uuid, role_name text, role_permissions text[])
returns uuid language plpgsql security definer set search_path = ''
as $$
declare saved_id uuid;
begin
 if not public.is_org_administrator(target_org) then raise exception 'Only organization administrators can manage roles.'; end if;
 if role_name is null or length(trim(role_name)) not between 2 and 120 then raise exception 'Role name must be between 2 and 120 characters.'; end if;
 if lower(trim(role_name)) in ('member','visitor','branch administrator','organization administrator') then raise exception 'That name is reserved for a built-in role.'; end if;
 if role_permissions is null or array_position(role_permissions, null) is not null or exists (
   select 1 from unnest(role_permissions) p where p <> all(array[
     'members.view','members.create','members.update','members.delete',
     'visitors.view','visitors.create','visitors.update','visitors.delete',
     'attendance.view','attendance.create'
   ]::text[])
 ) then raise exception 'One or more permissions are not supported.'; end if;
 if (role_permissions && array['members.create','members.update','members.delete']::text[] and not ('members.view'=any(role_permissions)))
   or (role_permissions && array['visitors.create','visitors.update','visitors.delete']::text[] and not ('visitors.view'=any(role_permissions)))
   or ('attendance.create'=any(role_permissions) and not ('attendance.view'=any(role_permissions))) then
   raise exception 'Select view access before granting create, edit or delete access for that area.';
 end if;
 if target_role is null then
   insert into public.roles(organization_id,name,permissions) values(target_org,trim(role_name),role_permissions) returning id into saved_id;
   insert into public.custom_church_roles(role_id,organization_id) values(saved_id,target_org);
 else
   update public.roles r set name=trim(role_name),permissions=role_permissions
   where r.id=target_role and r.organization_id=target_org
     and exists(select 1 from public.custom_church_roles c where c.role_id=r.id and c.organization_id=target_org)
   returning r.id into saved_id;
   if saved_id is null then raise exception 'Custom role not found in this church.'; end if;
 end if;
 return saved_id;
end
$$;

create function public.delete_custom_church_role(target_org uuid, target_role uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
 if not public.is_org_administrator(target_org) then raise exception 'Only organization administrators can manage roles.'; end if;
 if exists(select 1 from public.assignments a where a.role_id=target_role and a.organization_id=target_org) then
   raise exception 'Remove this role from all accounts before deleting it.';
 end if;
 delete from public.roles r where r.id=target_role and r.organization_id=target_org
   and exists(select 1 from public.custom_church_roles c where c.role_id=r.id and c.organization_id=target_org);
 if not found then raise exception 'Custom role not found in this church.'; end if;
end
$$;

create function public.custom_role_assignments(target_org uuid)
returns table (id uuid, role_id uuid, email text, branch_id uuid)
language plpgsql stable security definer set search_path = ''
as $$
begin
 if not public.is_org_administrator(target_org) then raise exception 'Only organization administrators can manage roles.'; end if;
 return query select a.id,a.role_id,u.email::text,a.branch_id
 from public.assignments a join public.custom_church_roles c on c.role_id=a.role_id and c.organization_id=a.organization_id
 join auth.users u on u.id=a.user_id where a.organization_id=target_org and a.active order by u.email,a.id limit 1000;
end
$$;

create function public.assign_custom_church_role(target_org uuid, target_role uuid, account_email text, target_branch uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare target_user uuid;
begin
 if not public.is_org_administrator(target_org) then raise exception 'Only organization administrators can assign roles.'; end if;
 if not exists(select 1 from public.custom_church_roles c where c.role_id=target_role and c.organization_id=target_org) then raise exception 'Custom role not found in this church.'; end if;
 if target_branch is not null and not exists(select 1 from public.branches b where b.id=target_branch and b.organization_id=target_org) then raise exception 'Branch does not belong to this church.'; end if;
 select u.id into target_user from auth.users u where lower(u.email)=lower(trim(account_email)) and u.email_confirmed_at is not null;
 if target_user is null then raise exception 'No confirmed account found for this email.'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(target_org::text || target_user::text,0));
 if not exists(select 1 from public.assignments a where a.user_id=target_user and a.organization_id=target_org and a.active) then raise exception 'This account must already have active access to the church.'; end if;
 if exists(select 1 from public.assignments a where a.user_id=target_user and a.organization_id=target_org and a.role_id=target_role and a.active and a.branch_id is not distinct from target_branch) then raise exception 'This account already has that role at this scope.'; end if;
 insert into public.assignments(user_id,organization_id,role_id,branch_id) values(target_user,target_org,target_role,target_branch);
end
$$;

create function public.remove_custom_role_assignment(target_org uuid, target_assignment uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare target_user uuid;
begin
 if not public.is_org_administrator(target_org) then raise exception 'Only organization administrators can remove roles.'; end if;
 select a.user_id into target_user from public.assignments a join public.custom_church_roles c
   on c.role_id=a.role_id and c.organization_id=a.organization_id
   where a.id=target_assignment and a.organization_id=target_org and a.active;
 if target_user is null then raise exception 'Custom role assignment not found.'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(target_org::text || target_user::text,0));
 if not exists(select 1 from public.assignments a where a.user_id=target_user and a.organization_id=target_org and a.active and a.id<>target_assignment) then
   raise exception 'Cannot remove the account’s last active church assignment.';
 end if;
 delete from public.assignments a where a.id=target_assignment and a.organization_id=target_org and a.active
   and exists(select 1 from public.custom_church_roles c where c.role_id=a.role_id and c.organization_id=a.organization_id);
 if not found then raise exception 'Custom role assignment not found.'; end if;
end
$$;

revoke all on function public.manageable_church_roles(uuid), public.save_custom_church_role(uuid,uuid,text,text[]),
 public.delete_custom_church_role(uuid,uuid), public.custom_role_assignments(uuid),
 public.assign_custom_church_role(uuid,uuid,text,uuid), public.remove_custom_role_assignment(uuid,uuid) from public, anon;
grant execute on function public.manageable_church_roles(uuid), public.save_custom_church_role(uuid,uuid,text,text[]),
 public.delete_custom_church_role(uuid,uuid), public.custom_role_assignments(uuid),
 public.assign_custom_church_role(uuid,uuid,text,uuid), public.remove_custom_role_assignment(uuid,uuid) to authenticated;
commit;
