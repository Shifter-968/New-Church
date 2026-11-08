-- Isolated PostgreSQL only, immediately after migration 014.
do $$ begin
 if not exists (select 1 from public.roles where organization_id = 'f1000000-0000-4000-8000-000000000001' and permissions = array['members.view','members.create','members.update','members.delete','visitors.view','visitors.create','visitors.update','visitors.delete','attendance.view','attendance.create']) then raise exception 'Standard branch role not upgraded'; end if;
 if not exists (select 1 from public.roles where organization_id = 'f1000000-0000-4000-8000-000000000002' and permissions = array['members.view']) then raise exception 'Custom branch role changed'; end if;
end $$;
delete from public.organizations where id in ('f1000000-0000-4000-8000-000000000001','f1000000-0000-4000-8000-000000000002');
