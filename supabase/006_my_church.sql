-- Apply once after 005_plan_catalog.sql.
begin;

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  first_name text not null default '' check (length(first_name) <= 100),
  last_name text not null default '' check (length(last_name) <= 100),
  middle_name text not null default '' check (length(middle_name) <= 100),
  phone text not null default '' check (length(phone) <= 40),
  phone_2 text not null default '' check (length(phone_2) <= 40),
  date_of_birth date,
  gender text not null default '' check (gender in ('', 'MALE', 'FEMALE', 'OTHER')),
  marital_status text not null default '',
  address text not null default '' check (length(address) <= 255),
  city text not null default '' check (length(city) <= 120),
  country text not null default '' check (length(country) <= 120),
  baptized boolean not null default false
);
alter table public.profiles enable row level security;
create policy "read own profile" on public.profiles for select to authenticated using (user_id = auth.uid());
create policy "create own profile" on public.profiles for insert to authenticated with check (user_id = auth.uid());
create policy "update own profile" on public.profiles for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update on public.profiles to authenticated;

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  message text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index notifications_user_created_idx on public.notifications (user_id, created_at desc);
alter table public.notifications enable row level security;
create policy "read own notifications" on public.notifications for select to authenticated using (user_id = auth.uid());
create policy "mark own notifications read" on public.notifications for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  title text not null check (length(trim(title)) between 1 and 200),
  content text not null check (length(trim(content)) between 1 and 10000),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now()
);
create index announcements_org_created_idx on public.announcements (organization_id, created_at desc);
alter table public.announcements enable row level security;
create policy "assigned users read church announcements" on public.announcements for select to authenticated using (public.has_org_access(organization_id));
create policy "administrators publish church announcements" on public.announcements for insert to authenticated with check (public.is_org_administrator(organization_id) and created_by = auth.uid());
grant select, insert on public.announcements to authenticated;

create table public.church_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  title text not null check (length(trim(title)) between 1 and 200),
  description text not null default '' check (length(description) <= 10000),
  starts_at timestamptz not null,
  ends_at timestamptz not null check (ends_at >= starts_at),
  location text not null default '' check (length(location) <= 255),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now()
);
create index church_events_org_start_idx on public.church_events (organization_id, starts_at);
alter table public.church_events enable row level security;
create policy "assigned users read church events" on public.church_events for select to authenticated using (public.has_org_access(organization_id));
create policy "administrators create church events" on public.church_events for insert to authenticated with check (public.is_org_administrator(organization_id) and created_by = auth.uid());
grant select, insert on public.church_events to authenticated;
commit;
