-- Apply once after 027_manual_member_duplicates.sql.
begin;

create table public.church_update_notices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  announcement_id uuid unique references public.announcements(id) on delete cascade,
  event_id uuid unique references public.church_events(id) on delete cascade,
  created_at timestamptz not null default now(),
  check ((announcement_id is null) <> (event_id is null))
);
create index church_update_notices_created_idx on public.church_update_notices (created_at desc, id desc);
create table public.church_update_notice_reads (
  notice_id uuid not null references public.church_update_notices(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (notice_id, user_id)
);
alter table public.church_update_notices enable row level security;
alter table public.church_update_notice_reads enable row level security;
revoke all on public.church_update_notices, public.church_update_notice_reads from public, anon, authenticated;

create function public.create_church_update_notice()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_table_name = 'announcements' then
    insert into public.church_update_notices(organization_id,announcement_id) values(new.organization_id,new.id);
  else
    insert into public.church_update_notices(organization_id,event_id) values(new.organization_id,new.id);
  end if;
  return new;
end
$$;
revoke all on function public.create_church_update_notice() from public,anon,authenticated;
create trigger announcement_update_notice after insert on public.announcements
  for each row execute function public.create_church_update_notice();
create trigger event_update_notice after insert on public.church_events
  for each row execute function public.create_church_update_notice();

create function public.my_church_update_notices()
returns table (notice_id uuid, organization_id uuid, organization_name text, kind text,
  title text, created_at timestamptz, read_at timestamptz)
language sql stable security definer set search_path = ''
as $$
  select n.id,n.organization_id,o.name,
    case when n.announcement_id is not null then 'announcement' else 'event' end,
    coalesce(a.title,e.title),n.created_at,r.read_at
  from public.church_update_notices n
  join public.organizations o on o.id=n.organization_id
  left join public.announcements a on a.id=n.announcement_id and a.organization_id=n.organization_id
  left join public.church_events e on e.id=n.event_id and e.organization_id=n.organization_id
  left join public.church_update_notice_reads r on r.notice_id=n.id and r.user_id=auth.uid()
  where auth.uid() is not null and
    ((a.id is not null and public.audience_visible(a.organization_id,a.audience_everyone,a.audience_roles,a.audience_teams))
      or (e.id is not null and public.audience_visible(e.organization_id,e.audience_everyone,e.audience_roles,e.audience_teams)))
  order by n.created_at desc,n.id desc limit 100
$$;

create function public.mark_church_update_notices_read(notice_ids uuid[])
returns void language plpgsql security definer set search_path = ''
as $$
declare requested integer; visible integer;
begin
  if auth.uid() is null then raise exception 'Sign in to mark notices read.'; end if;
  if notice_ids is null or cardinality(notice_ids) not between 1 and 100
    or array_position(notice_ids,null) is not null then raise exception 'Select between 1 and 100 notices.'; end if;
  select count(distinct id) into requested from unnest(notice_ids) x(id);
  with visible_notices as materialized (
    select n.id from public.church_update_notices n
    left join public.announcements a on a.id=n.announcement_id and a.organization_id=n.organization_id
    left join public.church_events e on e.id=n.event_id and e.organization_id=n.organization_id
    where n.id=any(notice_ids)
      and ((a.id is not null and public.audience_visible(a.organization_id,a.audience_everyone,a.audience_roles,a.audience_teams))
        or (e.id is not null and public.audience_visible(e.organization_id,e.audience_everyone,e.audience_roles,e.audience_teams)))
  ), inserted as (
    insert into public.church_update_notice_reads(notice_id,user_id)
      select id,auth.uid() from visible_notices
      on conflict (notice_id,user_id) do nothing
      returning notice_id
  )
  select count(*) into visible from visible_notices;
  if visible <> requested then raise exception 'A notice is no longer available. Refresh your inbox.'; end if;
end
$$;
revoke all on function public.my_church_update_notices(), public.mark_church_update_notices_read(uuid[]) from public,anon;
grant execute on function public.my_church_update_notices(), public.mark_church_update_notices_read(uuid[]) to authenticated;
commit;
