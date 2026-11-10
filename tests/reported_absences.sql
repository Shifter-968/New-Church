-- Isolated PostgreSQL only, after migration 024.
begin;
insert into public.organizations(id,name) values
 ('b0000000-0000-4000-8000-000000000001','Church A'),
 ('b0000000-0000-4000-8000-000000000002','Church B');
insert into public.branches(id,organization_id,name,latitude,longitude,radius_meters) values
 ('b1000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','Main',0,0,100),
 ('b1000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','Other',0,0,100);
insert into auth.users(id,email,email_confirmed_at)
 select ('b2000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,'test' || n || '@example.test',now()
 from generate_series(1,8) n;
insert into public.platform_owners values ('b2000000-0000-4000-8000-000000000008');
insert into public.roles(id,organization_id,name,is_org_admin,permissions) values
 ('b3000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','Person',false,'{}'),
 ('b3000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','Reviewer',false,array['attendance.absences.view']),
 ('b3000000-0000-4000-8000-000000000003','b0000000-0000-4000-8000-000000000001','Admin',true,'{}'),
 ('b3000000-0000-4000-8000-000000000004','b0000000-0000-4000-8000-000000000002','Admin',true,'{}');
insert into public.assignments(user_id,organization_id,branch_id,role_id) values
 ('b2000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','b3000000-0000-4000-8000-000000000001'),
 ('b2000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000002','b3000000-0000-4000-8000-000000000001'),
 ('b2000000-0000-4000-8000-000000000003','b0000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','b3000000-0000-4000-8000-000000000002'),
 ('b2000000-0000-4000-8000-000000000004','b0000000-0000-4000-8000-000000000001',null,'b3000000-0000-4000-8000-000000000003'),
 ('b2000000-0000-4000-8000-000000000005','b0000000-0000-4000-8000-000000000002',null,'b3000000-0000-4000-8000-000000000004'),
 ('b2000000-0000-4000-8000-000000000006','b0000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','b3000000-0000-4000-8000-000000000001');
insert into public.members(id,organization_id,branch_id,user_id,first_name,last_name,phone) values
 ('b4000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000001','Member','One','123'),
 ('b4000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000002','b2000000-0000-4000-8000-000000000002','Member','Two',null);
insert into public.visitors(id,organization_id,branch_id,user_id,first_name,last_name) values
 ('b5000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000006','Visitor','One');
insert into public.church_events(id,organization_id,title,starts_at,ends_at,created_by,audience_everyone,audience_roles) values
 ('b6000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','Service',now()-interval '1 hour',now()+interval '1 hour','b2000000-0000-4000-8000-000000000004',true,'{}'),
 ('b6000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','Past',now()-interval '2 hours',now()-interval '1 hour','b2000000-0000-4000-8000-000000000004',true,'{}'),
 ('b6000000-0000-4000-8000-000000000003','b0000000-0000-4000-8000-000000000001','Private',now(),now()+interval '1 hour','b2000000-0000-4000-8000-000000000004',false,array['b3000000-0000-4000-8000-000000000002']::uuid[]),
 ('b6000000-0000-4000-8000-000000000004','b0000000-0000-4000-8000-000000000002','Other church',now(),now()+interval '1 hour','b2000000-0000-4000-8000-000000000005',true,'{}');
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000001',true);
do $$ begin
 if (select count(*) from public.my_absence_events('b0000000-0000-4000-8000-000000000001')) <> 1 then raise exception 'Eligible events incorrect'; end if;
 begin perform public.report_my_absence('b6000000-0000-4000-8000-000000000003',''); raise exception 'Private event accepted'; exception when raise_exception then if sqlerrm='Private event accepted' then raise; end if; end;
 begin perform public.report_my_absence('b6000000-0000-4000-8000-000000000002',''); raise exception 'Past event accepted'; exception when raise_exception then if sqlerrm='Past event accepted' then raise; end if; end;
 begin perform public.report_my_absence('b6000000-0000-4000-8000-000000000004',''); raise exception 'Other church accepted'; exception when raise_exception then if sqlerrm='Other church accepted' then raise; end if; end;
 begin perform public.report_my_absence('b6000000-0000-4000-8000-000000000001',repeat('x',501)); raise exception 'Long reason accepted'; exception when raise_exception then if sqlerrm='Long reason accepted' then raise; end if; end;
 begin perform count(*) from public.reported_absences; raise exception 'Direct access allowed'; exception when insufficient_privilege then null; end;
 perform public.report_my_absence('b6000000-0000-4000-8000-000000000001','First');
 perform public.report_my_absence('b6000000-0000-4000-8000-000000000001','Updated');
 if not exists(select 1 from public.my_absence_events('b0000000-0000-4000-8000-000000000001') where reported and reason='Updated' and not present) then raise exception 'Notice not shown'; end if;
 if exists(select 1 from public.list_reported_absences('b0000000-0000-4000-8000-000000000001')) then raise exception 'Member saw management list'; end if;
end $$;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000002',true);
select public.report_my_absence('b6000000-0000-4000-8000-000000000001','');
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000006',true);
select public.report_my_absence('b6000000-0000-4000-8000-000000000001','Visitor notice');
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000003',true);
do $$ begin
 if (select count(*) from public.list_reported_absences('b0000000-0000-4000-8000-000000000001')) <> 2 then raise exception 'Branch visibility incorrect'; end if;
 if not exists(select 1 from public.list_reported_absences('b0000000-0000-4000-8000-000000000001') where person_kind='visitor') then raise exception 'Visitor missing'; end if;
 begin perform public.withdraw_my_absence('b6000000-0000-4000-8000-000000000001'); raise exception 'Other user withdrew report'; exception when raise_exception then if sqlerrm='Other user withdrew report' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000005',true);
do $$ begin if exists(select 1 from public.list_reported_absences('b0000000-0000-4000-8000-000000000001')) then raise exception 'Cross church leaked'; end if; end $$;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000004',true);
do $$ begin
 if (select count(*) from public.list_reported_absences('b0000000-0000-4000-8000-000000000001')) <> 3 then raise exception 'Admin cannot see reports'; end if;
 perform public.save_custom_church_role('b0000000-0000-4000-8000-000000000001',null,'Follow-up',array['attendance.absences.view']);
 perform public.admin_check_in('b6000000-0000-4000-8000-000000000001','member','b4000000-0000-4000-8000-000000000001');
 if not exists(select 1 from public.list_reported_absences('b0000000-0000-4000-8000-000000000001') where person_name='Member One' and present) then raise exception 'Later attendance not shown'; end if;
 if not exists(select 1 from public.support_activity where resource_type='reported_absences' and action='INSERT') then raise exception 'Audit missing'; end if;
end $$;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000001',true);
do $$ begin
 begin perform public.report_my_absence('b6000000-0000-4000-8000-000000000001',''); raise exception 'Present person reported absence'; exception when raise_exception then if sqlerrm='Present person reported absence' then raise; end if; end;
 perform public.withdraw_my_absence('b6000000-0000-4000-8000-000000000001');
 if exists(select 1 from public.my_absence_events('b0000000-0000-4000-8000-000000000001') where reported) then raise exception 'Notice remains'; end if;
end $$;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000008',true);
do $$ begin if (select count(*) from public.list_reported_absences('b0000000-0000-4000-8000-000000000001')) <> 2 then raise exception 'Owner cannot see reports'; end if; end $$;
reset role;
update public.church_events set starts_at=now()-interval '2 hours', ends_at=now()-interval '1 hour' where id='b6000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000006',true);
do $$ begin
 if not exists(select 1 from public.my_absence_events('b0000000-0000-4000-8000-000000000001') where reported) then raise exception 'Past notice unavailable'; end if;
 perform public.withdraw_my_absence('b6000000-0000-4000-8000-000000000001');
end $$;
rollback;
