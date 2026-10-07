-- Private reports for moderators. Reporters never see reports, and the reported
-- person is never told. Evidence is copied because pokes are purged after 7 days.
-- Reports outlive either account (ids become null) so moderation keeps its record.
create table poki_private.reports (
  id uuid primary key default gen_random_uuid(),
  reporter uuid references poki_private.profiles(id) on delete set null,
  reported uuid references poki_private.profiles(id) on delete set null,
  reported_username text not null,
  poke_id uuid,
  reason text not null check (reason in ('spam','harassment','inappropriate','impersonation','other')),
  details text check (char_length(details) between 1 and 300 and details !~ '[[:cntrl:]]'),
  evidence jsonb not null default '[]'::jsonb,
  status text not null default 'open' check (status in ('open','dismissed','actioned')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  check (reporter <> reported),
  check ((status='open') = (resolved_at is null))
);
create index reports_open on poki_private.reports(created_at) where status='open';
create index reports_reporter on poki_private.reports(reporter);
create index reports_reported on poki_private.reports(reported);
alter table poki_private.reports enable row level security;
revoke all on poki_private.reports from public, anon, authenticated;

-- Reporting a poke captures that message; reporting a person captures their last
-- five pokes to the reporter. Retrying an open report is a no-op.
create function public.poki_report(person_id uuid, reason text, poke_id uuid default null,
  details text default null, also_block boolean default false) returns void
language plpgsql security definer set search_path = '' as $$
declare me uuid := poki_private.actor(); note text := nullif(btrim(details),''); handle text; proof jsonb;
begin
  perform poki_private.throttle('report',5);
  if person_id=me then raise exception 'You cannot report yourself.'; end if;
  if not exists(select 1 from poki_private.profiles where id=me) then raise exception 'Create your profile first.'; end if;
  select p.username into handle from poki_private.profiles p where p.id=person_id;
  if handle is null then raise exception 'This person is not available.'; end if;
  if reason is null or reason not in ('spam','harassment','inappropriate','impersonation','other') then
    raise exception 'Choose a reason for your report.';
  end if;
  if char_length(note)>300 or note ~ '[[:cntrl:]]' then raise exception 'Keep details to one line of 300 characters.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(me::text||person_id::text,4));
  if poki_report.poke_id is not null then
    select jsonb_build_array(jsonb_build_object('message',p.message,'sent_at',p.created_at)) into proof
      from poki_private.pokes p where p.id=poki_report.poke_id and p.recipient=me and p.sender=person_id;
    if proof is null then raise exception 'This poke is no longer available.'; end if;
  else
    select coalesce(jsonb_agg(jsonb_build_object('message',x.message,'sent_at',x.created_at) order by x.created_at desc),'[]'::jsonb)
      into proof from (select p.message,p.created_at from poki_private.pokes p
        where p.sender=person_id and p.recipient=me order by p.created_at desc limit 5) x;
  end if;
  if not exists(select 1 from poki_private.reports r where r.reporter=me and r.reported=person_id
      and r.poke_id is not distinct from poki_report.poke_id and r.status='open') then
    insert into poki_private.reports(reporter,reported,reported_username,poke_id,reason,details,evidence)
      values(me,person_id,handle,poki_report.poke_id,poki_report.reason,note,proof);
  end if;
  if also_block then perform public.poki_block(person_id); end if;
end $$;

-- Moderator-only: oldest first, with how many open reports name the same person.
create function public.poki_list_reports(report_status text default 'open', max_rows integer default 50) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'status',r.status,'reason',r.reason,'details',r.details,
    'evidence',r.evidence,'poke_id',r.poke_id,'reporter_id',r.reporter,'created_at',r.created_at,'resolved_at',r.resolved_at,
    'reported',jsonb_build_object('id',r.reported,'username',r.reported_username,
      'open_reports',(select count(*) from poki_private.reports o where o.reported=r.reported and o.status='open')))
    order by r.created_at),'[]'::jsonb)
  from (select * from poki_private.reports where status=report_status
    order by created_at limit least(greatest(coalesce(max_rows,50),1),200)) r
$$;

-- Moderator-only. Removing the account resolves every open report naming that person,
-- then deletes the auth user so their profile, friendships and pokes cascade away.
create function public.poki_resolve_report(report_id uuid, outcome text, remove_account boolean default false) returns void
language plpgsql security definer set search_path = '' as $$
declare target uuid;
begin
  if outcome is null or outcome not in ('dismissed','actioned') or (remove_account and outcome<>'actioned') then
    raise exception 'Invalid report outcome.';
  end if;
  update poki_private.reports set status=outcome,resolved_at=now() where id=report_id and status='open' returning reported into target;
  if not found then raise exception 'This report is not open.'; end if;
  if remove_account and target is not null then
    update poki_private.reports set status='actioned',resolved_at=now() where reported=target and status='open';
    delete from auth.users where id=target;
  end if;
end $$;

-- Resolved reports are kept 90 days for appeals and repeat-abuse checks.
create or replace function poki_private.cleanup() returns void language sql security definer set search_path = '' as $$
  delete from poki_private.pokes where created_at < now()-interval '7 days';
  delete from poki_private.limits where bucket < now()-interval '1 hour';
  delete from poki_private.devices where expires_at < now();
  delete from poki_private.push_outbox where expires_at < now()-interval '1 day';
  delete from poki_private.reports where resolved_at < now()-interval '90 days';
$$;

revoke execute on function public.poki_report(uuid,text,uuid,text,boolean) from public, anon;
grant execute on function public.poki_report(uuid,text,uuid,text,boolean) to authenticated;
revoke execute on function public.poki_list_reports(text,integer), public.poki_resolve_report(uuid,text,boolean) from public, anon, authenticated;
grant execute on function public.poki_list_reports(text,integer), public.poki_resolve_report(uuid,text,boolean) to service_role;
