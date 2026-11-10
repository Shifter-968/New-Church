-- Run only against an isolated test database after migrations through 031.
begin;
insert into public.organizations(id,name) values ('e0000000-0000-4000-8000-000000000001','Workflow church');
insert into auth.users(id,email,email_confirmed_at) values
 ('e1000000-0000-4000-8000-000000000001','workflow-owner@example.test',now()),
 ('e1000000-0000-4000-8000-000000000002','workflow-member@example.test',now()),
 ('e1000000-0000-4000-8000-000000000003','workflow-admin@example.test',now()),
 ('e1000000-0000-4000-8000-000000000004','workflow-support@example.test',now());
insert into public.platform_owners values ('e1000000-0000-4000-8000-000000000004');
insert into public.roles(id,organization_id,name) values ('e2000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','Member');
insert into public.assignments(user_id,organization_id,role_id)
 select id,'e0000000-0000-4000-8000-000000000001','e2000000-0000-4000-8000-000000000001'
 from auth.users where id in ('e1000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000002','e1000000-0000-4000-8000-000000000003');
set local role authenticated;
select set_config('request.jwt.claim.sub','e1000000-0000-4000-8000-000000000001',true);
select set_config('test.wgroup',public.save_connect_group(null,'e0000000-0000-4000-8000-000000000001',null,'Workflow','','ACTIVE','')::text,true);
select public.add_connect_member(current_setting('test.wgroup')::uuid,'workflow-member@example.test');
select public.add_connect_member(current_setting('test.wgroup')::uuid,'workflow-admin@example.test');
select public.manage_connect_member(current_setting('test.wgroup')::uuid,'e1000000-0000-4000-8000-000000000003','ADMIN','ACTIVE');
select set_config('test.draft',public.save_connect_announcement_workflow(current_setting('test.wgroup')::uuid,null,'Secret draft','Draft text','DRAFT',2::smallint,true)::text,true);
select set_config('test.archive',public.save_connect_announcement_workflow(current_setting('test.wgroup')::uuid,null,'Archive','Archive text','ARCHIVED',0::smallint,false)::text,true);
select set_config('test.normal',public.save_connect_announcement_workflow(current_setting('test.wgroup')::uuid,null,'Normal','Normal text','PUBLISHED',0::smallint,false)::text,true);
select set_config('test.urgent',public.save_connect_announcement_workflow(current_setting('test.wgroup')::uuid,null,'Urgent','Urgent text','PUBLISHED',2::smallint,false)::text,true);
select set_config('test.pin',public.save_connect_announcement_workflow(current_setting('test.wgroup')::uuid,null,'Pinned','Pinned text','PUBLISHED',0::smallint,true)::text,true);
do $$ begin
 if (select count(*) from public.list_connect_announcement_board(current_setting('test.wgroup')::uuid)) <> 5 then raise exception 'Leaders cannot see workflow items'; end if;
 begin
  perform public.save_connect_announcement_workflow(current_setting('test.wgroup')::uuid,null,'No','No','WRONG',0::smallint,false);
  raise exception 'Invalid status accepted';
 exception when raise_exception then if sqlerrm='Invalid status accepted' then raise; end if; end;
 begin
  perform public.save_connect_announcement_workflow(current_setting('test.wgroup')::uuid,null,'No','No','DRAFT',3::smallint,false);
  raise exception 'Invalid priority accepted';
 exception when raise_exception then if sqlerrm='Invalid priority accepted' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','e1000000-0000-4000-8000-000000000002',true);
do $$ declare first_id uuid; second_id uuid; begin
 if (select count(*) from public.list_connect_announcement_board(current_setting('test.wgroup')::uuid)) <> 3 then raise exception 'Draft or archive visible to member'; end if;
 if (select count(*) from public.list_connect_announcements(current_setting('test.wgroup')::uuid)) <> 3 then raise exception 'Old endpoint exposed unpublished content'; end if;
 select id into first_id from public.list_connect_announcement_board(current_setting('test.wgroup')::uuid) limit 1;
 select id into second_id from public.list_connect_announcement_board(current_setting('test.wgroup')::uuid) offset 1 limit 1;
 if first_id <> current_setting('test.pin')::uuid or second_id <> current_setting('test.urgent')::uuid then raise exception 'Board ordering incorrect'; end if;
 begin
  perform public.save_connect_announcement_workflow(current_setting('test.wgroup')::uuid,current_setting('test.draft')::uuid,'No','No','PUBLISHED',0::smallint,false);
  raise exception 'Member changed draft';
 exception when raise_exception then if sqlerrm='Member changed draft' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','e1000000-0000-4000-8000-000000000003',true);
select public.save_connect_announcement_workflow(current_setting('test.wgroup')::uuid,current_setting('test.draft')::uuid,'Now published','Draft text','PUBLISHED',2::smallint,true);
select public.save_connect_announcement_workflow(current_setting('test.wgroup')::uuid,current_setting('test.normal')::uuid,'Normal','Normal text','ARCHIVED',0::smallint,false);
select set_config('request.jwt.claim.sub','e1000000-0000-4000-8000-000000000002',true);
do $$ begin
 if not exists(select 1 from public.list_connect_announcement_board(current_setting('test.wgroup')::uuid) where id=current_setting('test.draft')::uuid and published_at is not null) then raise exception 'Published draft missing'; end if;
 if exists(select 1 from public.list_connect_announcement_board(current_setting('test.wgroup')::uuid) where id=current_setting('test.normal')::uuid) then raise exception 'Archived content visible'; end if;
end $$;
select public.leave_connect_group(current_setting('test.wgroup')::uuid);
do $$ begin
 begin
  perform public.list_connect_announcement_board(current_setting('test.wgroup')::uuid);
  raise exception 'Former member read board';
 exception when raise_exception then if sqlerrm='Former member read board' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','e1000000-0000-4000-8000-000000000004',true);
do $$ begin
 begin
  perform public.list_connect_announcement_board(current_setting('test.wgroup')::uuid);
  raise exception 'Support read board without membership';
 exception when raise_exception then if sqlerrm='Support read board without membership' then raise; end if; end;
end $$;
reset role;
do $$ begin
 if has_function_privilege('anon','public.list_connect_announcement_board(uuid)','execute')
  or has_function_privilege('anon','public.save_connect_announcement_workflow(uuid,uuid,text,text,text,smallint,boolean)','execute') then raise exception 'Anonymous execution allowed'; end if;
end $$;
rollback;
