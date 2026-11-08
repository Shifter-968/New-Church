-- Run only against an isolated test database after migrations through 010.
begin;
insert into public.organizations (id, name) values ('10000000-0000-4000-8000-000000000001', 'Church A');
insert into public.branches (id, organization_id, name) values
 ('11000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Main');
insert into public.members (id, organization_id, branch_id, first_name, last_name, email, date_of_birth, phone, phone_2) values
 ('30000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', 'Jane', 'Doe', 'jane@example.test', '1990-01-01', null, null),
 ('30000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', 'Sam', 'Roe', null, null, '11111111', '22222222'),
 ('30000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', 'Alice', 'Smith', null, null, null, null),
 ('30000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', 'Mary', 'Jones', null, null, '12345678', null),
 ('30000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', 'Alex', 'Brown', null, null, null, null),
 ('30000000-0000-4000-8000-000000000006', '10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', 'Alex', 'Brown', null, null, null, null),
 ('30000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', 'Peter', 'Wood', null, null, '44444444', '55555555');
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
 ('00000000-0000-4000-8000-000000000001', 'jane@example.test', now(), '{"individual_registration":{"organization_id":"10000000-0000-4000-8000-000000000001","branch_id":"11000000-0000-4000-8000-000000000001","first_name":"Jane","last_name":"Doe","person_type":"MEMBER","birth_date":"1990-01-01","phone":"123"}}'),
 ('00000000-0000-4000-8000-000000000002', 'attacker@example.test', now(), '{"individual_registration":{"organization_id":"10000000-0000-4000-8000-000000000001","branch_id":"11000000-0000-4000-8000-000000000001","first_name":"Jane","last_name":"Doe","person_type":"MEMBER","birth_date":"1990-01-01","phone":"123"}}'),
 ('00000000-0000-4000-8000-000000000003', 'visitor@example.test', now(), '{"individual_registration":{"organization_id":"10000000-0000-4000-8000-000000000001","branch_id":"11000000-0000-4000-8000-000000000001","first_name":"A","last_name":"Visitor","person_type":"VISITOR","birth_date":"1990-01-01","phone":"123"}}'),
 ('00000000-0000-4000-8000-000000000004', 'unconfirmed@example.test', null, '{"individual_registration":{"organization_id":"10000000-0000-4000-8000-000000000001","branch_id":"11000000-0000-4000-8000-000000000001","first_name":"A","last_name":"Visitor","person_type":"VISITOR","birth_date":"1990-01-01","phone":"123"}}'),
 ('00000000-0000-4000-8000-000000000005', 'sam@example.test', now(), '{"individual_registration":{"organization_id":"10000000-0000-4000-8000-000000000001","branch_id":"11000000-0000-4000-8000-000000000001","first_name":"Sam","last_name":"Roe","person_type":"MEMBER","birth_date":"1985-01-01","phone":"2222 2222"}}'),
 ('00000000-0000-4000-8000-000000000006', 'alice@example.test', now(), '{"individual_registration":{"organization_id":"10000000-0000-4000-8000-000000000001","branch_id":"11000000-0000-4000-8000-000000000001","first_name":"Alice","last_name":"Smith","person_type":"MEMBER","birth_date":"1985-01-01","phone":"99999999"}}'),
 ('00000000-0000-4000-8000-000000000007', 'mary@example.test', now(), '{"individual_registration":{"organization_id":"10000000-0000-4000-8000-000000000001","branch_id":"11000000-0000-4000-8000-000000000001","first_name":"Mary","last_name":"Jone","person_type":"MEMBER","birth_date":"1985-01-01","phone":"12345678"}}'),
 ('00000000-0000-4000-8000-000000000008', 'admin@example.test', now(), '{}'),
 ('00000000-0000-4000-8000-000000000009', 'alex@example.test', now(), '{"individual_registration":{"organization_id":"10000000-0000-4000-8000-000000000001","branch_id":"11000000-0000-4000-8000-000000000001","first_name":"Alex","last_name":"Brown","person_type":"MEMBER","birth_date":"1985-01-01","phone":"99999999"}}'),
 ('00000000-0000-4000-8000-000000000010', 'peter@example.test', now(), '{"individual_registration":{"organization_id":"10000000-0000-4000-8000-000000000001","branch_id":"11000000-0000-4000-8000-000000000001","first_name":"Peter","last_name":"Wood","person_type":"MEMBER","birth_date":"1985-01-01","phone":"99999999"}}');
insert into public.roles (id, organization_id, name, permissions) values
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Reviewer',array['members.update']);
insert into public.assignments (user_id,organization_id,branch_id,role_id) values
 ('00000000-0000-4000-8000-000000000008','10000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000002', true);
do $$ begin
 if public.complete_individual_registration() <> 'pending' then raise exception 'Email mismatch should require review'; end if;
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
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000005', true);
do $$ begin if public.complete_individual_registration() <> 'completed' then raise exception 'Second phone did not match'; end if; end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000006', true);
do $$ begin if public.complete_individual_registration() <> 'completed' then raise exception 'Missing fields prevented exact match'; end if; end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000007', true);
do $$ begin
 if public.complete_individual_registration() <> 'pending' then raise exception 'Near name did not require review'; end if;
 if exists (select 1 from public.assignments where user_id = auth.uid()) then raise exception 'Pending applicant has access'; end if;
 if exists (select 1 from public.list_member_registration_reviews('10000000-0000-4000-8000-000000000001')) then raise exception 'Applicant can view the review queue'; end if;
 begin
  perform public.review_member_registration(auth.uid(), '30000000-0000-4000-8000-000000000004', 'approved');
  raise exception 'Applicant approved their own request';
 exception when raise_exception then if sqlerrm = 'Applicant approved their own request' then raise; end if;
 end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000009', true);
do $$ begin if public.complete_individual_registration() <> 'pending' then raise exception 'Duplicate exact matches must require review'; end if; end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000010', true);
do $$ begin if public.complete_individual_registration() <> 'pending' then raise exception 'Phone mismatch must require review'; end if; end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000008', true);
do $$ begin
 if (select count(*) from public.list_member_registration_reviews('10000000-0000-4000-8000-000000000001') where applicant_id = '00000000-0000-4000-8000-000000000007') <> 1 then raise exception 'Reviewer cannot see candidate'; end if;
 if (select count(*) from public.list_member_registration_reviews('10000000-0000-4000-8000-000000000001') where applicant_id = '00000000-0000-4000-8000-000000000009') <> 2 then raise exception 'Duplicate candidates missing'; end if;
 if not exists (select 1 from public.list_member_registration_reviews('10000000-0000-4000-8000-000000000001') where applicant_id = '00000000-0000-4000-8000-000000000002' and member_id is null) then raise exception 'Stale request disappeared'; end if;
 perform public.review_member_registration('00000000-0000-4000-8000-000000000007', '30000000-0000-4000-8000-000000000004', 'approved');
 perform public.review_member_registration('00000000-0000-4000-8000-000000000010', null, 'rejected');
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000010', true);
do $$ begin if public.complete_individual_registration() <> 'rejected' then raise exception 'Rejected request did not remain rejected'; end if; end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000007', true);
do $$ begin if public.complete_individual_registration() <> 'completed' then raise exception 'Approved member could not finish registration'; end if; end $$;
reset role;
do $$ begin
 if not exists (select 1 from public.members where user_id = '00000000-0000-4000-8000-000000000001') then raise exception 'Member record not linked'; end if;
 if (select count(*) from public.visitors where user_id = '00000000-0000-4000-8000-000000000003') <> 1 then raise exception 'Visitor record missing or duplicated'; end if;
 if exists (select 1 from public.assignments a join public.roles r on r.id = a.role_id where a.user_id <> '00000000-0000-4000-8000-000000000008' and (r.is_org_admin or cardinality(r.permissions) <> 0)) then raise exception 'Individual received elevated privileges'; end if;
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
