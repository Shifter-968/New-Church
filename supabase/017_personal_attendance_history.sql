-- Apply once after 016_custom_roles.sql.
begin;

create function public.my_attendance_history(target_org uuid)
returns table (event_id uuid, title text, starts_at timestamptz, ends_at timestamptz,
 branch_name text, checked_in_at timestamptz, method text)
language sql stable security definer set search_path = ''
as $$
 with person as (
   select m.id, m.branch_id, 'member'::text as kind
   from public.members m where m.organization_id=target_org and m.user_id=auth.uid() and m.status='active'
   union all
   select v.id, v.branch_id, 'visitor'::text
   from public.visitors v where v.organization_id=target_org and v.user_id=auth.uid()
 )
 select e.id,e.title,e.starts_at,e.ends_at,b.name,a.checked_in_at,a.method
 from person p
 join public.event_attendance a on a.organization_id=target_org
   and ((p.kind='member' and a.member_id=p.id) or (p.kind='visitor' and a.visitor_id=p.id))
 join public.church_events e on e.id=a.event_id and e.organization_id=target_org
 join public.branches b on b.id=a.branch_id and b.organization_id=target_org
 where (select count(*) from person)=1
   and exists (select 1 from public.assignments x where x.user_id=auth.uid() and x.active
     and x.organization_id=target_org and (x.branch_id is null or x.branch_id=p.branch_id))
   and public.audience_visible(e.organization_id,e.audience_everyone,e.audience_roles,e.audience_teams)
 order by a.checked_in_at desc,a.id desc limit 100
$$;
revoke all on function public.my_attendance_history(uuid) from public, anon;
grant execute on function public.my_attendance_history(uuid) to authenticated;
commit;
