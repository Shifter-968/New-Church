-- Run only against an isolated test database after migrations through 010.
begin;
insert into public.organizations (id, name) values ('10000000-0000-4000-8000-000000000001', 'Church A');
insert into public.branches (id, organization_id, name) values
 ('11000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Main');
insert into public.members (id, organization_id, branch_id, first_name, last_name, email, date_of_birth) values
 ('30000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', 'Jane', 'Doe', 'jane@example.test', '1990-01-01');
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
 ('00000000-0000-4000-8000-000000000001', 'jane@example.test', now(), '{"individual_registration":{"organization_id":"10000000-0000-4000-8000-000000000001","branch_id":"11000000-0000-4000-8000-000000000001","first_name":"Jane","last_name":"Doe","person_type":"MEMBER","birth_date":"1990-01-01","phone":"123"}}'),
 ('00000000-0000-4000-8000-000000000002', 'attacker@example.test', now(), '{"individual_registration":{"organization_id":"10000000-0000-4000-8000-000000000001","branch_id":"11000000-0000-4000-8000-000000000001","first_name":"Jane","last_name":"Doe","person_type":"MEMBER","birth_date":"1990-01-01","phone":"123"}}'),
 ('00000000-0000-4000-8000-000000000003', 'visitor@example.test', now(), '{"individual_registration":{"organization_id":"10000000-0000-4000-8000-000000000001","branch_id":"11000000-0000-4000-8000-000000000001","first_name":"A","last_name":"Visitor","person_type":"VISITOR","birth_date":"1990-01-01","phone":"123"}}'),
 ('00000000-0000-4000-8000-000000000004', 'unconfirmed@example.test', null, '{"individual_registration":{"organization_id":"10000000-0000-4000-8000-000000000001","branch_id":"11000000-0000-4000-8000-000000000001","first_name":"A","last_name":"Visitor","person_type":"VISITOR","birth_date":"1990-01-01","phone":"123"}}');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000002', true);
do $$ begin
 begin
  perform public.complete_individual_registration();
  raise exception 'Incorrect email matched member';
 exception when raise_exception then if sqlerrm = 'Incorrect email matched member' then raise; end if;
 end;
 begin
  update public.members set user_id = auth.uid();
  raise exception 'Direct member linking permitted';
 exception when insufficient_privilege then null;
 end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000004', true);
do $$ begin
 begin
  perform public.complete_individual_registration();
  raise exception 'Unconfirmed user registered';
 exception when raise_exception then if sqlerrm = 'Unconfirmed user registered' then raise; end if;
 end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
select public.complete_individual_registration();
select public.complete_individual_registration();
do $$ begin
 if (select count(*) from public.assignments where user_id = auth.uid()) <> 1 then raise exception 'Member assignment missing or duplicated'; end if;
 if not exists (select 1 from public.profiles where user_id = auth.uid() and first_name = 'Jane') then raise exception 'Profile missing'; end if;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000003', true);
select public.complete_individual_registration();
select public.complete_individual_registration();
do $$ begin
 if (select count(*) from public.assignments where user_id = auth.uid()) <> 1 then raise exception 'Visitor assignment missing or duplicated'; end if;
end $$;
reset role;
do $$ begin
 if not exists (select 1 from public.members where user_id = '00000000-0000-4000-8000-000000000001') then raise exception 'Member record not linked'; end if;
 if (select count(*) from public.visitors where user_id = '00000000-0000-4000-8000-000000000003') <> 1 then raise exception 'Visitor record missing or duplicated'; end if;
 if exists (select 1 from public.assignments a join public.roles r on r.id = a.role_id where r.is_org_admin or cardinality(r.permissions) <> 0) then raise exception 'Individual received elevated privileges'; end if;
 begin
  update public.members set status = 'inactive' where user_id = '00000000-0000-4000-8000-000000000001';
  raise exception 'Linked member status change left access active';
 exception when raise_exception then if sqlerrm = 'Linked member status change left access active' then raise; end if;
 end;
 begin
  delete from public.members where user_id = '00000000-0000-4000-8000-000000000001';
  raise exception 'Linked member deletion left access active';
 exception when raise_exception then if sqlerrm = 'Linked member deletion left access active' then raise; end if;
 end;
end $$;
rollback;
