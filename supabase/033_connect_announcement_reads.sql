-- Apply once after 032_registration_payment_proof.sql.
begin;

alter table public.connect_announcements add column revision bigint not null default 1;
create function public.revise_connect_announcement()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.title is distinct from old.title or new.content is distinct from old.content
    or (new.status = 'PUBLISHED' and old.status <> 'PUBLISHED') then
    new.revision := old.revision + 1;
  end if;
  return new;
end
$$;
revoke all on function public.revise_connect_announcement() from public, anon, authenticated;
create trigger connect_announcement_revision before update on public.connect_announcements
  for each row execute function public.revise_connect_announcement();

create table public.connect_announcement_reads (
  announcement_id uuid not null references public.connect_announcements(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  revision bigint not null,
  read_at timestamptz not null default now(),
  primary key (announcement_id, user_id)
);
alter table public.connect_announcement_reads enable row level security;
revoke all on public.connect_announcement_reads from public, anon, authenticated;

create function public.my_connect_announcement_board(target_id uuid)
returns table (id uuid, title text, content text, author_name text, created_at timestamptz,
  edited_at timestamptz, status text, priority smallint, pinned boolean, published_at timestamptz,
  revision bigint, read_at timestamptz)
language sql stable security definer set search_path = ''
as $$
  select board.id, board.title, board.content, board.author_name, board.created_at,
    board.edited_at, board.status, board.priority, board.pinned, board.published_at,
    a.revision, case when r.revision = a.revision then r.read_at else null end
  from public.list_connect_announcement_board(target_id) board
  join public.connect_announcements a on a.id = board.id and a.connect_id = target_id
  left join public.connect_announcement_reads r on r.announcement_id = a.id and r.user_id = auth.uid()
  order by board.pinned desc, board.priority desc, board.created_at desc, board.id desc
$$;

create function public.mark_connect_announcement_read(target_id uuid, announcement_id uuid, expected_revision bigint)
returns void language plpgsql security definer set search_path = ''
as $$
declare my_role text; current_announcement public.connect_announcements%rowtype;
begin
  perform 1 from public.connect_groups c where c.id = target_id for update;
  my_role := public.connect_active_role(target_id);
  if my_role is null then raise exception 'Only active Connect members can mark announcements read.'; end if;
  select * into current_announcement from public.connect_announcements a
    where a.id = announcement_id and a.connect_id = target_id;
  if not found or (current_announcement.status <> 'PUBLISHED' and my_role not in ('CREATOR', 'ADMIN')) then
    raise exception 'Announcement is no longer available. Refresh the board.';
  end if;
  if expected_revision is null or expected_revision <> current_announcement.revision then
    raise exception 'Announcement changed. Refresh the board before marking it read.';
  end if;
  insert into public.connect_announcement_reads(announcement_id, user_id, revision, read_at)
    values(announcement_id, auth.uid(), current_announcement.revision, now())
    on conflict on constraint connect_announcement_reads_pkey
    do update set revision = excluded.revision, read_at = excluded.read_at;
end
$$;
revoke all on function public.my_connect_announcement_board(uuid),
  public.mark_connect_announcement_read(uuid, uuid, bigint) from public, anon;
grant execute on function public.my_connect_announcement_board(uuid),
  public.mark_connect_announcement_read(uuid, uuid, bigint) to authenticated;
commit;
