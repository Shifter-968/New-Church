-- Isolated PostgreSQL only, after migration 023.
begin;
insert into public.organizations(id,name) values
 ('a1000000-0000-4000-8000-000000000001','Church A'),
 ('a1000000-0000-4000-8000-000000000002','Church B');
insert into public.branches(id,organization_id,name) values
 ('a2000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','Main'),
 ('a2000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000001','Other');
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
select ('a3000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
  'person' || n || '@example.test', case when n=7 then null else now() end,
  jsonb_build_object('individual_registration',jsonb_build_object(
    'organization_id','a1000000-0000-4000-8000-000000000001',
    'branch_id','a2000000-0000-4000-8000-000000000001',
    'first_name',case when n in (1,2,4,7,8) then 'Returning' else 'New' end,
    'last_name',case when n in (1,2,4,7,8) then 'Visitor' else 'Person' end,
    'person_type','VISITOR','birth_date','1990-01-01','phone','12345678'))
from generate_series(1,8) n;
insert into auth.users(id,email,email_confirmed_at) values
 ('a3000000-0000-4000-8000-000000000009','admin@example.test',now()),
 ('a3000000-0000-4000-8000-000000000010','branch@example.test',now()),
 ('a3000000-0000-4000-8000-000000000011','other@example.test',now());
insert into public.roles(id,organization_id,name,is_org_admin,permissions) values
 ('a4000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','Admin',true,'{}'),
 ('a4000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000001','Visitor reviewer',false,array['visitors.view','visitors.update']),
 ('a4000000-0000-4000-8000-000000000003','a1000000-0000-4000-8000-000000000002','Admin',true,'{}');
insert into public.assignments(user_id,organization_id,branch_id,role_id) values
 ('a3000000-0000-4000-8000-000000000009','a1000000-0000-4000-8000-000000000001',null,'a4000000-0000-4000-8000-000000000001'),
 ('a3000000-0000-4000-8000-000000000010','a1000000-0000-4000-8000-000000000001','a2000000-0000-4000-8000-000000000002','a4000000-0000-4000-8000-000000000002'),
 ('a3000000-0000-4000-8000-000000000011','a1000000-0000-4000-8000-000000000002',null,'a4000000-0000-4000-8000-000000000003');
insert into public.visitors(id,organization_id,branch_id,first_name,last_name,phone) values
 ('a5000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','a2000000-0000-4000-8000-000000000001','Returning','Visitor','1234 5678');
insert into public.church_events(id,organization_id,title,starts_at,ends_at,created_by) values
 ('a6000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','Past service',now()-interval '2 days',now()-interval '1 day','a3000000-0000-4000-8000-000000000009');
insert into public.event_attendance(organization_id,event_id,branch_id,visitor_id,checked_in_by,method) values
 ('a1000000-0000-4000-8000-000000000001','a6000000-0000-4000-8000-000000000001','a2000000-0000-4000-8000-000000000001','a5000000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000009','admin');
set local role authenticated;
select set_config('request.jwt.claim.sub','a3000000-0000-4000-8000-000000000001',true);
do $$ begin
 if public.complete_individual_registration() <> 'pending' or public.complete_individual_registration() <> 'pending' then raise exception 'Matching visitor should be pending'; end if;
 begin perform public.complete_individual_registration_before_visitor_review(); raise exception 'Legacy function accessible'; exception when insufficient_privilege then null; end;
 begin perform public.review_visitor_registration(auth.uid(),'a5000000-0000-4000-8000-000000000001','approved'); raise exception 'Applicant approved own request'; exception when raise_exception then if sqlerrm='Applicant approved own request' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','a3000000-0000-4000-8000-000000000007',true);
do $$ begin
 begin perform public.complete_individual_registration(); raise exception 'Unconfirmed user registered'; exception when raise_exception then if sqlerrm='Unconfirmed user registered' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','a3000000-0000-4000-8000-000000000010',true);
do $$ begin
 if exists(select 1 from public.list_visitor_registration_reviews('a1000000-0000-4000-8000-000000000001')) then raise exception 'Other branch saw review'; end if;
 begin perform public.review_visitor_registration('a3000000-0000-4000-8000-000000000001','a5000000-0000-4000-8000-000000000001','approved'); raise exception 'Other branch approved review'; exception when raise_exception then if sqlerrm='Other branch approved review' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','a3000000-0000-4000-8000-000000000011',true);
do $$ begin if exists(select 1 from public.list_visitor_registration_reviews('a1000000-0000-4000-8000-000000000001')) then raise exception 'Other church saw review'; end if; end $$;
select set_config('request.jwt.claim.sub','a3000000-0000-4000-8000-000000000009',true);
do $$ begin
 if not exists(select 1 from public.list_visitor_registration_reviews('a1000000-0000-4000-8000-000000000001') where visitor_id='a5000000-0000-4000-8000-000000000001') then raise exception 'Candidate missing'; end if;
 begin perform public.review_visitor_registration('a3000000-0000-4000-8000-000000000001',gen_random_uuid(),'approved'); raise exception 'Noncandidate approved'; exception when raise_exception then if sqlerrm='Noncandidate approved' then raise; end if; end;
 perform public.review_visitor_registration('a3000000-0000-4000-8000-000000000001','a5000000-0000-4000-8000-000000000001','approved');
end $$;
select set_config('request.jwt.claim.sub','a3000000-0000-4000-8000-000000000001',true);
do $$ begin
 if public.complete_individual_registration() <> 'completed' or public.complete_individual_registration() <> 'completed' then raise exception 'Approved visitor did not complete'; end if;
 if (select count(*) from public.my_attendance_history('a1000000-0000-4000-8000-000000000001')) <> 1 then raise exception 'Prior attendance missing'; end if;
 if (select count(*) from public.assignments where user_id=auth.uid()) <> 1 then raise exception 'Visitor assignment duplicated'; end if;
end $$;
select set_config('request.jwt.claim.sub','a3000000-0000-4000-8000-000000000002',true);
do $$ begin if public.complete_individual_registration() <> 'pending' then raise exception 'Linked possible match should be reviewed'; end if; end $$;
select set_config('request.jwt.claim.sub','a3000000-0000-4000-8000-000000000009',true);
select public.review_visitor_registration('a3000000-0000-4000-8000-000000000002',null,'new');
select set_config('request.jwt.claim.sub','a3000000-0000-4000-8000-000000000002',true);
do $$ begin if public.complete_individual_registration() <> 'completed' then raise exception 'Different person not registered'; end if; end $$;
select set_config('request.jwt.claim.sub','a3000000-0000-4000-8000-000000000004',true);
do $$ begin if public.complete_individual_registration() <> 'pending' then raise exception 'Matching visitor should be pending'; end if; end $$;
select set_config('request.jwt.claim.sub','a3000000-0000-4000-8000-000000000009',true);
select public.review_visitor_registration('a3000000-0000-4000-8000-000000000004',null,'rejected');
select set_config('request.jwt.claim.sub','a3000000-0000-4000-8000-000000000004',true);
do $$ begin if public.complete_individual_registration() <> 'rejected' then raise exception 'Rejected request registered'; end if; end $$;
-- A genuinely new visitor with no match follows the original registration path.
reset role;
update auth.users set raw_user_meta_data=jsonb_set(raw_user_meta_data,'{individual_registration,phone}','"99999999"') where id='a3000000-0000-4000-8000-000000000003';
set local role authenticated;
select set_config('request.jwt.claim.sub','a3000000-0000-4000-8000-000000000003',true);
do $$ begin if public.complete_individual_registration() <> 'completed' then raise exception 'New visitor did not register'; end if; end $$;
reset role;
insert into public.visitors(id,organization_id,branch_id,first_name,last_name,phone) values
 ('a5000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000001','a2000000-0000-4000-8000-000000000001','Another','Visitor','12345678');
set local role authenticated;
select set_config('request.jwt.claim.sub','a3000000-0000-4000-8000-000000000005',true);
do $$ begin if public.complete_individual_registration() <> 'pending' then raise exception 'Phone candidate missing'; end if; end $$;
select set_config('request.jwt.claim.sub','a3000000-0000-4000-8000-000000000006',true);
do $$ begin if public.complete_individual_registration() <> 'pending' then raise exception 'Second request missing'; end if; end $$;
select set_config('request.jwt.claim.sub','a3000000-0000-4000-8000-000000000009',true);
do $$ begin
 perform public.review_visitor_registration('a3000000-0000-4000-8000-000000000005','a5000000-0000-4000-8000-000000000002','approved');
 begin perform public.review_visitor_registration('a3000000-0000-4000-8000-000000000006','a5000000-0000-4000-8000-000000000002','approved'); raise exception 'Reserved visitor approved twice'; exception when raise_exception then if sqlerrm='Reserved visitor approved twice' then raise; end if; end;
end $$;
reset role;
delete from public.visitors where id='a5000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','a3000000-0000-4000-8000-000000000005',true);
do $$ begin
 begin perform public.complete_individual_registration(); raise exception 'Deleted approved record created a new visitor'; exception when raise_exception then if sqlerrm='Deleted approved record created a new visitor' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','a3000000-0000-4000-8000-000000000008',true);
do $$ begin if public.complete_individual_registration() <> 'pending' then raise exception 'Expected review'; end if; end $$;
select set_config('request.jwt.claim.sub','a3000000-0000-4000-8000-000000000009',true);
select public.review_visitor_registration('a3000000-0000-4000-8000-000000000008',null,'new');
reset role;
update auth.users set email='changed@example.test' where id='a3000000-0000-4000-8000-000000000008';
set local role authenticated;
select set_config('request.jwt.claim.sub','a3000000-0000-4000-8000-000000000008',true);
do $$ begin
 begin perform public.complete_individual_registration(); raise exception 'Changed email accepted'; exception when raise_exception then if sqlerrm='Changed email accepted' then raise; end if; end;
end $$;
rollback;
