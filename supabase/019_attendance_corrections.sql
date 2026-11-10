-- Apply once after 018_church_audit.sql.
begin;

create table public.attendance_corrections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  event_id uuid not null references public.church_events(id) on delete restrict,
  branch_id uuid not null,
  attendance_id uuid not null unique,
  member_id uuid references public.members(id) on delete restrict,
  visitor_id uuid references public.visitors(id) on delete restrict,
  checked_in_at timestamptz not null,
  checked_in_by uuid not null references auth.users(id),
  method text not null check (method in ('self', 'admin')),
  corrected_by uuid not null references auth.users(id),
  corrected_at timestamptz not null default now(),
  reason text not null check (length(trim(reason)) between 3 and 500),
  check ((member_id is null) <> (visitor_id is null)),
  foreign key (branch_id, organization_id) references public.branches(id, organization_id)
);
create index attendance_corrections_event_idx on public.attendance_corrections(organization_id, event_id, corrected_at desc, id desc);
alter table public.attendance_corrections enable row level security;
revoke all on public.attendance_corrections from public, anon, authenticated;

create function public.correct_attendance(target_org uuid, target_event uuid, target_attendance uuid, correction_reason text)
returns void language plpgsql security definer set search_path = ''
as $$
declare recorded public.event_attendance%rowtype;
begin
 if not public.is_org_administrator(target_org) then
   raise exception 'Only an organization administrator or platform owner can correct attendance.';
 end if;
 if correction_reason is null or length(trim(correction_reason)) not between 3 and 500 then
   raise exception 'Enter a correction reason between 3 and 500 characters.';
 end if;
 select a.* into recorded from public.event_attendance a
 where a.id=target_attendance and a.organization_id=target_org and a.event_id=target_event for update;
 if not found then raise exception 'Attendance record not found or already corrected. Refresh and try again.'; end if;
 if not exists (select 1 from public.church_events e where e.id=target_event and e.organization_id=target_org
   and public.audience_visible(e.organization_id,e.audience_everyone,e.audience_roles,e.audience_teams)) then
   raise exception 'This event is not available to your account.';
 end if;
 insert into public.attendance_corrections
   (organization_id,event_id,branch_id,attendance_id,member_id,visitor_id,checked_in_at,checked_in_by,method,corrected_by,reason)
 values (recorded.organization_id,recorded.event_id,recorded.branch_id,recorded.id,recorded.member_id,recorded.visitor_id,
   recorded.checked_in_at,recorded.checked_in_by,recorded.method,auth.uid(),trim(correction_reason));
 delete from public.event_attendance where id=recorded.id;
end
$$;

create function public.list_attendance_corrections(target_org uuid, target_event uuid)
returns table (id uuid, person_kind text, first_name text, last_name text, branch_id uuid,
 checked_in_at timestamptz, method text, corrected_at timestamptz, corrected_by uuid, reason text)
language plpgsql stable security definer set search_path = ''
as $$
begin
 if not public.is_org_administrator(target_org) then
   raise exception 'Only an organization administrator or platform owner can view corrections.';
 end if;
 if not exists (select 1 from public.church_events e where e.id=target_event and e.organization_id=target_org
   and public.audience_visible(e.organization_id,e.audience_everyone,e.audience_roles,e.audience_teams)) then
   raise exception 'This event is not available to your account.';
 end if;
 return query
 select c.id, case when c.member_id is not null then 'member' else 'visitor' end,
   coalesce(m.first_name,v.first_name),coalesce(m.last_name,v.last_name),c.branch_id,
   c.checked_in_at,c.method,c.corrected_at,c.corrected_by,c.reason
 from public.attendance_corrections c
 left join public.members m on m.id=c.member_id and m.organization_id=c.organization_id
 left join public.visitors v on v.id=c.visitor_id and v.organization_id=c.organization_id
 where c.organization_id=target_org and c.event_id=target_event
 order by c.corrected_at desc,c.id desc limit 100;
end
$$;
revoke all on function public.correct_attendance(uuid,uuid,uuid,text),
 public.list_attendance_corrections(uuid,uuid) from public, anon;
grant execute on function public.correct_attendance(uuid,uuid,uuid,text),
 public.list_attendance_corrections(uuid,uuid) to authenticated;
commit;
