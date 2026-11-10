-- Apply once after 037_manual_plan_billing.sql.
begin;

create function public.enforce_single_active_assignment()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.active then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.user_id::text || ':active-assignment', 0));
    if exists (
      select 1 from public.assignments a
      where a.user_id = new.user_id and a.active and a.id is distinct from new.id
    ) then
      raise exception 'This account already has an active church or branch assignment. Use a different email for the additional account.';
    end if;
  end if;
  return new;
end
$$;
revoke all on function public.enforce_single_active_assignment() from public, anon, authenticated;
create trigger enforce_single_active_assignment before insert or update of user_id, active
  on public.assignments for each row execute function public.enforce_single_active_assignment();

commit;
