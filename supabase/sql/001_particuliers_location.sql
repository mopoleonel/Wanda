-- Matching par proximité : ajoute la position GPS des prestataires
-- indépendants. Capturée côté app quand le prestataire passe "disponible"
-- (voir PrestataireRepository.setAvailability), utilisée côté citoyen pour
-- trier la liste des experts par distance (voir ServicePage._sortByDistance).
--
-- À exécuter une fois dans l'éditeur SQL de ton projet Supabase
-- (Dashboard > SQL Editor > New query).

alter table public.particuliers
  add column if not exists latitude double precision,
  add column if not exists longitude double precision;

-- Index utile si tu ajoutes plus tard une requête de proximité côté serveur
-- (ex: via PostGIS) plutôt que le tri côté client actuel.
create index if not exists particuliers_location_idx
  on public.particuliers (latitude, longitude)
  where latitude is not null and longitude is not null;
