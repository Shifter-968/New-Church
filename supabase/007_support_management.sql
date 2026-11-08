-- Apply once after 006_my_church.sql.
begin;

create policy "administrators update church announcements" on public.announcements
  for update to authenticated using (public.is_org_administrator(organization_id))
  with check (public.is_org_administrator(organization_id));
create policy "administrators delete church announcements" on public.announcements
  for delete to authenticated using (public.is_org_administrator(organization_id));
revoke update on public.announcements from public, anon, authenticated;
grant update (title, content), delete on public.announcements to authenticated;

create policy "administrators update church events" on public.church_events
  for update to authenticated using (public.is_org_administrator(organization_id))
  with check (public.is_org_administrator(organization_id));
create policy "administrators delete church events" on public.church_events
  for delete to authenticated using (public.is_org_administrator(organization_id));
revoke update on public.church_events from public, anon, authenticated;
grant update (title, description, starts_at, ends_at, location), delete on public.church_events to authenticated;

create table public.support_activity (
  id bigint generated always as identity primary key,
  organization_id uuid not null,
  actor_id uuid,
  resource_type text not null,
  resource_id uuid not null,
  action text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  created_at timestamptz not null default now()
);
create index support_activity_created_idx on public.support_activity (created_at desc);
alter table public.support_activity enable row level security;
create policy "owners read support activity" on public.support_activity
  for select to authenticated using (public.is_platform_owner());
revoke all on public.support_activity from public, anon, authenticated;
grant select on public.support_activity to authenticated;

create function public.record_support_activity()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    insert into public.support_activity (organization_id, actor_id, resource_type, resource_id, action)
      values (old.organization_id, auth.uid(), tg_table_name, old.id, tg_op);
    return old;
  end if;
  insert into public.support_activity (organization_id, actor_id, resource_type, resource_id, action)
    values (new.organization_id, auth.uid(), tg_table_name, new.id, tg_op);
  return new;
end
$$;
revoke all on function public.record_support_activity() from public, anon, authenticated;
create trigger announcement_activity after insert or update or delete on public.announcements
  for each row execute function public.record_support_activity();
create trigger church_event_activity after insert or update or delete on public.church_events
  for each row execute function public.record_support_activity();
commit;
