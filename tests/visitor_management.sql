-- Run only against an isolated test database after migration 011.
begin;
insert into public.organizations (id, name) values
 ('10000000-0000-4000-8000-000000000001', 'Church A'),
 ('10000000-0000-4000-8000-000000000002', 'Church B');
insert into public.branches (id, organization_id, name) values
 ('11000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Branch A'),
 ('11000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', 'Branch B'),
 ('11000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000002', 'Branch C');
insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-4000-8000-000000000001', 'owner@example.test', now()),
 ('00000000-0000-4000-8000-000000000002', 'branch@example.test', now()),
 ('00000000-0000-4000-8000-000000000003', 'visitor@example.test', now()),
 ('00000000-0000-4000-8000-000000000004', 'admin@example.test', now()),
 ('00000000-0000-4000-8000-000000000005', 'reader@example.test', now());
insert into public.platform_owners values ('00000000-0000-4000-8000-000000000001');
insert into public.roles (id, organization_id, name, is_org_admin, permissions) values
 ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Visitor manager', false, array['visitors.view','visitors.create','visitors.update','visitors.delete']),
 ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', 'Org admin', true, '{}'),
 ('20000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', 'Reader', false, array['visitors.view']);
insert into public.assignments (user_id, organization_id, branch_id, role_id) values
 ('00000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001'),
 ('00000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000001', null, '20000000-0000-4000-8000-000000000002'),
 ('00000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000003');
insert into public.visitors (id, organization_id, branch_id, user_id, first_name, last_name, email, phone) values
 ('30000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000003', 'Linked', 'Visitor', 'visitor@example.test', '123'),
 ('30000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000002', null, 'Other', 'Branch', null, null),
 ('30000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000002', '11000000-0000-4000-8000-000000000003', null, 'Other', 'Church', null, null);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000002', true);
do $$ begin
 if (select count(*) from public.visitors) <> 1 then raise exception 'Branch visibility incorrect'; end if;
 insert into public.visitors (organization_id, branch_id, first_name, last_name) values ('10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', 'Added', 'Visitor');
 begin
  insert into public.visitors (organization_id, branch_id, first_name, last_name) values
   ('10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', 'Batch', 'Allowed'),
   ('10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000002', 'Batch', 'Denied');
  raise exception 'Out-of-scope batch accepted';
 exception when insufficient_privilege then null; end;
 if exists (select 1 from public.visitors where first_name = 'Batch') then raise exception 'Batch was not atomic'; end if;
 begin
  insert into public.visitors (organization_id, branch_id, user_id, first_name, last_name) values ('10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', auth.uid(), 'Fake', 'Link');
  raise exception 'Direct user link allowed';
 exception when insufficient_privilege then null; end;
 begin
  delete from public.visitors where id = '30000000-0000-4000-8000-000000000001';
  raise exception 'Linked visitor deleted';
 exception when raise_exception then if sqlerrm = 'Linked visitor deleted' then raise; end if; end;
 begin
  update public.visitors set branch_id = null where id = '30000000-0000-4000-8000-000000000001';
  raise exception 'Linked visitor moved';
 exception when raise_exception then if sqlerrm = 'Linked visitor moved' then raise; end if; end;
 delete from public.visitors where first_name = 'Added';
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000005', true);
do $$ begin
 begin
  insert into public.visitors (organization_id, branch_id, first_name, last_name) values ('10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', 'Denied', 'Visitor');
  raise exception 'Read-only user inserted visitor';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000004', true);
do $$ begin if (select count(*) from public.visitors) <> 2 then raise exception 'Org admin scope incorrect'; end if; end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000003', true);
do $$ begin if (select count(*) from public.visitors) <> 0 then raise exception 'Ordinary account can view visitors'; end if; end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
do $$ begin
 if (select count(*) from public.visitors) <> 3 then raise exception 'Owner visibility incorrect'; end if;
 perform public.assign_branch_administrator('10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000003');
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000003', true);
do $$ begin
 if (select count(*) from public.visitors) <> 1 then raise exception 'Built-in branch administrator visibility incorrect'; end if;
 if not public.has_visitor_permission('10000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000002', 'create') then raise exception 'Built-in branch administrator cannot create visitors'; end if;
end $$;
rollback;
