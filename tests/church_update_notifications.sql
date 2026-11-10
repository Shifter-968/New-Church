-- Isolated PostgreSQL only, after migration 028.
begin;
insert into public.organizations(id,name) values
 ('a8000000-0000-4000-8000-000000000001','Church A'),
 ('a8000000-0000-4000-8000-000000000002','Church B');
insert into auth.users(id,email,email_confirmed_at)
 select ('a8100000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,'notifier' || n || '@example.test',now()
 from generate_series(1,6) n;
insert into public.platform_owners values ('a8100000-0000-4000-8000-000000000006');
insert into public.roles(id,organization_id,name,is_org_admin) values
 ('a8200000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000001','Member',false),
 ('a8200000-0000-4000-8000-000000000002','a8000000-0000-4000-8000-000000000001','Youth',false),
 ('a8200000-0000-4000-8000-000000000003','a8000000-0000-4000-8000-000000000001','Admin',true),
 ('a8200000-0000-4000-8000-000000000004','a8000000-0000-4000-8000-000000000002','Admin',true);
insert into public.assignments(user_id,organization_id,role_id) values
 ('a8100000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000001','a8200000-0000-4000-8000-000000000001'),
 ('a8100000-0000-4000-8000-000000000002','a8000000-0000-4000-8000-000000000001','a8200000-0000-4000-8000-000000000002'),
 ('a8100000-0000-4000-8000-000000000003','a8000000-0000-4000-8000-000000000001','a8200000-0000-4000-8000-000000000003'),
 ('a8100000-0000-4000-8000-000000000004','a8000000-0000-4000-8000-000000000002','a8200000-0000-4000-8000-000000000004');
insert into public.church_teams(id,organization_id,kind,name) values
 ('a8300000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000001','ministry','Choir');
insert into public.members(id,organization_id,user_id,first_name,last_name) values
 ('a8400000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000001','a8100000-0000-4000-8000-000000000001','First','Member');
insert into public.church_team_members(organization_id,team_id,member_id) values
 ('a8000000-0000-4000-8000-000000000001','a8300000-0000-4000-8000-000000000001','a8400000-0000-4000-8000-000000000001');
insert into public.announcements(id,organization_id,title,content,created_by,audience_everyone,audience_roles,audience_teams) values
 ('a8500000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000001','All notice','Hello','a8100000-0000-4000-8000-000000000003',true,'{}','{}'),
 ('a8500000-0000-4000-8000-000000000002','a8000000-0000-4000-8000-000000000001','Youth notice','Hello','a8100000-0000-4000-8000-000000000003',false,array['a8200000-0000-4000-8000-000000000002']::uuid[],'{}'),
 ('a8500000-0000-4000-8000-000000000003','a8000000-0000-4000-8000-000000000001','Choir notice','Hello','a8100000-0000-4000-8000-000000000003',false,'{}',array['a8300000-0000-4000-8000-000000000001']::uuid[]),
 ('a8500000-0000-4000-8000-000000000004','a8000000-0000-4000-8000-000000000002','Other church','Hello','a8100000-0000-4000-8000-000000000004',true,'{}','{}');
insert into public.church_events(id,organization_id,title,starts_at,ends_at,created_by) values
 ('a8600000-0000-4000-8000-000000000001','a8000000-0000-4000-8000-000000000001','Service',now(),now()+interval '1 hour','a8100000-0000-4000-8000-000000000003');
select set_config('test.hidden_notice',(select id::text from public.church_update_notices where announcement_id='a8500000-0000-4000-8000-000000000002'),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','a8100000-0000-4000-8000-000000000001',true);
do $$ declare notice uuid; unread uuid; begin
 if (select count(*) from public.my_church_update_notices()) <> 3 then raise exception 'Member audiences incorrect'; end if;
 if not exists(select 1 from public.my_church_update_notices() where kind='event' and title='Service') then raise exception 'Event notice missing'; end if;
 select notice_id into notice from public.my_church_update_notices() where title='All notice';
 perform public.mark_church_update_notices_read(array[notice,notice]);
 perform public.mark_church_update_notices_read(array[notice]);
 if not exists(select 1 from public.my_church_update_notices() where notice_id=notice and read_at is not null) then raise exception 'Read state missing'; end if;
 begin perform count(*) from public.church_update_notices; raise exception 'Direct notices exposed'; exception when insufficient_privilege then null; end;
 begin perform count(*) from public.church_update_notice_reads; raise exception 'Direct reads exposed'; exception when insufficient_privilege then null; end;
 begin perform public.mark_church_update_notices_read('{}'); raise exception 'Empty request accepted'; exception when raise_exception then if sqlerrm='Empty request accepted' then raise; end if; end;
 begin perform public.mark_church_update_notices_read(array[gen_random_uuid()]); raise exception 'Invisible notice marked'; exception when raise_exception then if sqlerrm='Invisible notice marked' then raise; end if; end;
 select notice_id into unread from public.my_church_update_notices() where title='Choir notice';
 begin perform public.mark_church_update_notices_read(array[unread,current_setting('test.hidden_notice')::uuid]); raise exception 'Mixed request accepted'; exception when raise_exception then if sqlerrm='Mixed request accepted' then raise; end if; end;
 if exists(select 1 from public.my_church_update_notices() where notice_id=unread and read_at is not null) then raise exception 'Invalid request partially marked'; end if;
 begin perform public.mark_church_update_notices_read(array_fill(notice,array[101])); raise exception 'Oversized request accepted'; exception when raise_exception then if sqlerrm='Oversized request accepted' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','a8100000-0000-4000-8000-000000000002',true);
do $$ begin
 if (select count(*) from public.my_church_update_notices()) <> 3 then raise exception 'Youth audience incorrect'; end if;
 if exists(select 1 from public.my_church_update_notices() where title='All notice' and read_at is not null) then raise exception 'Read state leaked between users'; end if;
 if exists(select 1 from public.my_church_update_notices() where title='Choir notice') then raise exception 'Team audience leaked'; end if;
end $$;
select set_config('request.jwt.claim.sub','a8100000-0000-4000-8000-000000000004',true);
do $$ begin if (select count(*) from public.my_church_update_notices()) <> 1 then raise exception 'Other church isolation failed'; end if; end $$;
select set_config('request.jwt.claim.sub','a8100000-0000-4000-8000-000000000005',true);
do $$ begin if exists(select 1 from public.my_church_update_notices()) then raise exception 'Unassigned account received updates'; end if; end $$;
select set_config('request.jwt.claim.sub','a8100000-0000-4000-8000-000000000006',true);
do $$ begin if (select count(*) from public.my_church_update_notices()) <> 5 then raise exception 'Owner visibility incorrect'; end if; end $$;
select set_config('request.jwt.claim.sub','a8100000-0000-4000-8000-000000000003',true);
insert into public.announcements(id,organization_id,title,content) values ('a8500000-0000-4000-8000-000000000005','a8000000-0000-4000-8000-000000000001','Admin published','Hello');
do $$ begin if not exists(select 1 from public.my_church_update_notices() where title='Admin published') then raise exception 'Authenticated publication did not create notice'; end if; end $$;
delete from public.announcements where id='a8500000-0000-4000-8000-000000000005';
update public.announcements set title='Updated title' where id='a8500000-0000-4000-8000-000000000001';
delete from public.announcements where id='a8500000-0000-4000-8000-000000000002';
reset role;
delete from public.church_team_members where team_id='a8300000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','a8100000-0000-4000-8000-000000000001',true);
do $$ begin
 if (select count(*) from public.my_church_update_notices()) <> 2 then raise exception 'Deletion or team revocation not applied'; end if;
 if not exists(select 1 from public.my_church_update_notices() where title='Updated title' and read_at is not null) then raise exception 'Updated title or read state incorrect'; end if;
end $$;
reset role;
update public.assignments set active=false where user_id='a8100000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ begin if exists(select 1 from public.my_church_update_notices()) then raise exception 'Assignment revocation failed'; end if; end $$;
reset role;
update public.assignments set active=true where user_id='a8100000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ begin if not exists(select 1 from public.my_church_update_notices() where title='Updated title' and read_at is not null) then raise exception 'Reacquired notice lost read state'; end if; end $$;
reset role;
insert into public.announcements(organization_id,title,content)
 select 'a8000000-0000-4000-8000-000000000001','Batch ' || n,'Hello' from generate_series(1,105) n;
set local role authenticated;
do $$ begin if (select count(*) from public.my_church_update_notices()) <> 100 then raise exception 'Inbox limit failed'; end if; end $$;
rollback;
