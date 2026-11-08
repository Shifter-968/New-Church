-- Run only against an isolated test database after schema.sql, 002, 006, 007 and 008.
-- The test database must provide Supabase-compatible auth.users and auth.uid().
begin;
insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-4000-8000-000000000001', 'owner@example.test', now()),
 ('00000000-0000-4000-8000-000000000002', 'admin@example.test', now()),
 ('00000000-0000-4000-8000-000000000003', 'member@example.test', now()),
 ('00000000-0000-4000-8000-000000000004', 'other@example.test', now()),
 ('00000000-0000-4000-8000-000000000005', 'branch@example.test', now()),
 ('00000000-0000-4000-8000-000000000006', 'otherbranch@example.test', now());
insert into public.platform_owners values ('00000000-0000-4000-8000-000000000001');
insert into public.organizations (id, name) values
 ('10000000-0000-4000-8000-000000000001', 'Church A'),
 ('10000000-0000-4000-8000-000000000002', 'Church B');
insert into public.branches (id, organization_id, name) values
 ('11000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Branch A'),
 ('11000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', 'Other branch'),
 ('11000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', 'Branch B');
insert into public.roles (id, organization_id, name, is_org_admin) values
 ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Admin', true),
 ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', 'Member', false),
 ('20000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000002', 'Member', false);
insert into public.assignments (user_id, organization_id, branch_id, role_id) values
 ('00000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', null, '20000000-0000-4000-8000-000000000001'),
 ('00000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', null, '20000000-0000-4000-8000-000000000002'),
 ('00000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000002', null, '20000000-0000-4000-8000-000000000003'),
 ('00000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000002'),
 ('00000000-0000-4000-8000-000000000006', '10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000002');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
select public.save_connect_group(null, '10000000-0000-4000-8000-000000000001',
 '11000000-0000-4000-8000-000000000001', 'Test Connect', 'Testing', 'ACTIVE', 'member@example.test');
do $$
declare g record;
begin
 select * into g from public.list_connect_groups(null);
 if g.owner_id <> '00000000-0000-4000-8000-000000000003' or g.my_role is not null or g.join_code is not null or g.member_count <> 1 then
   raise exception 'Support owner was joined or assigned incorrectly';
 end if;
 begin
   perform public.save_connect_group(null, '10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000002', 'Wrong branch', '', 'ACTIVE', 'member@example.test');
   raise exception 'Cross-church branch accepted';
 exception when raise_exception then
   if sqlerrm = 'Cross-church branch accepted' then raise; end if;
 end;
 begin
   perform public.save_connect_group(null, '10000000-0000-4000-8000-000000000001', null, 'Wrong owner', '', 'ACTIVE', 'other@example.test');
   raise exception 'Cross-church owner accepted';
 exception when raise_exception then
   if sqlerrm = 'Cross-church owner accepted' then raise; end if;
 end;
 begin
   perform * from public.connect_groups;
   raise exception 'Direct table read allowed';
 exception when insufficient_privilege then null;
 end;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000003', true);
do $$
declare g record;
begin
 select * into g from public.list_connect_groups(null);
 if g.my_role <> 'CREATOR' or g.join_code is null then raise exception 'Creator membership missing'; end if;
 begin
   perform public.save_connect_group(g.id, g.organization_id, g.branch_id, g.name, g.description, 'SUSPENDED', '');
   raise exception 'Creator changed administrator-only status';
 exception when raise_exception then
   if sqlerrm = 'Creator changed administrator-only status' then raise; end if;
 end;
end $$;
select set_config('test.connect_code', (select join_code from public.list_connect_groups(null)), true);

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000006', true);
do $$ begin
 begin
   perform public.join_connect_group('10000000-0000-4000-8000-000000000001', current_setting('test.connect_code'));
   raise exception 'Wrong branch joined group';
 exception when raise_exception then
   if sqlerrm = 'Wrong branch joined group' then raise; end if;
 end;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000005', true);
do $$
declare code text;
begin
 if exists (select 1 from public.list_connect_groups(null)) then raise exception 'Non-member can browse groups'; end if;
 -- The test harness provides the join code as a setting, just as a creator would share it.
 code := current_setting('test.connect_code');
 perform public.join_connect_group('10000000-0000-4000-8000-000000000001', code);
 if not exists (select 1 from public.list_connect_groups(null) where my_role = 'MEMBER' and member_count = 2) then
   raise exception 'Eligible member could not join';
 end if;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000004', true);
do $$
begin
 if exists (select 1 from public.list_connect_groups(null)) then raise exception 'Other church can browse group'; end if;
 begin
   perform public.join_connect_group('10000000-0000-4000-8000-000000000001', current_setting('test.connect_code'));
   raise exception 'Other church joined group';
 exception when raise_exception then
   if sqlerrm = 'Other church joined group' then raise; end if;
 end;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000002', true);
do $$
declare g record;
begin
 select * into g from public.list_connect_groups(null);
 if g.join_code is not null then raise exception 'Non-member administrator can read join code'; end if;
 perform public.save_connect_group(g.id, g.organization_id, g.branch_id, 'Renamed', g.description, 'ACTIVE', 'admin@example.test');
 select * into g from public.list_connect_groups(null);
 if g.owner_id <> auth.uid() or g.my_role <> 'CREATOR' or g.member_count <> 3 then raise exception 'Owner transfer failed'; end if;
 perform public.delete_connect_group(g.id);
 if exists (select 1 from public.list_connect_groups(null)) then raise exception 'Delete failed'; end if;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
do $$ begin
 if (select count(*) from public.support_activity where resource_type = 'connect_groups') <> 3 then raise exception 'Connect audit incomplete'; end if;
end $$;
rollback;
