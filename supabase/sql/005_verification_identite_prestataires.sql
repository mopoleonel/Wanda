-- Vérification d'identité des artisans (CNI camerounaise + selfie).
--
-- Objectif : pouvoir retrouver qui est réellement un prestataire en cas de
-- litige, en ne conservant que l'essentiel (principe de minimisation) :
--   * l'identité lue sur la CNI (nom, prénoms, date de naissance, numéro,
--     date d'expiration) ;
--   * les photos recto / verso de la CNI et un selfie, dans un espace de
--     stockage PRIVÉ (jamais d'URL publique) ;
--   * la preuve du consentement (date, version et texte exact accepté) ;
--   * un journal horodaté de chaque étape (création, validation, rejet).
--
-- La certification est FACULTATIVE : elle se fait depuis le profil de
-- l'artisan et lui donne le badge « Identité vérifiée » visible des
-- citoyens (colonne particuliers.identite_verifiee). La comparaison
-- selfie ↔ photo de la carte est faite par un administrateur WANDA.
--
-- À exécuter une fois dans Dashboard Supabase > SQL Editor.

-- ---------------------------------------------------------------------------
-- 1. Table des vérifications
-- ---------------------------------------------------------------------------
create table if not exists public.prestataire_verifications (
  id                    uuid primary key default gen_random_uuid(),
  -- « restrict » : une vérification ne disparaît pas avec le compte, elle
  -- reste disponible pour un litige pendant la durée de conservation.
  prestataire_id        uuid not null references auth.users(id) on delete restrict,
  type_document         text not null default 'CNI_CM',

  -- Identité lue sur la carte
  numero_document       text,
  nom                   text not null,
  prenoms               text not null,
  date_naissance        date,
  lieu_naissance        text,
  sexe                  text check (sexe in ('M', 'F')),
  date_expiration       date,

  -- Qualité de la lecture
  mrz_presente          boolean not null default false,
  mrz_valide            boolean not null default false,
  saisie_corrigee       boolean not null default false, -- nom retouché à la main

  -- Pièces (chemins dans le bucket privé « identites », pas des URL)
  recto_path            text not null,
  verso_path            text not null,
  selfie_path           text not null,

  -- Preuve du consentement
  consentement_at       timestamptz not null,
  consentement_version  text not null,
  consentement_texte    text not null,

  -- Revue par un administrateur
  statut                text not null default 'en_attente'
                        check (statut in ('en_attente', 'valide', 'rejete')),
  motif_rejet           text,
  verifie_par           uuid references auth.users(id),
  verifie_at            timestamptz,

  created_at            timestamptz not null default now()
);

create index if not exists prestataire_verifications_prestataire_idx
  on public.prestataire_verifications (prestataire_id, created_at desc);

-- Une même CNI ne peut servir qu'à un seul compte actif (anti-fraude).
create unique index if not exists prestataire_verifications_numero_unique
  on public.prestataire_verifications (numero_document)
  where numero_document is not null and statut <> 'rejete';

alter table public.prestataire_verifications enable row level security;

-- L'artisan peut déposer SA vérification (toujours « en attente »)...
drop policy if exists "verif_insert_soi" on public.prestataire_verifications;
create policy "verif_insert_soi" on public.prestataire_verifications
  for insert to authenticated
  with check (prestataire_id = auth.uid() and statut = 'en_attente'
              and verifie_par is null and verifie_at is null);

-- ... et consulter les siennes (pour connaître son statut).
drop policy if exists "verif_select_soi" on public.prestataire_verifications;
create policy "verif_select_soi" on public.prestataire_verifications
  for select to authenticated
  using (prestataire_id = auth.uid());

-- Aucune politique update / delete : seuls les administrateurs (rôle
-- service_role, tableau de bord Supabase) valident, rejettent ou suppriment.

-- ---------------------------------------------------------------------------
-- 2. Journal d'audit (traçabilité en cas de litige)
-- ---------------------------------------------------------------------------
create table if not exists public.prestataire_verifications_journal (
  id               bigint generated always as identity primary key,
  verification_id  uuid not null references public.prestataire_verifications(id),
  action           text not null,          -- creation | valide | rejete | ...
  ancien_statut    text,
  nouveau_statut   text,
  acteur           uuid,                   -- auth.uid() au moment de l'action
  details          text,
  at               timestamptz not null default now()
);

alter table public.prestataire_verifications_journal enable row level security;
-- Pas de politique : invisible et non modifiable depuis l'app.

create or replace function public.journaliser_verification()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into prestataire_verifications_journal
      (verification_id, action, nouveau_statut, acteur, details)
    values (new.id, 'creation', new.statut, auth.uid(),
            'consentement ' || new.consentement_version);
  elsif new.statut is distinct from old.statut then
    insert into prestataire_verifications_journal
      (verification_id, action, ancien_statut, nouveau_statut, acteur, details)
    values (new.id, new.statut, old.statut, new.statut,
            coalesce(new.verifie_par, auth.uid()), new.motif_rejet);
  end if;
  return new;
end $$;

drop trigger if exists trg_journal_verification on public.prestataire_verifications;
create trigger trg_journal_verification
  after insert or update on public.prestataire_verifications
  for each row execute function public.journaliser_verification();

-- La demande de certification n'est acceptée que si le profil de l'artisan
-- est complet (photo, nom, prénom, métier) : même règle que dans l'app.
create or replace function public.exiger_profil_complet()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from particuliers p
    where p.id = new.prestataire_id
      and coalesce(trim(p.photo_pro_url), '') <> ''
      and coalesce(trim(p.nom), '') <> ''
      and coalesce(trim(p.prenom), '') <> ''
      and coalesce(trim(p.service_propose), '') <> ''
  ) then
    raise exception 'PROFIL_INCOMPLET';
  end if;
  return new;
end $$;

drop trigger if exists trg_exiger_profil_complet on public.prestataire_verifications;
create trigger trg_exiger_profil_complet
  before insert on public.prestataire_verifications
  for each row execute function public.exiger_profil_complet();

-- ---------------------------------------------------------------------------
-- 3. Badge « Identité vérifiée » (visible des citoyens)
-- ---------------------------------------------------------------------------
-- Une version antérieure de ce script bloquait le passage « en ligne » sans
-- identité validée : la certification est désormais facultative.
drop trigger if exists trg_exiger_identite on public.particuliers;
drop function if exists public.exiger_identite_validee();

alter table public.particuliers
  add column if not exists identite_verifiee boolean not null default false;

-- Le badge suit le statut de la dernière décision d'un administrateur.
create or replace function public.maj_badge_identite()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.statut is distinct from old.statut
     and new.statut in ('valide', 'rejete') then
    perform set_config('wanda.maj_badge', 'on', true);
    update particuliers
       set identite_verifiee = (new.statut = 'valide')
     where id = new.prestataire_id;
    perform set_config('wanda.maj_badge', 'off', true);
  end if;
  return new;
end $$;

drop trigger if exists trg_maj_badge_identite on public.prestataire_verifications;
create trigger trg_maj_badge_identite
  after update of statut on public.prestataire_verifications
  for each row execute function public.maj_badge_identite();

-- Un artisan ne peut pas s'attribuer le badge lui-même : seule la fonction
-- ci-dessus (validation par un administrateur) peut changer la colonne.
create or replace function public.proteger_badge_identite()
returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('wanda.maj_badge', true), 'off') <> 'on' then
    if tg_op = 'INSERT' then
      new.identite_verifiee := false;
    else
      new.identite_verifiee := old.identite_verifiee;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_proteger_badge_identite on public.particuliers;
create trigger trg_proteger_badge_identite
  before insert or update on public.particuliers
  for each row execute function public.proteger_badge_identite();

-- ---------------------------------------------------------------------------
-- 4. Stockage privé des pièces : bucket « identites »
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('identites', 'identites', false)
on conflict (id) do update set public = false;

-- Chaque artisan dépose dans son propre dossier « <uid>/... ».
drop policy if exists "identites_insert_soi" on storage.objects;
create policy "identites_insert_soi" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'identites'
              and (storage.foldername(name))[1] = auth.uid()::text);

-- Il peut relire ses propres pièces (aperçu), jamais celles des autres.
drop policy if exists "identites_select_soi" on storage.objects;
create policy "identites_select_soi" on storage.objects
  for select to authenticated
  using (bucket_id = 'identites'
         and (storage.foldername(name))[1] = auth.uid()::text);

-- Pas d'update / delete : une pièce déposée ne peut pas être remplacée en
-- silence (nouvelle vérification = nouveaux fichiers horodatés).

-- ---------------------------------------------------------------------------
-- 5. Vue de travail pour les administrateurs
-- ---------------------------------------------------------------------------
create or replace view public.verifications_a_traiter
with (security_invoker = true) as
select v.id, v.created_at, v.prestataire_id,
       v.nom, v.prenoms, v.date_naissance, v.numero_document,
       v.date_expiration, v.mrz_valide, v.saisie_corrigee,
       v.recto_path, v.verso_path, v.selfie_path,
       p.service_propose, p.telephone
from public.prestataire_verifications v
left join public.particuliers p on p.id = v.prestataire_id
where v.statut = 'en_attente'
order by v.created_at;

-- Valider une vérification (à lancer par un administrateur) :
--   update prestataire_verifications
--      set statut = 'valide', verifie_par = '<uuid admin>', verifie_at = now()
--    where id = '<id>';
-- Rejeter :
--   update prestataire_verifications
--      set statut = 'rejete', motif_rejet = 'Selfie ne correspond pas',
--          verifie_par = '<uuid admin>', verifie_at = now()
--    where id = '<id>';
