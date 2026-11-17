-- Sécurité et isolation des données : politiques RLS manquantes
-- (citoyens, particuliers, entreprises, avis_prestataires, signalements).
--
-- Contexte :
-- * citoyens : contient les données privées des clients (nom, téléphone, email).
--   Chaque utilisateur ne doit pouvoir lire, insérer ou modifier que son propre profil.
-- * particuliers & entreprises : profils visibles en lecture (pour choisir un artisan
--   ou attribuer un signalement), mais modifiables UNIQUEMENT par leur propriétaire respectif.
-- * avis_prestataires : un client ne peut noter qu'une mission terminée le concernant,
--   une seule fois par mission (contrainte d'unicité), avec une note entre 1 et 5.
-- * signalements : le citoyen crée et suit ses incidents urbains ; l'entreprise
--   compétente traite et met à jour le statut.
--
-- À exécuter dans Dashboard Supabase > SQL Editor. Relançable sans risque.

-- ---------------------------------------------------------------------------
-- 1. Citoyens (clients) : isolation stricte
-- ---------------------------------------------------------------------------
alter table public.citoyens enable row level security;

drop policy if exists "citoyens_select_own" on public.citoyens;
create policy "citoyens_select_own" on public.citoyens
  for select to authenticated
  using (citoyen_id = auth.uid());

drop policy if exists "citoyens_insert_own" on public.citoyens;
create policy "citoyens_insert_own" on public.citoyens
  for insert to authenticated
  with check (citoyen_id = auth.uid());

drop policy if exists "citoyens_update_own" on public.citoyens;
create policy "citoyens_update_own" on public.citoyens
  for update to authenticated
  using (citoyen_id = auth.uid())
  with check (citoyen_id = auth.uid());

drop policy if exists "citoyens_delete_own" on public.citoyens;
create policy "citoyens_delete_own" on public.citoyens
  for delete to authenticated
  using (citoyen_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 2. Prestataires indépendants (particuliers) : lecture publique, modification par soi
-- ---------------------------------------------------------------------------
alter table public.particuliers enable row level security;

drop policy if exists "particuliers_select_tous" on public.particuliers;
create policy "particuliers_select_tous" on public.particuliers
  for select to authenticated
  using (true);

drop policy if exists "particuliers_insert_soi" on public.particuliers;
create policy "particuliers_insert_soi" on public.particuliers
  for insert to authenticated
  with check (id = auth.uid());

drop policy if exists "particuliers_update_soi" on public.particuliers;
create policy "particuliers_update_soi" on public.particuliers
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

drop policy if exists "particuliers_delete_soi" on public.particuliers;
create policy "particuliers_delete_soi" on public.particuliers
  for delete to authenticated
  using (id = auth.uid());

-- ---------------------------------------------------------------------------
-- 3. Entreprises partenaires : lecture publique, modification par soi
-- ---------------------------------------------------------------------------
alter table public.entreprises enable row level security;

drop policy if exists "entreprises_select_tous" on public.entreprises;
create policy "entreprises_select_tous" on public.entreprises
  for select to authenticated
  using (true);

drop policy if exists "entreprises_insert_soi" on public.entreprises;
create policy "entreprises_insert_soi" on public.entreprises
  for insert to authenticated
  with check (id = auth.uid());

drop policy if exists "entreprises_update_soi" on public.entreprises;
create policy "entreprises_update_soi" on public.entreprises
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

drop policy if exists "entreprises_delete_soi" on public.entreprises;
create policy "entreprises_delete_soi" on public.entreprises
  for delete to authenticated
  using (id = auth.uid());

-- ---------------------------------------------------------------------------
-- 4. Avis prestataires : un avis par mission terminée, note entre 1 et 5
-- ---------------------------------------------------------------------------
alter table public.avis_prestataires enable row level security;

-- Contraintes d'intégrité anti-fraude
alter table public.avis_prestataires
  drop constraint if exists avis_note_valide;
alter table public.avis_prestataires
  add constraint avis_note_valide check (note between 1 and 5);

-- Un seul avis par mission
create unique index if not exists avis_sollicitation_unique
  on public.avis_prestataires (sollicitation_id);

drop policy if exists "avis_select_tous" on public.avis_prestataires;
create policy "avis_select_tous" on public.avis_prestataires
  for select to authenticated
  using (true);

drop policy if exists "avis_insert_citoyen_termine" on public.avis_prestataires;
create policy "avis_insert_citoyen_termine" on public.avis_prestataires
  for insert to authenticated
  with check (
    citoyen_id = auth.uid()
    and exists (
      select 1 from public.sollicitations s
      where s.id = sollicitation_id
        and s.citoyen_id = auth.uid()
        and s.prestataire_id = avis_prestataires.prestataire_id
        and s.statut in ('termine', 'archive')
    )
  );

-- ---------------------------------------------------------------------------
-- 5. Signalements : citoyen dépose/suit, entreprise traite
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.signalements') is not null then
    execute 'alter table public.signalements enable row level security';

    execute 'drop policy if exists signalements_select on public.signalements';
    execute $pol$
      create policy signalements_select on public.signalements
        for select to authenticated
        using (
          citoyen_id = auth.uid()
          or entreprise_id = auth.uid()
          or exists (select 1 from public.entreprises e where e.id = auth.uid())
        )
    $pol$;

    execute 'drop policy if exists signalements_insert on public.signalements';
    execute $pol$
      create policy signalements_insert on public.signalements
        for insert to authenticated
        with check (citoyen_id = auth.uid())
    $pol$;

    execute 'drop policy if exists signalements_update on public.signalements';
    execute $pol$
      create policy signalements_update on public.signalements
        for update to authenticated
        using (
          entreprise_id = auth.uid()
          or (entreprise_id is null and exists (select 1 from public.entreprises e where e.id = auth.uid()))
        )
    $pol$;
  end if;
end $$;
