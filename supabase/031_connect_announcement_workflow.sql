-- Apply once after 030_connect_announcements.sql.
begin;

alter table public.connect_announcements
  add column status text not null default 'PUBLISHED' check (status in ('DRAFT', 'PUBLISHED', 'ARCHIVED')),
  add column priority smallint not null default 0 check (priority between 0 and 2),
  add column pinned boolean not null default false,
  add column published_at timestamptz;
alter table public.connect_announcements disable trigger connect_announcement_activity;
update public.connect_announcements set published_at = created_at;
alter table public.connect_announcements enable trigger connect_announcement_activity;
alter table public.connect_announcements alter column published_at set default now();
alter table public.connect_announcements add constraint connect_announcements_published_at_check
  check (status <> 'PUBLISHED' or published_at is not null);
create index connect_announcements_board_idx on public.connect_announcements
  (connect_id, pinned desc, priority desc, created_at desc, id desc);

create or replace function public.save_connect_announcement(target_id uuid, announcement_id uuid, announcement_title text, announcement_content text)
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
    insert into public.connect_announcements(connect_id, author_id, title, content, published_at)
      values (target_id, auth.uid(), trim(announcement_title), trim(announcement_content), now()) returning id into saved_id;
  else
    update public.connect_announcements set title=trim(announcement_title), content=trim(announcement_content), edited_at=now()
      where id=announcement_id and connect_id=target_id returning id into saved_id;
    if not found then raise exception 'Announcement not found in this Connect.'; end if;
  end if;
  return saved_id;
end
$$;

-- Keep the previous endpoint safe for older clients.
create or replace function public.list_connect_announcements(target_id uuid)
returns table (id uuid, title text, content text, author_name text, created_at timestamptz, edited_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if public.connect_active_role(target_id) is null then raise exception 'Only active Connect members can read announcements.'; end if;
  return query select a.id, a.title, a.content,
    coalesce(nullif(trim(concat_ws(' ', p.first_name, p.last_name)), ''), 'Church member'),
    a.created_at, a.edited_at
  from public.connect_announcements a left join public.profiles p on p.user_id = a.author_id
  where a.connect_id = target_id and a.status = 'PUBLISHED'
  order by a.pinned desc, a.priority desc, a.created_at desc, a.id desc limit 100;
end
$$;

create function public.list_connect_announcement_board(target_id uuid)
returns table (id uuid, title text, content text, author_name text, created_at timestamptz,
  edited_at timestamptz, status text, priority smallint, pinned boolean, published_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
declare my_role text;
begin
  my_role := public.connect_active_role(target_id);
  if my_role is null then raise exception 'Only active Connect members can read announcements.'; end if;
  return query select a.id, a.title, a.content,
    coalesce(nullif(trim(concat_ws(' ', p.first_name, p.last_name)), ''), 'Church member'),
    a.created_at, a.edited_at, a.status, a.priority, a.pinned, a.published_at
  from public.connect_announcements a left join public.profiles p on p.user_id = a.author_id
  where a.connect_id = target_id and (a.status = 'PUBLISHED' or my_role in ('CREATOR', 'ADMIN'))
  order by a.pinned desc, a.priority desc, a.created_at desc, a.id desc limit 100;
end
$$;

create function public.save_connect_announcement_workflow(target_id uuid, announcement_id uuid,
  announcement_title text, announcement_content text, new_status text, new_priority smallint, new_pinned boolean)
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
  if new_status is null or new_status not in ('DRAFT', 'PUBLISHED', 'ARCHIVED')
    or new_priority is null or new_priority not between 0 and 2 or new_pinned is null then
    raise exception 'Choose a valid status, priority and pin setting.';
  end if;
  if announcement_id is null then
    insert into public.connect_announcements(connect_id, author_id, title, content, status, priority, pinned, published_at)
      values (target_id, auth.uid(), trim(announcement_title), trim(announcement_content), new_status, new_priority,
        new_pinned, case when new_status = 'PUBLISHED' then now() else null end) returning id into saved_id;
  else
    update public.connect_announcements set title=trim(announcement_title), content=trim(announcement_content),
      status=new_status, priority=new_priority, pinned=new_pinned, edited_at=now(),
      published_at=case when new_status = 'PUBLISHED' and status <> 'PUBLISHED' then now() else published_at end
      where id=announcement_id and connect_id=target_id returning id into saved_id;
    if not found then raise exception 'Announcement not found in this Connect.'; end if;
  end if;
  return saved_id;
end
$$;
revoke all on function public.list_connect_announcement_board(uuid),
  public.save_connect_announcement_workflow(uuid,uuid,text,text,text,smallint,boolean) from public, anon;
grant execute on function public.list_connect_announcement_board(uuid),
  public.save_connect_announcement_workflow(uuid,uuid,text,text,text,smallint,boolean) to authenticated;
commit;
