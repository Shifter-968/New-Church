-- Isolated PostgreSQL only, after migration 041.
begin;
insert into public.organizations (id,name) values ('e0000000-0000-4000-8000-000000000001','Church A'),('e0000000-0000-4000-8000-000000000002','Church B');
insert into public.branches (id,organization_id,name,latitude,longitude,radius_meters) values
 ('e1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','Main',0,0,100),
 ('e1000000-0000-4000-8000-000000000002','e0000000-0000-4000-8000-000000000001','Other',null,null,100),
 ('e1000000-0000-4000-8000-000000000003','e0000000-0000-4000-8000-000000000002','Elsewhere',0,0,100);
insert into auth.users (id,email,email_confirmed_at) values
 ('e2000000-0000-4000-8000-000000000001','member@example.test',now()),
 ('e2000000-0000-4000-8000-000000000002','visitor@example.test',now()),
 ('e2000000-0000-4000-8000-000000000003','branch@example.test',now()),
 ('e2000000-0000-4000-8000-000000000004','admin@example.test',now()),
 ('e2000000-0000-4000-8000-000000000005','other@example.test',now()),
 ('e2000000-0000-4000-8000-000000000006','outsider@example.test',now()),
 ('e2000000-0000-4000-8000-000000000007','owner@example.test',now());
insert into public.platform_owners values ('e2000000-0000-4000-8000-000000000007');
insert into public.roles (id,organization_id,name,is_org_admin,permissions) values
 ('e3000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','Person',false,'{}'),
 ('e3000000-0000-4000-8000-000000000002','e0000000-0000-4000-8000-000000000001','Attendance manager',false,array['members.view','visitors.view','attendance.view','attendance.create']),
 ('e3000000-0000-4000-8000-000000000003','e0000000-0000-4000-8000-000000000001','Org admin',true,'{}');
insert into public.assignments (user_id,organization_id,branch_id,role_id) values
 ('e2000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000001','e3000000-0000-4000-8000-000000000001'),
 ('e2000000-0000-4000-8000-000000000002','e0000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000001','e3000000-0000-4000-8000-000000000001'),
 ('e2000000-0000-4000-8000-000000000003','e0000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000001','e3000000-0000-4000-8000-000000000002'),
 ('e2000000-0000-4000-8000-000000000004','e0000000-0000-4000-8000-000000000001',null,'e3000000-0000-4000-8000-000000000003'),
 ('e2000000-0000-4000-8000-000000000005','e0000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000002','e3000000-0000-4000-8000-000000000001');
insert into public.members (id,organization_id,branch_id,user_id,first_name,last_name) values
 ('e4000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000001','e2000000-0000-4000-8000-000000000001','Mary','Member'),
 ('e4000000-0000-4000-8000-000000000002','e0000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000002','e2000000-0000-4000-8000-000000000005','Other','Member');
insert into public.visitors (id,organization_id,branch_id,user_id,first_name,last_name) values
 ('e5000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000001','e2000000-0000-4000-8000-000000000002','Victor','Visitor'),
 ('e5000000-0000-4000-8000-000000000002','e0000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000001',null,'Manual','Visitor');
insert into public.church_events (id,organization_id,title,starts_at,ends_at,created_by,event_format,location,location_latitude,location_longitude) values
 ('e6000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','Service',now()-interval '1 hour',now()+interval '1 hour','e2000000-0000-4000-8000-000000000004','physical','Offsite venue',-26.3,31.1),
 ('e6000000-0000-4000-8000-000000000002','e0000000-0000-4000-8000-000000000001','Past',now()-interval '3 hours',now()-interval '1 hour','e2000000-0000-4000-8000-000000000004','physical','Church',-26.3,31.1),
 ('e6000000-0000-4000-8000-000000000003','e0000000-0000-4000-8000-000000000002','Other church',now()-interval '1 hour',now()+interval '1 hour','e2000000-0000-4000-8000-000000000007','physical','Church',0,0),
 ('e6000000-0000-4000-8000-000000000004','e0000000-0000-4000-8000-000000000001','Online service',now()-interval '1 hour',now()+interval '1 hour','e2000000-0000-4000-8000-000000000004','virtual','Online',null,null),
 ('e6000000-0000-4000-8000-000000000005','e0000000-0000-4000-8000-000000000001','Physical event without pin',now()-interval '1 hour',now()+interval '1 hour','e2000000-0000-4000-8000-000000000004','physical','Venue pending',null,null);
set local role authenticated;
select set_config('request.jwt.claim.sub','e2000000-0000-4000-8000-000000000001',true);
do $$ begin
 if (select count(*) from public.current_checkin_events('e0000000-0000-4000-8000-000000000001')) <> 3 then raise exception 'Ongoing events not found'; end if;
 if (select location_configured from public.current_checkin_events('e0000000-0000-4000-8000-000000000001') where event_id='e6000000-0000-4000-8000-000000000005') then raise exception 'Unpinned location reported as configured'; end if;
 begin perform public.self_check_in('e6000000-0000-4000-8000-000000000001',-26.302,31.1); raise exception 'Location outside 100 m accepted'; exception when raise_exception then if sqlerrm = 'Location outside 100 m accepted' then raise; end if; end;
 begin perform public.self_check_in('e6000000-0000-4000-8000-000000000001',null,31); raise exception 'Missing location accepted'; exception when raise_exception then if sqlerrm = 'Missing location accepted' then raise; end if; end;
 begin perform public.self_check_in('e6000000-0000-4000-8000-000000000002',-26.3,31.1); raise exception 'Past event accepted'; exception when raise_exception then if sqlerrm = 'Past event accepted' then raise; end if; end;
 begin perform public.self_check_in('e6000000-0000-4000-8000-000000000003',0,0); raise exception 'Other church accepted'; exception when raise_exception then if sqlerrm = 'Other church accepted' then raise; end if; end;
 begin perform public.self_check_in('e6000000-0000-4000-8000-000000000005',-26.3,31.1); raise exception 'Unpinned physical event accepted'; exception when raise_exception then if sqlerrm = 'Unpinned physical event accepted' then raise; end if; end;
 perform public.self_check_in('e6000000-0000-4000-8000-000000000001',-26.3005,31.1);
 perform public.self_check_in('e6000000-0000-4000-8000-000000000004',null,null);
 if not (select already_checked_in from public.current_checkin_events('e0000000-0000-4000-8000-000000000001') where event_id='e6000000-0000-4000-8000-000000000001') then raise exception 'Check-in not shown'; end if;
 begin perform public.self_check_in('e6000000-0000-4000-8000-000000000001',-26.3,31.1); raise exception 'Duplicate accepted'; exception when raise_exception then if sqlerrm = 'Duplicate accepted' then raise; end if; end;
 if not (select already_checked_in from public.current_checkin_events('e0000000-0000-4000-8000-000000000001') where event_id='e6000000-0000-4000-8000-000000000004') then raise exception 'Virtual check-in not shown'; end if;
 begin perform count(*) from public.event_attendance; raise exception 'Direct table read allowed'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','e2000000-0000-4000-8000-000000000002',true);
select public.self_check_in('e6000000-0000-4000-8000-000000000001',-26.3,31.1);
select set_config('request.jwt.claim.sub','e2000000-0000-4000-8000-000000000005',true);
select public.self_check_in('e6000000-0000-4000-8000-000000000001',-26.3,31.1);
select set_config('request.jwt.claim.sub','e2000000-0000-4000-8000-000000000003',true);
do $$ begin
 perform public.admin_check_in('e6000000-0000-4000-8000-000000000001','visitor','e5000000-0000-4000-8000-000000000002');
 if (select count(*) from public.list_event_attendance('e0000000-0000-4000-8000-000000000001','e6000000-0000-4000-8000-000000000001')) <> 4 then raise exception 'Shared attendance list missing records'; end if;
 begin perform public.admin_check_in('e6000000-0000-4000-8000-000000000001','member','e4000000-0000-4000-8000-000000000002'); raise exception 'Cross-branch attendance allowed'; exception when raise_exception then if sqlerrm = 'Cross-branch attendance allowed' then raise; end if; end;
 begin perform public.admin_check_in('e6000000-0000-4000-8000-000000000001','visitor','e5000000-0000-4000-8000-000000000001'); raise exception 'Admin duplicate allowed'; exception when raise_exception then if sqlerrm = 'Admin duplicate allowed' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','e2000000-0000-4000-8000-000000000004',true);
do $$ begin
 perform public.admin_check_in('e6000000-0000-4000-8000-000000000001','member','e4000000-0000-4000-8000-000000000002');
 begin delete from public.church_events where id='e6000000-0000-4000-8000-000000000001'; raise exception 'Event with attendance deleted'; exception when foreign_key_violation then null; end;
 begin delete from public.visitors where id='e5000000-0000-4000-8000-000000000002'; raise exception 'Visitor with attendance deleted'; exception when foreign_key_violation then null; end;
end $$;
select set_config('request.jwt.claim.sub','e2000000-0000-4000-8000-000000000003',true);
do $$ begin if (select count(*) from public.list_event_attendance('e0000000-0000-4000-8000-000000000001','e6000000-0000-4000-8000-000000000001')) <> 3 then raise exception 'Other branch record leaked'; end if; end $$;
select set_config('request.jwt.claim.sub','e2000000-0000-4000-8000-000000000006',true);
do $$ begin
 if exists(select 1 from public.list_event_attendance('e0000000-0000-4000-8000-000000000001','e6000000-0000-4000-8000-000000000001')) then raise exception 'Attendance leaked to outsider'; end if;
 begin perform public.admin_check_in('e6000000-0000-4000-8000-000000000002','visitor','e5000000-0000-4000-8000-000000000002'); raise exception 'Outsider marked attendance'; exception when raise_exception then if sqlerrm = 'Outsider marked attendance' then raise; end if; end;
end $$;
rollback;
