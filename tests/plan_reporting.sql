-- Isolated PostgreSQL only, after migration 021.
begin;
insert into public.organizations(id,name) values
 ('91000000-0000-4000-8000-000000000001','Church A'),
 ('91000000-0000-4000-8000-000000000002','Church B');
insert into public.branches(id,organization_id,name) values
 ('92000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','Main'),
 ('92000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000001','Other'),
 ('92000000-0000-4000-8000-000000000003','91000000-0000-4000-8000-000000000002','Elsewhere');
insert into auth.users(id,email,email_confirmed_at) values
 ('93000000-0000-4000-8000-000000000001','admin@example.test',now()),
 ('93000000-0000-4000-8000-000000000002','branch@example.test',now()),
 ('93000000-0000-4000-8000-000000000003','owner@example.test',now()),
 ('93000000-0000-4000-8000-000000000004','other@example.test',now());
insert into public.platform_owners values ('93000000-0000-4000-8000-000000000003');
insert into public.roles(id,organization_id,name,is_org_admin,permissions) values
 ('94000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','Admin',true,'{}'),
 ('94000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000001','Branch',false,array['members.view','reports.view']),
 ('94000000-0000-4000-8000-000000000003','91000000-0000-4000-8000-000000000002','Admin',true,'{}');
insert into public.assignments(user_id,organization_id,branch_id,role_id) values
 ('93000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001',null,'94000000-0000-4000-8000-000000000001'),
 ('93000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000002'),
 ('93000000-0000-4000-8000-000000000004','91000000-0000-4000-8000-000000000002',null,'94000000-0000-4000-8000-000000000003');
insert into public.plans(id,name,price,currency,billing_period,include_analytics,include_advanced_reporting,is_active) values
 ('95000000-0000-4000-8000-000000000001','Analytics',10,'SZL','MONTHLY',true,false,true),
 ('95000000-0000-4000-8000-000000000002','Reporting',10,'SZL','MONTHLY',false,true,true),
 ('95000000-0000-4000-8000-000000000003','Both',10,'SZL','MONTHLY',true,true,true),
 ('95000000-0000-4000-8000-000000000004','Inactive',10,'SZL','MONTHLY',true,true,false);
insert into public.members(id,organization_id,branch_id,first_name,last_name,status) values
 ('96000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','Active','Member','active'),
 ('96000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000002','Inactive','Member','inactive'),
 ('96000000-0000-4000-8000-000000000003','91000000-0000-4000-8000-000000000002','92000000-0000-4000-8000-000000000003','Other','Church','active');
insert into public.visitors(id,organization_id,branch_id,first_name,last_name) values
 ('97000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','Visitor','One');
insert into public.church_events(id,organization_id,title,starts_at,ends_at,created_by) values
 ('98000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','Service',now()-interval '1 hour',now(),'93000000-0000-4000-8000-000000000001');
insert into public.event_attendance(organization_id,event_id,branch_id,member_id,checked_in_by,method) values
 ('91000000-0000-4000-8000-000000000001','98000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','96000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000001','admin');
set local role authenticated;
select set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000001',true);
do $$ begin
 begin perform public.church_analytics('91000000-0000-4000-8000-000000000001'); raise exception 'Unassigned analytics allowed'; exception when raise_exception then if sqlerrm='Unassigned analytics allowed' then raise; end if; end;
 begin perform public.set_organization_plan('91000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000003'); raise exception 'Admin can assign plan'; exception when raise_exception then if sqlerrm='Admin can assign plan' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000003',true);
do $$ begin
 begin perform public.set_organization_plan('91000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000004'); raise exception 'Inactive plan assigned'; exception when raise_exception then if sqlerrm='Inactive plan assigned' then raise; end if; end;
 perform public.set_organization_plan('91000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000001');
end $$;
select set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000001',true);
do $$ begin
 if not exists(select 1 from public.church_analytics('91000000-0000-4000-8000-000000000001') where active_members=1 and visitors=1 and branches=2 and checkins_last_30_days=1) then raise exception 'Analytics totals incorrect'; end if;
 begin perform public.church_branch_report('91000000-0000-4000-8000-000000000001'); raise exception 'Unincluded report allowed'; exception when raise_exception then if sqlerrm='Unincluded report allowed' then raise; end if; end;
 begin perform count(*) from public.organization_plan_assignments; raise exception 'Direct plan assignment access allowed'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000002',true);
do $$ begin
 begin perform public.church_analytics('91000000-0000-4000-8000-000000000001'); raise exception 'Branch analytics leaked'; exception when raise_exception then if sqlerrm='Branch analytics leaked' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000004',true);
do $$ begin
 begin perform public.church_analytics('91000000-0000-4000-8000-000000000001'); raise exception 'Cross-church analytics leaked'; exception when raise_exception then if sqlerrm='Cross-church analytics leaked' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000003',true);
do $$ begin perform public.set_organization_plan('91000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000002'); end $$;
select set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000001',true);
do $$ begin
 if (select count(*) from public.church_branch_report('91000000-0000-4000-8000-000000000001')) <> 2 then raise exception 'Branch report count incorrect'; end if;
 if not exists(select 1 from public.church_branch_report('91000000-0000-4000-8000-000000000001') where branch_name='Main' and active_members=1 and visitors=1 and checkins_last_30_days=1) then raise exception 'Branch totals incorrect'; end if;
 begin perform public.church_analytics('91000000-0000-4000-8000-000000000001'); raise exception 'Unincluded analytics allowed'; exception when raise_exception then if sqlerrm='Unincluded analytics allowed' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000003',true);
do $$ begin
 perform public.set_organization_plan('91000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000003');
 if not exists(select 1 from public.church_analytics('91000000-0000-4000-8000-000000000001')) or not exists(select 1 from public.church_branch_report('91000000-0000-4000-8000-000000000001')) then raise exception 'Combined plan features missing'; end if;
end $$;
reset role;
update public.plans set is_active=false where id='95000000-0000-4000-8000-000000000003';
set local role authenticated;
do $$ begin
 begin perform public.church_branch_report('91000000-0000-4000-8000-000000000001'); raise exception 'Inactive plan report allowed'; exception when raise_exception then if sqlerrm='Inactive plan report allowed' then raise; end if; end;
 perform public.set_organization_plan('91000000-0000-4000-8000-000000000001',null);
 if exists(select 1 from public.organization_plan_features('91000000-0000-4000-8000-000000000001')) then raise exception 'Plan assignment remains'; end if;
 if not exists(select 1 from public.support_activity where resource_type='organization_plan_assignments' and action='DELETE') then raise exception 'Assignment audit missing'; end if;
end $$;
rollback;
