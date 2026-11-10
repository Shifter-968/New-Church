-- Run only against an isolated test database after migrations through 030.
begin;
insert into public.organizations(id,name) values
 ('d0000000-0000-4000-8000-000000000001','Announcement church'),
 ('d0000000-0000-4000-8000-000000000002','Other church');
insert into auth.users(id,email,email_confirmed_at) values
 ('d1000000-0000-4000-8000-000000000001','announce-creator@example.test',now()),
 ('d1000000-0000-4000-8000-000000000002','announce-admin@example.test',now()),
 ('d1000000-0000-4000-8000-000000000003','announce-member@example.test',now()),
 ('d1000000-0000-4000-8000-000000000004','announce-support@example.test',now()),
 ('d1000000-0000-4000-8000-000000000005','announce-outsider@example.test',now());
insert into public.platform_owners values ('d1000000-0000-4000-8000-000000000004');
insert into public.roles(id,organization_id,name) values
 ('d2000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','Member'),
 ('d2000000-0000-4000-8000-000000000002','d0000000-0000-4000-8000-000000000002','Member');
insert into public.assignments(user_id,organization_id,role_id) values
 ('d1000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000001'),
 ('d1000000-0000-4000-8000-000000000002','d0000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000001'),
 ('d1000000-0000-4000-8000-000000000003','d0000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000001'),
 ('d1000000-0000-4000-8000-000000000005','d0000000-0000-4000-8000-000000000002','d2000000-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-000000000001',true);
select set_config('test.announce_group',public.save_connect_group(null,'d0000000-0000-4000-8000-000000000001',null,'Announcements','','ACTIVE','')::text,true);
select set_config('test.other_group',public.save_connect_group(null,'d0000000-0000-4000-8000-000000000001',null,'Other','','ACTIVE','')::text,true);
select public.add_connect_member(current_setting('test.announce_group')::uuid,'announce-admin@example.test');
select public.add_connect_member(current_setting('test.announce_group')::uuid,'announce-member@example.test');
select public.manage_connect_member(current_setting('test.announce_group')::uuid,'d1000000-0000-4000-8000-000000000002','ADMIN','ACTIVE');
select set_config('test.announcement',public.save_connect_announcement(current_setting('test.announce_group')::uuid,null,'  Welcome  ',' Group news ')::text,true);
do $$ begin
 if not exists(select 1 from public.list_connect_announcements(current_setting('test.announce_group')::uuid) where title='Welcome' and content='Group news') then raise exception 'Announcement missing'; end if;
 begin
  perform public.save_connect_announcement(current_setting('test.other_group')::uuid,current_setting('test.announcement')::uuid,'Cross group','Invalid');
  raise exception 'Cross-group edit accepted';
 exception when raise_exception then if sqlerrm='Cross-group edit accepted' then raise; end if; end;
 begin
  perform public.save_connect_announcement(current_setting('test.announce_group')::uuid,null,'   ','Invalid');
  raise exception 'Blank title accepted';
 exception when raise_exception then if sqlerrm='Blank title accepted' then raise; end if; end;
 begin
  perform * from public.connect_announcements;
  raise exception 'Direct table exposed';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-000000000003',true);
do $$ begin
 if (select count(*) from public.list_connect_announcements(current_setting('test.announce_group')::uuid)) <> 1 then raise exception 'Member cannot read'; end if;
 begin
  perform public.save_connect_announcement(current_setting('test.announce_group')::uuid,null,'No','No');
  raise exception 'Member published';
 exception when raise_exception then if sqlerrm='Member published' then raise; end if; end;
 begin
  perform public.delete_connect_announcement(current_setting('test.announce_group')::uuid,current_setting('test.announcement')::uuid);
  raise exception 'Member deleted';
 exception when raise_exception then if sqlerrm='Member deleted' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-000000000004',true);
do $$ begin
 begin
  perform public.list_connect_announcements(current_setting('test.announce_group')::uuid);
  raise exception 'Non-member support read content';
 exception when raise_exception then if sqlerrm='Non-member support read content' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-000000000005',true);
do $$ begin
 begin
  perform public.list_connect_announcements(current_setting('test.announce_group')::uuid);
  raise exception 'Outsider read content';
 exception when raise_exception then if sqlerrm='Outsider read content' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-000000000002',true);
select public.save_connect_announcement(current_setting('test.announce_group')::uuid,current_setting('test.announcement')::uuid,'Edited','Updated');
do $$ begin
 if not exists(select 1 from public.list_connect_announcements(current_setting('test.announce_group')::uuid) where title='Edited' and edited_at is not null) then raise exception 'Admin edit failed'; end if;
end $$;
select public.delete_connect_announcement(current_setting('test.announce_group')::uuid,current_setting('test.announcement')::uuid);
select set_config('test.announcement',public.save_connect_announcement(current_setting('test.announce_group')::uuid,null,'New','Visible')::text,true);
select public.leave_connect_group(current_setting('test.announce_group')::uuid);
do $$ begin
 begin
  perform public.list_connect_announcements(current_setting('test.announce_group')::uuid);
  raise exception 'Former member read content';
 exception when raise_exception then if sqlerrm='Former member read content' then raise; end if; end;
end $$;
reset role;
update public.connect_groups set status='ARCHIVED' where id=current_setting('test.announce_group')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-000000000003',true);
do $$ begin
 begin
  perform public.list_connect_announcements(current_setting('test.announce_group')::uuid);
  raise exception 'Archived content visible';
 exception when raise_exception then if sqlerrm='Archived content visible' then raise; end if; end;
end $$;
reset role;
update public.connect_groups set status='ACTIVE' where id=current_setting('test.announce_group')::uuid;
update public.assignments set active=false where user_id='d1000000-0000-4000-8000-000000000003';
set local role authenticated;
do $$ begin
 begin
  perform public.list_connect_announcements(current_setting('test.announce_group')::uuid);
  raise exception 'Unassigned member read content';
 exception when raise_exception then if sqlerrm='Unassigned member read content' then raise; end if; end;
end $$;
reset role;
update public.assignments set active=true where user_id='d1000000-0000-4000-8000-000000000003';
insert into public.connect_announcements(connect_id,author_id,title,content)
 select current_setting('test.announce_group')::uuid,'d1000000-0000-4000-8000-000000000001','Notice ' || n,'Text' from generate_series(1,105) n;
set local role authenticated;
do $$ begin
 if (select count(*) from public.list_connect_announcements(current_setting('test.announce_group')::uuid)) <> 100 then raise exception 'List limit incorrect'; end if;
end $$;
reset role;
do $$ begin
 if (select count(*) from public.support_activity where resource_type='connect_announcements' and resource_id=current_setting('test.announcement')::uuid and action='INSERT') <> 1 then raise exception 'Missing audit metadata'; end if;
 if not exists(select 1 from public.support_activity where resource_type='connect_announcements' and action='DELETE') then raise exception 'Missing deletion audit'; end if;
 if has_function_privilege('anon','public.list_connect_announcements(uuid)','execute') then raise exception 'Anonymous execution allowed'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','d1000000-0000-4000-8000-000000000001',true);
select public.delete_connect_group(current_setting('test.announce_group')::uuid);
reset role;
do $$ begin
 if exists(select 1 from public.connect_announcements where connect_id=current_setting('test.announce_group')::uuid) then raise exception 'Group deletion did not remove announcements'; end if;
end $$;
rollback;
