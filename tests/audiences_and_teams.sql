-- Isolated PostgreSQL only, after migration 015.
begin;
insert into public.organizations (id,name) values ('b0000000-0000-4000-8000-000000000001','Church A'),('b0000000-0000-4000-8000-000000000002','Church B');
insert into public.branches (id,organization_id,name,latitude,longitude) values
 ('b1000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','Main',0,0);
insert into auth.users(id,email,email_confirmed_at) values
 ('b2000000-0000-4000-8000-000000000001','admin@example.test',now()),
 ('b2000000-0000-4000-8000-000000000002','youth@example.test',now()),
 ('b2000000-0000-4000-8000-000000000003','usher@example.test',now()),
 ('b2000000-0000-4000-8000-000000000004','other@example.test',now()),
 ('b2000000-0000-4000-8000-000000000005','outsider@example.test',now()),
 ('b2000000-0000-4000-8000-000000000006','support@example.test',now());
insert into public.platform_owners values ('b2000000-0000-4000-8000-000000000006');
insert into public.roles(id,organization_id,name,is_org_admin,permissions) values
 ('b3000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','Admin',true,'{}'),
 ('b3000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','Youth',false,'{}'),
 ('b3000000-0000-4000-8000-000000000003','b0000000-0000-4000-8000-000000000001','Member',false,array['attendance.view','attendance.create','members.view','visitors.view']),
 ('b3000000-0000-4000-8000-000000000004','b0000000-0000-4000-8000-000000000002','Other church',false,'{}');
insert into public.assignments(user_id,organization_id,branch_id,role_id) values
 ('b2000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001',null,'b3000000-0000-4000-8000-000000000001'),
 ('b2000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','b3000000-0000-4000-8000-000000000002'),
 ('b2000000-0000-4000-8000-000000000003','b0000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','b3000000-0000-4000-8000-000000000003'),
 ('b2000000-0000-4000-8000-000000000004','b0000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','b3000000-0000-4000-8000-000000000003');
insert into public.members(id,organization_id,branch_id,user_id,first_name,last_name) values
 ('b4000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000002','Youth','Person'),
 ('b4000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000004','Other','Person');
insert into public.visitors(id,organization_id,branch_id,user_id,first_name,last_name) values
 ('b5000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000003','Usher','Visitor');
insert into public.church_teams(id,organization_id,kind,name) values
 ('b6000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','department','Ushers'),
 ('b6000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002','ministry','Other');
insert into public.church_team_members(organization_id,team_id,visitor_id) values ('b0000000-0000-4000-8000-000000000001','b6000000-0000-4000-8000-000000000001','b5000000-0000-4000-8000-000000000001');
insert into public.church_events(id,organization_id,title,starts_at,ends_at,created_by,event_format,audience_everyone,audience_roles,audience_teams) values
 ('b7000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','Targeted',now()-interval '1 hour',now()+interval '1 hour','b2000000-0000-4000-8000-000000000001','virtual',false,array['b3000000-0000-4000-8000-000000000002']::uuid[],array['b6000000-0000-4000-8000-000000000001']::uuid[]),
 ('b7000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','Everyone',now()-interval '1 hour',now()+interval '1 hour','b2000000-0000-4000-8000-000000000001','virtual',true,'{}','{}');
insert into public.announcements(id,organization_id,title,content,created_by,audience_everyone,audience_roles,audience_teams) values
 ('b8000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','Targeted','Message','b2000000-0000-4000-8000-000000000001',false,'{}',array['b6000000-0000-4000-8000-000000000001']::uuid[]),
 ('b8000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','Everyone','Message','b2000000-0000-4000-8000-000000000001',true,'{}','{}');
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000002',true);
do $$ begin
 if (select count(*) from public.church_events) <> 2 or (select count(*) from public.announcements) <> 1 then raise exception 'Role audience incorrect'; end if;
 if (select count(*) from public.current_checkin_events('b0000000-0000-4000-8000-000000000001')) <> 2 then raise exception 'Role event check-in visibility incorrect'; end if;
 perform public.self_check_in('b7000000-0000-4000-8000-000000000001',0,0);
end $$;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000003',true);
do $$ begin
 if (select count(*) from public.church_events) <> 2 or (select count(*) from public.announcements) <> 2 then raise exception 'Visitor team audience incorrect'; end if;
 perform public.self_check_in('b7000000-0000-4000-8000-000000000001',0,0);
end $$;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000004',true);
do $$ begin
 if (select count(*) from public.church_events) <> 1 or (select count(*) from public.announcements) <> 1 then raise exception 'Targeted content leaked'; end if;
 if (select count(*) from public.current_checkin_events('b0000000-0000-4000-8000-000000000001')) <> 1 then raise exception 'Targeted check-in leaked'; end if;
 if exists(select 1 from public.list_event_attendance('b0000000-0000-4000-8000-000000000001','b7000000-0000-4000-8000-000000000001')) then raise exception 'Targeted attendance leaked'; end if;
 begin perform public.self_check_in('b7000000-0000-4000-8000-000000000001',0,0); raise exception 'Unauthorized self check-in'; exception when raise_exception then if sqlerrm='Unauthorized self check-in' then raise; end if; end;
 begin perform public.admin_check_in('b7000000-0000-4000-8000-000000000001','member','b4000000-0000-4000-8000-000000000002'); raise exception 'Unauthorized admin check-in'; exception when raise_exception then if sqlerrm='Unauthorized admin check-in' then raise; end if; end;
 begin perform public.self_check_in_unfiltered('b7000000-0000-4000-8000-000000000001',0,0); raise exception 'Private check-in callable'; exception when insufficient_privilege then null; end;
 begin perform public.audience_options('b0000000-0000-4000-8000-000000000001'); raise exception 'Audience metadata leaked'; exception when raise_exception then if sqlerrm='Audience metadata leaked' then raise; end if; end;
 if exists(select 1 from public.church_teams) then raise exception 'Team data leaked'; end if;
end $$;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000005',true);
do $$ begin if exists(select 1 from public.church_events) or exists(select 1 from public.announcements) then raise exception 'Content leaked outside organization'; end if; end $$;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000001',true);
do $$ begin
 if (select count(*) from public.church_events) <> 2 or (select count(*) from public.announcements) <> 2 then raise exception 'Admin support cannot see all content'; end if;
 begin update public.church_events set audience_roles=array['b3000000-0000-4000-8000-000000000004']::uuid[] where id='b7000000-0000-4000-8000-000000000001'; raise exception 'Cross-church audience allowed'; exception when raise_exception then if sqlerrm='Cross-church audience allowed' then raise; end if; end;
 begin update public.church_events set audience_roles='{}',audience_teams='{}' where id='b7000000-0000-4000-8000-000000000001'; raise exception 'Empty audience allowed'; exception when raise_exception then if sqlerrm='Empty audience allowed' then raise; end if; end;
 begin insert into public.church_team_members(organization_id,team_id,visitor_id) values ('b0000000-0000-4000-8000-000000000001','b6000000-0000-4000-8000-000000000002','b5000000-0000-4000-8000-000000000001'); raise exception 'Cross-church membership allowed'; exception when foreign_key_violation then null; end;
 begin delete from public.church_teams where id='b6000000-0000-4000-8000-000000000001'; raise exception 'Referenced team deleted'; exception when raise_exception then if sqlerrm='Referenced team deleted' then raise; end if; end;
 delete from public.church_team_members where team_id='b6000000-0000-4000-8000-000000000001';
end $$;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000003',true);
do $$ begin
 if (select count(*) from public.church_events) <> 1 or (select count(*) from public.announcements) <> 1 then raise exception 'Removed team member retained targeted access'; end if;
 begin perform public.self_check_in('b7000000-0000-4000-8000-000000000001',0,0); raise exception 'Removed team member can check in'; exception when raise_exception then if sqlerrm='Removed team member can check in' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000006',true);
do $$ begin if (select count(*) from public.church_events) <> 2 or (select count(*) from public.announcements) <> 2 then raise exception 'Platform support cannot see all content'; end if; end $$;
rollback;
