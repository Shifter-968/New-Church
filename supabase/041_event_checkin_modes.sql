-- Apply once after 040_event_recurrence_and_locations.sql.
begin;

alter table public.church_events
  add column event_format text not null default 'physical',
  add constraint church_events_event_format_check check (event_format in ('physical', 'virtual'));

grant update (event_format) on public.church_events to authenticated;

drop function public.current_checkin_events(uuid);
create function public.current_checkin_events(target_org uuid)
returns table (
  event_id uuid,
  title text,
  starts_at timestamptz,
  ends_at timestamptz,
  branch_name text,
  already_checked_in boolean,
  event_format text,
  location text,
  location_configured boolean
)
language sql stable security definer set search_path = ''
as $$
  with person as (
    select m.id, m.branch_id, 'member'::text as kind
    from public.members m
    where m.organization_id = target_org and m.user_id = auth.uid() and m.status = 'active'
    union all
    select v.id, v.branch_id, 'visitor'::text
    from public.visitors v
    where v.organization_id = target_org and v.user_id = auth.uid()
  )
  select e.id, e.title, e.starts_at, e.ends_at, b.name,
    exists (
      select 1 from public.event_attendance a
      where a.event_id = e.id
        and ((p.kind = 'member' and a.member_id = p.id) or (p.kind = 'visitor' and a.visitor_id = p.id))
    ),
    e.event_format, e.location,
    e.event_format = 'virtual' or (e.location_latitude is not null and e.location_longitude is not null)
  from person p
  join public.branches b on b.id = p.branch_id and b.organization_id = target_org
  join public.church_events e on e.organization_id = target_org
  where (select count(*) from person) = 1
    and exists (
      select 1 from public.assignments a
      where a.user_id = auth.uid() and a.active and a.organization_id = target_org
        and (a.branch_id is null or a.branch_id = p.branch_id)
    )
    and e.starts_at <= now() and e.ends_at >= now()
    and public.audience_visible(e.organization_id, e.audience_everyone, e.audience_roles, e.audience_teams)
  order by e.starts_at, e.id
  limit 100
$$;

create or replace function public.self_check_in_unfiltered(
  target_event uuid,
  device_latitude double precision,
  device_longitude double precision
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  ev public.church_events%rowtype;
  person record;
  person_count integer;
  h double precision;
  distance double precision;
begin
  if auth.uid() is null then raise exception 'Sign in to check in.'; end if;
  select * into ev from public.church_events where id = target_event;
  if not found then raise exception 'Event not found.'; end if;
  if now() < ev.starts_at or now() > ev.ends_at then
    raise exception 'Check-in is only available while the event is ongoing.';
  end if;
  if ev.event_format = 'physical' then
    if ev.location_latitude is null or ev.location_longitude is null then
      raise exception 'This physical event has no map pin. Contact your church administrator.';
    end if;
    if device_latitude is null or device_longitude is null
      or device_latitude not between -90 and 90 or device_longitude not between -180 and 180 then
      raise exception 'A valid device location is required for this physical event.';
    end if;
  end if;
  select count(*) into person_count from (
    select id from public.members
    where organization_id = ev.organization_id and user_id = auth.uid() and status = 'active'
    union all
    select id from public.visitors
    where organization_id = ev.organization_id and user_id = auth.uid()
  ) p;
  if person_count <> 1 then
    raise exception 'An unambiguous linked member or visitor record is required. Contact your church administrator.';
  end if;
  select * into person from (
    select id, branch_id, 'member'::text as kind from public.members
    where organization_id = ev.organization_id and user_id = auth.uid() and status = 'active'
    union all
    select id, branch_id, 'visitor'::text from public.visitors
    where organization_id = ev.organization_id and user_id = auth.uid()
  ) p;
  if person.branch_id is null or not exists (
    select 1 from public.assignments a
    where a.user_id = auth.uid() and a.active and a.organization_id = ev.organization_id
      and (a.branch_id is null or a.branch_id = person.branch_id)
  ) then
    raise exception 'A valid branch assignment is required for check-in.';
  end if;
  if ev.event_format = 'physical' then
    h := power(sin(radians(device_latitude - ev.location_latitude) / 2), 2)
      + cos(radians(ev.location_latitude)) * cos(radians(device_latitude))
      * power(sin(radians(device_longitude - ev.location_longitude) / 2), 2);
    distance := 12742000 * asin(sqrt(least(1.0, greatest(0.0, h))));
    if distance > 100 then raise exception 'You are more than 100 m from the event location.'; end if;
  end if;
  insert into public.event_attendance (
    organization_id, event_id, branch_id, member_id, visitor_id, checked_in_by, method
  )
  values (
    ev.organization_id, ev.id, person.branch_id,
    case when person.kind = 'member' then person.id end,
    case when person.kind = 'visitor' then person.id end,
    auth.uid(), 'self'
  )
  on conflict do nothing;
  if not found then raise exception 'You are already checked in for this event.'; end if;
end
$$;

revoke all on function public.current_checkin_events(uuid) from public, anon;
grant execute on function public.current_checkin_events(uuid) to authenticated;

commit;
