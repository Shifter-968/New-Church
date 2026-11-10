-- Run only against an isolated test database after migrations through 029.
begin;
insert into public.organizations(id,name) values ('c9000000-0000-4000-8000-000000000001','Leave test');
insert into auth.users(id,email,email_confirmed_at) values
 ('c9100000-0000-4000-8000-000000000001','leave-creator@example.test',now()),
 ('c9100000-0000-4000-8000-000000000002','leave-admin@example.test',now()),
 ('c9100000-0000-4000-8000-000000000003','leave-member@example.test',now()),
 ('c9100000-0000-4000-8000-000000000004','leave-outsider@example.test',now());
insert into public.roles(id,organization_id,name) values
 ('c9200000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','Member');
insert into public.assignments(user_id,organization_id,role_id)
 select id,'c9000000-0000-4000-8000-000000000001','c9200000-0000-4000-8000-000000000001'
 from auth.users where id in ('c9100000-0000-4000-8000-000000000001','c9100000-0000-4000-8000-000000000002','c9100000-0000-4000-8000-000000000003');
set local role authenticated;
select set_config('request.jwt.claim.sub','c9100000-0000-4000-8000-000000000001',true);
select set_config('test.leave_group',public.save_connect_group(null,'c9000000-0000-4000-8000-000000000001',null,'Leave group','','ACTIVE','')::text,true);
select set_config('test.leave_code',(select join_code from public.list_connect_groups('c9000000-0000-4000-8000-000000000001')),true);
select public.add_connect_member(current_setting('test.leave_group')::uuid,'leave-admin@example.test');
select public.add_connect_member(current_setting('test.leave_group')::uuid,'leave-member@example.test');
select public.manage_connect_member(current_setting('test.leave_group')::uuid,'c9100000-0000-4000-8000-000000000002','ADMIN','ACTIVE');
select public.send_connect_message(current_setting('test.leave_group')::uuid,'History remains');
do $$ begin
 begin
  perform public.leave_connect_group(current_setting('test.leave_group')::uuid);
  raise exception 'Creator left';
 exception when raise_exception then if sqlerrm='Creator left' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','c9100000-0000-4000-8000-000000000002',true);
select public.leave_connect_group(current_setting('test.leave_group')::uuid);
do $$ begin
 if exists(select 1 from public.list_connect_groups(null)) then raise exception 'Left group still visible'; end if;
 begin
  perform public.list_connect_messages(current_setting('test.leave_group')::uuid);
  raise exception 'Former member read messages';
 exception when raise_exception then if sqlerrm='Former member read messages' then raise; end if; end;
 begin
  perform public.leave_connect_group(current_setting('test.leave_group')::uuid);
  raise exception 'Repeated leave accepted';
 exception when raise_exception then if sqlerrm='Repeated leave accepted' then raise; end if; end;
end $$;
select public.join_connect_group('c9000000-0000-4000-8000-000000000001',current_setting('test.leave_code'));
do $$ begin
 if not exists(select 1 from public.list_connect_groups(null) where my_role='MEMBER') then raise exception 'Rejoined admin regained privileges'; end if;
 if not exists(select 1 from public.list_connect_messages(current_setting('test.leave_group')::uuid) where content='History remains') then raise exception 'Rejoined member cannot see conversation'; end if;
end $$;
select set_config('request.jwt.claim.sub','c9100000-0000-4000-8000-000000000004',true);
do $$ begin
 begin
  perform public.leave_connect_group(current_setting('test.leave_group')::uuid);
  raise exception 'Outsider left group';
 exception when raise_exception then if sqlerrm='Outsider left group' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','c9100000-0000-4000-8000-000000000001',true);
select public.manage_connect_member(current_setting('test.leave_group')::uuid,'c9100000-0000-4000-8000-000000000003','MEMBER','BANNED');
select set_config('request.jwt.claim.sub','c9100000-0000-4000-8000-000000000003',true);
do $$ begin
 begin
  perform public.leave_connect_group(current_setting('test.leave_group')::uuid);
  raise exception 'Banned member left';
 exception when raise_exception then if sqlerrm='Banned member left' then raise; end if; end;
 begin
  perform public.join_connect_group('c9000000-0000-4000-8000-000000000001',current_setting('test.leave_code'));
  raise exception 'Banned member rejoined';
 exception when raise_exception then if sqlerrm='Banned member rejoined' then raise; end if; end;
end $$;
reset role;
update public.connect_groups set status='ARCHIVED' where id=current_setting('test.leave_group')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub','c9100000-0000-4000-8000-000000000002',true);
select public.leave_connect_group(current_setting('test.leave_group')::uuid);
reset role;
do $$ begin
 if not exists(select 1 from public.connect_members where connect_id=current_setting('test.leave_group')::uuid and user_id='c9100000-0000-4000-8000-000000000002' and status='INACTIVE' and role='MEMBER') then raise exception 'Archived leave failed'; end if;
 if not exists(select 1 from public.support_activity where resource_type='connect_members' and resource_id=current_setting('test.leave_group')::uuid and actor_id='c9100000-0000-4000-8000-000000000002' and action='UPDATE') then raise exception 'Leave not audited'; end if;
 if has_function_privilege('anon','public.leave_connect_group(uuid)','execute') then raise exception 'Anonymous execution allowed'; end if;
end $$;
update public.connect_groups set status='ACTIVE' where id=current_setting('test.leave_group')::uuid;
insert into public.platform_owners values ('c9100000-0000-4000-8000-000000000004');
set local role authenticated;
select set_config('request.jwt.claim.sub','c9100000-0000-4000-8000-000000000004',true);
select public.save_connect_group(current_setting('test.leave_group')::uuid,'c9000000-0000-4000-8000-000000000001',null,'Leave group','','ACTIVE','leave-admin@example.test');
select set_config('request.jwt.claim.sub','c9100000-0000-4000-8000-000000000001',true);
select public.leave_connect_group(current_setting('test.leave_group')::uuid);
do $$ begin
 if exists(select 1 from public.list_connect_groups(null)) then raise exception 'Former creator did not leave'; end if;
end $$;
select set_config('request.jwt.claim.sub','c9100000-0000-4000-8000-000000000002',true);
do $$ begin
 begin
  perform public.leave_connect_group(current_setting('test.leave_group')::uuid);
  raise exception 'New creator left';
 exception when raise_exception then if sqlerrm='New creator left' then raise; end if; end;
end $$;
rollback;
