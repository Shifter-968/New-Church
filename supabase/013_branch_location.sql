-- Apply once after 012_visitor_duplicate_check.sql.
begin;
revoke update on public.branches from public, anon, authenticated;
alter table public.branches
  add column latitude numeric,
  add column longitude numeric,
  add column radius_meters integer not null default 100 check (radius_meters between 20 and 2000),
  add column location_label text not null default '' check (length(location_label) <= 255),
  add constraint branch_coordinates_valid check (
    (latitude is null and longitude is null) or
    (latitude is not null and longitude is not null and latitude between -90 and 90 and longitude between -180 and 180)
  );

create function public.save_branch_location(target_org uuid, target_branch uuid, new_latitude numeric, new_longitude numeric, new_radius integer, new_label text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_org_administrator(target_org) then
    raise exception 'Only an organization administrator or platform owner can set branch locations.';
  end if;
  if new_latitude is null or new_latitude not between -90 and 90 or new_longitude is null or new_longitude not between -180 and 180
     or new_radius is null or new_radius not between 20 and 2000 or length(coalesce(new_label, '')) > 255 then
    raise exception 'Enter valid coordinates and a radius from 20 to 2000 metres.';
  end if;
  update public.branches set latitude = new_latitude, longitude = new_longitude,
    radius_meters = new_radius, location_label = trim(coalesce(new_label, ''))
    where id = target_branch and organization_id = target_org;
  if not found then raise exception 'Branch does not belong to this church.'; end if;
end
$$;
revoke all on function public.save_branch_location(uuid, uuid, numeric, numeric, integer, text) from public, anon;
grant execute on function public.save_branch_location(uuid, uuid, numeric, numeric, integer, text) to authenticated;
commit;
