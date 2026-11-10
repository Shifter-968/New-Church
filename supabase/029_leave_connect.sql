-- Apply once after 028_church_update_notifications.sql.
begin;

create function public.leave_connect_group(target_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare group_row public.connect_groups%rowtype; membership public.connect_members%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in to leave a Connect.'; end if;
  select * into group_row from public.connect_groups c where c.id = target_id for update;
  if not found then raise exception 'Connect not found.'; end if;
  select * into membership from public.connect_members m
    where m.connect_id = target_id and m.user_id = auth.uid();
  if not found or membership.status <> 'ACTIVE' then
    raise exception 'You are not an active member of this Connect.';
  end if;
  if group_row.owner_id = auth.uid() or membership.role = 'CREATOR' then
    raise exception 'Transfer ownership before leaving this Connect.';
  end if;
  update public.connect_members set status = 'INACTIVE', role = 'MEMBER'
    where connect_id = target_id and user_id = auth.uid();
end
$$;
revoke all on function public.leave_connect_group(uuid) from public, anon;
grant execute on function public.leave_connect_group(uuid) to authenticated;

commit;
