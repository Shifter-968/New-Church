-- Apply once after 026_member_import_duplicates.sql.
begin;

-- A church-wide creator can also add a person without a branch.
create or replace function public.find_member_import_duplicates(target_org uuid, target_branch uuid, candidates jsonb)
returns table (row_number bigint, matches jsonb)
language plpgsql stable security invoker set search_path = ''
as $$
begin
  if jsonb_typeof(candidates) is distinct from 'array' or jsonb_array_length(candidates) not between 1 and 500 then
    raise exception 'Provide between 1 and 500 member records.';
  end if;
  if (target_branch is not null and not exists(select 1 from public.branches b where b.id=target_branch and b.organization_id=target_org))
    or not public.has_member_permission(target_org,target_branch,'view')
    or not public.has_member_permission(target_org,target_branch,'create') then
    raise exception 'Viewing and creating members in the selected scope are required for a duplicate check.';
  end if;
  return query
  with inputs as materialized (
    select c.ordinality, nullif(lower(trim(c.details ->> 'first_name')),'') first_name,
      nullif(lower(trim(c.details ->> 'last_name')),'') last_name,
      nullif(lower(trim(c.details ->> 'email')),'') email,
      array_remove(array[
        nullif(regexp_replace(coalesce(c.details ->> 'phone',''),'[^0-9]','','g'),''),
        nullif(regexp_replace(coalesce(c.details ->> 'phone_2',''),'[^0-9]','','g'),'')
      ],null) phones
    from jsonb_array_elements(candidates) with ordinality as c(details,ordinality)
  ), visible_members as materialized (
    select existing.id, existing.created_at, lower(trim(existing.first_name)) first_name,
      lower(trim(existing.last_name)) last_name, nullif(lower(trim(existing.email)),'') email,
      array_remove(array[
        nullif(regexp_replace(coalesce(existing.phone,''),'[^0-9]','','g'),''),
        nullif(regexp_replace(coalesce(existing.phone_2,''),'[^0-9]','','g'),'')
      ],null) phones,
      jsonb_build_object('id',existing.id,'first_name',existing.first_name,'last_name',existing.last_name,
        'email',existing.email,'phone',existing.phone,'phone_2',existing.phone_2,
        'branch_id',existing.branch_id,'status',existing.status) details
    from public.members existing where existing.organization_id=target_org
  ), matched as (
    select i.ordinality,m.id,m.details,
      row_number() over(partition by i.ordinality order by m.created_at desc,m.id) rank
    from inputs i join visible_members m on
      (i.first_name is not null and i.last_name is not null and i.first_name=m.first_name and i.last_name=m.last_name)
      or (i.email is not null and i.email=m.email)
      or i.phones && m.phones
  )
  select matched.ordinality,jsonb_agg(matched.details order by matched.id)
  from matched where matched.rank <= 5 group by matched.ordinality order by matched.ordinality;
end
$$;
commit;
