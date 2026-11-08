-- Isolated PostgreSQL only, after migration 013 and before 014.
insert into public.organizations (id,name) values
 ('f1000000-0000-4000-8000-000000000001','Standard role'),
 ('f1000000-0000-4000-8000-000000000002','Custom role');
insert into public.roles (organization_id,name,permissions) values
 ('f1000000-0000-4000-8000-000000000001','Branch Administrator',array['members.view','members.create','members.update','members.delete','visitors.view','visitors.create','visitors.update','visitors.delete']),
 ('f1000000-0000-4000-8000-000000000002','Branch Administrator',array['members.view']);
