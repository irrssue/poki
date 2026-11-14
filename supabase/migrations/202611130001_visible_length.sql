-- Count poke messages in visible characters (approximate grapheme clusters)
-- instead of code points, so "👨‍👩‍👧‍👦" or "👍🏽" costs one of the 30 characters.
-- PostgreSQL has no grapheme segmentation, so this mirrors MessageValidator.visibleLength
-- in iOS exactly: pair regional indicators into flags, drop combining marks,
-- variation selectors, skin-tone modifiers and tag characters, then fold every
-- zero-width-joiner sequence into its first member. contracts/message-length.json
-- holds the fixtures both sides are tested against. A code-point cap keeps
-- payloads bounded now that one visible character can be several code points.
create function poki_private.visible_length(value text) returns integer
language sql immutable strict set search_path = '' as $$
  select pg_catalog.char_length(
    pg_catalog.regexp_replace(
      pg_catalog.regexp_replace(
        pg_catalog.regexp_replace(value, '[\U0001F1E6-\U0001F1FF]{2}', 'R', 'g'),
        '[̀-ͯ᪰-᫿᷀-᷿⃐-⃿︀-️︠-︯\U0001F3FB-\U0001F3FF\U000E0020-\U000E007F\U000E0100-\U000E01EF]',
        '', 'g'),
      '‍.?', '', 'g'))
$$;
revoke execute on function poki_private.visible_length(text) from public, anon, authenticated;

alter table poki_private.pokes drop constraint pokes_message_check;
alter table poki_private.pokes add constraint pokes_message_check check (
  poki_private.visible_length(message) between 1 and 30
  and char_length(message) <= 256 and message !~ '[[:cntrl:]]');

create or replace function public.poki_send(recipient_id uuid, message text, poke_id uuid) returns void language plpgsql security definer set search_path = '' as $$
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
  if char_length(btrim(message))=0 or char_length(message)>256 or poki_private.visible_length(message) not between 1 and 30
    or message ~ '[[:cntrl:]]' then raise exception 'Invalid poke message.'; end if;
  if exists(select 1 from poki_private.pokes where sender=me and created_at>now()-interval '3 seconds') then raise exception 'Wait a moment before your next poke.'; end if;
  perform poki_private.throttle('poke',20);
  insert into poki_private.pokes(id,sender,recipient,message) values(poke_id,me,recipient_id,message);
end $$;
