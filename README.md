# AfriChurch — fresh React edition

An independent React **JavaScript** application, with a new Supabase database and Netlify deployment configuration. It does not connect to, migrate, or modify the previous system.

## What works in this first slice

- A public landing page and debounced church search backed by Supabase RPCs, including branch selection for individual registration.
- Church registration creates an email/password account and a pending application. A platform owner can approve or reject it; approval creates the organization and an organization-wide administrator assignment. Email confirmation is required before approval. Existing accounts cannot yet submit a new application through the interface.
- Supabase email/password sign-in and sign-out.
- Platform owners can create and select church workspaces.
- Platform owners can create and edit the plan catalogue, including pricing, limits and feature flags. Plans are not yet selected in registration, assigned to organizations, billed, or enforced.
- A member directory with search, add, edit and removal, subject to database-enforced permissions and organization/branch scope.
- Individual email/password registration for members and visitors. After email confirmation and sign-in, members are matched to active, unlinked records within the selected church and branch. First and last names must match; a recorded email and birth date must match, and if the record has phone numbers at least one of the submitted numbers must match one of them (ignoring phone punctuation). Fields missing from the church record do not prevent a match. If exactly one record matches, linking is automatic. This intentionally allows name-only matching when no other details are stored: **a confirmed new email does not prove that the account belongs to the member**, and public or guessed details can be used to impersonate someone. Keep member records complete and confirm identities where possible.
- Ambiguous exact matches or potential matches with one differing field (including a name up to one inserted, deleted or substituted character) appear in Membership requests for users with `members.update` permission in that branch. An administrator must independently confirm identity, choose a candidate and approve or reject. The applicant must sign in and check status after approval to complete registration. More distant mismatches are not queued; the applicant must contact the church. Visitors receive a separate visitor record. Registration creates a basic role with no management permissions and a private profile. Branch, status and deletion are temporarily blocked for linked member records until account-access management can safely synchronize access. Existing accounts cannot yet register as an individual through this flow, and visitors do not yet have a management directory or a full visitor dashboard.
- An overview based on accessible members and branches. The directory currently loads at most 1,000 members; search and overview counts cover only those loaded.
- Organization-wide or branch-scoped assignments, and permission bundles stored in the database.
- Permission-aware workspace navigation and branch creation/branch administrator assignment for organization administrators and owners. An administrator can assign an existing confirmed Supabase Auth account by email; account invitations are not yet implemented. The branch administrator role currently grants only the four member-management permissions.
- Account profile editing, password change, personal notification inbox, church-wide announcements and a church event list. Platform owners can view announcements and events across churches, filter by church, and create, edit or delete records for a selected church. Organization administrators can manage records for their own church. Migration 007 also records creation, editing and deletion activity for announcements and events; the owner audit screen shows the latest 100 such changes. This is not a full audit trail. Profiles are private account records, not synchronized to member records. Automatic notifications, targeted audiences and a month-grid calendar are not yet implemented. Lists are limited to 100 records; the calendar defaults to ongoing and upcoming events.
- Community includes Connect groups: platform owners and organization administrators can manage group setup across their church scope without joining, and assign a confirmed, actively assigned church account as owner. An assigned church user can create a group, and eligible users can join an active group by code. A branch-specific group requires an organization-wide or matching branch assignment. Creators can add, remove, ban, restore and promote/demote members; church administrators can assist with membership, while only creators can change group admin roles. Active group members can send and edit their own text messages and delete their own messages for everyone; creators and group admins can delete any group message for everyone. Deletion replaces the message content with a tombstone; it is not a guarantee of erasure from backups. Non-member support cannot read or delete messages. Group, membership and message changes are included as metadata in support activity, not message content. Lists show at most 100 groups and the latest 100 messages; use Refresh to see updates. Media, leaving, granular roles, invitations, direct conversations and Connect announcements are not yet available.

Plan selection, payment, Google sign-in, full event management, attendance, ministries, visitor management, reports, role editing, full community functionality, full member/visitor self-service dashboards and the rest of the previous application's functionality are **not implemented yet**. Navigation placeholders are not functional modules. No payment is collected or checked during church registration. This is a foundation, not a feature-complete replacement.

The SQL tests in `tests/` are intended only for an isolated, disposable PostgreSQL cluster. On a fresh cluster, run `tests/connect_test_auth.sql`, `supabase/schema.sql`, migrations 002, 006, 007, 008, 009 and 010, and then the Connect and individual registration tests with `psql -v ON_ERROR_STOP=1`, in that order. The Auth stand-in is not Supabase and must never be applied to a live project. A passing local test does not replace testing against real Supabase accounts and policies.

## 1. Create a fresh Supabase project

1. Create a **new**, separate Supabase project. Do not use the old application's database.
2. In its SQL editor, run [supabase/schema.sql](supabase/schema.sql), [supabase/002_public_search_and_branch_admin.sql](supabase/002_public_search_and_branch_admin.sql), [supabase/003_organization_applications.sql](supabase/003_organization_applications.sql), [supabase/004_branch_admin_by_email.sql](supabase/004_branch_admin_by_email.sql), [supabase/005_plan_catalog.sql](supabase/005_plan_catalog.sql), [supabase/006_my_church.sql](supabase/006_my_church.sql), [supabase/007_support_management.sql](supabase/007_support_management.sql), [supabase/008_connect_groups.sql](supabase/008_connect_groups.sql), [supabase/009_connect_conversations.sql](supabase/009_connect_conversations.sql), and [supabase/010_individual_registration.sql](supabase/010_individual_registration.sql), **once each, in order**. If earlier migrations have already been applied, run only the remaining files. Do not rerun the initial schema on a database with existing tables of the same names.
3. In Authentication > Users, create the initial owner user and confirm their email. Then use the SQL editor, replacing the email with the exact email for that account:

   ```sql
   insert into public.platform_owners (user_id)
   select id from auth.users where lower(email) = lower('owner@example.com')
   on conflict (user_id) do nothing;
   ```

   Check that the statement inserted a row (or the owner already exists). Only a trusted project administrator with SQL editor access should grant or revoke platform ownership. Platform owners can access members across all churches and create churches.
4. To test church registration, enable email signup and email confirmation in Supabase Authentication. Set the site URL and redirect allowlist for the local and deployed app URLs, including `/login`; configure email delivery as appropriate. The Auth signup trigger stores application details and the owner reviews them. Public signup also allows accounts without applications; these receive no organization access. Configure Auth rate limits and abuse protection before public use. Never put a service-role key or database password in the frontend.

## 2. Run locally

Copy `.env.example` to `.env.local` and fill in the project's URL and **publishable or anon** key from Supabase. These values are public client configuration; access control is enforced by the SQL policies. In PowerShell:

```powershell
cd "New Church System"
npm install
npm run dev
```

Register a church with a new account, confirm its email, then sign in as the owner and open **Church applications** to approve it. The applicant can then sign in to their workspace. No example or old church data is loaded.

The React app connects through the Supabase API and does **not** need the PostgreSQL connection string or database password. Keep those credentials out of `.env.local`, Netlify's `VITE_` variables, and browser code. Use the Supabase SQL editor for the SQL setup above, or a trusted server-side database client if needed. The supplied connection URI ends in `/postgres`, which is the database name in that URI; verify the actual database name in Supabase before changing it.

## 3. Set up branches and staff access

Organization administrators can create branches and assign a branch administrator by the email of an existing confirmed account in the Branches screen. Invitations and normal account creation for staff are not implemented. Until role management screens are implemented, a trusted administrator can use the SQL editor for additional assignments. Replace all placeholder UUIDs with real IDs; the staff user must already exist in Supabase Auth. The SQL editor bypasses row-level security, so access to it must be restricted.

```sql
-- Find the organization ID after the owner creates it in the app.
select id, name from public.organizations;

-- Optional branch.
insert into public.branches (organization_id, name)
values ('organization-uuid', 'Main branch');

-- Organization-wide administrator: all member actions in this organization.
insert into public.roles (organization_id, name, is_org_admin)
values ('organization-uuid', 'Organization Administrator', true)
returning id;

insert into public.assignments (user_id, organization_id, role_id)
values ('staff-auth-user-uuid', 'organization-uuid', 'role-uuid');

-- Example branch-scoped role, with explicit member permissions.
insert into public.roles (organization_id, name, permissions)
values ('organization-uuid', 'Branch Member Manager',
        array['members.view', 'members.create', 'members.update', 'members.delete'])
returning id;

insert into public.assignments (user_id, organization_id, branch_id, role_id)
values ('staff-auth-user-uuid', 'organization-uuid', 'branch-uuid', 'role-uuid');
```

An organization-wide assignment has a null `branch_id`. A branch-scoped assignment only covers members in that branch; members without a branch are accessible only to organization-wide assignments or platform owners. `is_org_admin` grants full member access only when the assignment is organization-wide. Other roles use `members.view`, `members.create`, `members.update`, and `members.delete`; include `members.view` for anyone managing records. Assignments may be disabled using `active = false`. Multiple assignments contribute their permissions within their individual scopes. Additional navigation permissions are listed in `src/navigation.js`, but their underlying modules and server-side policies are not yet implemented. Hiding navigation is not a security boundary. The previous app's other permission categories and scope types have not yet been implemented.

Churches are discoverable by default; set `organizations.is_discoverable` to false for a church that should not appear in public search. Search and branch lookup expose only IDs and names to unauthenticated visitors. Church-scoped sign-in selects the requested church only if the signed-in user has access; it does not grant access.

## 4. Deploy to Netlify

Create a Netlify site from a repository containing this folder. Set the base directory to `New Church System` if the folder is not the repository root. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` as Netlify environment variables, then deploy. [netlify.toml](netlify.toml) configures the build, publish directory, and single-page app fallback. Add the deployed HTTPS URL to Supabase Authentication's URL configuration as appropriate. Do not expose service-role keys.

Before using real member information, review the Supabase project's security, backups, user provisioning, and access assignments; test row-level security using separate owner, organization, and branch accounts. This initial implementation has not been deployed or tested against your Supabase project.

## Checks

```powershell
npm test
npm run build
```
