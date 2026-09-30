-- All social writes run through authenticated functions; clients cannot write tables.
create schema if not exists poki_private;
revoke all on schema poki_private from public, anon, authenticated;
create table poki_private.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null check (username ~ '^[a-z0-9_]{3,24}$'),
  name text not null check (char_length(name) between 1 and 40),
  created_at timestamptz not null default now()
);
create table poki_private.connections (
  id uuid primary key default gen_random_uuid(),
  sender uuid not null references poki_private.profiles(id) on delete cascade,
  recipient uuid not null references poki_private.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  updated_at timestamptz not null default now(),
  check (sender <> recipient)
);
create unique index connections_pair on poki_private.connections (least(sender,recipient), greatest(sender,recipient));
create table poki_private.pokes (
  id uuid primary key,
  sender uuid not null references poki_private.profiles(id) on delete cascade,
  recipient uuid not null references poki_private.profiles(id) on delete cascade,
  message text not null check (char_length(message) between 1 and 30 and message !~ '[[:cntrl:]]'),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  check (sender <> recipient)
);
create index incoming_pokes on poki_private.pokes(recipient, created_at desc);
create table poki_private.limits (
  user_id uuid not null references auth.users(id) on delete cascade,
  action text not null,
  bucket timestamptz not null,
  count integer not null,
  primary key (user_id,action)
);
alter table poki_private.profiles enable row level security;
alter table poki_private.connections enable row level security;
alter table poki_private.pokes enable row level security;
alter table poki_private.limits enable row level security;

create function poki_private.actor() returns uuid language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Sign in to continue.'; end if;
  return auth.uid();
end $$;
create function poki_private.throttle(action_name text, maximum integer) returns void language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  insert into poki_private.limits values (poki_private.actor(), action_name, date_trunc('minute',now()), 1)
  on conflict (user_id,action) do update set
    count = case when limits.bucket = excluded.bucket then limits.count + 1 else 1 end,
    bucket = excluded.bucket returning count into n;
  if n > maximum then raise exception 'Please wait a minute before trying again.'; end if;
end $$;

create function public.poki_create_profile(username text, display_name text) returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := poki_private.actor(); handle text := lower(trim(leading '@' from btrim(username)));
begin
  if handle !~ '^[a-z0-9_]{3,24}$' or char_length(btrim(display_name)) not between 1 and 40 then
    raise exception 'Use 3–24 letters, numbers or underscores for your username and a name up to 40 characters.';
  end if;
  insert into poki_private.profiles(id, username, name) values(me, handle, btrim(display_name));
exception when unique_violation then raise exception 'That username is taken, or your profile already exists.';
end $$;

create function public.poki_snapshot() returns jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid := poki_private.actor(); result jsonb;
begin
  select jsonb_build_object(
    'profile', (select jsonb_build_object('id',p.id,'username',p.username,'name',p.name) from poki_private.profiles p where p.id=me),
    'friends', coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'username',p.username,'name',p.name) order by p.username)
      from poki_private.connections c join poki_private.profiles p on p.id=case when c.sender=me then c.recipient else c.sender end
      where me in(c.sender,c.recipient) and c.status='accepted'),'[]'::jsonb),
    'requests', coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'incoming',c.recipient=me,
      'person',jsonb_build_object('id',p.id,'username',p.username,'name',p.name)) order by c.updated_at desc)
      from poki_private.connections c join poki_private.profiles p on p.id=case when c.sender=me then c.recipient else c.sender end
      where me in(c.sender,c.recipient) and c.status='pending'),'[]'::jsonb),
    'pokes', coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'message',q.message,'unread',q.read_at is null,
      'person',jsonb_build_object('id',p.id,'username',p.username,'name',p.name)) order by q.created_at desc)
      from (select * from poki_private.pokes where recipient=me and created_at>now()-interval '24 hours' order by created_at desc limit 50) q
      join poki_private.profiles p on p.id=q.sender),'[]'::jsonb)
  ) into result;
  return result;
end $$;

create function public.poki_search(username text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid := poki_private.actor(); result jsonb;
begin
  perform poki_private.throttle('search',30);
  select jsonb_build_object('person',jsonb_build_object('id',p.id,'username',p.username,'name',p.name),
    'relationship',case when c.status='accepted' then 'accepted' when c.status='pending' and c.sender=me then 'outgoing'
      when c.status='pending' then 'incoming' else 'none' end)
  into result from poki_private.profiles p left join poki_private.connections c
    on least(c.sender,c.recipient)=least(me,p.id) and greatest(c.sender,c.recipient)=greatest(me,p.id)
  where p.username=lower(trim(leading '@' from btrim(username))) and p.id<>me;
  return result;
end $$;

create function public.poki_request(recipient_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := poki_private.actor(); existing poki_private.connections;
begin
  perform poki_private.throttle('request',10);
  if recipient_id=me then raise exception 'You cannot add yourself.'; end if;
  if not exists(select 1 from poki_private.profiles where id=me) then raise exception 'Create your profile first.'; end if;
  -- Serialize both directions of a pair, including its first insertion.
  perform pg_advisory_xact_lock(hashtextextended(least(me,recipient_id)::text||greatest(me,recipient_id)::text,0));
  select * into existing from poki_private.connections where least(sender,recipient)=least(me,recipient_id) and greatest(sender,recipient)=greatest(me,recipient_id) for update;
  if found then
    if existing.status in ('accepted','pending') then return; end if;
    if existing.updated_at > now()-interval '24 hours' then raise exception 'Please wait before sending another request.'; end if;
    update poki_private.connections set sender=me,recipient=recipient_id,status='pending',updated_at=now() where id=existing.id;
  else
    insert into poki_private.connections(sender,recipient) values(me,recipient_id);
  end if;
end $$;

create function public.poki_respond(request_id uuid, accept boolean) returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := poki_private.actor();
begin
  update poki_private.connections set status=case when accept then 'accepted' else 'declined' end,updated_at=now()
  where id=request_id and recipient=me and status='pending';
  if not found then raise exception 'This request is no longer available.'; end if;
end $$;

create function public.poki_send(recipient_id uuid, message text, poke_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := poki_private.actor(); previous poki_private.pokes;
begin
  perform pg_advisory_xact_lock(hashtextextended(me::text,1));
  select * into previous from poki_private.pokes where id=poke_id;
  if found then
    if previous.sender=me and previous.recipient=recipient_id and previous.message=message then return; end if;
    raise exception 'Please start a new poke.';
  end if;
  perform 1 from poki_private.connections where least(sender,recipient)=least(me,recipient_id)
    and greatest(sender,recipient)=greatest(me,recipient_id) and status='accepted' for update;
  if not found then raise exception 'You can only poke accepted friends.'; end if;
  if char_length(btrim(message))=0 or char_length(message)>30 or message ~ '[[:cntrl:]]' then raise exception 'Invalid poke message.'; end if;
  if exists(select 1 from poki_private.pokes where sender=me and created_at>now()-interval '3 seconds') then raise exception 'Wait a moment before your next poke.'; end if;
  perform poki_private.throttle('poke',20);
  insert into poki_private.pokes(id,sender,recipient,message) values(poke_id,me,recipient_id,message);
end $$;

create function public.poki_read(poke_ids uuid[]) returns void language plpgsql security definer set search_path = '' as $$
begin
  update poki_private.pokes set read_at=now() where recipient=poki_private.actor() and id=any(poke_ids) and read_at is null;
end $$;

revoke all on all tables in schema poki_private from public, anon, authenticated;
revoke execute on all functions in schema poki_private from public, anon, authenticated;
revoke execute on function public.poki_create_profile(text,text), public.poki_snapshot(), public.poki_search(text), public.poki_request(uuid), public.poki_respond(uuid,boolean), public.poki_send(uuid,text,uuid), public.poki_read(uuid[]) from public, anon;
grant execute on function public.poki_create_profile(text,text), public.poki_snapshot(), public.poki_search(text), public.poki_request(uuid), public.poki_respond(uuid,boolean), public.poki_send(uuid,text,uuid), public.poki_read(uuid[]) to authenticated;
