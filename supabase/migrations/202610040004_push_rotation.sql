-- An APNs token identifies one app install, so the newest signed-in registration
-- owns it. Keychain state survives reinstalls; without this, a phone that changed
-- accounts stayed unreachable until the previous owner's row expired.
create or replace function public.poki_register_device(device_id uuid, device_token text, apns_environment text) returns void
language plpgsql security definer set search_path = '' as $$
declare me uuid := poki_private.actor(); existing poki_private.devices;
begin
  if device_id is null or device_token is null or device_token !~ '^[0-9a-f]{64,200}$'
    or length(device_token)%2<>0 or apns_environment is null or apns_environment not in ('sandbox','production') then
    raise exception 'Invalid notification registration.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(me::text,2));
  perform pg_advisory_xact_lock(hashtextextended(apns_environment||device_token,3));
  select * into existing from poki_private.devices where id=device_id for update;
  if found and existing.owner<>me then raise exception 'Notification registration unavailable.'; end if;
  -- FOUND is overwritten by the delete below.
  -- Cascades the previous holder's queued deliveries, so they never reach this phone.
  delete from poki_private.devices d where d.token=device_token and d.environment=apns_environment and d.id<>device_id;
  if existing.id is null and (select count(*) from poki_private.devices where owner=me)>=10 then
    raise exception 'Too many notification devices.';
  end if;
  insert into poki_private.devices(id,owner,token,environment) values(device_id,me,device_token,apns_environment)
  on conflict (id) do update set token=excluded.token, environment=excluded.environment,
    version=case when devices.token=excluded.token and devices.environment=excluded.environment then devices.version else gen_random_uuid() end,
    registered_at=clock_timestamp(), expires_at=now()+interval '30 days';
exception when unique_violation then raise exception 'Notification registration unavailable.';
end $$;

-- Expired registrations are never delivered to; drop them with their queued work.
create or replace function poki_private.cleanup() returns void language sql security definer set search_path = '' as $$
  delete from poki_private.pokes where created_at < now()-interval '7 days';
  delete from poki_private.limits where bucket < now()-interval '1 hour';
  delete from poki_private.devices where expires_at < now();
  delete from poki_private.push_outbox where expires_at < now()-interval '1 day';
$$;
