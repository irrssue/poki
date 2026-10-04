-- Remove, block, account deletion, and retention cleanup.
create table poki_private.blocks (
  blocker uuid not null references poki_private.profiles(id) on delete cascade,
  blocked uuid not null references poki_private.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked),
  check (blocker <> blocked)
);
create index blocks_blocked on poki_private.blocks(blocked);
alter table poki_private.blocks enable row level security;
revoke all on poki_private.blocks from public, anon, authenticated;

create function poki_private.blocked_between(a uuid, b uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from poki_private.blocks where (blocker=a and blocked=b) or (blocker=b and blocked=a))
$$;

-- Ends a friendship or cancels/dismisses a pending request. Declined rows keep their cooldown.
create function public.poki_remove(person_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := poki_private.actor();
begin
  perform pg_advisory_xact_lock(hashtextextended(least(me,person_id)::text||greatest(me,person_id)::text,0));
  delete from poki_private.connections where least(sender,recipient)=least(me,person_id)
    and greatest(sender,recipient)=greatest(me,person_id) and status in ('accepted','pending');
end $$;

create function public.poki_block(person_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := poki_private.actor();
begin
  if person_id=me then raise exception 'You cannot block yourself.'; end if;
  if not exists(select 1 from poki_private.profiles where id=me) then raise exception 'Create your profile first.'; end if;
  if not exists(select 1 from poki_private.profiles where id=person_id) then raise exception 'This person is not available.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(least(me,person_id)::text||greatest(me,person_id)::text,0));
  insert into poki_private.blocks(blocker,blocked) values(me,person_id) on conflict do nothing;
  delete from poki_private.connections where least(sender,recipient)=least(me,person_id) and greatest(sender,recipient)=greatest(me,person_id);
end $$;

create function public.poki_unblock(person_id uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from poki_private.blocks where blocker=poki_private.actor() and blocked=person_id;
end $$;

-- Deleting the auth user cascades to the profile, connections, pokes, blocks, and limits.
create function public.poki_delete_account() returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from auth.users where id=poki_private.actor();
end $$;

create or replace function public.poki_request(recipient_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := poki_private.actor(); existing poki_private.connections;
begin
  perform poki_private.throttle('request',10);
  if recipient_id=me then raise exception 'You cannot add yourself.'; end if;
  if not exists(select 1 from poki_private.profiles where id=me) then raise exception 'Create your profile first.'; end if;
  -- Serialize both directions of a pair, including its first insertion.
  perform pg_advisory_xact_lock(hashtextextended(least(me,recipient_id)::text||greatest(me,recipient_id)::text,0));
  if poki_private.blocked_between(me,recipient_id) or not exists(select 1 from poki_private.profiles where id=recipient_id) then
    raise exception 'This person is not available.';
  end if;
  select * into existing from poki_private.connections where least(sender,recipient)=least(me,recipient_id) and greatest(sender,recipient)=greatest(me,recipient_id) for update;
  if found then
    if existing.status in ('accepted','pending') then return; end if;
    if existing.updated_at > now()-interval '24 hours' then raise exception 'Please wait before sending another request.'; end if;
    update poki_private.connections set sender=me,recipient=recipient_id,status='pending',updated_at=now() where id=existing.id;
  else
    insert into poki_private.connections(sender,recipient) values(me,recipient_id);
  end if;
end $$;

create or replace function public.poki_search(username text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid := poki_private.actor(); result jsonb;
begin
  perform poki_private.throttle('search',30);
  select jsonb_build_object('person',jsonb_build_object('id',p.id,'username',p.username,'name',p.name),
    'relationship',case when c.status='accepted' then 'accepted' when c.status='pending' and c.sender=me then 'outgoing'
      when c.status='pending' then 'incoming' else 'none' end)
  into result from poki_private.profiles p left join poki_private.connections c
    on least(c.sender,c.recipient)=least(me,p.id) and greatest(c.sender,c.recipient)=greatest(me,p.id)
  where p.username=lower(trim(leading '@' from btrim(poki_search.username))) and p.id<>me
    and not poki_private.blocked_between(me,p.id);
  return result;
end $$;

create or replace function public.poki_snapshot() returns jsonb language plpgsql security definer set search_path = '' as $$
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
      from (select * from poki_private.pokes x where recipient=me and created_at>now()-interval '24 hours'
        and not exists(select 1 from poki_private.blocks b where b.blocker=me and b.blocked=x.sender)
        order by created_at desc limit 50) q
      join poki_private.profiles p on p.id=q.sender),'[]'::jsonb),
    'blocked', coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'username',p.username,'name',p.name) order by p.username)
      from poki_private.blocks b join poki_private.profiles p on p.id=b.blocked where b.blocker=me),'[]'::jsonb)
  ) into result;
  return result;
end $$;

-- The inbox shows 24 hours; keep a short buffer for support, then drop message payloads.
create function poki_private.cleanup() returns void language sql security definer set search_path = '' as $$
  delete from poki_private.pokes where created_at < now()-interval '7 days';
  delete from poki_private.limits where bucket < now()-interval '1 hour';
$$;

do $$
begin
  if exists(select 1 from pg_available_extensions where name='pg_cron') then
    execute 'create extension if not exists pg_cron with schema pg_catalog';
    perform cron.schedule('poki-cleanup', '17 * * * *', 'select poki_private.cleanup()');
  end if;
end $$;

revoke execute on function poki_private.blocked_between(uuid,uuid), poki_private.cleanup() from public, anon, authenticated;
revoke execute on function public.poki_remove(uuid), public.poki_block(uuid), public.poki_unblock(uuid), public.poki_delete_account() from public, anon;
grant execute on function public.poki_remove(uuid), public.poki_block(uuid), public.poki_unblock(uuid), public.poki_delete_account() to authenticated;
