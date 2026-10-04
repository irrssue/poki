-- Device tokens and delivery work never appear in client snapshots.
create table poki_private.devices (
  id uuid primary key,
  owner uuid not null references poki_private.profiles(id) on delete cascade,
  token text not null check (token ~ '^[0-9a-f]{64,200}$' and length(token)%2=0),
  environment text not null check (environment in ('sandbox','production')),
  version uuid not null default gen_random_uuid(),
  registered_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default now()+interval '30 days',
  unique (token,environment)
);
create index devices_owner on poki_private.devices(owner);
create table poki_private.push_outbox (
  poke_id uuid primary key references poki_private.pokes(id) on delete cascade,
  expires_at timestamptz not null default now()+interval '15 minutes'
);
create table poki_private.push_deliveries (
  id uuid primary key default gen_random_uuid(),
  poke_id uuid not null references poki_private.push_outbox(poke_id) on delete cascade,
  device_id uuid not null references poki_private.devices(id) on delete cascade,
  device_version uuid not null,
  state text not null default 'pending' check (state in ('pending','sending','sent','dropped')),
  attempts integer not null default 0,
  available_at timestamptz not null default now(),
  lease_id uuid,
  lease_until timestamptz,
  unique (poke_id,device_id)
);
create index push_ready on poki_private.push_deliveries(available_at) where state in ('pending','sending');
alter table poki_private.devices enable row level security;
alter table poki_private.push_outbox enable row level security;
alter table poki_private.push_deliveries enable row level security;
revoke all on poki_private.devices, poki_private.push_outbox, poki_private.push_deliveries from public, anon, authenticated;

create function public.poki_register_device(device_id uuid, device_token text, apns_environment text) returns void
language plpgsql security definer set search_path = '' as $$
declare me uuid := poki_private.actor(); existing poki_private.devices;
begin
  if device_id is null or device_token is null or device_token !~ '^[0-9a-f]{64,200}$'
    or length(device_token)%2<>0 or apns_environment is null or apns_environment not in ('sandbox','production') then
    raise exception 'Invalid notification registration.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(me::text,2));
  select * into existing from poki_private.devices where id=device_id for update;
  if found and existing.owner<>me then raise exception 'Notification registration unavailable.'; end if;
  if not found and (select count(*) from poki_private.devices where owner=me)>=10 then
    raise exception 'Too many notification devices.';
  end if;
  insert into poki_private.devices(id,owner,token,environment) values(device_id,me,device_token,apns_environment)
  on conflict (id) do update set token=excluded.token, environment=excluded.environment,
    version=case when devices.token=excluded.token and devices.environment=excluded.environment then devices.version else gen_random_uuid() end,
    registered_at=clock_timestamp(), expires_at=now()+interval '30 days';
exception when unique_violation then raise exception 'Notification registration unavailable.';
end $$;

create function public.poki_unregister_device(device_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare me uuid := poki_private.actor();
begin
  delete from poki_private.devices where id=device_id and owner=me;
end $$;

-- The trigger shares the poke transaction: enqueue failure rolls back acceptance.
-- Only INSERT fires, so idempotent poki_send retries cannot enqueue twice.
create function poki_private.enqueue_push() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into poki_private.push_outbox(poke_id) values(new.id);
  insert into poki_private.push_deliveries(poke_id,device_id,device_version)
    select new.id,d.id,d.version from poki_private.devices d where d.owner=new.recipient and d.expires_at>now();
  return new;
end $$;
create trigger poke_push after insert on poki_private.pokes for each row execute function poki_private.enqueue_push();

create function poki_private.push_allowed(delivery_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from poki_private.push_deliveries j
    join poki_private.push_outbox o on o.poke_id=j.poke_id
    join poki_private.pokes p on p.id=j.poke_id
    join poki_private.devices d on d.id=j.device_id
    where j.id=delivery_id and o.expires_at>now() and d.expires_at>now()
      and d.owner=p.recipient and d.version=j.device_version
      and not poki_private.blocked_between(p.sender,p.recipient)
      and not exists(select 1 from poki_private.mutes m where m.owner=p.recipient and m.muted=p.sender)
      and exists(select 1 from poki_private.connections c where c.status='accepted'
        and least(c.sender,c.recipient)=least(p.sender,p.recipient)
        and greatest(c.sender,c.recipient)=greatest(p.sender,p.recipient)))
$$;

-- These RPCs are worker-only. Leases make overlapping workers and crashes safe.
create function public.poki_claim_push() returns jsonb language plpgsql security definer set search_path = '' as $$
declare job poki_private.push_deliveries;
begin
  for job in select * from poki_private.push_deliveries
    where (state='pending' and available_at<=now()) or (state='sending' and lease_until<=now())
    order by available_at for update skip locked limit 100
  loop
    if job.attempts>=5 or not poki_private.push_allowed(job.id) then
      update poki_private.push_deliveries set state='dropped',lease_id=null,lease_until=null where id=job.id;
      continue;
    end if;
    update poki_private.push_deliveries set state='sending',attempts=attempts+1,
      lease_id=gen_random_uuid(),lease_until=now()+interval '60 seconds' where id=job.id returning * into job;
    return jsonb_build_object('id',job.id,'lease_id',job.lease_id);
  end loop;
  return null;
end $$;

-- Recheck immediately before transport, including after a job has been leased.
create function public.poki_push_payload(delivery_id uuid, claim_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare job poki_private.push_deliveries; payload jsonb;
begin
  select * into job from poki_private.push_deliveries where id=delivery_id and lease_id=claim_id
    and state='sending' and lease_until>now() for update;
  if not found then return null; end if;
  if not poki_private.push_allowed(job.id) then
    update poki_private.push_deliveries set state='dropped',lease_id=null,lease_until=null where id=job.id;
    return null;
  end if;
  select jsonb_build_object('id',job.id,'token',d.token,'environment',d.environment,
    'recipient_id',p.recipient,'sender_id',p.sender,'sender_name',s.name,'message',p.message,
    'expires_at',extract(epoch from o.expires_at)::bigint,'attempts',job.attempts)
    into payload from poki_private.devices d join poki_private.pokes p on p.id=job.poke_id
    join poki_private.profiles s on s.id=p.sender join poki_private.push_outbox o on o.poke_id=p.id
    where d.id=job.device_id;
  return payload;
end $$;

create function public.poki_finish_push(delivery_id uuid, claim_id uuid, outcome text, invalidated_at double precision default null)
returns void language plpgsql security definer set search_path = '' as $$
declare job poki_private.push_deliveries;
begin
  if outcome is null or outcome not in ('sent','retry','drop','invalid') then raise exception 'Invalid push outcome.'; end if;
  select * into job from poki_private.push_deliveries where id=delivery_id and lease_id=claim_id
    and state='sending' and lease_until>now() for update;
  if not found then return; end if;
  update poki_private.push_deliveries set state=case when outcome='sent' then 'sent'
    when outcome='retry' and attempts<5 and poki_private.push_allowed(id) then 'pending' else 'dropped' end,
    available_at=now()+make_interval(secs=>least(300,5*power(2,attempts)::integer)),lease_id=null,lease_until=null
    where id=job.id;
  if outcome='invalid' then
    -- A late 410 must not invalidate a newly registered/rotated token.
    delete from poki_private.devices where id=job.device_id and version=job.device_version
      and (invalidated_at is null or registered_at<=to_timestamp(invalidated_at/1000.0));
  end if;
end $$;

revoke execute on function poki_private.enqueue_push(),poki_private.push_allowed(uuid) from public,anon,authenticated;
revoke execute on function public.poki_register_device(uuid,text,text),public.poki_unregister_device(uuid) from public,anon;
grant execute on function public.poki_register_device(uuid,text,text),public.poki_unregister_device(uuid) to authenticated;
revoke execute on function public.poki_claim_push(),public.poki_push_payload(uuid,uuid),public.poki_finish_push(uuid,uuid,text,double precision) from public,anon,authenticated;
grant execute on function public.poki_claim_push(),public.poki_push_payload(uuid,uuid),public.poki_finish_push(uuid,uuid,text,double precision) to service_role;
