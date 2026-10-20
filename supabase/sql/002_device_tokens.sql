-- Notifications push (FCM) : stocke les tokens d'appareil par utilisateur.
-- Un utilisateur peut avoir plusieurs tokens (plusieurs appareils installés).
--
-- À exécuter une fois dans l'éditeur SQL de ton projet Supabase.

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  fcm_token text not null unique,
  platform text not null default 'android',
  created_at timestamptz not null default now()
);

create index if not exists device_tokens_user_id_idx
  on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

-- Chaque utilisateur ne gère que ses propres tokens.
create policy "device_tokens_select_own"
  on public.device_tokens for select
  using (auth.uid() = user_id);

create policy "device_tokens_insert_own"
  on public.device_tokens for insert
  with check (auth.uid() = user_id);

create policy "device_tokens_delete_own"
  on public.device_tokens for delete
  using (auth.uid() = user_id);
