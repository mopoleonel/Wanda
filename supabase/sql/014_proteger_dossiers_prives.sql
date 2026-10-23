-- Protéger les dossiers privés du stockage (« demandes », « identites »).
--
-- Constat du 23/10/2026 (test sur la base réelle) : un utilisateur connecté
-- a pu déposer un fichier dans le dossier « demandes » d'un AUTRE
-- utilisateur. Les politiques de 005 / 010 n'autorisent que son propre
-- dossier, mais les politiques RLS s'additionnent : une politique plus
-- ancienne, valable pour tous les buckets (sans condition sur bucket_id),
-- suffit à tout ouvrir.
--
-- Ce script ne supprime rien : il retrouve chaque politique de
-- storage.objects qui ne mentionne pas bucket_id et lui ajoute
-- « bucket_id not in ('demandes', 'identites') ». Les autres buckets
-- (profils, signalements, entreprise_assets…) gardent exactement leur
-- comportement actuel ; les deux buckets privés ne sont plus régis que par
-- leurs politiques dédiées (dossier de l'utilisateur, accès croisé de 011).
--
-- À exécuter dans Dashboard Supabase > SQL Editor. Relançable.
--
-- Pour voir les politiques avant / après :
--   select policyname, cmd, roles, qual, with_check
--     from pg_policies where schemaname = 'storage' and tablename = 'objects'
--    order by policyname;

do $$
declare
  p record;
  garde constant text := 'bucket_id <> ALL (ARRAY[''demandes''::text, ''identites''::text])';
begin
  for p in
    select policyname, cmd, qual, with_check
    from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and coalesce(qual, '') not like '%bucket_id%'
      and coalesce(with_check, '') not like '%bucket_id%'
  loop
    if p.cmd in ('SELECT', 'DELETE') or (p.cmd in ('UPDATE', 'ALL') and p.qual is not null) then
      execute format('alter policy %I on storage.objects using ((%s) and %s)',
                     p.policyname, coalesce(p.qual, 'true'), garde);
    end if;
    if p.cmd in ('INSERT', 'UPDATE', 'ALL') and (p.with_check is not null or p.cmd = 'INSERT') then
      execute format('alter policy %I on storage.objects with check ((%s) and %s)',
                     p.policyname, coalesce(p.with_check, 'true'), garde);
    end if;
    raise notice 'Politique « % » (%) : dossiers privés exclus', p.policyname, p.cmd;
  end loop;
end $$;
