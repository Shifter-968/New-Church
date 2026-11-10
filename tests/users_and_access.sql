-- Isolated PostgreSQL only, after migration 022.
begin;
insert into public.organizations(id,name) values
 ('81000000-0000-4000-8000-000000000001','Church A'),
 ('81000000-0000-4000-8000-000000000002','Church B');
insert into public.branches(id,organization_id,name) values
 ('82000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','Main');
insert into auth.users(id,email,email_confirmed_at) values
 ('83000000-0000-4000-8000-000000000001','admin-a@example.test',now()),
 ('83000000-0000-4000-8000-000000000002','branch@example.test',now()),
 ('83000000-0000-4000-8000-000000000003','admin-b@example.test',now()),
 ('83000000-0000-4000-8000-000000000004','owner@example.test',now()),
 ('83000000-0000-4000-8000-000000000005','other@example.test',now());
insert into public.platform_owners values ('83000000-0000-4000-8000-000000000004');
insert into public.roles(id,organization_id,name,is_org_admin,permissions) values
 ('84000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','Organization Administrator',true,'{}'),
 ('84000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000001','Branch Administrator',false,array['members.view','attendance.view']),
 ('84000000-0000-4000-8000-000000000003','81000000-0000-4000-8000-000000000001','Member',false,'{}'),
 ('84000000-0000-4000-8000-000000000004','81000000-0000-4000-8000-000000000002','Admin',true,'{}');
insert into public.assignments(id,user_id,organization_id,branch_id,role_id,active) values
 ('85000000-0000-4000-8000-000000000001','83000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001',null,'84000000-0000-4000-8000-000000000001',true),
 ('85000000-0000-4000-8000-000000000002','83000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000001','82000000-0000-4000-8000-000000000001','84000000-0000-4000-8000-000000000002',true),
 ('85000000-0000-4000-8000-000000000003','83000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000001','82000000-0000-4000-8000-000000000001','84000000-0000-4000-8000-000000000003',true),
 ('85000000-0000-4000-8000-000000000004','83000000-0000-4000-8000-000000000003','81000000-0000-4000-8000-000000000002',null,'84000000-0000-4000-8000-000000000004',true),
 ('85000000-0000-4000-8000-000000000005','83000000-0000-4000-8000-000000000005','81000000-0000-4000-8000-000000000001','82000000-0000-4000-8000-000000000001','84000000-0000-4000-8000-000000000002',true),
 ('85000000-0000-4000-8000-000000000006','83000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000001','82000000-0000-4000-8000-000000000001','84000000-0000-4000-8000-000000000002',false);
set local role authenticated;
select set_config('request.jwt.claim.sub','83000000-0000-4000-8000-000000000002',true);
do $$ begin
 begin perform public.list_church_access('81000000-0000-4000-8000-000000000001'); raise exception 'Branch user listed access'; exception when raise_exception then if sqlerrm='Branch user listed access' then raise; end if; end;
 begin perform public.remove_branch_administrator_assignment('81000000-0000-4000-8000-000000000001','85000000-0000-4000-8000-000000000002'); raise exception 'Branch user removed access'; exception when raise_exception then if sqlerrm='Branch user removed access' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','83000000-0000-4000-8000-000000000003',true);
do $$ begin
 begin perform public.list_church_access('81000000-0000-4000-8000-000000000001'); raise exception 'Other church listed access'; exception when raise_exception then if sqlerrm='Other church listed access' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','83000000-0000-4000-8000-000000000001',true);
do $$ declare v_role_id uuid; v_assignment_id uuid; begin
 if (select count(*) from public.list_church_access('81000000-0000-4000-8000-000000000001')) <> 4 then raise exception 'List includes incorrect assignments'; end if;
 if not exists(select 1 from public.list_church_access('81000000-0000-4000-8000-000000000001') where assignment_kind='branch_admin' and scope_name='Main') then raise exception 'Branch assignment missing'; end if;
 if not exists(select 1 from public.list_church_access('81000000-0000-4000-8000-000000000001') where assignment_kind='organization_admin') then raise exception 'Organization admin classification missing'; end if;
 if not exists(select 1 from public.list_church_access('81000000-0000-4000-8000-000000000001') where assignment_kind='protected' and role_name='Member') then raise exception 'Member classification missing'; end if;
 begin perform public.remove_branch_administrator_assignment('81000000-0000-4000-8000-000000000001','85000000-0000-4000-8000-000000000005'); raise exception 'Last assignment removed'; exception when raise_exception then if sqlerrm='Last assignment removed' then raise; end if; end;
 begin perform public.remove_branch_administrator_assignment('81000000-0000-4000-8000-000000000001','85000000-0000-4000-8000-000000000003'); raise exception 'Protected member role removed'; exception when raise_exception then if sqlerrm='Protected member role removed' then raise; end if; end;
 begin perform public.remove_branch_administrator_assignment('81000000-0000-4000-8000-000000000001','85000000-0000-4000-8000-000000000004'); raise exception 'Other church assignment removed'; exception when raise_exception then if sqlerrm='Other church assignment removed' then raise; end if; end;
 perform public.remove_branch_administrator_assignment('81000000-0000-4000-8000-000000000001','85000000-0000-4000-8000-000000000002');
 begin perform public.remove_branch_administrator_assignment('81000000-0000-4000-8000-000000000001','85000000-0000-4000-8000-000000000002'); raise exception 'Duplicate removal succeeded'; exception when raise_exception then if sqlerrm='Duplicate removal succeeded' then raise; end if; end;
 if exists(select 1 from public.list_church_access('81000000-0000-4000-8000-000000000001') where assignment_id='85000000-0000-4000-8000-000000000002') then raise exception 'Removed role remains'; end if;
 if not exists(select 1 from public.list_church_access('81000000-0000-4000-8000-000000000001') where assignment_id='85000000-0000-4000-8000-000000000003') then raise exception 'Other role removed'; end if;
 v_role_id := public.save_custom_church_role('81000000-0000-4000-8000-000000000001',null,'Usher','{}');
 perform public.assign_custom_church_role('81000000-0000-4000-8000-000000000001',v_role_id,'branch@example.test','82000000-0000-4000-8000-000000000001');
 select x.assignment_id into v_assignment_id from public.list_church_access('81000000-0000-4000-8000-000000000001') x where x.assignment_kind='custom';
 if v_assignment_id is null then raise exception 'Custom assignment not listed'; end if;
 perform public.remove_custom_role_assignment('81000000-0000-4000-8000-000000000001',v_assignment_id);
 if not exists(select 1 from public.support_activity where resource_type='assignments' and resource_id='85000000-0000-4000-8000-000000000002' and action='DELETE' and actor_id=auth.uid()) then raise exception 'Assignment removal not audited'; end if;
end $$;
select set_config('request.jwt.claim.sub','83000000-0000-4000-8000-000000000004',true);
do $$ begin if (select count(*) from public.list_church_access('81000000-0000-4000-8000-000000000001')) <> 3 then raise exception 'Owner list incorrect'; end if; end $$;
rollback;
