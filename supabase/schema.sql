create table if not exists public.token_racing_users (
  id uuid primary key,
  handle text not null unique,
  invite_code text not null unique,
  avatar_data_url text,
  created_at timestamptz not null default now()
);

create table if not exists public.token_racing_friend_requests (
  id uuid primary key,
  from_user_id uuid not null references public.token_racing_users(id) on delete cascade,
  to_user_id uuid not null references public.token_racing_users(id) on delete cascade,
  status text not null check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  check (from_user_id <> to_user_id)
);

create unique index if not exists token_racing_friend_requests_pair_idx
on public.token_racing_friend_requests (
  least(from_user_id, to_user_id),
  greatest(from_user_id, to_user_id)
);

create table if not exists public.token_racing_usage (
  user_id uuid not null references public.token_racing_users(id) on delete cascade,
  timeframe text not null,
  app text not null,
  period_start timestamptz not null,
  tokens integer not null default 0 check (tokens >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, timeframe, app)
);

alter table public.token_racing_users enable row level security;
alter table public.token_racing_friend_requests enable row level security;
alter table public.token_racing_usage enable row level security;

-- Token Racing's Vercel API uses the service-role key server-side. Do not expose
-- the service-role key in the macOS app or website JavaScript.
