-- Isolated test database only: run immediately after migration 011.
do $$ begin
 if not exists (select 1 from public.roles where organization_id = 'f0000000-0000-4000-8000-000000000001' and permissions = array['members.view','members.create','members.update','members.delete','visitors.view','visitors.create','visitors.update','visitors.delete']) then
  raise exception 'Original branch administrator role not upgraded';
 end if;
 if not exists (select 1 from public.roles where organization_id = 'f0000000-0000-4000-8000-000000000002' and permissions = array['members.view']) then
  raise exception 'Customized role changed';
 end if;
end $$;
delete from public.organizations where id in ('f0000000-0000-4000-8000-000000000001', 'f0000000-0000-4000-8000-000000000002');
