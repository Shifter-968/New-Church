-- Isolated test database only: run after migration 010 and before 011.
insert into public.organizations (id, name) values
 ('f0000000-0000-4000-8000-000000000001', 'Original role church'),
 ('f0000000-0000-4000-8000-000000000002', 'Custom role church');
insert into public.roles (organization_id, name, permissions) values
 ('f0000000-0000-4000-8000-000000000001', 'Branch Administrator', array['members.view','members.create','members.update','members.delete']),
 ('f0000000-0000-4000-8000-000000000002', 'Branch Administrator', array['members.view']);
