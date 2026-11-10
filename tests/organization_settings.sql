-- Isolated PostgreSQL only, after migration 025.
begin;
insert into public.organizations(id,name) values
 ('d1000000-0000-4000-8000-000000000001','Church Alpha'),
 ('d1000000-0000-4000-8000-000000000002','Church Beta');
insert into public.branches(id,organization_id,name) values
 ('d2000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','Main');
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
select ('d3000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,'test' || n || '@example.test',now(),
  case when n in (1,2,3) then jsonb_build_object('individual_registration',jsonb_build_object(
    'organization_id','d1000000-0000-4000-8000-000000000001',
    'branch_id','d2000000-0000-4000-8000-000000000001',
    'first_name',case when n=3 then 'Existing' else 'New' end,
    'last_name',case when n=3 then 'Member' else 'Visitor' end,
    'person_type',case when n=3 then 'MEMBER' else 'VISITOR' end,
    'birth_date','1990-01-01','phone',case when n=1 then '111' else '222' end)) else '{}'::jsonb end
from generate_series(1,7) n;
insert into public.platform_owners values ('d3000000-0000-4000-8000-000000000007');
insert into public.roles(id,organization_id,name,is_org_admin,permissions) values
 ('d4000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','Admin',true,'{}'),
 ('d4000000-0000-4000-8000-000000000002','d1000000-0000-4000-8000-000000000002','Admin',true,'{}'),
 ('d4000000-0000-4000-8000-000000000003','d1000000-0000-4000-8000-000000000001','Branch',false,array['org.settings.manage']);
insert into public.assignments(user_id,organization_id,branch_id,role_id) values
 ('d3000000-0000-4000-8000-000000000004','d1000000-0000-4000-8000-000000000001',null,'d4000000-0000-4000-8000-000000000001'),
 ('d3000000-0000-4000-8000-000000000005','d1000000-0000-4000-8000-000000000002',null,'d4000000-0000-4000-8000-000000000002'),
 ('d3000000-0000-4000-8000-000000000006','d1000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000001','d4000000-0000-4000-8000-000000000003');
insert into public.members(id,organization_id,branch_id,first_name,last_name,phone) values
 ('d5000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000001','Existing','Member','222');
set local role authenticated;
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000001',true);
do $$ begin
 if public.complete_individual_registration() <> 'completed' then raise exception 'Default registration failed'; end if;
 begin perform public.complete_individual_registration_before_settings(); raise exception 'Settings bypass available'; exception when insufficient_privilege then null; end;
 begin perform public.complete_individual_registration_before_visitor_review(); raise exception 'Legacy bypass available'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000005',true);
do $$ begin
 begin perform public.organization_settings('d1000000-0000-4000-8000-000000000001'); raise exception 'Other admin read settings'; exception when raise_exception then if sqlerrm='Other admin read settings' then raise; end if; end;
 begin perform public.save_organization_settings('d1000000-0000-4000-8000-000000000001','Changed',true,true,true); raise exception 'Other admin changed settings'; exception when raise_exception then if sqlerrm='Other admin changed settings' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000006',true);
do $$ begin
 begin perform public.organization_settings('d1000000-0000-4000-8000-000000000001'); raise exception 'Branch user read settings'; exception when raise_exception then if sqlerrm='Branch user read settings' then raise; end if; end;
 begin perform public.save_organization_settings('d1000000-0000-4000-8000-000000000001','Changed',true,true,true); raise exception 'Branch user changed settings'; exception when raise_exception then if sqlerrm='Branch user changed settings' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000004',true);
do $$ begin
 begin perform public.save_organization_settings('d1000000-0000-4000-8000-000000000001',' ',true,true,true); raise exception 'Invalid name accepted'; exception when raise_exception then if sqlerrm='Invalid name accepted' then raise; end if; end;
 begin perform public.save_organization_settings('d1000000-0000-4000-8000-000000000001','Church',null,true,true); raise exception 'Null flag accepted'; exception when raise_exception then if sqlerrm='Null flag accepted' then raise; end if; end;
 perform public.save_organization_settings('d1000000-0000-4000-8000-000000000001',' Renamed Church ',true,true,false);
 if not exists(select 1 from public.organization_settings('d1000000-0000-4000-8000-000000000001') where name='Renamed Church' and not allow_visitor_registration and allow_member_registration) then raise exception 'Saved settings incorrect'; end if;
 if not exists(select 1 from public.support_activity where organization_id='d1000000-0000-4000-8000-000000000001' and resource_type='organizations' and actor_id=auth.uid() and action='UPDATE') then raise exception 'Audit missing'; end if;
end $$;
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000002',true);
do $$ begin
 begin perform public.complete_individual_registration(); raise exception 'Visitor pause bypassed'; exception when raise_exception then if sqlerrm='Visitor pause bypassed' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000003',true);
do $$ begin if public.complete_individual_registration() <> 'completed' then raise exception 'Member should still register'; end if; end $$;
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000001',true);
do $$ begin if public.complete_individual_registration() <> 'completed' then raise exception 'Existing registration affected'; end if; end $$;
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000007',true);
select public.save_organization_settings('d1000000-0000-4000-8000-000000000001','Hidden Church',false,true,true);
set local role anon;
do $$ begin
 if exists(select 1 from public.public_registration_options('d1000000-0000-4000-8000-000000000001')) then raise exception 'Hidden options leaked'; end if;
 if exists(select 1 from public.search_public_churches('Hidden Church')) then raise exception 'Hidden church listed'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000002',true);
do $$ begin
 begin perform public.complete_individual_registration(); raise exception 'Hidden registration bypassed'; exception when raise_exception then if sqlerrm='Hidden registration bypassed' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000007',true);
select public.save_organization_settings('d1000000-0000-4000-8000-000000000001','Hidden Church',true,true,true);
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000002',true);
do $$ begin
 if public.complete_individual_registration() <> 'pending' then raise exception 'Restored visitor registration failed'; end if;
end $$;
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000004',true);
select public.save_organization_settings('d1000000-0000-4000-8000-000000000001','Hidden Church',true,true,false);
reset role;
update auth.users set raw_user_meta_data=jsonb_set(raw_user_meta_data,'{individual_registration,person_type}','"MEMBER"') where id='d3000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000002',true);
do $$ begin
 begin perform public.complete_individual_registration(); raise exception 'Pending snapshot bypassed'; exception when raise_exception then if sqlerrm='Pending snapshot bypassed' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000004',true);
select public.review_visitor_registration('d3000000-0000-4000-8000-000000000002',null,'new');
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000002',true);
do $$ begin
 begin perform public.complete_individual_registration(); raise exception 'Approved snapshot bypassed'; exception when raise_exception then if sqlerrm='Approved snapshot bypassed' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000004',true);
select public.save_organization_settings('d1000000-0000-4000-8000-000000000001','Hidden Church',true,true,true);
select set_config('request.jwt.claim.sub','d3000000-0000-4000-8000-000000000002',true);
do $$ begin if public.complete_individual_registration() <> 'completed' then raise exception 'Approved visitor did not resume'; end if; end $$;
rollback;
