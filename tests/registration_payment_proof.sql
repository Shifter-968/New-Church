-- Isolated PostgreSQL only, after storage_test_standin.sql and migration 032.
begin;
insert into public.plans(id,name,price,currency,billing_period,is_active) values
 ('f3000000-0000-4000-8000-000000000001','Test paid',100,'USD','MONTHLY',true),
 ('f3000000-0000-4000-8000-000000000002','Inactive',50,'USD','ANNUALLY',false),
 ('f3000000-0000-4000-8000-000000000003','Free',0,'USD','MONTHLY',true);
insert into auth.users(id,email,email_confirmed_at) values
 ('f1000000-0000-4000-8000-000000000001','payment-owner@example.test',now()),
 ('f1000000-0000-4000-8000-000000000002','payment-outsider@example.test',now());
insert into public.platform_owners values ('f1000000-0000-4000-8000-000000000001');
do $$ begin
 begin
  insert into auth.users(id,email,raw_user_meta_data) values ('f1000000-0000-4000-8000-000000000010','invalid@example.test',
   '{"organization_application":{"purchase_authorized":true,"plan_id":"f3000000-0000-4000-8000-000000000002"}}');
  raise exception 'Inactive plan accepted';
 exception when raise_exception then if sqlerrm='Inactive plan accepted' then raise; end if; end;
 begin
  insert into auth.users(id,email,raw_user_meta_data) values ('f1000000-0000-4000-8000-000000000010','invalid@example.test',
   '{"organization_application":{"purchase_authorized":true,"plan_id":"f3000000-0000-4000-8000-000000000001","plan_price":"100","plan_currency":"USD","plan_period":"MONTHLY"}}');
  raise exception 'Missing reference accepted';
 exception when raise_exception then if sqlerrm='Missing reference accepted' then raise; end if; end;
 begin
  insert into auth.users(id,email,raw_user_meta_data) values ('f1000000-0000-4000-8000-000000000010','invalid@example.test',
   '{"organization_application":{"purchase_authorized":true,"plan_id":"f3000000-0000-4000-8000-000000000001","plan_price":"1","plan_currency":"USD","plan_period":"MONTHLY"}}');
  raise exception 'Changed price accepted';
 exception when raise_exception then if sqlerrm='Changed price accepted' then raise; end if; end;
end $$;
insert into auth.users(id,email,raw_user_meta_data) values
 ('f1000000-0000-4000-8000-000000000003','payment-applicant@example.test',
  '{"organization_application":{"purchase_authorized":true,"plan_id":"f3000000-0000-4000-8000-000000000001","plan_price":"100","plan_currency":"USD","plan_period":"MONTHLY","payment_method":"Transfer","transaction_reference":"ABC123","organization_name":"Proof Church","account_role":"CHURCH_ADMIN","address":"Street","city":"Town","country":"Country","first_name":"Ada","last_name":"Test","phone":"123","birth_date":"1990-01-01"}}'),
 ('f1000000-0000-4000-8000-000000000004','payment-no-receipt@example.test',
  '{"organization_application":{"purchase_authorized":true,"plan_id":"f3000000-0000-4000-8000-000000000003","plan_price":"0","plan_currency":"USD","plan_period":"MONTHLY","organization_name":"Free Church","account_role":"CHURCH_ADMIN","address":"Street","city":"Town","country":"Country","first_name":"Bee","last_name":"Test","phone":"123","birth_date":"1990-01-01"}}');
select set_config('test.application',(select id::text from public.organization_applications where applicant_user_id='f1000000-0000-4000-8000-000000000003'),true);
do $$ begin
 if not exists(select 1 from public.organization_applications where id=current_setting('test.application')::uuid
   and requested_plan_name='Test paid' and requested_plan_price=100 and transaction_reference='ABC123') then raise exception 'Plan snapshot missing'; end if;
 if not exists(select 1 from storage.buckets where id='registration-payment-proofs' and not public and file_size_limit=8388608) then raise exception 'Private bucket configuration missing'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','f1000000-0000-4000-8000-000000000003',true);
do $$ begin
 begin
  insert into storage.objects(bucket_id,name) values('registration-payment-proofs',auth.uid()::text || '/receipt');
  raise exception 'Unconfirmed upload accepted';
 exception when insufficient_privilege then null; end;
 begin
  perform public.submit_organization_payment_details();
  raise exception 'Unconfirmed submission accepted';
 exception when raise_exception then if sqlerrm='Unconfirmed submission accepted' then raise; end if; end;
end $$;
reset role;
update auth.users set email_confirmed_at=now() where id in ('f1000000-0000-4000-8000-000000000003','f1000000-0000-4000-8000-000000000004');
set local role authenticated;
select set_config('request.jwt.claim.sub','f1000000-0000-4000-8000-000000000001',true);
do $$ begin
 begin
  perform public.review_organization_application(current_setting('test.application')::uuid,'approved');
  raise exception 'Unsubmitted application approved';
 exception when raise_exception then if sqlerrm='Unsubmitted application approved' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','f1000000-0000-4000-8000-000000000003',true);
insert into storage.objects(bucket_id,name) values('registration-payment-proofs',auth.uid()::text || '/receipt');
do $$ begin
 begin
  insert into storage.objects(bucket_id,name) values('registration-payment-proofs','f1000000-0000-4000-8000-000000000004/receipt');
  raise exception 'Cross-account upload accepted';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','f1000000-0000-4000-8000-000000000002',true);
do $$ begin if exists(select 1 from storage.objects where bucket_id='registration-payment-proofs') then raise exception 'Outsider saw receipt'; end if; end $$;
select set_config('request.jwt.claim.sub','f1000000-0000-4000-8000-000000000001',true);
do $$ begin if exists(select 1 from storage.objects where bucket_id='registration-payment-proofs') then raise exception 'Owner saw unsubmitted receipt'; end if; end $$;
select set_config('request.jwt.claim.sub','f1000000-0000-4000-8000-000000000003',true);
select public.submit_organization_payment_details();
do $$ begin
 if not exists(select 1 from public.organization_applications where id=current_setting('test.application')::uuid and receipt_submitted and payment_submitted_at is not null) then raise exception 'Receipt not submitted'; end if;
 delete from storage.objects where bucket_id='registration-payment-proofs' and name=auth.uid()::text || '/receipt';
 if found then raise exception 'Submitted receipt removed'; end if;
end $$;
select set_config('request.jwt.claim.sub','f1000000-0000-4000-8000-000000000001',true);
do $$ begin if not exists(select 1 from storage.objects where bucket_id='registration-payment-proofs') then raise exception 'Owner cannot download submitted receipt'; end if; end $$;
select public.review_organization_application(current_setting('test.application')::uuid,'approved');
reset role;
do $$ begin
 if not exists(select 1 from public.organization_applications a join public.organization_plan_assignments p on p.organization_id=a.organization_id
   where a.id=current_setting('test.application')::uuid and a.status='approved' and p.plan_id=a.requested_plan_id) then raise exception 'Approved plan not assigned'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','f1000000-0000-4000-8000-000000000004',true);
select public.submit_organization_payment_details();
do $$ begin
 if not exists(select 1 from public.organization_applications where applicant_user_id=auth.uid() and payment_submitted_at is not null and not receipt_submitted) then raise exception 'Optional receipt submission failed'; end if;
end $$;
reset role;
update public.plans set is_active=false where id='f3000000-0000-4000-8000-000000000003';
select set_config('test.free_application',(select id::text from public.organization_applications where applicant_user_id='f1000000-0000-4000-8000-000000000004'),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','f1000000-0000-4000-8000-000000000001',true);
do $$ begin
 begin
  perform public.review_organization_application(current_setting('test.free_application')::uuid,'approved');
  raise exception 'Inactive plan approved';
 exception when raise_exception then if sqlerrm='Inactive plan approved' then raise; end if; end;
end $$;
reset role;
update public.plans set is_active=true where id='f3000000-0000-4000-8000-000000000003';
set local role authenticated;
select public.review_organization_application(current_setting('test.free_application')::uuid,'approved');
reset role;
insert into public.organization_applications(applicant_user_id,applicant_email,organization_name,account_role,address,city,country,first_name,last_name,phone,birth_date)
 values('f1000000-0000-4000-8000-000000000002','payment-outsider@example.test','Old application','CHURCH_ADMIN','Street','Town','Country','Old','Test','123','1990-01-01');
select set_config('test.old_application',(select id::text from public.organization_applications where applicant_user_id='f1000000-0000-4000-8000-000000000002'),true);
set local role authenticated;
select public.review_organization_application(current_setting('test.old_application')::uuid,'approved');
reset role;
do $$ begin
 if not exists(select 1 from public.organization_applications where id=current_setting('test.old_application')::uuid and status='approved' and requested_plan_id is null) then raise exception 'Legacy approval failed'; end if;
 if has_function_privilege('anon','public.submit_organization_payment_details()','execute') then raise exception 'Anonymous payment submission allowed'; end if;
end $$;
rollback;
