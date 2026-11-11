-- Isolated PostgreSQL only, after migration 043.
begin;
insert into public.organizations(id,name) values ('d0000000-0000-4000-8000-000000000001','Children Church');
insert into public.branches(id,organization_id,name) values
 ('d1000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','Main'),
 ('d1000000-0000-4000-8000-000000000002','d0000000-0000-4000-8000-000000000001','Other');
insert into auth.users(id,email,email_confirmed_at) values
 ('d2000000-0000-4000-8000-000000000001','children-teacher@example.test',now()),
 ('d2000000-0000-4000-8000-000000000002','member-viewer@example.test',now()),
 ('d2000000-0000-4000-8000-000000000003','outsider@example.test',now()),
 ('d2000000-0000-4000-8000-000000000004','admin@example.test',now());
insert into public.roles(id,organization_id,name,is_org_admin,permissions) values
 ('d3000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','Initial account',false,'{}'),
 ('d3000000-0000-4000-8000-000000000002','d0000000-0000-4000-8000-000000000001','Member viewer',false,array['members.view']),
 ('d3000000-0000-4000-8000-000000000003','d0000000-0000-4000-8000-000000000001','Church admin',true,'{}');
insert into public.assignments(user_id,organization_id,branch_id,role_id) values
 ('d2000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','d3000000-0000-4000-8000-000000000001'),
 ('d2000000-0000-4000-8000-000000000002','d0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','d3000000-0000-4000-8000-000000000002'),
 ('d2000000-0000-4000-8000-000000000004','d0000000-0000-4000-8000-000000000001',null,'d3000000-0000-4000-8000-000000000003');
insert into public.church_children(id,organization_id,branch_id,first_name,last_name,parent_contact) values
 ('d4000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','Child','One','Parent'),
 ('d4000000-0000-4000-8000-000000000002','d0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000002','Child','Two','Parent');
insert into public.church_events(id,organization_id,title,starts_at,ends_at,created_by) values
 ('d5000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','Church-wide event',now()-interval '1 hour',now()+interval '1 hour','d2000000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000004',true);
do $$ declare role_id uuid; begin
 role_id := public.save_custom_church_role('d0000000-0000-4000-8000-000000000001',null,'Sunday School Teachers',array['children.view','children.create','children.update','children.delete']);
 perform public.assign_custom_church_role('d0000000-0000-4000-8000-000000000001',role_id,'children-teacher@example.test','d1000000-0000-4000-8000-000000000001');
end $$;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000001',true);
do $$ begin
 if (select count(*) from public.church_children) <> 1 then raise exception 'Children teacher branch scope failed'; end if;
 if (select count(*) from public.church_families) <> 0 then raise exception 'Children-only role can see family records'; end if;
 if (select count(*) from public.members) <> 0 then raise exception 'Children-only role can see member records'; end if;
 insert into public.church_children_events(id,organization_id,branch_id,title,starts_at,ends_at)
 values('d6000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','Sunday School',now()-interval '1 hour',now()+interval '1 hour');
 if public.mark_child_event_attendance('d6000000-0000-4000-8000-000000000001','d4000000-0000-4000-8000-000000000001') is null then raise exception 'Manual child attendance was not recorded'; end if;
 begin perform public.mark_child_event_attendance('d6000000-0000-4000-8000-000000000001','d4000000-0000-4000-8000-000000000002'); raise exception 'Cross-branch attendance accepted'; exception when raise_exception then if sqlerrm = 'Cross-branch attendance accepted' then raise; end if; end;
 begin perform public.mark_child_event_attendance('d6000000-0000-4000-8000-000000000001','d4000000-0000-4000-8000-000000000001'); raise exception 'Duplicate child attendance accepted'; exception when raise_exception then if sqlerrm = 'Duplicate child attendance accepted' then raise; end if; end;
 perform public.remove_child_event_attendance((select id from public.church_children_event_attendance where event_id='d6000000-0000-4000-8000-000000000001'));
 if exists(select 1 from public.church_children_event_attendance where event_id='d6000000-0000-4000-8000-000000000001') then raise exception 'Attendance correction failed'; end if;
end $$;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000002',true);
do $$ begin
 if (select count(*) from public.church_children) <> 1 then raise exception 'Existing member-view access to children was removed'; end if;
 begin
  insert into public.church_children_events(organization_id,branch_id,title,starts_at,ends_at)
  values('d0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','Forbidden',now()-interval '1 hour',now()+interval '1 hour');
  raise exception 'Member-view role created a children event';
 exception when insufficient_privilege then null;
 end;
end $$;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000003',true);
do $$ begin
 if exists(select 1 from public.church_children) or exists(select 1 from public.church_children_events) then raise exception 'Children data leaked to outsider'; end if;
end $$;
reset role;
do $$ begin
 if has_function_privilege('anon','public.mark_child_event_attendance(uuid,uuid)','execute') then raise exception 'Anonymous child attendance execution granted'; end if;
end $$;
rollback;
