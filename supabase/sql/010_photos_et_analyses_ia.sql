-- Services ménagers (3/5) : photos des demandes (privées) et analyses IA.
--
-- * Bucket PRIVÉ « demandes » : photos jointes à une demande (état du
--   logement, volume de linge, de poubelles, nuisibles) et aux demandes
--   d'ajustement. Chemin : <auteur_id>/<dossier>/<fichier>.jpg. Jamais d'URL
--   publique : l'app affiche des URL signées de courte durée. Pas de
--   suppression ni de remplacement : ce sont des preuves en cas de litige.
--   La lecture par l'autre partie (prestataire / client) est ouverte en 011,
--   une fois la demande créée.
-- * Table « analyses_ia » : chaque analyse de l'Edge Function
--   analyze-demande-menage est enregistrée par le serveur (clé service_role)
--   et reliée à la demande à sa création. L'app ne peut ni l'écrire ni la
--   modifier : le résultat conservé est bien celui de l'IA.
-- * Les pièces d'identité (bucket « identites ») ne sont jamais lues par
--   cette fonction.
--
-- Prérequis : 008. À exécuter dans Dashboard Supabase > SQL Editor.
-- Relançable.

insert into storage.buckets (id, name, public)
values ('demandes', 'demandes', false)
on conflict (id) do update set public = false;

drop policy if exists "demandes_insert_soi" on storage.objects;
create policy "demandes_insert_soi" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'demandes'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "demandes_select_soi" on storage.objects;
create policy "demandes_select_soi" on storage.objects
  for select to authenticated
  using (bucket_id = 'demandes'
         and (storage.foldername(name))[1] = auth.uid()::text);

create table if not exists public.analyses_ia (
  id          uuid primary key default gen_random_uuid(),
  citoyen_id  uuid not null references auth.users(id),
  service     text not null,
  reponses    jsonb not null default '{}',
  photos      text[] not null default '{}',
  resultat    jsonb,           -- réponse JSON de l'IA (null si échec)
  erreur      text,            -- cause de l'échec (réseau, quota…)
  modele      text,
  created_at  timestamptz not null default now()
);

create index if not exists analyses_ia_citoyen_idx
  on public.analyses_ia (citoyen_id, created_at desc);

alter table public.analyses_ia enable row level security;

drop policy if exists "analyses_select_soi" on public.analyses_ia;
create policy "analyses_select_soi" on public.analyses_ia
  for select to authenticated
  using (citoyen_id = auth.uid());
-- Pas de politique insert / update / delete : seule l'Edge Function
-- (service_role) écrit.
