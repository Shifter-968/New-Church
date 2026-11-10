-- Run only against an isolated test database after migrations through 033.
begin;
insert into public.organizations(id,name) values ('b1000000-0000-4000-8000-000000000001','Read test');
insert into auth.users(id,email,email_confirmed_at) values
 ('b2000000-0000-4000-8000-000000000001','read-creator@example.test',now()),
 ('b2000000-0000-4000-8000-000000000002','read-member@example.test',now()),
 ('b2000000-0000-4000-8000-000000000003','read-other@example.test',now()),
 ('b2000000-0000-4000-8000-000000000004','read-support@example.test',now());
insert into public.platform_owners values ('b2000000-0000-4000-8000-000000000004');
insert into public.roles(id,organization_id,name) values
 ('b3000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','Member');
insert into public.assignments(user_id,organization_id,role_id)
 select id,'b1000000-0000-4000-8000-000000000001','b3000000-0000-4000-8000-000000000001'
 from auth.users where id in ('b2000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000002','b2000000-0000-4000-8000-000000000003');
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000001',true);
select set_config('test.group',public.save_connect_group(null,'b1000000-0000-4000-8000-000000000001',null,'Read group','','ACTIVE','')::text,true);
select set_config('test.other_group',public.save_connect_group(null,'b1000000-0000-4000-8000-000000000001',null,'Other group','','ACTIVE','')::text,true);
select public.add_connect_member(current_setting('test.group')::uuid,'read-member@example.test');
select public.add_connect_member(current_setting('test.group')::uuid,'read-other@example.test');
select set_config('test.code',(select join_code from public.list_connect_groups(null) where id=current_setting('test.group')::uuid),true);
select set_config('test.news',public.save_connect_announcement_workflow(current_setting('test.group')::uuid,null,'News','Message','PUBLISHED',0::smallint,false)::text,true);
select set_config('test.draft',public.save_connect_announcement_workflow(current_setting('test.group')::uuid,null,'Private','Draft','DRAFT',0::smallint,false)::text,true);
select set_config('test.archive',public.save_connect_announcement_workflow(current_setting('test.group')::uuid,null,'Archived','Archive','ARCHIVED',0::smallint,false)::text,true);
select public.manage_connect_member(current_setting('test.group')::uuid,'b2000000-0000-4000-8000-000000000003','ADMIN','ACTIVE');
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000003',true);
select public.mark_connect_announcement_read(current_setting('test.group')::uuid,current_setting('test.draft')::uuid,1);
select public.mark_connect_announcement_read(current_setting('test.group')::uuid,current_setting('test.archive')::uuid,1);
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000001',true);
do $$ begin
 begin
  perform public.mark_connect_announcement_read(current_setting('test.other_group')::uuid,current_setting('test.news')::uuid,1);
  raise exception 'Cross-group mark accepted';
 exception when raise_exception then if sqlerrm='Cross-group mark accepted' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000002',true);
do $$ begin
 if not exists(select 1 from public.my_connect_announcement_board(current_setting('test.group')::uuid) where id=current_setting('test.news')::uuid and read_at is null and revision=1) then raise exception 'Initial unread state missing'; end if;
 begin
  perform public.mark_connect_announcement_read(current_setting('test.group')::uuid,current_setting('test.draft')::uuid,1);
  raise exception 'Member marked draft';
 exception when raise_exception then if sqlerrm='Member marked draft' then raise; end if; end;
 begin
  perform public.mark_connect_announcement_read(current_setting('test.group')::uuid,current_setting('test.archive')::uuid,1);
  raise exception 'Member marked archive';
 exception when raise_exception then if sqlerrm='Member marked archive' then raise; end if; end;
 begin
  perform public.mark_connect_announcement_read(current_setting('test.group')::uuid,current_setting('test.news')::uuid,null);
  raise exception 'Null revision accepted';
 exception when raise_exception then if sqlerrm='Null revision accepted' then raise; end if; end;
 begin
  perform count(*) from public.connect_announcement_reads;
  raise exception 'Private reads exposed';
 exception when insufficient_privilege then null; end;
end $$;
select public.mark_connect_announcement_read(current_setting('test.group')::uuid,current_setting('test.news')::uuid,1);
select public.mark_connect_announcement_read(current_setting('test.group')::uuid,current_setting('test.news')::uuid,1);
do $$ begin
 if not exists(select 1 from public.my_connect_announcement_board(current_setting('test.group')::uuid) where id=current_setting('test.news')::uuid and read_at is not null) then raise exception 'Read state missing'; end if;
end $$;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000003',true);
do $$ begin
 if not exists(select 1 from public.my_connect_announcement_board(current_setting('test.group')::uuid) where id=current_setting('test.news')::uuid and read_at is null) then raise exception 'Read state leaked between users'; end if;
end $$;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000001',true);
select public.save_connect_announcement_workflow(current_setting('test.group')::uuid,current_setting('test.news')::uuid,'News','Message','PUBLISHED',2::smallint,true);
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000002',true);
do $$ begin
 if not exists(select 1 from public.my_connect_announcement_board(current_setting('test.group')::uuid) where id=current_setting('test.news')::uuid and read_at is not null and revision=1) then raise exception 'Priority reset read'; end if;
end $$;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000001',true);
select public.save_connect_announcement_workflow(current_setting('test.group')::uuid,current_setting('test.news')::uuid,'Updated','Message','PUBLISHED',2::smallint,true);
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000002',true);
do $$ begin
 if not exists(select 1 from public.my_connect_announcement_board(current_setting('test.group')::uuid) where id=current_setting('test.news')::uuid and read_at is null and revision=2) then raise exception 'Edit did not reset read'; end if;
 begin
  perform public.mark_connect_announcement_read(current_setting('test.group')::uuid,current_setting('test.news')::uuid,1);
  raise exception 'Stale mark accepted';
 exception when raise_exception then if sqlerrm='Stale mark accepted' then raise; end if; end;
end $$;
select public.mark_connect_announcement_read(current_setting('test.group')::uuid,current_setting('test.news')::uuid,2);
select public.leave_connect_group(current_setting('test.group')::uuid);
do $$ begin
 begin
  perform public.mark_connect_announcement_read(current_setting('test.group')::uuid,current_setting('test.news')::uuid,2);
  raise exception 'Former member marked read';
 exception when raise_exception then if sqlerrm='Former member marked read' then raise; end if; end;
end $$;
select public.join_connect_group('b1000000-0000-4000-8000-000000000001',current_setting('test.code'));
do $$ begin if not exists(select 1 from public.my_connect_announcement_board(current_setting('test.group')::uuid) where id=current_setting('test.news')::uuid and read_at is not null) then raise exception 'Rejoin lost read state'; end if; end $$;
reset role;
update public.assignments set active=false where user_id='b2000000-0000-4000-8000-000000000002';
set local role authenticated;
do $$ begin
 begin
  perform public.my_connect_announcement_board(current_setting('test.group')::uuid);
  raise exception 'Former assignee read board';
 exception when raise_exception then if sqlerrm='Former assignee read board' then raise; end if; end;
 begin
  perform public.mark_connect_announcement_read(current_setting('test.group')::uuid,current_setting('test.news')::uuid,2);
  raise exception 'Former assignee marked read';
 exception when raise_exception then if sqlerrm='Former assignee marked read' then raise; end if; end;
end $$;
reset role;
update public.assignments set active=true where user_id='b2000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000001',true);
select public.save_connect_announcement_workflow(current_setting('test.group')::uuid,current_setting('test.news')::uuid,'Updated','Message','ARCHIVED',2::smallint,true);
select public.save_connect_announcement_workflow(current_setting('test.group')::uuid,current_setting('test.news')::uuid,'Updated','Message','PUBLISHED',2::smallint,true);
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000002',true);
do $$ begin if not exists(select 1 from public.my_connect_announcement_board(current_setting('test.group')::uuid) where id=current_setting('test.news')::uuid and read_at is null and revision=3) then raise exception 'Republish did not reset read'; end if; end $$;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000004',true);
do $$ begin
 begin
  perform public.my_connect_announcement_board(current_setting('test.group')::uuid);
  raise exception 'Non-member support read board';
 exception when raise_exception then if sqlerrm='Non-member support read board' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000001',true);
select public.delete_connect_announcement(current_setting('test.group')::uuid,current_setting('test.news')::uuid);
reset role;
do $$ begin
 if exists(select 1 from public.connect_announcement_reads where announcement_id=current_setting('test.news')::uuid) then raise exception 'Delete retained read markers'; end if;
 if has_function_privilege('anon','public.mark_connect_announcement_read(uuid,uuid,bigint)','execute')
  or has_function_privilege('anon','public.my_connect_announcement_board(uuid)','execute') then raise exception 'Anonymous access permitted'; end if;
end $$;
insert into public.connect_announcements(connect_id,author_id,title,content)
 select current_setting('test.group')::uuid,'b2000000-0000-4000-8000-000000000001','Bulk ' || n,'Message'
 from generate_series(1,105) n;
set local role authenticated;
do $$ begin
 if (select count(*) from public.my_connect_announcement_board(current_setting('test.group')::uuid)) <> 100 then raise exception 'Board limit incorrect'; end if;
 if (select count(*) from public.list_connect_announcement_board(current_setting('test.group')::uuid)) <> 100 then raise exception 'Old board limit changed'; end if;
 if (select count(*) from public.list_connect_announcements(current_setting('test.group')::uuid)) <> 100 then raise exception 'Old published endpoint changed'; end if;
end $$;
rollback;
