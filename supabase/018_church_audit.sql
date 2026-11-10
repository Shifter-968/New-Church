-- Apply once after 017_personal_attendance_history.sql.
begin;

create index support_activity_org_created_idx on public.support_activity (organization_id, created_at desc, id desc);
create policy "organization administrators read their activity" on public.support_activity
 for select to authenticated using (public.is_org_administrator(organization_id));

create trigger member_activity after insert or update or delete on public.members
 for each row execute function public.record_support_activity();
create trigger visitor_activity after insert or update or delete on public.visitors
 for each row execute function public.record_support_activity();
create trigger branch_activity after insert or update or delete on public.branches
 for each row execute function public.record_support_activity();
create trigger role_activity after insert or update or delete on public.roles
 for each row execute function public.record_support_activity();
create trigger assignment_activity after insert or update or delete on public.assignments
 for each row execute function public.record_support_activity();
create trigger team_activity after insert or update or delete on public.church_teams
 for each row execute function public.record_support_activity();
create trigger team_membership_activity after insert or update or delete on public.church_team_members
 for each row execute function public.record_support_activity();
create trigger attendance_activity after insert or update or delete on public.event_attendance
 for each row execute function public.record_support_activity();

commit;
