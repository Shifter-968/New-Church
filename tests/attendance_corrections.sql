-- Isolated PostgreSQL only, after migration 019.
begin;
insert into public.organizations(id,name) values
 ('a9000000-0000-4000-8000-000000000001','Church A'),
 ('a9000000-0000-4000-8000-000000000002','Church B');
insert into public.branches(id,organization_id,name,latitude,longitude) values
 ('a9100000-0000-4000-8000-000000000001','a9000000-0000-4000-8000-000000000001','Main',0,0);
insert into auth.users(id,email,email_confirmed_at) values
 ('a9200000-0000-4000-8000-000000000001','admin@example.test',now()),
 ('a9200000-0000-4000-8000-000000000002','member@example.test',now()),
 ('a9200000-0000-4000-8000-000000000003','visitor@example.test',now()),
 ('a9200000-0000-4000-8000-000000000004','branch@example.test',now()),
 ('a9200000-0000-4000-8000-000000000005','otheradmin@example.test',now()),
 ('a9200000-0000-4000-8000-000000000006','owner@example.test',now());
insert into public.platform_owners values ('a9200000-0000-4000-8000-000000000006');
insert into public.roles(id,organization_id,name,is_org_admin,permissions) values
 ('a9300000-0000-4000-8000-000000000001','a9000000-0000-4000-8000-000000000001','Admin',true,'{}'),
 ('a9300000-0000-4000-8000-000000000002','a9000000-0000-4000-8000-000000000001','Person',false,'{}'),
 ('a9300000-0000-4000-8000-000000000003','a9000000-0000-4000-8000-000000000001','Branch',false,array['attendance.view','attendance.create','members.view','visitors.view']),
 ('a9300000-0000-4000-8000-000000000004','a9000000-0000-4000-8000-000000000002','Admin',true,'{}');
insert into public.assignments(user_id,organization_id,branch_id,role_id) values
 ('a9200000-0000-4000-8000-000000000001','a9000000-0000-4000-8000-000000000001',null,'a9300000-0000-4000-8000-000000000001'),
 ('a9200000-0000-4000-8000-000000000002','a9000000-0000-4000-8000-000000000001','a9100000-0000-4000-8000-000000000001','a9300000-0000-4000-8000-000000000002'),
 ('a9200000-0000-4000-8000-000000000003','a9000000-0000-4000-8000-000000000001','a9100000-0000-4000-8000-000000000001','a9300000-0000-4000-8000-000000000002'),
 ('a9200000-0000-4000-8000-000000000004','a9000000-0000-4000-8000-000000000001','a9100000-0000-4000-8000-000000000001','a9300000-0000-4000-8000-000000000003'),
 ('a9200000-0000-4000-8000-000000000005','a9000000-0000-4000-8000-000000000002',null,'a9300000-0000-4000-8000-000000000004');
insert into public.members(id,organization_id,branch_id,user_id,first_name,last_name) values
 ('a9400000-0000-4000-8000-000000000001','a9000000-0000-4000-8000-000000000001','a9100000-0000-4000-8000-000000000001','a9200000-0000-4000-8000-000000000002','Member','One');
insert into public.visitors(id,organization_id,branch_id,user_id,first_name,last_name) values
 ('a9500000-0000-4000-8000-000000000001','a9000000-0000-4000-8000-000000000001','a9100000-0000-4000-8000-000000000001','a9200000-0000-4000-8000-000000000003','Visitor','One');
insert into public.church_events(id,organization_id,title,starts_at,ends_at,created_by) values
 ('a9600000-0000-4000-8000-000000000001','a9000000-0000-4000-8000-000000000001','Service',now()-interval '1 hour',now()+interval '1 hour','a9200000-0000-4000-8000-000000000001');
insert into public.event_attendance(id,organization_id,event_id,branch_id,member_id,visitor_id,checked_in_by,method) values
 ('a9700000-0000-4000-8000-000000000001','a9000000-0000-4000-8000-000000000001','a9600000-0000-4000-8000-000000000001','a9100000-0000-4000-8000-000000000001','a9400000-0000-4000-8000-000000000001',null,'a9200000-0000-4000-8000-000000000002','self'),
 ('a9700000-0000-4000-8000-000000000002','a9000000-0000-4000-8000-000000000001','a9600000-0000-4000-8000-000000000001','a9100000-0000-4000-8000-000000000001',null,'a9500000-0000-4000-8000-000000000001','a9200000-0000-4000-8000-000000000001','admin');
set local role authenticated;
select set_config('request.jwt.claim.sub','a9200000-0000-4000-8000-000000000004',true);
do $$ begin
 begin perform public.correct_attendance('a9000000-0000-4000-8000-000000000001','a9600000-0000-4000-8000-000000000001','a9700000-0000-4000-8000-000000000001','Mistake'); raise exception 'Branch correction allowed'; exception when raise_exception then if sqlerrm='Branch correction allowed' then raise; end if; end;
 begin perform public.list_attendance_corrections('a9000000-0000-4000-8000-000000000001','a9600000-0000-4000-8000-000000000001'); raise exception 'Branch correction history allowed'; exception when raise_exception then if sqlerrm='Branch correction history allowed' then raise; end if; end;
 begin perform count(*) from public.attendance_corrections; raise exception 'Direct table read allowed'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','a9200000-0000-4000-8000-000000000005',true);
do $$ begin
 begin perform public.correct_attendance('a9000000-0000-4000-8000-000000000001','a9600000-0000-4000-8000-000000000001','a9700000-0000-4000-8000-000000000001','Mistake'); raise exception 'Cross-church correction allowed'; exception when raise_exception then if sqlerrm='Cross-church correction allowed' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','a9200000-0000-4000-8000-000000000001',true);
do $$ begin
 begin perform public.correct_attendance('a9000000-0000-4000-8000-000000000001','a9600000-0000-4000-8000-000000000001','a9700000-0000-4000-8000-000000000001','  '); raise exception 'Blank reason allowed'; exception when raise_exception then if sqlerrm='Blank reason allowed' then raise; end if; end;
 perform public.correct_attendance('a9000000-0000-4000-8000-000000000001','a9600000-0000-4000-8000-000000000001','a9700000-0000-4000-8000-000000000001','  Wrong person  ');
 if not exists(select 1 from public.list_attendance_corrections('a9000000-0000-4000-8000-000000000001','a9600000-0000-4000-8000-000000000001') where reason='Wrong person' and person_kind='member' and corrected_by=auth.uid() and method='self') then raise exception 'Correction details missing'; end if;
 if (select count(*) from public.list_event_attendance('a9000000-0000-4000-8000-000000000001','a9600000-0000-4000-8000-000000000001')) <> 1 then raise exception 'Active attendance count incorrect'; end if;
 begin perform public.correct_attendance('a9000000-0000-4000-8000-000000000001','a9600000-0000-4000-8000-000000000001','a9700000-0000-4000-8000-000000000001','Again'); raise exception 'Duplicate correction allowed'; exception when raise_exception then if sqlerrm='Duplicate correction allowed' then raise; end if; end;
 begin delete from public.church_events where id='a9600000-0000-4000-8000-000000000001'; raise exception 'Event with correction deleted'; exception when foreign_key_violation then null; end;
end $$;
select set_config('request.jwt.claim.sub','a9200000-0000-4000-8000-000000000002',true);
do $$ begin
 if exists(select 1 from public.my_attendance_history('a9000000-0000-4000-8000-000000000001')) then raise exception 'Corrected check-in in personal history'; end if;
 perform public.self_check_in('a9600000-0000-4000-8000-000000000001',0,0);
 if (select count(*) from public.my_attendance_history('a9000000-0000-4000-8000-000000000001')) <> 1 then raise exception 'Re-check-in missing'; end if;
end $$;
select set_config('request.jwt.claim.sub','a9200000-0000-4000-8000-000000000006',true);
do $$ begin
 perform public.correct_attendance('a9000000-0000-4000-8000-000000000001','a9600000-0000-4000-8000-000000000001','a9700000-0000-4000-8000-000000000002','Duplicate visitor');
 if not exists(select 1 from public.list_attendance_corrections('a9000000-0000-4000-8000-000000000001','a9600000-0000-4000-8000-000000000001') where person_kind='visitor' and corrected_by=auth.uid() and method='admin') then raise exception 'Owner visitor correction missing'; end if;
end $$;
rollback;
