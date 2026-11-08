-- Apply once after 011_visitor_management.sql.
begin;

create function public.find_visitor_duplicates(target_org uuid, candidates jsonb)
returns table (row_number bigint, matches jsonb)
language plpgsql stable security invoker set search_path = ''
as $$
begin
  if jsonb_typeof(candidates) is distinct from 'array' or jsonb_array_length(candidates) not between 1 and 500 then
    raise exception 'Provide between 1 and 500 visitor records.';
  end if;
  return query
  select c.ordinality, jsonb_agg(to_jsonb(v) order by v.id)
  from jsonb_array_elements(candidates) with ordinality as c(details, ordinality)
  cross join lateral (
    select existing.id, existing.first_name, existing.last_name, existing.email, existing.phone, existing.branch_id
    from public.visitors existing
    where existing.organization_id = target_org and (
      (nullif(trim(c.details ->> 'first_name'), '') is not null
       and nullif(trim(c.details ->> 'last_name'), '') is not null
       and lower(trim(existing.first_name)) = lower(trim(c.details ->> 'first_name'))
       and lower(trim(existing.last_name)) = lower(trim(c.details ->> 'last_name')))
      or (nullif(trim(c.details ->> 'email'), '') is not null
       and lower(trim(existing.email)) = lower(trim(c.details ->> 'email')))
      or (nullif(regexp_replace(coalesce(c.details ->> 'phone', ''), '[^0-9]', '', 'g'), '') is not null
       and regexp_replace(coalesce(existing.phone, ''), '[^0-9]', '', 'g') = regexp_replace(c.details ->> 'phone', '[^0-9]', '', 'g'))
    )
    order by existing.created_at desc, existing.id
    limit 5
  ) v
  group by c.ordinality
  order by c.ordinality;
end
$$;
revoke all on function public.find_visitor_duplicates(uuid, jsonb) from public, anon;
grant execute on function public.find_visitor_duplicates(uuid, jsonb) to authenticated;
commit;
