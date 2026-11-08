-- Apply once after 008_connect_groups.sql.
begin;

alter table public.connect_members drop constraint connect_members_role_check;
alter table public.connect_members add constraint connect_members_role_check
  check (role in ('CREATOR', 'ADMIN', 'MEMBER'));

create table public.connect_messages (
  id uuid primary key default gen_random_uuid(),
  connect_id uuid not null references public.connect_groups(id) on delete cascade,
  sender_id uuid references auth.users(id) on delete set null,
  content text,
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz,
  deleted_by uuid references auth.users(id) on delete set null,
  check ((deleted_at is null and content is not null and length(trim(content)) between 1 and 10000)
    or (deleted_at is not null and content is null))
);
create index connect_messages_group_time_idx on public.connect_messages (connect_id, created_at desc, id desc);
alter table public.connect_messages enable row level security;
revoke all on public.connect_messages from public, anon, authenticated;

create function public.record_connect_activity()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare org_id uuid; recorded_id uuid;
begin
  select c.organization_id into org_id from public.connect_groups c where c.id = new.connect_id;
  if tg_table_name = 'connect_members' then recorded_id := new.connect_id;
  else recorded_id := new.id; end if;
  insert into public.support_activity (organization_id, actor_id, resource_type, resource_id, action)
    values (org_id, auth.uid(), tg_table_name, recorded_id, tg_op);
  return new;
end
$$;
revoke all on function public.record_connect_activity() from public, anon, authenticated;
create trigger connect_member_activity after insert or update on public.connect_members
  for each row execute function public.record_connect_activity();
create trigger connect_message_activity after insert or update on public.connect_messages
  for each row execute function public.record_connect_activity();

create function public.connect_active_role(target_id uuid)
returns text language sql stable security definer set search_path = ''
as $$
  select m.role from public.connect_groups c
  join public.connect_members m on m.connect_id = c.id and m.user_id = auth.uid()
  where c.id = target_id and c.status = 'ACTIVE' and m.status = 'ACTIVE'
    and public.connect_has_assignment(auth.uid(), c.organization_id, c.branch_id)
$$;
revoke all on function public.connect_active_role(uuid) from public, anon, authenticated;

create function public.list_connect_members(target_id uuid)
returns table (user_id uuid, display_name text, email text, role text, status text, joined_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
declare group_row public.connect_groups%rowtype; my_role text; support boolean;
begin
  select * into group_row from public.connect_groups c where c.id = target_id;
  if not found then raise exception 'Connect not found.'; end if;
  my_role := public.connect_active_role(target_id);
  support := public.is_org_administrator(group_row.organization_id);
  if my_role is null and not support then raise exception 'You cannot view this Connect membership.'; end if;
  return query select m.user_id,
    coalesce(nullif(trim(concat_ws(' ', p.first_name, p.last_name)), ''), 'Church member'),
    case when my_role = 'CREATOR' or support or m.user_id = auth.uid() then u.email::text else null end,
    m.role, m.status, m.joined_at
  from public.connect_members m join auth.users u on u.id = m.user_id
  left join public.profiles p on p.user_id = m.user_id
  where m.connect_id = target_id and (m.status = 'ACTIVE' or my_role = 'CREATOR' or support)
  order by case m.role when 'CREATOR' then 0 when 'ADMIN' then 1 else 2 end, m.joined_at, m.user_id;
end
$$;

create function public.add_connect_member(target_id uuid, account_email text)
returns void language plpgsql security definer set search_path = ''
as $$
declare group_row public.connect_groups%rowtype; chosen_user uuid; existing public.connect_members%rowtype;
begin
  select * into group_row from public.connect_groups c where c.id = target_id for update;
  if not found then raise exception 'Connect not found.'; end if;
  if group_row.status <> 'ACTIVE' then raise exception 'Only active Connects can accept members.'; end if;
  if public.connect_active_role(target_id) is distinct from 'CREATOR'
    and not public.is_org_administrator(group_row.organization_id) then
    raise exception 'Only the Connect creator or a church administrator can add members.';
  end if;
  select u.id into chosen_user from auth.users u
    where lower(u.email) = lower(trim(account_email)) and u.email_confirmed_at is not null;
  if chosen_user is null or not public.connect_has_assignment(chosen_user, group_row.organization_id, group_row.branch_id) then
    raise exception 'The account must be confirmed and actively assigned to this church and branch.';
  end if;
  select * into existing from public.connect_members m where m.connect_id = target_id and m.user_id = chosen_user;
  if found and existing.status = 'ACTIVE' then raise exception 'This person is already a member.'; end if;
  insert into public.connect_members (connect_id, user_id, role, status)
    values (target_id, chosen_user, 'MEMBER', 'ACTIVE')
    on conflict (connect_id, user_id) do update set role = 'MEMBER', status = 'ACTIVE', joined_at = now();
end
$$;

create function public.manage_connect_member(target_id uuid, target_user uuid, new_role text, new_status text)
returns void language plpgsql security definer set search_path = ''
as $$
declare group_row public.connect_groups%rowtype; membership public.connect_members%rowtype; my_role text;
begin
  select * into group_row from public.connect_groups c where c.id = target_id for update;
  if not found then raise exception 'Connect not found.'; end if;
  my_role := public.connect_active_role(target_id);
  if my_role is distinct from 'CREATOR' and not public.is_org_administrator(group_row.organization_id) then
    raise exception 'Only the Connect creator or a church administrator can manage members.';
  end if;
  select * into membership from public.connect_members m where m.connect_id = target_id and m.user_id = target_user;
  if not found then raise exception 'Membership not found.'; end if;
  if membership.role = 'CREATOR' or target_user = group_row.owner_id then
    raise exception 'Transfer ownership before changing the creator.';
  end if;
  if new_role is null or new_role not in ('ADMIN', 'MEMBER') or new_status is null or new_status not in ('ACTIVE', 'INACTIVE', 'BANNED') then
    raise exception 'Invalid membership role or status.';
  end if;
  if (new_role is distinct from membership.role) and my_role is distinct from 'CREATOR' then
    raise exception 'Only the Connect creator can assign or change group administrator roles.';
  end if;
  if new_status = 'ACTIVE' and not public.connect_has_assignment(target_user, group_row.organization_id, group_row.branch_id) then
    raise exception 'The person no longer has an eligible church assignment.';
  end if;
  if new_status <> 'ACTIVE' then new_role := 'MEMBER'; end if;
  update public.connect_members set role = new_role, status = new_status
    where connect_id = target_id and user_id = target_user;
end
$$;

create function public.list_connect_messages(target_id uuid)
returns table (id uuid, sender_id uuid, sender_name text, content text, created_at timestamptz, edited_at timestamptz, deleted_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if public.connect_active_role(target_id) is null then raise exception 'Only active Connect members can read messages.'; end if;
  return query select recent.id, recent.sender_id,
    coalesce(nullif(trim(concat_ws(' ', p.first_name, p.last_name)), ''), 'Church member'),
    recent.content, recent.created_at, recent.edited_at, recent.deleted_at
  from (select m.* from public.connect_messages m where m.connect_id = target_id
    order by m.created_at desc, m.id desc limit 100) recent
  left join public.profiles p on p.user_id = recent.sender_id
  order by recent.created_at, recent.id;
end
$$;

create function public.send_connect_message(target_id uuid, message_text text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare message_id uuid;
begin
  perform 1 from public.connect_groups c where c.id = target_id for update;
  if public.connect_active_role(target_id) is null then raise exception 'Only active Connect members can send messages.'; end if;
  insert into public.connect_messages (connect_id, sender_id, content)
    values (target_id, auth.uid(), trim(message_text)) returning id into message_id;
  return message_id;
end
$$;

create function public.edit_connect_message(target_id uuid, message_id uuid, message_text text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform 1 from public.connect_groups c where c.id = target_id for update;
  if public.connect_active_role(target_id) is null then raise exception 'Only active Connect members can edit messages.'; end if;
  update public.connect_messages set content = trim(message_text), edited_at = now()
    where id = message_id and connect_id = target_id and sender_id = auth.uid() and deleted_at is null;
  if not found then raise exception 'Message not found or you cannot edit it.'; end if;
end
$$;

create function public.delete_connect_message(target_id uuid, message_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare my_role text;
begin
  perform 1 from public.connect_groups c where c.id = target_id for update;
  my_role := public.connect_active_role(target_id);
  if my_role is null then raise exception 'Only active Connect members can delete messages.'; end if;
  update public.connect_messages set content = null, deleted_at = now(), deleted_by = auth.uid()
    where id = message_id and connect_id = target_id and deleted_at is null
      and (sender_id = auth.uid() or my_role in ('CREATOR', 'ADMIN'));
  if not found then raise exception 'Message not found or you cannot delete it.'; end if;
end
$$;

revoke all on function public.list_connect_members(uuid), public.add_connect_member(uuid, text),
  public.manage_connect_member(uuid, uuid, text, text), public.list_connect_messages(uuid),
  public.send_connect_message(uuid, text), public.edit_connect_message(uuid, uuid, text),
  public.delete_connect_message(uuid, uuid) from public, anon;
grant execute on function public.list_connect_members(uuid), public.add_connect_member(uuid, text),
  public.manage_connect_member(uuid, uuid, text, text), public.list_connect_messages(uuid),
  public.send_connect_message(uuid, text), public.edit_connect_message(uuid, uuid, text),
  public.delete_connect_message(uuid, uuid) to authenticated;
commit;
