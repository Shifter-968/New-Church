-- Apply once after 034_member_registration_name_phone.sql.
begin;

create function public.submit_organization_application(registration jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  applicant_email text;
  selected_plan public.plans%rowtype;
  method text;
  reference text;
  plan_uuid uuid;
  birth_date date;
  gender text;
begin
  if auth.uid() is null then raise exception 'Sign in to submit a church application.'; end if;
  if jsonb_typeof(registration) is distinct from 'object' then
    raise exception 'Church registration details are invalid.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(auth.uid()::text || ':organization-application', 0));
  select u.email into applicant_email from auth.users u
    where u.id = auth.uid() and u.email_confirmed_at is not null;
  if not found then raise exception 'Confirm your email before submitting a church application.'; end if;
  if exists (select 1 from public.organization_applications a where a.applicant_user_id = auth.uid()) then
    return;
  end if;
  if registration ->> 'purchase_authorized' is distinct from 'true' then
    raise exception 'Church registration requires authorization.';
  end if;
  if length(trim(coalesce(registration ->> 'organization_name', ''))) not between 2 and 120
    or coalesce(registration ->> 'account_role', '') not in ('FOUNDING_PASTOR', 'CHURCH_ADMIN')
    or length(trim(coalesce(registration ->> 'address', ''))) not between 1 and 255
    or length(trim(coalesce(registration ->> 'city', ''))) not between 1 and 120
    or length(trim(coalesce(registration ->> 'country', ''))) not between 1 and 120
    or length(trim(coalesce(registration ->> 'first_name', ''))) not between 1 and 100
    or length(trim(coalesce(registration ->> 'last_name', ''))) not between 1 and 100
    or length(trim(coalesce(registration ->> 'phone', ''))) not between 1 and 40 then
    raise exception 'Review the required church registration details.';
  end if;
  birth_date := nullif(registration ->> 'birth_date', '')::date;
  gender := nullif(registration ->> 'gender', '');
  if birth_date is null or birth_date >= current_date
    or gender is not null and gender not in ('MALE', 'FEMALE', 'OTHER') then
    raise exception 'Review the birth date and gender fields.';
  end if;
  plan_uuid := nullif(registration ->> 'plan_id', '')::uuid;
  select * into selected_plan from public.plans p
    where p.id = plan_uuid and p.is_active for share;
  if not found then raise exception 'Select an available church plan.'; end if;
  if nullif(registration ->> 'plan_price', '')::numeric is distinct from selected_plan.price
    or registration ->> 'plan_currency' is distinct from selected_plan.currency
    or registration ->> 'plan_period' is distinct from selected_plan.billing_period then
    raise exception 'The selected plan price or billing period changed. Refresh and review it before registering.';
  end if;
  method := nullif(trim(registration ->> 'payment_method'), '');
  reference := nullif(trim(registration ->> 'transaction_reference'), '');
  if length(method) > 100 or length(reference) > 255
    or (selected_plan.price > 0 and (method is null or reference is null)) then
    raise exception 'Enter a payment method and transaction reference for the selected paid plan.';
  end if;
  insert into public.organization_applications
    (applicant_user_id, applicant_email, organization_name, account_role, address, city, country,
     first_name, last_name, phone, birth_date, gender, requested_plan_id, requested_plan_name,
     requested_plan_price, requested_plan_currency, requested_plan_period, payment_method, transaction_reference)
  values
    (auth.uid(), applicant_email, trim(registration ->> 'organization_name'), registration ->> 'account_role',
     trim(registration ->> 'address'), trim(registration ->> 'city'), trim(registration ->> 'country'),
     trim(registration ->> 'first_name'), trim(registration ->> 'last_name'), trim(registration ->> 'phone'),
     birth_date, gender, selected_plan.id, selected_plan.name, selected_plan.price, selected_plan.currency,
     selected_plan.billing_period, method, reference);
end
$$;
revoke all on function public.submit_organization_application(jsonb) from public, anon;
grant execute on function public.submit_organization_application(jsonb) to authenticated;

commit;
