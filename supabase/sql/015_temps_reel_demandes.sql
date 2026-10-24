-- Temps réel sur les demandes, ajustements et passages.
--
-- Constat du 24/10/2026 (test sur téléphone) : une demande créée par le
-- client est bien enregistrée, mais « Mes demandes » ne l'affiche pas tant
-- que l'écran n'est pas rechargé. Le flux de l'app (.stream()) s'appuie sur
-- la publication « supabase_realtime », dont ces tables ne font pas partie.
-- Même effet quand le prestataire accepte, termine ou demande un ajustement.
--
-- Les règles RLS s'appliquent aussi au temps réel : chacun ne reçoit que les
-- lignes qu'il a le droit de lire.
--
-- À exécuter dans Dashboard Supabase > SQL Editor. Relançable.

do $$
declare
  t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  foreach t in array array['sollicitations', 'ajustements', 'passages'] loop
    if to_regclass('public.' || t) is not null and not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
      raise notice 'Temps réel activé sur %', t;
    end if;
  end loop;
end $$;
