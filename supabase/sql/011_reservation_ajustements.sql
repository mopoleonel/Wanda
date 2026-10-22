-- Services ménagers (4/5) : réservation au prix du serveur, refus,
-- ajustements, passages d'abonnement.
--
-- * creer_demande(...) : SEUL moyen de créer une demande ménagère. Le prix
--   est recalculé ici (calculer_prix_demande, 009) : l'app ne peut pas
--   imposer un montant.
-- * Les colonnes de la demande (service, réponses, prix, photos, analyse IA)
--   ne peuvent plus être modifiées par un utilisateur ensuite.
-- * Statuts : seules les transitions prévues sont permises, à la bonne
--   personne (le prestataire accepte, refuse, termine ; le client annule,
--   classe).
-- * Aucun supplément sur place : le prestataire demande un ajustement
--   (demander_ajustement), le client l'accepte ou le refuse
--   (repondre_ajustement). Le prix est mis à jour par le serveur.
-- * Abonnement : chaque passage effectué est pointé par le prestataire
--   (pointer_passage) et visible du client.
-- * Photos : le prestataire lit celles de la demande, le client celles des
--   ajustements.
--
-- Prérequis : 008, 009, 010. À exécuter dans Dashboard Supabase > SQL Editor.
-- Relançable.

-- ---------------------------------------------------------------------------
-- 1. Création d'une demande
-- ---------------------------------------------------------------------------
create or replace function public.creer_demande(
  p_prestataire uuid,
  p_service     text,
  p_formule     text,
  p_frequence   text,
  p_reponses    jsonb,
  p_produits    boolean,
  p_photos      text[],
  p_analyse     uuid,
  p_date        date,
  p_creneau     text
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  v_cit  record;
  v_prix jsonb;
  v_ia   jsonb;
  v_id   uuid;
  v_ph   text;
begin
  if v_uid is null then raise exception 'NON_CONNECTE'; end if;

  select nom, prenom, telephone into v_cit from citoyens where citoyen_id = v_uid;
  if not found then raise exception 'CITOYEN_INCONNU'; end if;
  if coalesce(trim(v_cit.nom), '') = '' or coalesce(trim(v_cit.telephone), '') = '' then
    raise exception 'PROFIL_CITOYEN_INCOMPLET';
  end if;

  if not exists (select 1 from particuliers
                 where id = p_prestataire and is_available
                   and p_service = any(services)) then
    raise exception 'PRESTATAIRE_INDISPONIBLE';
  end if;

  if coalesce(cardinality(p_photos), 0) not between 1 and 3 then
    raise exception 'PHOTOS_REQUISES';
  end if;
  foreach v_ph in array p_photos loop
    if v_ph not like v_uid::text || '/%' then
      raise exception 'PHOTO_INVALIDE';
    end if;
  end loop;

  if p_date is null or p_date < current_date then
    raise exception 'DATE_INVALIDE';
  end if;

  v_prix := calculer_prix_demande(p_service, p_formule, p_frequence,
                                  p_reponses, coalesce(p_produits, false));

  if p_analyse is not null then
    select resultat into v_ia from analyses_ia
     where id = p_analyse and citoyen_id = v_uid;
  end if;

  insert into sollicitations (
    prestataire_id, citoyen_id, nom_citoyen, prenom_citoyen, numero_citoyen,
    date_sollicitation, statut,
    service, formule, frequence, reponses, produits_fournis,
    minutes_estimees, prix_passage, prix_total, prix_detail,
    photos, ia_analyse, date_souhaitee, creneau)
  values (
    p_prestataire, v_uid, v_cit.nom, v_cit.prenom, v_cit.telephone,
    now(), 'en_attente',
    p_service, p_formule,
    case when p_formule = 'abonnement' then p_frequence end,
    coalesce(p_reponses, '{}'),
    coalesce(p_produits, false) or p_service = 'nuisibles',
    (v_prix ->> 'minutes')::int, (v_prix ->> 'prix_passage')::int,
    (v_prix ->> 'prix_total')::int, v_prix,
    p_photos, v_ia, p_date, p_creneau)
  returning id into v_id;

  return v_id;
end $$;

grant execute on function public.creer_demande(uuid, text, text, text, jsonb, boolean, text[], uuid, date, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Protection des demandes et transitions de statut
-- ---------------------------------------------------------------------------
-- Les fonctions « security definer » ci-dessus et ci-dessous s'exécutent
-- avec le rôle propriétaire : current_user n'y vaut pas 'authenticated',
-- ce contrôle ne vise donc que les écritures directes depuis l'app.
create or replace function public.proteger_demande()
returns trigger language plpgsql set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if current_user <> 'authenticated' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.service is not null or new.prix_total is not null
       or new.prix_passage is not null or new.ia_analyse is not null then
      raise exception 'DEMANDE_VIA_SERVEUR';
    end if;
    return new;
  end if;

  if (new.service, new.formule, new.frequence, new.reponses,
      new.produits_fournis, new.minutes_estimees, new.prix_passage,
      new.prix_total, new.prix_detail, new.photos, new.ia_analyse,
      new.prestataire_id, new.citoyen_id)
     is distinct from
     (old.service, old.formule, old.frequence, old.reponses,
      old.produits_fournis, old.minutes_estimees, old.prix_passage,
      old.prix_total, old.prix_detail, old.photos, old.ia_analyse,
      old.prestataire_id, old.citoyen_id) then
    raise exception 'PRIX_PROTEGE';
  end if;

  if new.statut is distinct from old.statut then
    if v_uid = old.prestataire_id and (old.statut, new.statut) in
         (('en_attente', 'accepte'), ('en_attente', 'refuse'),
          ('accepte', 'termine')) then
      null;
    elsif v_uid = old.citoyen_id and (old.statut, new.statut) in
         (('en_attente', 'annule'), ('accepte', 'annule'),
          ('termine', 'archive'), ('annule', 'archive'),
          ('refuse', 'archive')) then
      null;
    else
      raise exception 'TRANSITION_INTERDITE';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_proteger_demande on public.sollicitations;
create trigger trg_proteger_demande
  before insert or update on public.sollicitations
  for each row execute function public.proteger_demande();

-- ---------------------------------------------------------------------------
-- 3. Ajustements (aucun supplément sur place)
-- ---------------------------------------------------------------------------
create table if not exists public.ajustements (
  id               uuid primary key default gen_random_uuid(),
  sollicitation_id uuid not null references public.sollicitations(id) on delete restrict,
  minutes_supp     integer not null default 0 check (minutes_supp between 0 and 600),
  produits_supp    integer not null default 0 check (produits_supp between 0 and 100000),
  motif            text not null check (length(trim(motif)) between 3 and 500),
  photos           text[] not null default '{}',
  prix_supp        integer not null,
  statut           text not null default 'en_attente'
                   check (statut in ('en_attente', 'accepte', 'refuse')),
  created_at       timestamptz not null default now(),
  repondu_at       timestamptz
);

create index if not exists ajustements_sollicitation_idx
  on public.ajustements (sollicitation_id, created_at desc);

-- Un seul ajustement en attente à la fois par demande.
create unique index if not exists ajustements_un_en_attente
  on public.ajustements (sollicitation_id) where statut = 'en_attente';

alter table public.ajustements enable row level security;

drop policy if exists "ajustements_select_parties" on public.ajustements;
create policy "ajustements_select_parties" on public.ajustements
  for select to authenticated
  using (exists (select 1 from public.sollicitations s
                 where s.id = sollicitation_id
                   and auth.uid() in (s.citoyen_id, s.prestataire_id)));
-- Pas d'écriture directe : demander_ajustement / repondre_ajustement.

create or replace function public.demander_ajustement(
  p_sollicitation uuid, p_minutes integer, p_produits integer,
  p_motif text, p_photos text[]
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_s   record;
  v_ph  text;
  v_id  uuid;
  v_prix integer;
begin
  select * into v_s from sollicitations where id = p_sollicitation;
  if not found or v_s.prestataire_id is distinct from v_uid then
    raise exception 'NON_AUTORISE';
  end if;
  if v_s.statut <> 'accepte' then raise exception 'AJUSTEMENT_IMPOSSIBLE'; end if;
  if coalesce(p_minutes, 0) <= 0 and coalesce(p_produits, 0) <= 0 then
    raise exception 'AJUSTEMENT_VIDE';
  end if;
  foreach v_ph in array coalesce(p_photos, '{}') loop
    if v_ph not like v_uid::text || '/%' then raise exception 'PHOTO_INVALIDE'; end if;
  end loop;

  v_prix := _centaine((coalesce(p_minutes, 0)
                       * _tarif(tarifs_json(), 'global', 'tarif_horaire') + 30) / 60
                      + coalesce(p_produits, 0));

  insert into ajustements (sollicitation_id, minutes_supp, produits_supp,
                           motif, photos, prix_supp)
  values (p_sollicitation, coalesce(p_minutes, 0), coalesce(p_produits, 0),
          trim(p_motif), coalesce(p_photos, '{}'), v_prix)
  returning id into v_id;
  return v_id;
exception when unique_violation then
  raise exception 'AJUSTEMENT_DEJA_EN_ATTENTE';
end $$;

create or replace function public.repondre_ajustement(
  p_ajustement uuid, p_accepte boolean
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_a record;
begin
  select a.*, s.citoyen_id into v_a
    from ajustements a join sollicitations s on s.id = a.sollicitation_id
   where a.id = p_ajustement;
  if not found or v_a.citoyen_id is distinct from auth.uid() then
    raise exception 'NON_AUTORISE';
  end if;
  if v_a.statut <> 'en_attente' then raise exception 'DEJA_REPONDU'; end if;

  update ajustements
     set statut = case when p_accepte then 'accepte' else 'refuse' end,
         repondu_at = now()
   where id = p_ajustement;

  if p_accepte then
    update sollicitations
       set prix_total = coalesce(prix_total, 0) + v_a.prix_supp,
           minutes_estimees = coalesce(minutes_estimees, 0) + v_a.minutes_supp
     where id = v_a.sollicitation_id;
  end if;
end $$;

grant execute on function public.demander_ajustement(uuid, integer, integer, text, text[]) to authenticated;
grant execute on function public.repondre_ajustement(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Passages d'un abonnement
-- ---------------------------------------------------------------------------
create table if not exists public.passages (
  id               uuid primary key default gen_random_uuid(),
  sollicitation_id uuid not null references public.sollicitations(id) on delete restrict,
  effectue_le      timestamptz not null default now()
);

create index if not exists passages_sollicitation_idx
  on public.passages (sollicitation_id, effectue_le desc);

alter table public.passages enable row level security;

drop policy if exists "passages_select_parties" on public.passages;
create policy "passages_select_parties" on public.passages
  for select to authenticated
  using (exists (select 1 from public.sollicitations s
                 where s.id = sollicitation_id
                   and auth.uid() in (s.citoyen_id, s.prestataire_id)));

create or replace function public.pointer_passage(p_sollicitation uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_s  record;
  v_id uuid;
begin
  select * into v_s from sollicitations where id = p_sollicitation;
  if not found or v_s.prestataire_id is distinct from auth.uid() then
    raise exception 'NON_AUTORISE';
  end if;
  if v_s.formule <> 'abonnement' or v_s.statut <> 'accepte' then
    raise exception 'PASSAGE_IMPOSSIBLE';
  end if;
  -- Un passage au plus par jour (évite les doubles appuis).
  if exists (select 1 from passages where sollicitation_id = p_sollicitation
             and effectue_le::date = current_date) then
    raise exception 'PASSAGE_DEJA_POINTE';
  end if;
  insert into passages (sollicitation_id) values (p_sollicitation)
  returning id into v_id;
  return v_id;
end $$;

grant execute on function public.pointer_passage(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Photos : chaque partie voit celles de l'autre, une fois la demande créée
-- ---------------------------------------------------------------------------
drop policy if exists "demandes_select_prestataire" on storage.objects;
create policy "demandes_select_prestataire" on storage.objects
  for select to authenticated
  using (bucket_id = 'demandes'
         and exists (select 1 from public.sollicitations s
                     where s.prestataire_id = auth.uid()
                       and name = any(s.photos)));

drop policy if exists "demandes_select_client_ajustement" on storage.objects;
create policy "demandes_select_client_ajustement" on storage.objects
  for select to authenticated
  using (bucket_id = 'demandes'
         and exists (select 1 from public.ajustements a
                     join public.sollicitations s on s.id = a.sollicitation_id
                     where s.citoyen_id = auth.uid()
                       and name = any(a.photos)));
