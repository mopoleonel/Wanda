-- Informations figées après certification d'identité.
--
-- Dès qu'un artisan a une certification EN COURS (en attente de revue) ou
-- VALIDÉE, il ne peut plus modifier lui-même :
--   * nom et prénom      : ils doivent rester ceux lus sur sa CNI ;
--   * métier             : le domaine sous lequel les citoyens l'ont trouvé
--                          et noté (changer de métier garderait le badge et
--                          les avis d'un autre métier) ;
--   * téléphone          : son identifiant de connexion.
-- La photo professionnelle, la disponibilité et l'abonnement restent libres.
--
-- Même règle que dans l'app (Particulier.champsFiges). Une correction reste
-- possible par l'équipe WANDA (SQL Editor ou clé service_role), qui n'est
-- pas concernée par ce contrôle.
--
-- Prérequis : 005_verification_identite_prestataires.sql.
-- À exécuter une fois dans Dashboard Supabase > SQL Editor.

create or replace function public.figer_identite_certifiee()
-- Pas de « security definer » : current_user doit rester celui de la
-- requête. L'artisan ne modifie que sa propre ligne et peut lire ses
-- propres vérifications (politique verif_select_soi).
returns trigger language plpgsql set search_path = public as $$
begin
  -- Seules les requêtes des utilisateurs de l'app sont contrôlées.
  if current_user <> 'authenticated' then
    return new;
  end if;

  if (new.nom is distinct from old.nom
      or new.prenom is distinct from old.prenom
      or new.service_propose is distinct from old.service_propose
      or new.telephone is distinct from old.telephone)
     and (old.identite_verifiee
          or exists (select 1 from prestataire_verifications v
                     where v.prestataire_id = old.id
                       and v.statut = 'en_attente')) then
    raise exception 'IDENTITE_FIGEE';
  end if;
  return new;
end $$;

drop trigger if exists trg_figer_identite_certifiee on public.particuliers;
create trigger trg_figer_identite_certifiee
  before update of nom, prenom, service_propose, telephone
  on public.particuliers
  for each row execute function public.figer_identite_certifiee();
