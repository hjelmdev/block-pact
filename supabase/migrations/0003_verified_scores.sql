-- Block Pact – server-verified highscores.
--
-- Clients no longer write scores. They upload a replay (setup + every tick's
-- inputs) to score_submissions. A verifier (the dedicated Godot server, or
-- the scheduled GitHub workflow) replays it headless with the deterministic
-- simulation and, if it reproduces, stores the score it computed itself.
-- Only the service role can claim/finish submissions and insert scores.

-- Submissions ------------------------------------------------------------------
create table if not exists public.score_submissions (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  mode_id text not null check (char_length(mode_id) between 1 and 48),
  ruleset text not null check (char_length(ruleset) between 1 and 24),
  slot smallint not null check (slot between 0 and 15),
  claimed_score integer not null check (claimed_score >= 0),
  sim_version integer not null,
  replay jsonb not null check (octet_length(replay::text) <= 262144),
  replay_hash text generated always as (md5(replay::text)) stored,
  status text not null default 'pending'
    check (status in ('pending', 'checking', 'verified', 'rejected', 'unsupported')),
  reason text,
  score_id bigint references public.scores (id) on delete set null,
  claimed_at timestamptz,
  checked_at timestamptz,
  created_at timestamptz not null default now()
);

-- The same replay (and seat) can only be submitted once per user.
create unique index if not exists score_submissions_unique_replay
  on public.score_submissions (user_id, replay_hash, slot);
create index if not exists score_submissions_queue_idx
  on public.score_submissions (created_at) where status in ('pending', 'checking');
create index if not exists score_submissions_user_idx
  on public.score_submissions (user_id, created_at desc);

alter table public.score_submissions enable row level security;

create policy "users read their own submissions"
  on public.score_submissions for select using ((select auth.uid()) = user_id);
create policy "users submit their own replays"
  on public.score_submissions for insert with check (
    (select auth.uid()) = user_id
    and status = 'pending' and reason is null and score_id is null
    and claimed_at is null and checked_at is null
  );

-- Simple flood protection: at most 30 open and 120 per hour per user.
create or replace function public.limit_score_submissions()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.score_submissions
      where user_id = new.user_id and status in ('pending', 'checking')) >= 30 then
    raise exception 'too many pending submissions' using errcode = 'P0001';
  end if;
  if (select count(*) from public.score_submissions
      where user_id = new.user_id and created_at > now() - interval '1 hour') >= 120 then
    raise exception 'too many submissions this hour' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke execute on function public.limit_score_submissions() from public, anon, authenticated;

drop trigger if exists score_submissions_limit on public.score_submissions;
create trigger score_submissions_limit
  before insert on public.score_submissions
  for each row execute function public.limit_score_submissions();

-- Scores: verifier only ----------------------------------------------------------
drop policy if exists "users insert their own scores" on public.scores;
revoke insert, update, delete on public.scores from anon, authenticated;

alter table public.scores
  add column if not exists submission_id bigint unique;

-- Verifier API (service role only) -------------------------------------------------

-- Hands out up to p_limit open submissions. Ones claimed but never finished
-- (verifier crashed) are handed out again after p_stale_seconds.
create or replace function public.claim_score_submissions(p_limit integer default 5, p_stale_seconds integer default 300)
returns setof public.score_submissions
language sql set search_path = '' as $$
  update public.score_submissions s
  set status = 'checking', claimed_at = now()
  where s.id in (
    select id from public.score_submissions
    where status = 'pending'
       or (status = 'checking' and claimed_at < now() - make_interval(secs => p_stale_seconds))
    order by created_at
    limit greatest(1, least(p_limit, 50))
    for update skip locked
  )
  returning s.*;
$$;

-- Records the verdict. For 'verified' the score row is written from the
-- values the verifier computed – never from what the client claimed.
create or replace function public.finish_score_submission(
  p_id bigint, p_status text, p_score integer default 0, p_lines integer default 0,
  p_players integer default 1, p_duration_s integer default 0, p_reason text default null)
returns bigint
language plpgsql set search_path = '' as $$
declare
  sub public.score_submissions;
  new_score_id bigint;
begin
  if p_status not in ('verified', 'rejected', 'unsupported') then
    raise exception 'bad status %', p_status;
  end if;
  select * into sub from public.score_submissions where id = p_id and status = 'checking' for update;
  if not found then
    return null;
  end if;
  if p_status = 'verified' then
    insert into public.scores (user_id, mode_id, ruleset, score, lines, players, duration_s, seed, submission_id)
    values (sub.user_id, sub.mode_id, sub.ruleset, p_score, p_lines, p_players, p_duration_s,
            case when (sub.replay #>> '{setup,seed}') ~ '^-?[0-9]{1,18}$'
                 then (sub.replay #>> '{setup,seed}')::bigint end, sub.id)
    returning id into new_score_id;
  end if;
  update public.score_submissions
  set status = p_status, reason = left(p_reason, 200), score_id = new_score_id, checked_at = now()
  where id = p_id;
  return coalesce(new_score_id, 0);
end;
$$;

revoke execute on function public.claim_score_submissions(integer, integer) from public, anon, authenticated;
revoke execute on function public.finish_score_submission(bigint, text, integer, integer, integer, integer, text) from public, anon, authenticated;
grant execute on function public.claim_score_submissions(integer, integer) to service_role;
grant execute on function public.finish_score_submission(bigint, text, integer, integer, integer, integer, text) to service_role;
