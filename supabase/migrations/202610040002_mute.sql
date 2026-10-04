-- Directional mute preferences are private and do not change friendships or sending.
create table poki_private.mutes (
  owner uuid not null references poki_private.profiles(id) on delete cascade,
  muted uuid not null references poki_private.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner, muted),
  check (owner <> muted)
);
create index mutes_muted on poki_private.mutes(muted);
alter table poki_private.mutes enable row level security;
revoke all on poki_private.mutes from public, anon, authenticated;

create function public.poki_mute(person_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := poki_private.actor();
begin
  if person_id=me then raise exception 'You cannot mute yourself.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(least(me,person_id)::text||greatest(me,person_id)::text,0));
  perform 1 from poki_private.connections where least(sender,recipient)=least(me,person_id)
    and greatest(sender,recipient)=greatest(me,person_id) and status='accepted' for update;
  if not found then raise exception 'You can only mute accepted friends.'; end if;
  insert into poki_private.mutes(owner,muted) values(me,person_id) on conflict do nothing;
end $$;

-- Unmute remains available after removing or blocking a friend.
create function public.poki_unmute(person_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := poki_private.actor();
begin
  delete from poki_private.mutes where owner=me and muted=person_id;
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
        and not exists(select 1 from poki_private.mutes m where m.owner=me and m.muted=x.sender)
        order by created_at desc limit 50) q
      join poki_private.profiles p on p.id=q.sender),'[]'::jsonb),
    'blocked', coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'username',p.username,'name',p.name) order by p.username)
      from poki_private.blocks b join poki_private.profiles p on p.id=b.blocked where b.blocker=me),'[]'::jsonb),
    'muted', coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'username',p.username,'name',p.name) order by p.username)
      from poki_private.mutes m join poki_private.profiles p on p.id=m.muted where m.owner=me),'[]'::jsonb)
  ) into result;
  return result;
end $$;

revoke execute on function public.poki_mute(uuid), public.poki_unmute(uuid) from public, anon;
grant execute on function public.poki_mute(uuid), public.poki_unmute(uuid) to authenticated;
