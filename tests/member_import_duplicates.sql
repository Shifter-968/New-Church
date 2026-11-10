-- Isolated PostgreSQL only, after migration 026.
begin;
insert into public.organizations(id,name) values
 ('e7000000-0000-4000-8000-000000000001','Church A'),
 ('e7000000-0000-4000-8000-000000000002','Church B');
insert into public.branches(id,organization_id,name) values
 ('e7100000-0000-4000-8000-000000000001','e7000000-0000-4000-8000-000000000001','One'),
 ('e7100000-0000-4000-8000-000000000002','e7000000-0000-4000-8000-000000000001','Two'),
 ('e7100000-0000-4000-8000-000000000003','e7000000-0000-4000-8000-000000000002','Other');
insert into auth.users(id,email,email_confirmed_at) values
 ('e7200000-0000-4000-8000-000000000001','branch@example.test',now()),
 ('e7200000-0000-4000-8000-000000000002','admin@example.test',now()),
 ('e7200000-0000-4000-8000-000000000003','other@example.test',now()),
 ('e7200000-0000-4000-8000-000000000004','create@example.test',now());
insert into public.roles(id,organization_id,name,is_org_admin,permissions) values
 ('e7300000-0000-4000-8000-000000000001','e7000000-0000-4000-8000-000000000001','Branch',false,array['members.view','members.create']),
 ('e7300000-0000-4000-8000-000000000002','e7000000-0000-4000-8000-000000000001','Admin',true,'{}'),
 ('e7300000-0000-4000-8000-000000000003','e7000000-0000-4000-8000-000000000002','Admin',true,'{}'),
 ('e7300000-0000-4000-8000-000000000004','e7000000-0000-4000-8000-000000000001','Create only',false,array['members.create']);
insert into public.assignments(user_id,organization_id,branch_id,role_id) values
 ('e7200000-0000-4000-8000-000000000001','e7000000-0000-4000-8000-000000000001','e7100000-0000-4000-8000-000000000001','e7300000-0000-4000-8000-000000000001'),
 ('e7200000-0000-4000-8000-000000000002','e7000000-0000-4000-8000-000000000001',null,'e7300000-0000-4000-8000-000000000002'),
 ('e7200000-0000-4000-8000-000000000003','e7000000-0000-4000-8000-000000000002',null,'e7300000-0000-4000-8000-000000000003'),
 ('e7200000-0000-4000-8000-000000000004','e7000000-0000-4000-8000-000000000001','e7100000-0000-4000-8000-000000000001','e7300000-0000-4000-8000-000000000004');
insert into public.members(organization_id,branch_id,first_name,last_name,email,phone,phone_2,status,created_at) values
 ('e7000000-0000-4000-8000-000000000001','e7100000-0000-4000-8000-000000000001','Jane','Doe','Jane@example.test','111-22','333 44','inactive','2000-01-01'),
 ('e7000000-0000-4000-8000-000000000001','e7100000-0000-4000-8000-000000000002','Jane','Doe',null,null,null,'active',now()),
 ('e7000000-0000-4000-8000-000000000002','e7100000-0000-4000-8000-000000000003','Jane','Doe',null,null,null,'active',now());
insert into public.members(organization_id,branch_id,first_name,last_name)
select 'e7000000-0000-4000-8000-000000000001','e7100000-0000-4000-8000-000000000001','Filler',n::text from generate_series(1,1001) n;
set local role authenticated;
select set_config('request.jwt.claim.sub','e7200000-0000-4000-8000-000000000001',true);
do $$ begin
 if (select count(*) from public.find_member_import_duplicates('e7000000-0000-4000-8000-000000000001','e7100000-0000-4000-8000-000000000001',
   '[{"first_name":"jane","last_name":"DOE"},{"email":"JANE@example.test"},{"phone":"33344"},{"phone_2":"11122"}]')) <> 4 then raise exception 'Matching beyond list limit or normalization failed'; end if;
 if (select jsonb_array_length(matches) from public.find_member_import_duplicates('e7000000-0000-4000-8000-000000000001','e7100000-0000-4000-8000-000000000001','[{"first_name":"Jane","last_name":"Doe"}]')) <> 1 then raise exception 'Cross-branch result leaked'; end if;
 if (select count(*) from public.find_member_import_duplicates('e7000000-0000-4000-8000-000000000001','e7100000-0000-4000-8000-000000000001',(select jsonb_agg(jsonb_build_object('first_name','Jane','last_name','Doe')) from generate_series(1,500)))) <> 500 then raise exception 'Large batch results missing'; end if;
 begin perform public.find_member_import_duplicates('e7000000-0000-4000-8000-000000000001','e7100000-0000-4000-8000-000000000002','[{}]'); raise exception 'Cross-branch check allowed'; exception when raise_exception then if sqlerrm='Cross-branch check allowed' then raise; end if; end;
 begin perform public.find_member_import_duplicates('e7000000-0000-4000-8000-000000000001','e7100000-0000-4000-8000-000000000001','[]'); raise exception 'Empty input accepted'; exception when raise_exception then if sqlerrm='Empty input accepted' then raise; end if; end;
 begin perform public.find_member_import_duplicates('e7000000-0000-4000-8000-000000000001','e7100000-0000-4000-8000-000000000001',(select jsonb_agg('{}'::jsonb) from generate_series(1,501))); raise exception 'Oversized input accepted'; exception when raise_exception then if sqlerrm='Oversized input accepted' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','e7200000-0000-4000-8000-000000000002',true);
do $$ begin
 if (select jsonb_array_length(matches) from public.find_member_import_duplicates('e7000000-0000-4000-8000-000000000001','e7100000-0000-4000-8000-000000000001','[{"first_name":"Jane","last_name":"Doe"}]')) <> 2 then raise exception 'Admin does not see both branches'; end if;
end $$;
select set_config('request.jwt.claim.sub','e7200000-0000-4000-8000-000000000003',true);
do $$ begin
 begin perform public.find_member_import_duplicates('e7000000-0000-4000-8000-000000000001','e7100000-0000-4000-8000-000000000001','[{}]'); raise exception 'Other church access'; exception when raise_exception then if sqlerrm='Other church access' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','e7200000-0000-4000-8000-000000000004',true);
do $$ begin
 begin perform public.find_member_import_duplicates('e7000000-0000-4000-8000-000000000001','e7100000-0000-4000-8000-000000000001','[{}]'); raise exception 'Create-only check accepted'; exception when raise_exception then if sqlerrm='Create-only check accepted' then raise; end if; end;
end $$;
rollback;
