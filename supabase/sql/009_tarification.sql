-- Services ménagers (2/5) : tarification fixée par WANDA.
--
-- Prix = temps estimé × tarif horaire + déplacement + produits.
-- Tous les paramètres sont dans la table `tarifs`, lisible par les
-- utilisateurs connectés (estimation en direct dans l'app) et modifiable
-- UNIQUEMENT par un administrateur (aucune politique d'écriture : SQL Editor
-- ou clé service_role).
--
-- `calculer_prix(...)` est le calcul de référence. L'app en a une copie
-- exacte en Dart (lib/data/pricing/tarification.dart) pour l'affichage en
-- direct ; le prix ENREGISTRÉ est toujours celui du serveur (voir 011).
-- Le bloc de contrôle en fin de script vérifie 8 cas partagés avec les tests
-- Dart (test/data/pricing/tarification_test.dart) : la migration échoue si
-- le calcul SQL diverge.
--
-- Prérequis : 008. À exécuter dans Dashboard Supabase > SQL Editor.
-- Relançable : les valeurs déjà modifiées par un administrateur sont
-- conservées.

-- ---------------------------------------------------------------------------
-- 1. Table des paramètres
-- ---------------------------------------------------------------------------
create table if not exists public.tarifs (
  service     text not null,     -- global | menage | linge | dechets | nuisibles
  cle         text not null,
  valeur      numeric not null check (valeur >= 0),
  unite       text not null check (unite in ('min', 'fcfa', 'pourcent', 'nombre')),
  libelle     text not null,
  modifie_le  timestamptz not null default now(),
  primary key (service, cle)
);

alter table public.tarifs enable row level security;

drop policy if exists "tarifs_lecture" on public.tarifs;
create policy "tarifs_lecture" on public.tarifs
  for select to authenticated using (true);
-- Pas de politique insert / update / delete : administrateurs seulement.

create or replace function public.tarifs_horodater()
returns trigger language plpgsql as $$
begin
  new.modifie_le := now();
  return new;
end $$;

drop trigger if exists trg_tarifs_horodater on public.tarifs;
create trigger trg_tarifs_horodater
  before update on public.tarifs
  for each row execute function public.tarifs_horodater();

-- Valeurs de départ (identiques à `Tarifs.depart` côté Dart). Celles du
-- cahier des charges : tarif horaire, déplacement, ménage (pièces, options,
-- état). Les autres sont des PROPOSITIONS à ajuster.
insert into public.tarifs (service, cle, valeur, unite, libelle) values
  ('global', 'tarif_horaire',      1200, 'fcfa',     'Tarif horaire du prestataire'),
  ('global', 'deplacement',        1000, 'fcfa',     'Frais de déplacement par passage'),
  ('global', 'remise_abonnement',     0, 'pourcent', 'Remise sur les formules abonnement'),
  ('global', 'seuil_ecart_ia',       50, 'pourcent', 'Écart IA / déclaration au-delà duquel on propose une correction'),
  ('menage', 'chambre',              30, 'min',      'Temps par chambre'),
  ('menage', 'salon',                40, 'min',      'Temps par salon'),
  ('menage', 'cuisine',              45, 'min',      'Temps par cuisine'),
  ('menage', 'douche_wc',            30, 'min',      'Temps par douche / WC'),
  ('menage', 'canape',               40, 'min',      'Nettoyage d''un canapé (proposé)'),
  ('menage', 'tapis',                25, 'min',      'Nettoyage d''un tapis (proposé)'),
  ('menage', 'vitres',               30, 'min',      'Option vitres'),
  ('menage', 'frigo',                20, 'min',      'Option intérieur du frigo'),
  ('menage', 'four',                 20, 'min',      'Option intérieur du four'),
  ('menage', 'etat_sale',            25, 'pourcent', 'Majoration du temps : logement sale'),
  ('menage', 'etat_tres_sale',       50, 'pourcent', 'Majoration du temps : logement très sale'),
  ('menage', 'produits',           1500, 'fcfa',     'Produits apportés par le prestataire (proposé)'),
  ('linge', 'panier',                40, 'min',      'Lavage, étendage et pliage d''un panier (proposé)'),
  ('linge', 'draps_delicats',        15, 'min',      'Draps ou vêtements délicats, par panier (proposé)'),
  ('linge', 'piece_repassage',        4, 'min',      'Repassage, par pièce (proposé)'),
  ('linge', 'produits',             500, 'fcfa',     'Lessive apportée, par panier (proposé)'),
  ('dechets', 'sac',                  5, 'min',      'Temps par sac (proposé)'),
  ('dechets', 'etage',                2, 'min',      'Temps par étage à descendre (proposé)'),
  ('dechets', 'distance_10m',         1, 'min',      'Temps par tranche de 10 m jusqu''au bac (proposé)'),
  ('dechets', 'minimum',             15, 'min',      'Durée minimale facturée par passage (proposé)'),
  ('nuisibles', 'piece',             20, 'min',      'Temps de traitement par pièce (proposé)'),
  ('nuisibles', 'produit_cafards',  1500, 'fcfa',    'Produit anti-cafards, par pièce (proposé)'),
  ('nuisibles', 'produit_moustiques', 1000, 'fcfa',  'Produit anti-moustiques, par pièce (proposé)'),
  ('nuisibles', 'produit_punaises', 3000, 'fcfa',    'Produit anti-punaises de lit, par pièce (proposé)'),
  ('nuisibles', 'produit_rongeurs', 2500, 'fcfa',    'Dératisation, par pièce (proposé)'),
  ('nuisibles', 'produit_fourmis',  1000, 'fcfa',    'Produit anti-fourmis, par pièce (proposé)'),
  ('nuisibles', 'infestation_moyenne', 50, 'pourcent', 'Majoration produits : infestation moyenne (proposé)'),
  ('nuisibles', 'infestation_forte', 100, 'pourcent', 'Majoration produits : infestation forte (proposé)')
on conflict (service, cle) do nothing;

-- Modifier un paramètre (administrateur, SQL Editor) :
--   update tarifs set valeur = 1300
--    where service = 'global' and cle = 'tarif_horaire';
--   update tarifs set valeur = 10
--    where service = 'global' and cle = 'remise_abonnement';
-- Voir tous les paramètres :
--   select service, cle, valeur, unite, libelle from tarifs order by 1, 2;

-- ---------------------------------------------------------------------------
-- 2. Calcul
-- ---------------------------------------------------------------------------

-- Tous les paramètres sous forme { service: { cle: valeur } }.
create or replace function public.tarifs_json()
returns jsonb language sql stable as $$
  select coalesce(jsonb_object_agg(service, cles), '{}'::jsonb)
  from (select service, jsonb_object_agg(cle, round(valeur)) as cles
        from public.tarifs group by service) t
$$;

create or replace function public._tarif(p jsonb, s text, c text)
returns integer language sql immutable as $$
  select coalesce(round((p -> s ->> c)::numeric), 0)::integer
$$;

-- Entier d'une réponse (0 si absent ou non numérique, tronqué comme en Dart).
create or replace function public._rep_int(r jsonb, c text)
returns integer language sql immutable as $$
  select case when jsonb_typeof(r -> c) = 'number'
              then trunc((r ->> c)::numeric)::integer else 0 end
$$;

create or replace function public._rep_oui(r jsonb, c text)
returns boolean language sql immutable as $$
  select coalesce(r -> c = 'true'::jsonb, false)
$$;

create or replace function public._centaine(x integer)
returns integer language sql immutable as $$
  select case when x <= 0 then 0 else ((x + 99) / 100) * 100 end
$$;

-- Calcul de référence, pur (les tarifs sont passés en paramètre).
create or replace function public.calculer_prix(
  p_tarifs   jsonb,
  p_service  text,
  p_formule  text,
  p_frequence text,
  p_reponses jsonb,
  p_produits boolean
) returns jsonb language plpgsql immutable as $$
declare
  r        jsonb := coalesce(p_reponses, '{}'::jsonb);
  s        text  := p_service;
  minutes  integer := 0;
  produits integer := 0;
  ps       integer := 1;     -- passages par semaine (déchets)
  maj      integer := 0;
  n        integer;
  base     integer;
  hebdo    boolean := p_formule = 'abonnement' and p_frequence = 'hebdomadaire';
  main_oeuvre  integer;
  deplacement  integer;
  prix_passage integer;
  passages     integer;
  remise       integer;
  prix_total   integer;
begin
  if s = 'menage' then
    minutes := greatest(_rep_int(r, 'chambres'), 0)  * _tarif(p_tarifs, s, 'chambre')
             + greatest(_rep_int(r, 'salons'), 0)    * _tarif(p_tarifs, s, 'salon')
             + greatest(_rep_int(r, 'cuisines'), 0)  * _tarif(p_tarifs, s, 'cuisine')
             + greatest(_rep_int(r, 'douche_wc'), 0) * _tarif(p_tarifs, s, 'douche_wc')
             + greatest(_rep_int(r, 'canapes'), 0)   * _tarif(p_tarifs, s, 'canape')
             + greatest(_rep_int(r, 'tapis'), 0)     * _tarif(p_tarifs, s, 'tapis');
    if _rep_oui(r, 'vitres') then minutes := minutes + _tarif(p_tarifs, s, 'vitres'); end if;
    if _rep_oui(r, 'frigo')  then minutes := minutes + _tarif(p_tarifs, s, 'frigo');  end if;
    if _rep_oui(r, 'four')   then minutes := minutes + _tarif(p_tarifs, s, 'four');   end if;
    maj := case r ->> 'etat'
             when 'sale'      then _tarif(p_tarifs, s, 'etat_sale')
             when 'tres_sale' then _tarif(p_tarifs, s, 'etat_tres_sale')
             else 0 end;
    if maj > 0 then
      minutes := (minutes * (100 + maj) + 99) / 100;
    end if;
    if p_produits then produits := _tarif(p_tarifs, s, 'produits'); end if;

  elsif s = 'linge' then
    n := greatest(_rep_int(r, 'paniers'), 1);
    minutes := n * _tarif(p_tarifs, s, 'panier');
    if _rep_oui(r, 'draps_delicats') then
      minutes := minutes + n * _tarif(p_tarifs, s, 'draps_delicats');
    end if;
    if _rep_oui(r, 'repassage') then
      minutes := minutes + greatest(_rep_int(r, 'pieces_repassage'), 0)
                         * _tarif(p_tarifs, s, 'piece_repassage');
    end if;
    if p_produits then produits := n * _tarif(p_tarifs, s, 'produits'); end if;

  elsif s = 'dechets' then
    if hebdo then
      ps := least(greatest(_rep_int(r, 'passages_semaine'), 1), 7);
      n := (_rep_int(r, 'sacs') + ps - 1) / ps;
    else
      n := _rep_int(r, 'sacs');
    end if;
    minutes := greatest(n, 0) * _tarif(p_tarifs, s, 'sac')
             + greatest(_rep_int(r, 'etage'), 0) * _tarif(p_tarifs, s, 'etage');
    if (r ->> 'distance_bac') ~ '^[0-9]+$' then
      minutes := minutes + (((r ->> 'distance_bac')::integer + 9) / 10)
                         * _tarif(p_tarifs, s, 'distance_10m');
    end if;
    minutes := greatest(minutes, _tarif(p_tarifs, s, 'minimum'));

  elsif s = 'nuisibles' then
    n := greatest(_rep_int(r, 'pieces'), 1);
    minutes := n * _tarif(p_tarifs, s, 'piece');
    base := n * _tarif(p_tarifs, s, 'produit_' || coalesce(r ->> 'nuisible', 'cafards'));
    maj := case r ->> 'infestation'
             when 'moyenne' then _tarif(p_tarifs, s, 'infestation_moyenne')
             when 'forte'   then _tarif(p_tarifs, s, 'infestation_forte')
             else 0 end;
    produits := (base * (100 + maj) + 99) / 100;

  else
    raise exception 'SERVICE_INCONNU';
  end if;

  main_oeuvre  := (minutes * _tarif(p_tarifs, 'global', 'tarif_horaire') + 30) / 60;
  deplacement  := _tarif(p_tarifs, 'global', 'deplacement');
  prix_passage := _centaine(main_oeuvre + deplacement + produits);
  passages     := case when hebdo then 4 * ps else 1 end;
  remise       := case when p_formule = 'abonnement'
                       then _tarif(p_tarifs, 'global', 'remise_abonnement') else 0 end;
  prix_total   := _centaine((prix_passage * passages * (100 - remise) + 99) / 100);

  return jsonb_build_object(
    'minutes', minutes, 'main_oeuvre', main_oeuvre, 'deplacement', deplacement,
    'produits', produits, 'prix_passage', prix_passage, 'passages', passages,
    'prix_total', prix_total);
end $$;

-- Ce que l'app appelle pour le prix « confirmé par le serveur ».
create or replace function public.calculer_prix_demande(
  p_service text, p_formule text, p_frequence text,
  p_reponses jsonb, p_produits boolean
) returns jsonb language sql stable as $$
  select public.calculer_prix(public.tarifs_json(), p_service, p_formule,
                              p_frequence, p_reponses,
                              p_produits or p_service = 'nuisibles')
$$;

grant execute on function public.calculer_prix_demande(text, text, text, jsonb, boolean)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Contrôle : 8 cas partagés avec les tests Dart, sur les tarifs de départ
-- ---------------------------------------------------------------------------
do $$
declare
  depart jsonb := '{
    "global": {"tarif_horaire": 1200, "deplacement": 1000, "remise_abonnement": 0},
    "menage": {"chambre": 30, "salon": 40, "cuisine": 45, "douche_wc": 30,
               "canape": 40, "tapis": 25, "vitres": 30, "frigo": 20, "four": 20,
               "etat_sale": 25, "etat_tres_sale": 50, "produits": 1500},
    "linge": {"panier": 40, "draps_delicats": 15, "piece_repassage": 4, "produits": 500},
    "dechets": {"sac": 5, "etage": 2, "distance_10m": 1, "minimum": 15},
    "nuisibles": {"piece": 20, "produit_cafards": 1500, "produit_moustiques": 1000,
                  "produit_punaises": 3000, "produit_rongeurs": 2500,
                  "produit_fourmis": 1000, "infestation_moyenne": 50,
                  "infestation_forte": 100}}';
  c record;
  res jsonb;
begin
  for c in select * from (values
    ('menage', 'ponctuelle', null::text,
     '{"chambres":2,"salons":1,"cuisines":1,"douche_wc":1,"etat":"normal"}'::jsonb,
     false, 175, 4500, 1, 4500),
    ('menage', 'ponctuelle', null,
     '{"chambres":3,"salons":1,"cuisines":1,"douche_wc":2,"vitres":true,"frigo":true,"four":false,"etat":"sale"}',
     true, 357, 9700, 1, 9700),
    ('menage', 'abonnement', 'hebdomadaire',
     '{"chambres":1,"salons":1,"cuisines":1,"douche_wc":1,"etat":"tres_sale"}',
     false, 218, 5400, 4, 21600),
    ('linge', 'ponctuelle', null,
     '{"paniers":2,"draps_delicats":true,"repassage":true,"pieces_repassage":10}',
     true, 150, 5000, 1, 5000),
    ('dechets', 'abonnement', 'hebdomadaire',
     '{"sacs":6,"passages_semaine":2,"etage":3,"distance_bac":"50"}',
     false, 26, 1600, 8, 12800),
    ('dechets', 'ponctuelle', null,
     '{"sacs":1,"etage":0,"distance_bac":"10"}',
     false, 15, 1300, 1, 1300),
    ('nuisibles', 'ponctuelle', null,
     '{"nuisible":"punaises","pieces":3,"infestation":"forte"}',
     true, 60, 20200, 1, 20200),
    ('nuisibles', 'abonnement', 'mensuel',
     '{"nuisible":"cafards","pieces":1,"infestation":"faible"}',
     true, 20, 2900, 1, 2900)
  ) as t(service, formule, frequence, reponses, produits,
         minutes, prix_passage, passages, prix_total)
  loop
    res := public.calculer_prix(depart, c.service, c.formule, c.frequence,
                                c.reponses, c.produits);
    if (res ->> 'minutes')::int <> c.minutes
       or (res ->> 'prix_passage')::int <> c.prix_passage
       or (res ->> 'passages')::int <> c.passages
       or (res ->> 'prix_total')::int <> c.prix_total then
      raise exception 'Contrôle tarification échoué pour % % : obtenu %, attendu % min / % / % / %',
        c.service, c.reponses, res, c.minutes, c.prix_passage, c.passages, c.prix_total;
    end if;
  end loop;
  raise notice 'Tarification : 8 cas de contrôle OK';
end $$;

-- Essai sur les tarifs actuels (SQL Editor) :
--   select calculer_prix_demande('menage', 'ponctuelle', null,
--     '{"chambres":2,"salons":1,"cuisines":1,"douche_wc":1,"etat":"normal"}', false);
