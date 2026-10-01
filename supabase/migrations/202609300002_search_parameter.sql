create or replace function public.poki_search(username text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid := poki_private.actor(); result jsonb;
begin
  perform poki_private.throttle('search',30);
  select jsonb_build_object('person',jsonb_build_object('id',p.id,'username',p.username,'name',p.name),
    'relationship',case when c.status='accepted' then 'accepted' when c.status='pending' and c.sender=me then 'outgoing'
      when c.status='pending' then 'incoming' else 'none' end)
  into result from poki_private.profiles p left join poki_private.connections c
    on least(c.sender,c.recipient)=least(me,p.id) and greatest(c.sender,c.recipient)=greatest(me,p.id)
  where p.username=lower(trim(leading '@' from btrim(poki_search.username))) and p.id<>me;
  return result;
end $$;

