-- Run only against an isolated test database after migrations through 009.
begin;
insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-4000-8000-000000000001', 'platform@example.test', now()),
 ('00000000-0000-4000-8000-000000000002', 'creator@example.test', now()),
 ('00000000-0000-4000-8000-000000000003', 'moderator@example.test', now()),
 ('00000000-0000-4000-8000-000000000004', 'member@example.test', now()),
 ('00000000-0000-4000-8000-000000000005', 'outsider@example.test', now());
insert into public.platform_owners values ('00000000-0000-4000-8000-000000000001');
insert into public.organizations (id, name) values
 ('10000000-0000-4000-8000-000000000001', 'Church A'),
 ('10000000-0000-4000-8000-000000000002', 'Church B');
insert into public.roles (id, organization_id, name) values
 ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Member'),
 ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', 'Member');
insert into public.assignments (user_id, organization_id, role_id) values
 ('00000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001'),
 ('00000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001'),
 ('00000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001'),
 ('00000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000002', true);
select set_config('test.group_id', public.save_connect_group(null, '10000000-0000-4000-8000-000000000001', null, 'Group', '', 'ACTIVE', '')::text, true);
select public.add_connect_member(current_setting('test.group_id')::uuid, 'moderator@example.test');
select public.add_connect_member(current_setting('test.group_id')::uuid, 'member@example.test');
select public.manage_connect_member(current_setting('test.group_id')::uuid, '00000000-0000-4000-8000-000000000003', 'ADMIN', 'ACTIVE');
select set_config('test.creator_message', public.send_connect_message(current_setting('test.group_id')::uuid, 'Creator message')::text, true);

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000004', true);
select set_config('test.member_message', public.send_connect_message(current_setting('test.group_id')::uuid, 'Member message')::text, true);
select public.edit_connect_message(current_setting('test.group_id')::uuid, current_setting('test.member_message')::uuid, 'Edited member message');
do $$ begin
 begin
   perform public.delete_connect_message(current_setting('test.group_id')::uuid, current_setting('test.creator_message')::uuid);
   raise exception 'Regular member deleted another user message';
 exception when raise_exception then
   if sqlerrm = 'Regular member deleted another user message' then raise; end if;
 end;
 begin
   perform public.manage_connect_member(current_setting('test.group_id')::uuid, '00000000-0000-4000-8000-000000000004', 'ADMIN', 'ACTIVE');
   raise exception 'Regular member promoted themselves';
 exception when raise_exception then
   if sqlerrm = 'Regular member promoted themselves' then raise; end if;
 end;
 begin
   perform * from public.connect_messages;
   raise exception 'Direct message table read allowed';
 exception when insufficient_privilege then null;
 end;
end $$;
select public.delete_connect_message(current_setting('test.group_id')::uuid, current_setting('test.member_message')::uuid);
do $$ begin
 if not exists (select 1 from public.list_connect_messages(current_setting('test.group_id')::uuid)
   where id = current_setting('test.member_message')::uuid and content is null and deleted_at is not null) then
   raise exception 'Own deletion not visible to everyone';
 end if;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000003', true);
select public.delete_connect_message(current_setting('test.group_id')::uuid, current_setting('test.creator_message')::uuid);
do $$ begin
 begin
   perform public.manage_connect_member(current_setting('test.group_id')::uuid, '00000000-0000-4000-8000-000000000004', 'ADMIN', 'ACTIVE');
   raise exception 'Group admin promoted another member';
 exception when raise_exception then
   if sqlerrm = 'Group admin promoted another member' then raise; end if;
 end;
end $$;
select set_config('test.admin_message', public.send_connect_message(current_setting('test.group_id')::uuid, 'Admin message')::text, true);

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000002', true);
select public.delete_connect_message(current_setting('test.group_id')::uuid, current_setting('test.admin_message')::uuid);
select public.manage_connect_member(current_setting('test.group_id')::uuid, '00000000-0000-4000-8000-000000000003', 'MEMBER', 'ACTIVE');
select public.manage_connect_member(current_setting('test.group_id')::uuid, '00000000-0000-4000-8000-000000000004', 'MEMBER', 'BANNED');
select set_config('test.demoted_target', public.send_connect_message(current_setting('test.group_id')::uuid, 'Still visible')::text, true);
do $$ begin
 begin
   perform public.manage_connect_member(current_setting('test.group_id')::uuid, auth.uid(), 'MEMBER', 'INACTIVE');
   raise exception 'Creator was removed';
 exception when raise_exception then
   if sqlerrm = 'Creator was removed' then raise; end if;
 end;
 begin
   perform public.add_connect_member(current_setting('test.group_id')::uuid, 'outsider@example.test');
   raise exception 'Other church added';
 exception when raise_exception then
   if sqlerrm = 'Other church added' then raise; end if;
 end;
end $$;
select set_config('test.join_code', (select join_code from public.list_connect_groups(null)), true);

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000003', true);
do $$ begin
 begin
   perform public.delete_connect_message(current_setting('test.group_id')::uuid, current_setting('test.demoted_target')::uuid);
   raise exception 'Demoted admin retained delete permission';
 exception when raise_exception then
   if sqlerrm = 'Demoted admin retained delete permission' then raise; end if;
 end;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000004', true);
do $$ begin
 begin
   perform public.list_connect_messages(current_setting('test.group_id')::uuid);
   raise exception 'Removed member can read messages';
 exception when raise_exception then
   if sqlerrm = 'Removed member can read messages' then raise; end if;
 end;
 begin
   perform public.join_connect_group('10000000-0000-4000-8000-000000000001', current_setting('test.join_code'));
   raise exception 'Banned member rejoined';
 exception when raise_exception then
   if sqlerrm = 'Banned member rejoined' then raise; end if;
 end;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000002', true);
select public.manage_connect_member(current_setting('test.group_id')::uuid, '00000000-0000-4000-8000-000000000004', 'MEMBER', 'ACTIVE');
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000004', true);
do $$ begin
 if not exists (select 1 from public.list_connect_messages(current_setting('test.group_id')::uuid)
   where id = current_setting('test.demoted_target')::uuid and content = 'Still visible') then
   raise exception 'Restored member cannot read messages';
 end if;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
do $$ begin
 if (select count(*) from public.list_connect_members(current_setting('test.group_id')::uuid)) <> 3 then
   raise exception 'Support cannot view group membership';
 end if;
 if not exists (select 1 from public.support_activity where resource_type = 'connect_members')
   or not exists (select 1 from public.support_activity where resource_type = 'connect_messages') then
   raise exception 'Connect membership or message metadata was not audited';
 end if;
 begin
   perform public.manage_connect_member(current_setting('test.group_id')::uuid, '00000000-0000-4000-8000-000000000003', 'ADMIN', 'ACTIVE');
   raise exception 'Non-member support promoted a group admin';
 exception when raise_exception then
   if sqlerrm = 'Non-member support promoted a group admin' then raise; end if;
 end;
 begin
   perform public.list_connect_messages(current_setting('test.group_id')::uuid);
   raise exception 'Non-member support read private messages';
 exception when raise_exception then
   if sqlerrm = 'Non-member support read private messages' then raise; end if;
 end;
 begin
   perform public.delete_connect_message(current_setting('test.group_id')::uuid, current_setting('test.admin_message')::uuid);
   raise exception 'Non-member support could delete message';
 exception when raise_exception then
   if sqlerrm = 'Non-member support could delete message' then raise; end if;
 end;
end $$;
rollback;
