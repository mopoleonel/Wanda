-- Mini-Supabase pour tester les migrations WANDA hors production (schéma
-- fidèle : citoyens.citoyen_id, particuliers.id, auth.users, storage).
create extension if not exists pgcrypto;
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;

create schema auth;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text, phone text unique, updated_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create function auth.role() returns text language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), current_user::text) $$;

create schema storage;
create table storage.buckets (id text primary key, name text, public boolean);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text, name text, owner uuid default auth.uid(),
  created_at timestamptz default now());
alter table storage.objects enable row level security;
-- Comme en production (constat du 23/10/2026) : une ancienne politique
-- large, sans condition sur le bucket. 014 doit en exclure les dossiers privés.
create policy acces_large_ecriture on storage.objects for insert
  to authenticated with check (true);
create policy acces_large_lecture on storage.objects for select
  to authenticated using (true);
create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1] $$;

-- Tables existantes (colonnes utilisées par l'app).
create table public.citoyens (
  citoyen_id uuid primary key references auth.users(id), nom text, prenom text,
  email text, telephone text, photo_url text);
create table public.particuliers (
  id uuid primary key references auth.users(id), nom text, prenom text,
  telephone text, service_propose text, photo_pro_url text,
  is_available boolean default false, latitude double precision,
  longitude double precision, abonnement_expire_at timestamptz,
  type_abonnement text, essai_utilise boolean default false);
create table public.entreprises (
  id uuid primary key references auth.users(id), nom_entreprise text,
  secteur_activite text, telephone text, logo_url text);
create table public.sollicitations (
  id uuid primary key default gen_random_uuid(),
  prestataire_id uuid references public.particuliers(id),
  citoyen_id uuid references auth.users(id),
  nom_citoyen text, prenom_citoyen text, numero_citoyen text,
  date_sollicitation timestamptz default now(), date_fin timestamptz,
  statut text not null default 'en_attente'
    check (statut in ('en_attente', 'accepte', 'termine', 'annule', 'archive')));
alter table public.sollicitations enable row level security;
create policy sol_select on public.sollicitations for select to authenticated
  using (citoyen_id = auth.uid() or prestataire_id = auth.uid());
create policy sol_update on public.sollicitations for update to authenticated
  using (citoyen_id = auth.uid() or prestataire_id = auth.uid());
create policy sol_insert on public.sollicitations for insert to authenticated
  with check (citoyen_id = auth.uid());
create table public.avis_prestataires (
  id uuid primary key default gen_random_uuid(), sollicitation_id uuid,
  prestataire_id uuid, citoyen_id uuid, note int, commentaire text,
  created_at timestamptz default now());
create function public.notify_push(uuid, text, text) returns void
  language sql as $$ select $$;

grant usage on schema public, auth, storage to anon, authenticated, service_role;
grant all on all tables in schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
grant all on storage.objects, storage.buckets to authenticated, service_role;
grant select on auth.users to authenticated;
