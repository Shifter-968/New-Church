-- Apply once after 003_organization_applications.sql.
begin;
create function public.assign_branch_administrator_by_email(org_id uuid, target_branch_id uuid, account_email text)
returns void language plpgsql security definer set search_path = ''
as $$
declare target_user_id uuid;
begin
  if not public.is_org_administrator(org_id) then
    raise exception 'Only an organization administrator or platform owner can assign branch administrators';
  end if;
  select id into target_user_id from auth.users
    where lower(email) = lower(trim(account_email)) and email_confirmed_at is not null;
  if target_user_id is null then
    raise exception 'No confirmed account found for this email. The person must create and confirm an account first.';
  end if;
  perform public.assign_branch_administrator(org_id, target_branch_id, target_user_id);
end
$$;
revoke all on function public.assign_branch_administrator_by_email(uuid, uuid, text) from public, anon;
grant execute on function public.assign_branch_administrator_by_email(uuid, uuid, text) to authenticated;
commit;
