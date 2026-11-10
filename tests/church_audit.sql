-- Isolated PostgreSQL only, after migration 018.
begin;
insert into public.organizations(id,name) values
 ('f0000000-0000-4000-8000-000000000001','Church A'),
 ('f0000000-0000-4000-8000-000000000002','Church B');
insert into auth.users(id,email,email_confirmed_at) values
 ('f1000000-0000-4000-8000-000000000001','a@example.test',now()),
 ('f1000000-0000-4000-8000-000000000002','b@example.test',now()),
 ('f1000000-0000-4000-8000-000000000003','branch@example.test',now()),
 ('f1000000-0000-4000-8000-000000000004','owner@example.test',now());
insert into public.platform_owners values ('f1000000-0000-4000-8000-000000000004');
insert into public.branches(id,organization_id,name) values
 ('f2000000-0000-4000-8000-000000000001','f0000000-0000-4000-8000-000000000001','Main');
insert into public.roles(id,organization_id,name,is_org_admin,permissions) values
 ('f3000000-0000-4000-8000-000000000001','f0000000-0000-4000-8000-000000000001','Admin',true,'{}'),
 ('f3000000-0000-4000-8000-000000000002','f0000000-0000-4000-8000-000000000002','Admin',true,'{}'),
 ('f3000000-0000-4000-8000-000000000003','f0000000-0000-4000-8000-000000000001','Branch',false,array['members.view']);
insert into public.assignments(user_id,organization_id,branch_id,role_id) values
 ('f1000000-0000-4000-8000-000000000001','f0000000-0000-4000-8000-000000000001',null,'f3000000-0000-4000-8000-000000000001'),
 ('f1000000-0000-4000-8000-000000000002','f0000000-0000-4000-8000-000000000002',null,'f3000000-0000-4000-8000-000000000002'),
 ('f1000000-0000-4000-8000-000000000003','f0000000-0000-4000-8000-000000000001','f2000000-0000-4000-8000-000000000001','f3000000-0000-4000-8000-000000000003');
delete from public.support_activity where organization_id in ('f0000000-0000-4000-8000-000000000001','f0000000-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('request.jwt.claim.sub','f1000000-0000-4000-8000-000000000001',true);
insert into public.members(organization_id,branch_id,first_name,last_name) values
 ('f0000000-0000-4000-8000-000000000001','f2000000-0000-4000-8000-000000000001','Test','Member');
update public.members set first_name='Edited' where organization_id='f0000000-0000-4000-8000-000000000001' and first_name='Test';
insert into public.church_teams(id,organization_id,name,kind) values
 ('f5000000-0000-4000-8000-000000000001','f0000000-0000-4000-8000-000000000001','Ushers','department');
insert into public.church_team_members(organization_id,team_id,member_id)
 select organization_id,'f5000000-0000-4000-8000-000000000001',id from public.members where organization_id='f0000000-0000-4000-8000-000000000001' and first_name='Edited';
select public.save_custom_church_role('f0000000-0000-4000-8000-000000000001',null,'Custom','{}');
do $$ begin
 if (select count(*) from public.support_activity where resource_type='members' and action in ('INSERT','UPDATE')) <> 2 then raise exception 'Member changes not recorded'; end if;
 if not exists(select 1 from public.support_activity where resource_type='church_team_members' and action='INSERT') then raise exception 'Team membership change missing'; end if;
 if not exists(select 1 from public.support_activity where resource_type='roles' and action='INSERT') then raise exception 'Role change missing'; end if;
 if exists(select 1 from public.support_activity where actor_id <> auth.uid() or actor_id is null) then raise exception 'Wrong actor'; end if;
 begin insert into public.support_activity(organization_id,resource_type,resource_id,action) values('f0000000-0000-4000-8000-000000000001','fake','f4000000-0000-4000-8000-000000000001','INSERT'); raise exception 'Audit write allowed'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','f1000000-0000-4000-8000-000000000002',true);
do $$ begin if exists(select 1 from public.support_activity) then raise exception 'Cross-church audit leaked'; end if; end $$;
select set_config('request.jwt.claim.sub','f1000000-0000-4000-8000-000000000003',true);
do $$ begin if exists(select 1 from public.support_activity) then raise exception 'Branch user saw church audit'; end if; end $$;
select set_config('request.jwt.claim.sub','f1000000-0000-4000-8000-000000000004',true);
do $$ begin if (select count(*) from public.support_activity) < 5 then raise exception 'Owner cannot see activity'; end if; end $$;
rollback;
