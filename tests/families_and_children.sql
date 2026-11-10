-- Isolated PostgreSQL only, after migration 020.
begin;
insert into public.organizations(id,name) values
 ('a0000000-0000-4000-8000-000000000001','Church A'),('a0000000-0000-4000-8000-000000000002','Church B');
insert into public.branches(id,organization_id,name) values
 ('a1000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','Main'),
 ('a1000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','Other'),
 ('a1000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000002','Elsewhere');
insert into auth.users(id,email,email_confirmed_at) values
 ('a2000000-0000-4000-8000-000000000001','admin@example.test',now()),
 ('a2000000-0000-4000-8000-000000000002','branch@example.test',now()),
 ('a2000000-0000-4000-8000-000000000003','reader@example.test',now()),
 ('a2000000-0000-4000-8000-000000000004','outsider@example.test',now()),
 ('a2000000-0000-4000-8000-000000000005','owner@example.test',now());
insert into public.platform_owners values ('a2000000-0000-4000-8000-000000000005');
insert into public.roles(id,organization_id,name,is_org_admin,permissions) values
 ('a3000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','Admin',true,'{}'),
 ('a3000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','Branch',false,array['members.view','members.create','members.update','members.delete']),
 ('a3000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000001','Reader',false,array['members.view']);
insert into public.assignments(user_id,organization_id,branch_id,role_id) values
 ('a2000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001',null,'a3000000-0000-4000-8000-000000000001'),
 ('a2000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000002'),
 ('a2000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000003');
insert into public.members(id,organization_id,branch_id,first_name,last_name) values
 ('a4000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','Parent','One'),
 ('a4000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000002','Other','Branch'),
 ('a4000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000003','Other','Church');
insert into public.church_families(id,organization_id,branch_id,name,primary_contact) values
 ('a5000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','Family','Contact'),
 ('a5000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000002','Other','Contact');
insert into public.church_children(id,organization_id,branch_id,first_name,last_name,parent_contact) values
 ('a6000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','Child','One','Contact');
set local role authenticated;
select set_config('request.jwt.claim.sub','a2000000-0000-4000-8000-000000000002',true);
do $$ begin
 if (select count(*) from public.church_families) <> 1 or (select count(*) from public.church_children) <> 1 then raise exception 'Branch visibility incorrect'; end if;
 insert into public.church_family_people(organization_id,branch_id,family_id,member_id,relationship)
 values('a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','a5000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','Parent');
 insert into public.church_family_people(organization_id,branch_id,family_id,child_id,relationship)
 values('a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','a5000000-0000-4000-8000-000000000001','a6000000-0000-4000-8000-000000000001','Child');
 update public.church_family_people set relationship='Guardian' where family_id='a5000000-0000-4000-8000-000000000001' and member_id='a4000000-0000-4000-8000-000000000001';
 if not exists(select 1 from public.church_family_people where relationship='Guardian') then raise exception 'Relationship edit failed'; end if;
 begin insert into public.church_children(organization_id,branch_id,first_name,last_name,parent_contact,date_of_birth) values('a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','Future','Child','Contact',current_date+1); raise exception 'Future birth date allowed'; exception when check_violation then null; end;
 begin insert into public.church_family_people(organization_id,branch_id,family_id,member_id) values('a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','a5000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000002'); raise exception 'Cross-branch member linked'; exception when foreign_key_violation then null; end;
 begin insert into public.church_family_people(organization_id,branch_id,family_id,member_id) values('a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','a5000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000003'); raise exception 'Cross-church member linked'; exception when foreign_key_violation then null; end;
 begin insert into public.church_children(organization_id,branch_id,first_name,last_name,parent_contact) values('a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000002','Forbidden','Child','Contact'); raise exception 'Cross-branch child created'; exception when insufficient_privilege then null; end;
 begin delete from public.church_children where id='a6000000-0000-4000-8000-000000000001'; raise exception 'Linked child deleted'; exception when foreign_key_violation then null; end;
end $$;
select set_config('request.jwt.claim.sub','a2000000-0000-4000-8000-000000000003',true);
do $$ begin
 if (select count(*) from public.church_family_people) <> 2 then raise exception 'Reader cannot see links'; end if;
 begin insert into public.church_children(organization_id,branch_id,first_name,last_name,parent_contact) values('a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','Forbidden','Child','Contact'); raise exception 'Read-only create allowed'; exception when insufficient_privilege then null; end;
 delete from public.church_family_people; if found then raise exception 'Read-only link delete allowed'; end if;
end $$;
select set_config('request.jwt.claim.sub','a2000000-0000-4000-8000-000000000004',true);
do $$ begin if exists(select 1 from public.church_children) or exists(select 1 from public.church_families) or exists(select 1 from public.church_family_people) then raise exception 'Outsider data leak'; end if; end $$;
select set_config('request.jwt.claim.sub','a2000000-0000-4000-8000-000000000001',true);
do $$ begin
 begin update public.members set branch_id='a1000000-0000-4000-8000-000000000002' where id='a4000000-0000-4000-8000-000000000001'; raise exception 'Linked member moved'; exception when foreign_key_violation then null; end;
 if not exists(select 1 from public.support_activity where resource_type='church_family_people' and action='INSERT' and actor_id='a2000000-0000-4000-8000-000000000002') then raise exception 'Family link audit missing'; end if;
 delete from public.church_family_people where family_id='a5000000-0000-4000-8000-000000000001';
 delete from public.church_children where id='a6000000-0000-4000-8000-000000000001';
 update public.members set branch_id='a1000000-0000-4000-8000-000000000002' where id='a4000000-0000-4000-8000-000000000001';
end $$;
select set_config('request.jwt.claim.sub','a2000000-0000-4000-8000-000000000005',true);
do $$ begin if (select count(*) from public.church_families) <> 2 then raise exception 'Owner visibility incorrect'; end if; end $$;
rollback;
