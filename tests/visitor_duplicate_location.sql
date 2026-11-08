-- Run only against an isolated test database after migration 013.
begin;
insert into public.organizations (id, name) values
 ('a0000000-0000-4000-8000-000000000001', 'Church A'),
 ('a0000000-0000-4000-8000-000000000002', 'Church B');
insert into public.branches (id, organization_id, name) values
 ('a1000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'One'),
 ('a1000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000001', 'Two'),
 ('a1000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000002', 'Three');
insert into auth.users (id, email, email_confirmed_at) values
 ('a2000000-0000-4000-8000-000000000001','branch@example.test',now()),
 ('a2000000-0000-4000-8000-000000000002','admin@example.test',now()),
 ('a2000000-0000-4000-8000-000000000003','owner@example.test',now());
insert into public.platform_owners values ('a2000000-0000-4000-8000-000000000003');
insert into public.roles (id, organization_id, name, is_org_admin, permissions) values
 ('a3000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','Viewer',false,array['visitors.view']),
 ('a3000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','Admin',true,'{}');
insert into public.assignments (user_id, organization_id, branch_id, role_id) values
 ('a2000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000001'),
 ('a2000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001',null,'a3000000-0000-4000-8000-000000000002');
insert into public.visitors (organization_id, branch_id, first_name, last_name, email, phone, created_at) values
 ('a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','Jane','Doe','Jane@example.test','+1 (555) 123', '2000-01-01'),
 ('a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000002','Jane','Doe','other@example.test','999',now()),
 ('a0000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000003','Jane','Doe','other@example.test','999',now());
insert into public.visitors (organization_id, branch_id, first_name, last_name)
select 'a0000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 'Filler', n::text from generate_series(1,1001) n;

set local role authenticated;
select set_config('request.jwt.claim.sub','a2000000-0000-4000-8000-000000000001',true);
do $$ begin
 if (select count(*) from public.find_visitor_duplicates('a0000000-0000-4000-8000-000000000001', '[{"first_name":"jane","last_name":"DOE"},{"first_name":"X","last_name":"Y","phone":"1 555 123"},{"first_name":"X","last_name":"Y","email":"JANE@example.test"}]')) <> 3 then
  raise exception 'Matching beyond directory cap, normalization or branch isolation failed';
 end if;
 if (select count(*) from public.find_visitor_duplicates('a0000000-0000-4000-8000-000000000001', (select jsonb_agg(jsonb_build_object('first_name','Jane','last_name','Doe')) from generate_series(1,500)))) <> 500 then
  raise exception 'Large import duplicate results were lost';
 end if;
 if exists (select 1 from public.find_visitor_duplicates('a0000000-0000-4000-8000-000000000002', '[{"first_name":"Jane","last_name":"Doe"}]')) then raise exception 'Other church visible'; end if;
 begin
  perform public.save_branch_location('a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001',1,2,100,'test');
  raise exception 'Unauthorized location update';
 exception when raise_exception then if sqlerrm = 'Unauthorized location update' then raise; end if; end;
 begin
  update public.branches set latitude = 1, longitude = 2 where id = 'a1000000-0000-4000-8000-000000000001';
  raise exception 'Direct location write permitted';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','a2000000-0000-4000-8000-000000000002',true);
do $$ begin
 if (select jsonb_array_length(matches) from public.find_visitor_duplicates('a0000000-0000-4000-8000-000000000001', '[{"first_name":"Jane","last_name":"Doe"}]')) <> 2 then raise exception 'Org admin must see both branches'; end if;
 perform public.save_branch_location('a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001',-26.3,31.1,100,'Main');
 begin
  perform public.save_branch_location('a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001',91,31,100,'Invalid');
  raise exception 'Invalid coordinates accepted';
 exception when raise_exception then if sqlerrm = 'Invalid coordinates accepted' then raise; end if; end;
 begin
  perform public.save_branch_location('a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001',0,0,19,'Invalid');
  raise exception 'Invalid radius accepted';
 exception when raise_exception then if sqlerrm = 'Invalid radius accepted' then raise; end if; end;
 begin
  perform public.save_branch_location('a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000003',0,0,100,'Invalid');
  raise exception 'Wrong church branch accepted';
 exception when raise_exception then if sqlerrm = 'Wrong church branch accepted' then raise; end if; end;
 if not exists(select 1 from public.branches where id = 'a1000000-0000-4000-8000-000000000001' and latitude = -26.3 and longitude = 31.1 and radius_meters = 100) then raise exception 'Location not saved'; end if;
end $$;
select set_config('request.jwt.claim.sub','a2000000-0000-4000-8000-000000000003',true);
select public.save_branch_location('a0000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000003',0,0,2000,'Support');
rollback;
