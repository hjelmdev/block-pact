-- Block Pact – initial schema for accounts, highscores and achievements.
-- Apply in the Supabase SQL editor (or `supabase db push`).
-- Guests never touch these tables; only authenticated users write.

-- Profiles ------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  nickname text check (char_length(nickname) between 1 and 16),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles are readable by everyone"
  on public.profiles for select using (true);
create policy "users insert their own profile"
  on public.profiles for insert with check ((select auth.uid()) = id);
create policy "users update their own profile"
  on public.profiles for update using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

-- Create a profile automatically on sign-up (nickname from the OAuth name).
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, nickname)
  values (
    new.id,
    left(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', 'Player'), 16)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Scores --------------------------------------------------------------------
create table if not exists public.scores (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  mode_id text not null,
  score integer not null check (score >= 0),
  lines integer not null default 0,
  players smallint not null default 1,
  duration_s integer not null default 0,
  seed bigint,
  created_at timestamptz not null default now()
);

create index if not exists scores_mode_score_idx on public.scores (mode_id, score desc);
create index if not exists scores_user_idx on public.scores (user_id);

alter table public.scores enable row level security;

create policy "scores are readable by everyone"
  on public.scores for select using (true);
create policy "users insert their own scores"
  on public.scores for insert with check ((select auth.uid()) = user_id);

-- Best score per user and mode, with nickname (what the game reads).
create or replace view public.leaderboard
with (security_invoker = true) as
select distinct on (s.mode_id, s.user_id)
  s.mode_id,
  s.user_id,
  coalesce(p.nickname, 'Player') as nickname,
  s.score,
  s.lines,
  s.created_at
from public.scores s
left join public.profiles p on p.id = s.user_id
order by s.mode_id, s.user_id, s.score desc;

-- Achievements ----------------------------------------------------------------
create table if not exists public.player_achievements (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  achievement_id text not null,
  unlocked_at timestamptz not null default now(),
  primary key (user_id, achievement_id)
);

alter table public.player_achievements enable row level security;

create policy "users read their own achievements"
  on public.player_achievements for select using ((select auth.uid()) = user_id);
create policy "users unlock their own achievements"
  on public.player_achievements for insert with check ((select auth.uid()) = user_id);

-- NOTE: scores are submitted by the client, so they can be faked. Because the
-- simulation is deterministic, a later step can store the input log + seed
-- and verify scores server-side (Edge Function running the headless sim).
