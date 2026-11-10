-- Apply once after 019_attendance_corrections.sql.
begin;

alter table public.members add constraint members_id_org_branch_unique unique (id, organization_id, branch_id);
create table public.church_families (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 branch_id uuid not null,
 name text not null check (length(trim(name)) between 1 and 120),
 primary_contact text not null check (length(trim(primary_contact)) between 1 and 120),
 address text not null default '' check (length(address) <= 255),
 notes text not null default '' check (length(notes) <= 1000),
 foreign key (branch_id, organization_id) references public.branches(id, organization_id),
 unique (id, organization_id, branch_id)
);
create table public.church_children (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 branch_id uuid not null,
 first_name text not null check (length(trim(first_name)) between 1 and 100),
 last_name text not null check (length(trim(last_name)) between 1 and 100),
 date_of_birth date check (date_of_birth <= current_date),
 residence text not null default '' check (length(residence) <= 255),
 parent_contact text not null check (length(trim(parent_contact)) between 1 and 120),
 foreign key (branch_id, organization_id) references public.branches(id, organization_id),
 unique (id, organization_id, branch_id)
);
create table public.church_family_people (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null,
 branch_id uuid not null,
 family_id uuid not null,
 member_id uuid,
 child_id uuid,
 relationship text not null default '' check (length(relationship) <= 120),
 check ((member_id is null) <> (child_id is null)),
 foreign key (family_id, organization_id, branch_id) references public.church_families(id, organization_id, branch_id) on delete cascade,
 foreign key (member_id, organization_id, branch_id) references public.members(id, organization_id, branch_id) on delete restrict,
 foreign key (child_id, organization_id, branch_id) references public.church_children(id, organization_id, branch_id) on delete restrict,
 unique (family_id, member_id),
 unique (family_id, child_id)
);
create index church_families_scope_idx on public.church_families(organization_id, branch_id, name);
create index church_children_scope_idx on public.church_children(organization_id, branch_id, last_name);
create index church_family_people_family_idx on public.church_family_people(family_id);

alter table public.church_families enable row level security;
alter table public.church_children enable row level security;
alter table public.church_family_people enable row level security;
revoke all on public.church_families, public.church_children, public.church_family_people from public, anon, authenticated;
grant select, delete on public.church_families, public.church_children, public.church_family_people to authenticated;
grant insert (organization_id,branch_id,name,primary_contact,address,notes) on public.church_families to authenticated;
grant update (name,primary_contact,address,notes) on public.church_families to authenticated;
grant insert (organization_id,branch_id,first_name,last_name,date_of_birth,residence,parent_contact) on public.church_children to authenticated;
grant update (first_name,last_name,date_of_birth,residence,parent_contact) on public.church_children to authenticated;
grant insert (organization_id,branch_id,family_id,member_id,child_id,relationship) on public.church_family_people to authenticated;
grant update (relationship) on public.church_family_people to authenticated;

create policy "families view" on public.church_families for select to authenticated using (public.has_member_permission(organization_id,branch_id,'view'));
create policy "families create" on public.church_families for insert to authenticated with check (public.has_member_permission(organization_id,branch_id,'create'));
create policy "families update" on public.church_families for update to authenticated using (public.has_member_permission(organization_id,branch_id,'update')) with check (public.has_member_permission(organization_id,branch_id,'update'));
create policy "families delete" on public.church_families for delete to authenticated using (public.has_member_permission(organization_id,branch_id,'delete'));
create policy "children view" on public.church_children for select to authenticated using (public.has_member_permission(organization_id,branch_id,'view'));
create policy "children create" on public.church_children for insert to authenticated with check (public.has_member_permission(organization_id,branch_id,'create'));
create policy "children update" on public.church_children for update to authenticated using (public.has_member_permission(organization_id,branch_id,'update')) with check (public.has_member_permission(organization_id,branch_id,'update'));
create policy "children delete" on public.church_children for delete to authenticated using (public.has_member_permission(organization_id,branch_id,'delete'));
create policy "family people view" on public.church_family_people for select to authenticated using (public.has_member_permission(organization_id,branch_id,'view'));
create policy "family people create" on public.church_family_people for insert to authenticated with check (public.has_member_permission(organization_id,branch_id,'update'));
create policy "family people update" on public.church_family_people for update to authenticated using (public.has_member_permission(organization_id,branch_id,'update')) with check (public.has_member_permission(organization_id,branch_id,'update'));
create policy "family people delete" on public.church_family_people for delete to authenticated using (public.has_member_permission(organization_id,branch_id,'update'));
create trigger family_activity after insert or update or delete on public.church_families for each row execute function public.record_support_activity();
create trigger child_activity after insert or update or delete on public.church_children for each row execute function public.record_support_activity();
create trigger family_person_activity after insert or update or delete on public.church_family_people for each row execute function public.record_support_activity();
commit;
