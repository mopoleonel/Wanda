-- Déclenche l'envoi de notifications push via l'Edge Function
-- `send-push-notification` sur les événements métier clés :
--   1. Nouvelle sollicitation reçue  -> notifie le prestataire
--   2. Sollicitation acceptée/terminée -> notifie le citoyen
--   3. Nouveau signalement assigné   -> notifie l'entreprise
--
-- Prérequis : l'extension pg_net (déjà activée par défaut sur la plupart des
-- projets Supabase récents). Remplace <PROJECT_REF> par la référence de ton
-- projet Supabase avant d'exécuter ce script.

create extension if not exists pg_net;

-- Stocke la clé service-role dans un paramètre de config Postgres pour ne
-- pas la répéter dans chaque fonction. À définir une fois :
--   alter database postgres set app.settings.service_role_key = '<ta-clé-service-role>';
--   alter database postgres set app.settings.edge_functions_url = 'https://<PROJECT_REF>.supabase.co/functions/v1';

create or replace function public.notify_push(
  target_user_id uuid,
  notif_title text,
  notif_body text
) returns void as $$
declare
  service_key text := current_setting('app.settings.service_role_key', true);
  base_url text := current_setting('app.settings.edge_functions_url', true);
begin
  if service_key is null or base_url is null then
    -- Configuration non faite : on ignore silencieusement plutôt que de
    -- faire échouer l'opération métier (insert/update) qui a déclenché ceci.
    return;
  end if;

  perform net.http_post(
    url := base_url || '/send-push-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || service_key
    ),
    body := jsonb_build_object(
      'userId', target_user_id,
      'title', notif_title,
      'body', notif_body
    )
  );
end;
$$ language plpgsql security definer;

-- 1. Nouvelle sollicitation -> prestataire
create or replace function public.trigger_notify_new_sollicitation()
returns trigger as $$
begin
  perform public.notify_push(
    new.prestataire_id,
    'Nouvelle demande',
    coalesce(new.nom_citoyen, 'Un citoyen') || ' a besoin de vos services.'
  );
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_sollicitation_created on public.sollicitations;
create trigger on_sollicitation_created
  after insert on public.sollicitations
  for each row execute function public.trigger_notify_new_sollicitation();

-- 2. Sollicitation acceptée/terminée -> citoyen
create or replace function public.trigger_notify_sollicitation_status()
returns trigger as $$
begin
  if new.statut = 'accepte' and old.statut is distinct from 'accepte' then
    perform public.notify_push(
      new.citoyen_id,
      'Mission acceptée',
      'Un expert est en route pour votre demande.'
    );
  elsif new.statut = 'termine' and old.statut is distinct from 'termine' then
    perform public.notify_push(
      new.citoyen_id,
      'Mission terminée',
      'Votre mission est terminée. Pensez à noter le prestataire !'
    );
  end if;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_sollicitation_status_changed on public.sollicitations;
create trigger on_sollicitation_status_changed
  after update on public.sollicitations
  for each row execute function public.trigger_notify_sollicitation_status();

-- 3. Nouveau signalement assigné -> entreprise
create or replace function public.trigger_notify_new_signalement()
returns trigger as $$
begin
  if new.entreprise_id is not null then
    perform public.notify_push(
      new.entreprise_id,
      'Nouveau signalement',
      'Un incident (' || new.type_probleme || ') vous a été assigné.'
    );
  end if;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_signalement_created on public.signalements;
create trigger on_signalement_created
  after insert on public.signalements
  for each row execute function public.trigger_notify_new_signalement();
