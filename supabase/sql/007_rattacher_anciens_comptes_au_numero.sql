-- Connexion uniquement par numéro + code WhatsApp : rattacher les anciens
-- comptes (créés avec un mot de passe) à leur numéro de téléphone.
--
-- Depuis la suppression de l'option « Ancien compte », l'app ne se connecte
-- plus que par code WhatsApp (auth.signInWithOtp(phone)). Supabase Auth
-- retrouve alors l'utilisateur par sa colonne auth.users.phone. Or les
-- anciens comptes n'ont pas de téléphone dans Auth :
--   * prestataires « numéro + mot de passe » : email technique
--     « 237XXXXXXXXX@prestataire.wanda.app » ;
--   * comptes créés par email : le numéro n'est que dans citoyens /
--     particuliers / entreprises.
-- Sans ce script, leur premier code créerait un NOUVEAU compte vide et
-- l'app répondrait « Ce numéro est déjà lié à un compte WANDA ».
--
-- Format de auth.users.phone : chiffres seuls, indicatif compris, sans « + »
-- (ex. 237699000001).
--
-- À exécuter une fois dans Dashboard Supabase > SQL Editor, étape par étape.

-- ---------------------------------------------------------------------------
-- 1. Numéro attendu pour chaque compte sans téléphone dans Auth
-- ---------------------------------------------------------------------------
create or replace function pg_temp.numero_auth(t text)
returns text language sql immutable as $$
  select case
    when d ~ '^6\d{8}$'      then '237' || d   -- 699000001 (Cameroun)
    when d ~ '^00\d{8,15}$'  then substr(d, 3) -- 00237699000001
    when d ~ '^[1-9]\d{7,14}$' then d          -- 237699000001
  end
  from (select regexp_replace(coalesce(t, ''), '\D', '', 'g') as d) x
$$;

create temp table rattachements as
select u.id, u.email,
       coalesce(
         -- Prestataire à mot de passe : le numéro est dans l'email technique.
         case when u.email like '%@prestataire.wanda.app'
              then pg_temp.numero_auth(split_part(u.email, '@', 1)) end,
         pg_temp.numero_auth(p.telephone),
         pg_temp.numero_auth(e.telephone),
         pg_temp.numero_auth(c.telephone)
       ) as numero
from auth.users u
left join public.particuliers p on p.id = u.id
left join public.entreprises  e on e.id = u.id
left join public.citoyens     c on c.id = u.id
where coalesce(u.phone, '') = '';

-- ---------------------------------------------------------------------------
-- 2. À VÉRIFIER AVANT de continuer
-- ---------------------------------------------------------------------------
-- a) Comptes impossibles à rattacher (aucun numéro connu) : ils ne pourront
--    plus se connecter. Ajouter le numéro à la main dans leur fiche, puis
--    relancer ce script.
select id, email from rattachements where numero is null;

-- b) Conflits : le numéro appartient déjà à un autre utilisateur Auth.
--    Souvent un compte VIDE créé par un premier essai de code (aucune
--    fiche citoyen / particulier / entreprise). Après vérification, le
--    supprimer (Authentication > Users) puis relancer ce script.
select r.id as ancien_compte, r.email, r.numero,
       u.id as compte_qui_a_ce_numero,
       not exists (select 1 from public.citoyens     where id = u.id)
   and not exists (select 1 from public.particuliers where id = u.id)
   and not exists (select 1 from public.entreprises  where id = u.id)
         as compte_vide
from rattachements r
join auth.users u on u.phone = r.numero and u.id <> r.id;

-- c) Doublons : plusieurs anciens comptes avec le même numéro (un seul
--    pourra le garder). À trancher à la main.
select numero, array_agg(id) as comptes
from rattachements where numero is not null
group by numero having count(*) > 1;

-- ---------------------------------------------------------------------------
-- 3. Rattachement (sans conflit ni doublon)
-- ---------------------------------------------------------------------------
update auth.users u
   set phone = r.numero,
       updated_at = now()
  from rattachements r
 where u.id = r.id
   and r.numero is not null
   and not exists (select 1 from auth.users o
                   where o.phone = r.numero and o.id <> r.id)
   and (select count(*) from rattachements d where d.numero = r.numero) = 1;

-- Résultat : comptes rattachés.
select r.id, r.email, r.numero
from rattachements r join auth.users u on u.id = r.id
where u.phone = r.numero;
