-- Correctif de 011 : la table « citoyens » a pour identifiant `citoyen_id`
-- (et non `id`). Sans ce correctif, toute réservation échoue avec
-- « column "id" does not exist ».
--
-- À exécuter une fois dans Dashboard Supabase > SQL Editor si 011 a été
-- appliqué avant le 22/10/2026 (le fichier 011 est corrigé pour les
-- nouvelles installations). Relançable.

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
