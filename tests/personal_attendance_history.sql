-- Isolated PostgreSQL only, after migration 017.
begin;
insert into public.organizations(id,name) values
 ('d0000000-0000-4000-8000-000000000001','Church A'),
 ('d0000000-0000-4000-8000-000000000002','Church B');
insert into public.branches(id,organization_id,name) values
 ('d1000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','Main');
insert into auth.users(id,email,email_confirmed_at) values
 ('d2000000-0000-4000-8000-000000000001','member@example.test',now()),
 ('d2000000-0000-4000-8000-000000000002','visitor@example.test',now()),
 ('d2000000-0000-4000-8000-000000000003','admin@example.test',now()),
 ('d2000000-0000-4000-8000-000000000004','outsider@example.test',now());
insert into public.roles(id,organization_id,name,is_org_admin) values
 ('d3000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','Person',false),
 ('d3000000-0000-4000-8000-000000000002','d0000000-0000-4000-8000-000000000001','Targeted',false),
 ('d3000000-0000-4000-8000-000000000003','d0000000-0000-4000-8000-000000000001','Admin',true);
insert into public.assignments(user_id,organization_id,branch_id,role_id) values
 ('d2000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','d3000000-0000-4000-8000-000000000001'),
 ('d2000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','d3000000-0000-4000-8000-000000000002'),
 ('d2000000-0000-4000-8000-000000000002','d0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','d3000000-0000-4000-8000-000000000001'),
 ('d2000000-0000-4000-8000-000000000003','d0000000-0000-4000-8000-000000000001',null,'d3000000-0000-4000-8000-000000000003');
insert into public.members(id,organization_id,branch_id,user_id,first_name,last_name) values
 ('d4000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000001','Member','One');
insert into public.visitors(id,organization_id,branch_id,user_id,first_name,last_name) values
 ('d5000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000002','Visitor','One');
insert into public.church_events(id,organization_id,title,starts_at,ends_at,created_by,audience_everyone,audience_roles) values
 ('d6000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','Public',now()-interval '2 hours',now()-interval '1 hour','d2000000-0000-4000-8000-000000000003',true,'{}'),
 ('d6000000-0000-4000-8000-000000000002','d0000000-0000-4000-8000-000000000001','Targeted',now()-interval '2 hours',now()-interval '1 hour','d2000000-0000-4000-8000-000000000003',false,array['d3000000-0000-4000-8000-000000000002']::uuid[]);
insert into public.event_attendance(organization_id,event_id,branch_id,member_id,visitor_id,checked_in_by,method) values
 ('d0000000-0000-4000-8000-000000000001','d6000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','d4000000-0000-4000-8000-000000000001',null,'d2000000-0000-4000-8000-000000000001','self'),
 ('d0000000-0000-4000-8000-000000000001','d6000000-0000-4000-8000-000000000002','d1000000-0000-4000-8000-000000000001','d4000000-0000-4000-8000-000000000001',null,'d2000000-0000-4000-8000-000000000003','admin'),
 ('d0000000-0000-4000-8000-000000000001','d6000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001',null,'d5000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000003','admin');
set local role authenticated;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000001',true);
do $$ begin
 if (select count(*) from public.my_attendance_history('d0000000-0000-4000-8000-000000000001')) <> 2 then raise exception 'Member history missing'; end if;
 if (select count(*) from public.my_attendance_history('d0000000-0000-4000-8000-000000000002')) <> 0 then raise exception 'Cross-church history leaked'; end if;
end $$;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000002',true);
do $$ begin
 if (select count(*) from public.my_attendance_history('d0000000-0000-4000-8000-000000000001')) <> 1 then raise exception 'Visitor history incorrect'; end if;
 if not exists(select 1 from public.my_attendance_history('d0000000-0000-4000-8000-000000000001') where method='admin') then raise exception 'Admin-marked history missing'; end if;
end $$;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000004',true);
do $$ begin if exists(select 1 from public.my_attendance_history('d0000000-0000-4000-8000-000000000001')) then raise exception 'Outsider history leaked'; end if; end $$;
reset role;
update public.assignments set active=false where user_id='d2000000-0000-4000-8000-000000000001' and role_id='d3000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000001',true);
do $$ begin if (select count(*) from public.my_attendance_history('d0000000-0000-4000-8000-000000000001')) <> 1 then raise exception 'Revoked audience visible in history'; end if; end $$;
reset role;
update public.assignments set active=false where user_id='d2000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ begin if exists(select 1 from public.my_attendance_history('d0000000-0000-4000-8000-000000000001')) then raise exception 'History visible after access revoked'; end if; end $$;
rollback;
