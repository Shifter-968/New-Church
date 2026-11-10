-- Apply once after 029_leave_connect.sql.
begin;

create table public.connect_announcements (
  id uuid primary key default gen_random_uuid(),
  connect_id uuid not null references public.connect_groups(id) on delete cascade,
  author_id uuid references auth.users(id) on delete set null,
  title text not null check (length(trim(title)) between 1 and 200),
  content text not null check (length(trim(content)) between 1 and 10000),
  created_at timestamptz not null default now(),
  edited_at timestamptz
);
create index connect_announcements_group_time_idx on public.connect_announcements (connect_id, created_at desc, id desc);
alter table public.connect_announcements enable row level security;
revoke all on public.connect_announcements from public, anon, authenticated;

create function public.record_connect_announcement_activity()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare org_id uuid;
begin
  select c.organization_id into org_id from public.connect_groups c where c.id = coalesce(new.connect_id, old.connect_id);
  if org_id is not null then
    insert into public.support_activity (organization_id, actor_id, resource_type, resource_id, action)
      values (org_id, auth.uid(), 'connect_announcements', coalesce(new.id, old.id), tg_op);
  end if;
  return coalesce(new, old);
end
$$;
revoke all on function public.record_connect_announcement_activity() from public, anon, authenticated;
create trigger connect_announcement_activity after insert or update or delete on public.connect_announcements
  for each row execute function public.record_connect_announcement_activity();

create function public.list_connect_announcements(target_id uuid)
returns table (id uuid, title text, content text, author_name text, created_at timestamptz, edited_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if public.connect_active_role(target_id) is null then raise exception 'Only active Connect members can read announcements.'; end if;
  return query select a.id, a.title, a.content,
    coalesce(nullif(trim(concat_ws(' ', p.first_name, p.last_name)), ''), 'Church member'),
    a.created_at, a.edited_at
  from public.connect_announcements a left join public.profiles p on p.user_id = a.author_id
  where a.connect_id = target_id order by a.created_at desc, a.id desc limit 100;
end
$$;

create function public.save_connect_announcement(target_id uuid, announcement_id uuid, announcement_title text, announcement_content text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare saved_id uuid; my_role text;
begin
  perform 1 from public.connect_groups c where c.id = target_id for update;
  my_role := public.connect_active_role(target_id);
  if my_role is null or my_role not in ('CREATOR', 'ADMIN') then
    raise exception 'Only active Connect creators and admins can manage announcements.';
  end if;
  if announcement_title is null or length(trim(announcement_title)) not between 1 and 200
    or announcement_content is null or length(trim(announcement_content)) not between 1 and 10000 then
    raise exception 'Enter a title and announcement within the allowed length.';
  end if;
  if announcement_id is null then
    insert into public.connect_announcements(connect_id, author_id, title, content)
      values (target_id, auth.uid(), trim(announcement_title), trim(announcement_content)) returning id into saved_id;
  else
    update public.connect_announcements set title=trim(announcement_title), content=trim(announcement_content), edited_at=now()
      where id=announcement_id and connect_id=target_id returning id into saved_id;
    if not found then raise exception 'Announcement not found in this Connect.'; end if;
  end if;
  return saved_id;
end
$$;

create function public.delete_connect_announcement(target_id uuid, announcement_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare my_role text;
begin
  perform 1 from public.connect_groups c where c.id=target_id for update;
  my_role := public.connect_active_role(target_id);
  if my_role is null or my_role not in ('CREATOR','ADMIN') then
    raise exception 'Only active Connect creators and admins can manage announcements.';
  end if;
  delete from public.connect_announcements where id=announcement_id and connect_id=target_id;
  if not found then raise exception 'Announcement not found in this Connect.'; end if;
end
$$;
revoke all on function public.list_connect_announcements(uuid), public.save_connect_announcement(uuid,uuid,text,text),
  public.delete_connect_announcement(uuid,uuid) from public, anon;
grant execute on function public.list_connect_announcements(uuid), public.save_connect_announcement(uuid,uuid,text,text),
  public.delete_connect_announcement(uuid,uuid) to authenticated;
commit;
