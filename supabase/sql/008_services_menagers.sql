-- Services ménagers à domicile (1/5) : catégories, prestataires
-- multi-services, sollicitation enrichie.
--
-- * Les 4 anciens métiers (Plombier, Électricien, Maçon, Froid & Clim) sont
--   RETIRÉS : la colonne particuliers.service_propose est supprimée.
-- * Un prestataire propose une ou plusieurs catégories :
--   menage | linge | dechets | nuisibles  (colonne particuliers.services).
--   Les prestataires existants repartent sans service : ils ne sont plus
--   visibles (profil incomplet) tant qu'ils n'ont pas choisi leurs services
--   dans l'app.
-- * Certification (005/006) : nom, prénom et téléphone restent figés ; les
--   services peuvent être complétés mais plus retirés.
-- * La sollicitation reçoit les champs d'une demande ménagère (service,
--   formule, réponses, prix calculé par le serveur, photos, analyse IA) et
--   le statut « refuse ». Les colonnes de prix sont protégées en 009.
--
-- Prérequis : 005, 006. À exécuter dans Dashboard Supabase > SQL Editor.
-- Relançable sans risque.

-- ---------------------------------------------------------------------------
-- 1. Prestataires : services multiples
-- ---------------------------------------------------------------------------
alter table public.particuliers
  add column if not exists services text[] not null default '{}';

alter table public.particuliers
  drop constraint if exists particuliers_services_valides;
alter table public.particuliers
  add constraint particuliers_services_valides
  check (services <@ array['menage', 'linge', 'dechets', 'nuisibles']::text[]);

create index if not exists particuliers_services_idx
  on public.particuliers using gin (services);

-- La vue d'administration et les triggers 005/006 lisent l'ancienne
-- colonne : on les remplace avant de la supprimer.
drop view if exists public.verifications_a_traiter;
drop trigger if exists trg_figer_identite_certifiee on public.particuliers;

alter table public.particuliers drop column if exists service_propose;

-- ---------------------------------------------------------------------------
-- 2. Certification : profil complet = photo, nom, prénom, au moins un service
-- ---------------------------------------------------------------------------
create or replace function public.exiger_profil_complet()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from particuliers p
    where p.id = new.prestataire_id
      and coalesce(trim(p.photo_pro_url), '') <> ''
      and coalesce(trim(p.nom), '') <> ''
      and coalesce(trim(p.prenom), '') <> ''
      and cardinality(p.services) > 0
  ) then
    raise exception 'PROFIL_INCOMPLET';
  end if;
  return new;
end $$;

-- Compte certifié (ou certification en cours) : nom, prénom et téléphone
-- figés ; un service déjà proposé ne peut plus être retiré (ajout permis).
-- Pas de « security definer » : current_user reste celui de la requête.
create or replace function public.figer_identite_certifiee()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user <> 'authenticated' then
    return new;
  end if;

  if (new.nom is distinct from old.nom
      or new.prenom is distinct from old.prenom
      or new.telephone is distinct from old.telephone
      or not (old.services <@ new.services))
     and (old.identite_verifiee
          or exists (select 1 from prestataire_verifications v
                     where v.prestataire_id = old.id
                       and v.statut = 'en_attente')) then
    raise exception 'IDENTITE_FIGEE';
  end if;
  return new;
end $$;

create trigger trg_figer_identite_certifiee
  before update of nom, prenom, services, telephone
  on public.particuliers
  for each row execute function public.figer_identite_certifiee();

create or replace view public.verifications_a_traiter
with (security_invoker = true) as
select v.id, v.created_at, v.prestataire_id,
       v.nom, v.prenoms, v.date_naissance, v.numero_document,
       v.date_expiration, v.mrz_valide, v.saisie_corrigee,
       v.recto_path, v.verso_path, v.selfie_path,
       p.services, p.telephone
from public.prestataire_verifications v
left join public.particuliers p on p.id = v.prestataire_id
where v.statut = 'en_attente'
order by v.created_at;

-- ---------------------------------------------------------------------------
-- 3. Sollicitation enrichie (demande de service ménager)
-- ---------------------------------------------------------------------------
alter table public.sollicitations
  add column if not exists service          text,
  add column if not exists formule          text,
  add column if not exists frequence        text,
  add column if not exists reponses         jsonb,
  add column if not exists produits_fournis boolean not null default false,
  add column if not exists minutes_estimees integer,
  add column if not exists prix_passage     integer,
  add column if not exists prix_total       integer,
  add column if not exists prix_detail      jsonb,
  add column if not exists photos           text[] not null default '{}',
  add column if not exists ia_analyse       jsonb,
  add column if not exists date_souhaitee   date,
  add column if not exists creneau          text,
  add column if not exists motif_refus      text;

alter table public.sollicitations
  drop constraint if exists sollicitations_demande_valide;
alter table public.sollicitations
  add constraint sollicitations_demande_valide check (
    (service is null or service in ('menage', 'linge', 'dechets', 'nuisibles'))
    and (formule is null or formule in ('ponctuelle', 'abonnement'))
    and (frequence is null or frequence in ('hebdomadaire', 'mensuel'))
    and (formule is distinct from 'abonnement' or frequence is not null)
    and (creneau is null or creneau in ('matin', 'apres_midi'))
  );

-- Statuts : on remplace toute contrainte existante sur « statut » par la
-- liste complète, qui ajoute « refuse ».
do $$
declare c record;
begin
  for c in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    where rel.relname = 'sollicitations' and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%statut%'
  loop
    execute format('alter table public.sollicitations drop constraint %I',
                   c.conname);
  end loop;
end $$;

alter table public.sollicitations
  add constraint sollicitations_statut_valide check (
    statut in ('en_attente', 'accepte', 'refuse', 'termine', 'annule', 'archive')
  );

create index if not exists sollicitations_service_idx
  on public.sollicitations (service);

-- Contrôle : prestataires et leurs services.
--   select id, nom, prenom, services from particuliers order by nom;
