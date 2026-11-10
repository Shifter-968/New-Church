-- Apply once after 039_individual_registration_demographics.sql.
begin;

alter table public.church_events
  add column location_latitude double precision,
  add column location_longitude double precision,
  add column recurrence_series_id uuid,
  add column recurrence_frequency text not null default 'none',
  add column recurrence_interval integer not null default 1,
  add column recurrence_weekdays smallint[] not null default '{}',
  add column recurrence_until date,
  add constraint church_events_location_coordinates_check check (
    (location_latitude is null and location_longitude is null)
    or (location_latitude is not null and location_longitude is not null
      and location_latitude between -90 and 90 and location_longitude between -180 and 180)
  ),
  add constraint church_events_recurrence_frequency_check check (recurrence_frequency in ('none', 'daily', 'weekly', 'monthly')),
  add constraint church_events_recurrence_interval_check check (recurrence_interval between 1 and 365),
  add constraint church_events_recurrence_weekdays_check check (
    array_position(recurrence_weekdays, null) is null
    and recurrence_weekdays <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]
  ),
  add constraint church_events_recurrence_series_check check (
    (recurrence_frequency = 'none' and recurrence_series_id is null and recurrence_until is null)
    or (recurrence_frequency <> 'none' and recurrence_series_id is not null and recurrence_until is not null)
  );

grant update (location_latitude, location_longitude, recurrence_series_id, recurrence_frequency,
  recurrence_interval, recurrence_weekdays, recurrence_until) on public.church_events to authenticated;

commit;