-- Block Pact – leaderboards per ruleset (classic vs party with special blocks
-- and powerups) and a chosen avatar per profile.

alter table public.scores
  add column if not exists ruleset text not null default 'classic'
  check (char_length(ruleset) between 1 and 24);

create index if not exists scores_mode_ruleset_score_idx
  on public.scores (mode_id, ruleset, score desc);

alter table public.profiles
  add column if not exists avatar text
  check (avatar is null or char_length(avatar) <= 32);

-- New columns must be appended at the end of an existing view.
create or replace view public.leaderboard
with (security_invoker = true) as
select distinct on (s.mode_id, s.ruleset, s.user_id)
  s.mode_id,
  s.user_id,
  coalesce(p.nickname, 'Player') as nickname,
  s.score,
  s.lines,
  s.created_at,
  s.ruleset,
  p.avatar
from public.scores s
left join public.profiles p on p.id = s.user_id
order by s.mode_id, s.ruleset, s.user_id, s.score desc;
