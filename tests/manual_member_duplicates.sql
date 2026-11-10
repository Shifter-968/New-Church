-- Isolated PostgreSQL only, after migration 027.
begin;
insert into public.organizations(id,name) values
 ('f7000000-0000-4000-8000-000000000001','Church A'),
 ('f7000000-0000-4000-8000-000000000002','Church B');
insert into public.branches(id,organization_id,name) values
 ('f7100000-0000-4000-8000-000000000001','f7000000-0000-4000-8000-000000000001','Main'),
 ('f7100000-0000-4000-8000-000000000002','f7000000-0000-4000-8000-000000000001','Other'),
 ('f7100000-0000-4000-8000-000000000003','f7000000-0000-4000-8000-000000000002','Elsewhere');
insert into auth.users(id,email,email_confirmed_at) values
 ('f7200000-0000-4000-8000-000000000001','branch@example.test',now()),
 ('f7200000-0000-4000-8000-000000000002','admin@example.test',now()),
 ('f7200000-0000-4000-8000-000000000003','owner@example.test',now()),
 ('f7200000-0000-4000-8000-000000000004','other@example.test',now());
insert into public.platform_owners values ('f7200000-0000-4000-8000-000000000003');
insert into public.roles(id,organization_id,name,is_org_admin,permissions) values
 ('f7300000-0000-4000-8000-000000000001','f7000000-0000-4000-8000-000000000001','Branch',false,array['members.view','members.create']),
 ('f7300000-0000-4000-8000-000000000002','f7000000-0000-4000-8000-000000000001','Admin',true,'{}');
insert into public.assignments(user_id,organization_id,branch_id,role_id) values
 ('f7200000-0000-4000-8000-000000000001','f7000000-0000-4000-8000-000000000001','f7100000-0000-4000-8000-000000000001','f7300000-0000-4000-8000-000000000001'),
 ('f7200000-0000-4000-8000-000000000002','f7000000-0000-4000-8000-000000000001',null,'f7300000-0000-4000-8000-000000000002');
insert into public.members(organization_id,branch_id,first_name,last_name,phone,phone_2,status) values
 ('f7000000-0000-4000-8000-000000000001','f7100000-0000-4000-8000-000000000001','Jane','Doe',null,'123 456','active'),
 ('f7000000-0000-4000-8000-000000000001','f7100000-0000-4000-8000-000000000002','Jane','Doe',null,null,'inactive'),
 ('f7000000-0000-4000-8000-000000000001',null,'Jane','Doe',null,null,'active'),
 ('f7000000-0000-4000-8000-000000000002','f7100000-0000-4000-8000-000000000003','Jane','Doe',null,null,'active');
set local role authenticated;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000001',true);
do $$ begin
 if (select jsonb_array_length(matches) from public.find_member_import_duplicates('f7000000-0000-4000-8000-000000000001','f7100000-0000-4000-8000-000000000001','[{"first_name":"jane","last_name":"doe"}]')) <> 1 then raise exception 'Visible branch match incorrect'; end if;
 if not exists(select 1 from public.find_member_import_duplicates('f7000000-0000-4000-8000-000000000001','f7100000-0000-4000-8000-000000000001','[{"first_name":"Different","last_name":"Person","phone":"123-456"}]')) then raise exception 'Second phone did not match'; end if;
 begin perform public.find_member_import_duplicates('f7000000-0000-4000-8000-000000000001',null,'[{"first_name":"Jane","last_name":"Doe"}]'); raise exception 'Branch user searched no branch'; exception when raise_exception then if sqlerrm='Branch user searched no branch' then raise; end if; end;
 begin perform public.find_member_import_duplicates('f7000000-0000-4000-8000-000000000001','f7100000-0000-4000-8000-000000000002','[{}]'); raise exception 'Branch user searched other branch'; exception when raise_exception then if sqlerrm='Branch user searched other branch' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000002',true);
do $$ begin
 if (select jsonb_array_length(matches) from public.find_member_import_duplicates('f7000000-0000-4000-8000-000000000001',null,'[{"first_name":"Jane","last_name":"Doe"}]')) <> 3 then raise exception 'Organization-wide check missed matches'; end if;
 begin perform public.find_member_import_duplicates('f7000000-0000-4000-8000-000000000001','f7100000-0000-4000-8000-000000000003','[{}]'); raise exception 'Other church branch allowed'; exception when raise_exception then if sqlerrm='Other church branch allowed' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000003',true);
do $$ begin if (select jsonb_array_length(matches) from public.find_member_import_duplicates('f7000000-0000-4000-8000-000000000001',null,'[{"first_name":"Jane","last_name":"Doe"}]')) <> 3 then raise exception 'Owner check incorrect'; end if; end $$;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000004',true);
do $$ begin
 begin perform public.find_member_import_duplicates('f7000000-0000-4000-8000-000000000001',null,'[{}]'); raise exception 'Unassigned user allowed'; exception when raise_exception then if sqlerrm='Unassigned user allowed' then raise; end if; end;
end $$;
rollback;
