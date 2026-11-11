-- Run only against an isolated test database after migrations through 042.
begin;
insert into public.organizations(id,name) values ('c1000000-0000-4000-8000-000000000001','Match church');
insert into public.branches(id,organization_id,name) values
 ('c2000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','Main'),
 ('c2000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000001','Other');
insert into public.members(id,organization_id,branch_id,first_name,last_name,phone,phone_2,email,date_of_birth) values
 ('c3000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001','Exact','Person','011 234','022-333','different@example.test','1980-01-01'),
 ('c3000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001','Missing','Phone',null,null,null,null),
 ('c3000000-0000-4000-8000-000000000003','c1000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001','Wrong','Phone','444444',null,null,null),
 ('c3000000-0000-4000-8000-000000000004','c1000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001','Actual','Member','555555',null,null,null),
 ('c3000000-0000-4000-8000-000000000005','c1000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001','Double','Member','666666',null,null,null),
 ('c3000000-0000-4000-8000-000000000006','c1000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001','Double','Member','666666',null,null,null),
 ('c3000000-0000-4000-8000-000000000007','c1000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000002','Other','Branch','777777',null,null,null);
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
select id, id::text || '@example.test', now(), jsonb_build_object('individual_registration',jsonb_build_object(
 'organization_id','c1000000-0000-4000-8000-000000000001',
 'branch_id','c2000000-0000-4000-8000-000000000001',
 'person_type','MEMBER','first_name',first_name,'last_name',last_name,'birth_date','1990-01-01','phone',phone,'phone_2',phone_2))
from (values
 ('c4000000-0000-4000-8000-000000000001'::uuid,'Exact Middle Names','Person','022333','011234'),
 ('c4000000-0000-4000-8000-000000000002'::uuid,'Missing','Phone','111111',null),
 ('c4000000-0000-4000-8000-000000000003'::uuid,'Wrong','Phone','222222',null),
 ('c4000000-0000-4000-8000-000000000004'::uuid,'Completely','Different','333333',null),
 ('c4000000-0000-4000-8000-000000000005'::uuid,'Double','Member','666666',null),
 ('c4000000-0000-4000-8000-000000000006'::uuid,'Actual','Membr','555555',null)
) fixtures(id,first_name,last_name,phone,phone_2);
insert into auth.users(id,email,email_confirmed_at) values
 ('c4000000-0000-4000-8000-000000000010','reviewer@example.test',now()),
 ('c4000000-0000-4000-8000-000000000011','other-reviewer@example.test',now());
insert into public.roles(id,organization_id,name,permissions) values
 ('c5000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','Reviewer',array['members.view','members.update']);
insert into public.assignments(user_id,organization_id,branch_id,role_id) values
 ('c4000000-0000-4000-8000-000000000010','c1000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001','c5000000-0000-4000-8000-000000000001'),
 ('c4000000-0000-4000-8000-000000000011','c1000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000002','c5000000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claim.sub','c4000000-0000-4000-8000-000000000001',true);
do $$ begin
 if public.complete_individual_registration() <> 'completed' then raise exception 'Matching name and second phone did not link'; end if;
 if public.complete_individual_registration() <> 'completed' then raise exception 'Completion not idempotent'; end if;
end $$;
select set_config('request.jwt.claim.sub','c4000000-0000-4000-8000-000000000002',true);
do $$ begin
 begin
  perform public.complete_individual_registration();
  raise exception 'Missing saved member phone was not reported';
 exception when raise_exception then
  if sqlerrm = 'Missing saved member phone was not reported' then raise; end if;
  if position('contact your church administrators' in lower(sqlerrm)) = 0 then raise; end if;
 end;
end $$;
select set_config('request.jwt.claim.sub','c4000000-0000-4000-8000-000000000003',true);
do $$ begin if public.complete_individual_registration() <> 'pending' then raise exception 'Phone mismatch did not require review'; end if; end $$;
select set_config('request.jwt.claim.sub','c4000000-0000-4000-8000-000000000004',true);
do $$ begin if public.complete_individual_registration() <> 'pending' then raise exception 'No match did not require review'; end if; end $$;
reset role;
update auth.users set raw_user_meta_data=jsonb_set(raw_user_meta_data,'{individual_registration,person_type}','"VISITOR"')
 where id='c4000000-0000-4000-8000-000000000004';
set local role authenticated;
do $$ begin if public.complete_individual_registration() <> 'pending' then raise exception 'Edited metadata bypassed member review'; end if; end $$;
select set_config('request.jwt.claim.sub','c4000000-0000-4000-8000-000000000005',true);
do $$ begin if public.complete_individual_registration() <> 'pending' then raise exception 'Duplicate exact matches did not require review'; end if; end $$;
select set_config('request.jwt.claim.sub','c4000000-0000-4000-8000-000000000006',true);
do $$ begin if public.complete_individual_registration() <> 'pending' then raise exception 'Name mismatch did not require review'; end if; end $$;
select set_config('request.jwt.claim.sub','c4000000-0000-4000-8000-000000000011',true);
do $$ begin
 begin
  perform public.search_member_registration_candidates('c4000000-0000-4000-8000-000000000004','Actual');
  raise exception 'Other branch searched review';
 exception when raise_exception then if sqlerrm='Other branch searched review' then raise; end if; end;
 begin
  perform public.review_member_registration('c4000000-0000-4000-8000-000000000004','c3000000-0000-4000-8000-000000000004','approved');
  raise exception 'Other branch approved review';
 exception when raise_exception then if sqlerrm='Other branch approved review' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','c4000000-0000-4000-8000-000000000010',true);
do $$ begin
 if not exists (select 1 from public.list_member_registration_reviews('c1000000-0000-4000-8000-000000000001') where applicant_id='c4000000-0000-4000-8000-000000000004' and member_id is null) then raise exception 'No-match request missing'; end if;
 if not exists (select 1 from public.search_member_registration_candidates('c4000000-0000-4000-8000-000000000004','Actual') where member_id='c3000000-0000-4000-8000-000000000004') then raise exception 'Manual search failed'; end if;
 if exists (select 1 from public.search_member_registration_candidates('c4000000-0000-4000-8000-000000000004','Other') where member_id='c3000000-0000-4000-8000-000000000007') then raise exception 'Cross-branch member exposed'; end if;
 begin
  perform public.review_member_registration('c4000000-0000-4000-8000-000000000004','c3000000-0000-4000-8000-000000000007','approved');
  raise exception 'Cross-branch approval accepted';
 exception when raise_exception then if sqlerrm='Cross-branch approval accepted' then raise; end if; end;
 perform public.review_member_registration('c4000000-0000-4000-8000-000000000004','c3000000-0000-4000-8000-000000000004','approved');
end $$;
select set_config('request.jwt.claim.sub','c4000000-0000-4000-8000-000000000004',true);
do $$ begin if public.complete_individual_registration() <> 'completed' then raise exception 'Approved review did not complete'; end if; end $$;
reset role;
do $$ begin
 if has_function_privilege('anon','public.search_member_registration_candidates(uuid,text)','execute')
  or has_function_privilege('authenticated','public.complete_individual_registration_before_visitor_review()','execute')
  or has_function_privilege('authenticated','public.complete_registration_before_member_review_guard()','execute') then raise exception 'Private operation exposed'; end if;
 if not exists(select 1 from public.individual_registrations where user_id='c4000000-0000-4000-8000-000000000004' and person_type='MEMBER') then raise exception 'Approved snapshot was not used'; end if;
 if exists(select 1 from public.assignments where user_id in ('c4000000-0000-4000-8000-000000000002','c4000000-0000-4000-8000-000000000003','c4000000-0000-4000-8000-000000000005','c4000000-0000-4000-8000-000000000006')) then raise exception 'Pending account has access'; end if;
end $$;
rollback;
