-- Services ménagers (5/5) : notifications push.
--
-- Remplace les messages de 003 pour les demandes (le vocabulaire « expert
-- en route » ne convient plus) et ajoute refus, ajustements et passages.
-- Les notifications des signalements (003) ne changent pas.
--
-- Prérequis : 003, 011. À exécuter dans Dashboard Supabase > SQL Editor.
-- Relançable.

create or replace function public._libelle_service(s text)
returns text language sql immutable as $$
  select case s
    when 'menage'    then 'Ménage'
    when 'linge'     then 'Linge'
    when 'dechets'   then 'Ramassage des poubelles'
    when 'nuisibles' then 'Lutte contre les nuisibles'
    else 'Service' end
$$;

create or replace function public._montant(x integer)
returns text language sql immutable as $$
  select replace(to_char(coalesce(x, 0), 'FM999G999G999'), ',', ' ') || ' FCFA'
$$;

-- Nouvelle demande -> prestataire
create or replace function public.trigger_notify_new_sollicitation()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.notify_push(
    new.prestataire_id,
    case when new.service is null then 'Nouvelle mission'
         else 'Nouvelle demande : ' || _libelle_service(new.service) end,
    case when new.prix_total is null
         then coalesce(new.nom_citoyen, 'Un client') || ' a besoin de vos services.'
         else coalesce(new.nom_citoyen, 'Un client') || ' · ' || _montant(new.prix_total)
              || '. Consultez la demande pour accepter ou refuser.' end);
  return new;
end $$;

-- Changement de statut -> client
create or replace function public.trigger_notify_sollicitation_status()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.statut is not distinct from old.statut then
    return new;
  end if;
  if new.statut = 'accepte' then
    perform public.notify_push(new.citoyen_id, 'Demande confirmée',
      'Votre prestataire a accepté : ' || _libelle_service(new.service) || '.');
  elsif new.statut = 'refuse' then
    perform public.notify_push(new.citoyen_id, 'Demande refusée',
      'Le prestataire n''est pas disponible. Choisissez-en un autre depuis votre demande.');
  elsif new.statut = 'termine' then
    perform public.notify_push(new.citoyen_id, 'Service terminé',
      'Pensez à noter votre prestataire.');
  end if;
  return new;
end $$;

-- Ajustement demandé -> client ; réponse -> prestataire
create or replace function public.trigger_notify_ajustement()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_s record;
begin
  select citoyen_id, prestataire_id into v_s
    from sollicitations where id = new.sollicitation_id;
  if tg_op = 'INSERT' then
    perform public.notify_push(v_s.citoyen_id, 'Ajustement demandé',
      'Votre prestataire demande +' || _montant(new.prix_supp)
      || '. Acceptez ou refusez dans « Mes demandes ».');
  elsif new.statut is distinct from old.statut then
    perform public.notify_push(v_s.prestataire_id,
      case when new.statut = 'accepte' then 'Ajustement accepté'
           else 'Ajustement refusé' end,
      case when new.statut = 'accepte'
           then 'Le client a accepté +' || _montant(new.prix_supp) || '.'
           else 'Le client a refusé : le prix initial reste dû.' end);
  end if;
  return new;
end $$;

drop trigger if exists on_ajustement_change on public.ajustements;
create trigger on_ajustement_change
  after insert or update on public.ajustements
  for each row execute function public.trigger_notify_ajustement();

-- Passage pointé -> client
create or replace function public.trigger_notify_passage()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_c uuid;
begin
  select citoyen_id into v_c from sollicitations where id = new.sollicitation_id;
  perform public.notify_push(v_c, 'Passage effectué',
    'Votre prestataire a pointé le passage d''aujourd''hui.');
  return new;
end $$;

drop trigger if exists on_passage_pointe on public.passages;
create trigger on_passage_pointe
  after insert on public.passages
  for each row execute function public.trigger_notify_passage();
