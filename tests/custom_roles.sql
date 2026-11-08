-- Isolated PostgreSQL only, after migration 016.
begin;
insert into public.organizations(id,name) values
 ('c0000000-0000-4000-8000-000000000001','Church A'),('c0000000-0000-4000-8000-000000000002','Church B');
insert into public.branches(id,organization_id,name) values
 ('c1000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001','Main'),
 ('c1000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000001','Second'),
 ('c1000000-0000-4000-8000-000000000003','c0000000-0000-4000-8000-000000000002','Other');
insert into auth.users(id,email,email_confirmed_at) values
 ('c2000000-0000-4000-8000-000000000001','admin@example.test',now()),
 ('c2000000-0000-4000-8000-000000000002','member@example.test',now()),
 ('c2000000-0000-4000-8000-000000000003','outsider@example.test',now()),
 ('c2000000-0000-4000-8000-000000000004','owner@example.test',now());
insert into public.platform_owners values ('c2000000-0000-4000-8000-000000000004');
insert into public.roles(id,organization_id,name,is_org_admin) values
 ('c3000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001','Organization Administrator',true),
 ('c3000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000001','Member',false);
insert into public.assignments(user_id,organization_id,branch_id,role_id) values
 ('c2000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001',null,'c3000000-0000-4000-8000-000000000001'),
 ('c2000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','c3000000-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-000000000001',true);
do $$
declare role_id uuid; assignment_id uuid;
begin
 role_id := public.save_custom_church_role('c0000000-0000-4000-8000-000000000001',null,'Youth',array['members.view','members.create']);
 if not exists(select 1 from public.audience_options('c0000000-0000-4000-8000-000000000001') where id=role_id) then raise exception 'New role missing from audience options'; end if;
 begin perform public.save_custom_church_role('c0000000-0000-4000-8000-000000000001',null,'Member','{}'); raise exception 'Reserved role allowed'; exception when raise_exception then if sqlerrm='Reserved role allowed' then raise; end if; end;
 begin perform public.save_custom_church_role('c0000000-0000-4000-8000-000000000001','c3000000-0000-4000-8000-000000000002','Changed','{}'); raise exception 'Built-in role editable'; exception when raise_exception then if sqlerrm='Built-in role editable' then raise; end if; end;
 begin perform public.save_custom_church_role('c0000000-0000-4000-8000-000000000001',role_id,'Youth',array['roles.manage']); raise exception 'Unsupported permission allowed'; exception when raise_exception then if sqlerrm='Unsupported permission allowed' then raise; end if; end;
 begin perform public.save_custom_church_role('c0000000-0000-4000-8000-000000000001',role_id,'Youth',array['members.delete']); raise exception 'Write without view allowed'; exception when raise_exception then if sqlerrm='Write without view allowed' then raise; end if; end;
 begin perform public.assign_custom_church_role('c0000000-0000-4000-8000-000000000001',role_id,'outsider@example.test',null); raise exception 'Outsider assigned'; exception when raise_exception then if sqlerrm='Outsider assigned' then raise; end if; end;
 begin perform public.assign_custom_church_role('c0000000-0000-4000-8000-000000000001',role_id,'member@example.test','c1000000-0000-4000-8000-000000000003'); raise exception 'Cross-church branch accepted'; exception when raise_exception then if sqlerrm='Cross-church branch accepted' then raise; end if; end;
 perform public.assign_custom_church_role('c0000000-0000-4000-8000-000000000001',role_id,'member@example.test','c1000000-0000-4000-8000-000000000001');
 begin perform public.assign_custom_church_role('c0000000-0000-4000-8000-000000000001',role_id,'member@example.test','c1000000-0000-4000-8000-000000000001'); raise exception 'Duplicate assigned'; exception when raise_exception then if sqlerrm='Duplicate assigned' then raise; end if; end;
 select a.id into assignment_id from public.custom_role_assignments('c0000000-0000-4000-8000-000000000001') a limit 1;
 if assignment_id is null then raise exception 'Assignment not listed'; end if;
 begin perform public.delete_custom_church_role('c0000000-0000-4000-8000-000000000001',role_id); raise exception 'Assigned role deleted'; exception when raise_exception then if sqlerrm='Assigned role deleted' then raise; end if; end;
 insert into public.church_events(organization_id,title,starts_at,ends_at,created_by,audience_everyone,audience_roles)
 values('c0000000-0000-4000-8000-000000000001','Youth meeting',now(),now()+interval '1 hour','c2000000-0000-4000-8000-000000000001',false,array[role_id]);
 perform set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-000000000002',true);
 if not public.has_member_permission('c0000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','create') then raise exception 'Branch permission missing'; end if;
 if public.has_member_permission('c0000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000002','create') then raise exception 'Branch permission leaked'; end if;
 if not exists(select 1 from public.church_events where title='Youth meeting') then raise exception 'Custom audience inaccessible'; end if;
 begin perform public.manageable_church_roles('c0000000-0000-4000-8000-000000000001'); raise exception 'Non-admin managed roles'; exception when raise_exception then if sqlerrm='Non-admin managed roles' then raise; end if; end;
 perform set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-000000000001',true);
 perform public.save_custom_church_role('c0000000-0000-4000-8000-000000000001',role_id,'Youth',array['members.view']);
 perform set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-000000000002',true);
 if public.has_member_permission('c0000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','create') then raise exception 'Updated permission remains'; end if;
 if not public.has_member_permission('c0000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','view') then raise exception 'Retained permission missing'; end if;
 perform set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-000000000001',true);
 perform public.remove_custom_role_assignment('c0000000-0000-4000-8000-000000000001',assignment_id);
 perform set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-000000000002',true);
 if public.has_member_permission('c0000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','view') then raise exception 'Revoked permission remains'; end if;
 if exists(select 1 from public.church_events where title='Youth meeting') then raise exception 'Revoked audience remains'; end if;
 perform set_config('request.jwt.claim.sub','c2000000-0000-4000-8000-000000000004',true);
 begin perform public.delete_custom_church_role('c0000000-0000-4000-8000-000000000001',role_id); raise exception 'Audience role deleted'; exception when raise_exception then if sqlerrm='Audience role deleted' then raise; end if; end;
 delete from public.church_events where title='Youth meeting';
 perform public.delete_custom_church_role('c0000000-0000-4000-8000-000000000001',role_id);
end $$;
rollback;
