-- Scénario complet joué en tant qu'utilisateurs connectés (rôle authenticated).
\set ON_ERROR_STOP 1
-- Triggers de notification de 003 (absents du mini-Supabase) branchés ici.
drop trigger if exists on_sollicitation_created on sollicitations;
create trigger on_sollicitation_created after insert on sollicitations
  for each row execute function trigger_notify_new_sollicitation();
drop trigger if exists on_sollicitation_status_changed on sollicitations;
create trigger on_sollicitation_status_changed after update on sollicitations
  for each row execute function trigger_notify_sollicitation_status();

-- Prestataire de test : ménage + linge, en ligne.
insert into auth.users(id, phone) values ('11111111-1111-1111-1111-111111111111','237690000001')
on conflict do nothing;
insert into particuliers(id, nom, prenom, telephone, photo_pro_url, services, is_available)
values ('11111111-1111-1111-1111-111111111111','Essai','Testeur','+237690000001','x.jpg','{linge,menage}', true)
on conflict (id) do update set services = '{linge,menage}', is_available = true;

insert into auth.users(id, phone) values
  ('22222222-2222-2222-2222-222222222222', '237690000002'),
  ('33333333-3333-3333-3333-333333333333', '237690000003')
on conflict do nothing;
insert into citoyens(citoyen_id, nom, prenom, telephone)
  values ('22222222-2222-2222-2222-222222222222', 'Mbarga', 'Lucie', '+237690000002')
on conflict do nothing;
update particuliers set is_available = true;  -- prestataire 1111… : linge + menage

create or replace function pg_temp.attendre_erreur(sql text, code text) returns void
language plpgsql as $$
begin
  execute sql;
  raise exception 'ÉCHEC : % aurait dû lever %', sql, code;
exception when raise_exception or check_violation or insufficient_privilege then
  if sqlerrm not like '%' || code || '%' then
    raise exception 'ÉCHEC : % a levé « % » au lieu de %', sql, sqlerrm, code;
  end if;
  raise notice 'OK refusé : %', code;
end $$;

-- ===== Client =====
set role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);

-- Insérer directement un prix : refusé
select pg_temp.attendre_erreur($$insert into sollicitations(prestataire_id, citoyen_id, statut, service, prix_total)
  values ('11111111-1111-1111-1111-111111111111', auth.uid(), 'en_attente', 'menage', 10)$$, 'DEMANDE_VIA_SERVEUR');

-- Photos obligatoires, et dans son propre dossier
select pg_temp.attendre_erreur($$select creer_demande('11111111-1111-1111-1111-111111111111','menage','ponctuelle',null,
  '{"chambres":2,"salons":1,"cuisines":1,"douche_wc":1,"etat":"normal"}', false, '{}', null, current_date, 'matin')$$, 'PHOTOS_REQUISES');
select pg_temp.attendre_erreur($$select creer_demande('11111111-1111-1111-1111-111111111111','menage','ponctuelle',null,
  '{"chambres":2}', false, array['autre/x.jpg'], null, current_date, 'matin')$$, 'PHOTO_INVALIDE');
-- Service non proposé par ce prestataire
select pg_temp.attendre_erreur($$select creer_demande('11111111-1111-1111-1111-111111111111','nuisibles','ponctuelle',null,
  '{"pieces":2}', true, array['22222222-2222-2222-2222-222222222222/d1/1.jpg'], null, current_date, 'matin')$$, 'PRESTATAIRE_INDISPONIBLE');
-- Date passée
select pg_temp.attendre_erreur($$select creer_demande('11111111-1111-1111-1111-111111111111','menage','ponctuelle',null,
  '{"chambres":2}', false, array['22222222-2222-2222-2222-222222222222/d1/1.jpg'], null, current_date - 1, 'matin')$$, 'DATE_INVALIDE');

-- Demande valide : le prix vient du serveur
select creer_demande('11111111-1111-1111-1111-111111111111','menage','ponctuelle',null,
  '{"chambres":2,"salons":1,"cuisines":1,"douche_wc":1,"etat":"normal"}', false,
  array['22222222-2222-2222-2222-222222222222/d1/1.jpg'], null, current_date + 1, 'matin') as demande_id \gset
select service, prix_total, minutes_estimees, statut, nom_citoyen from sollicitations where id = :'demande_id';
do $$ begin
  if (select prix_total from sollicitations order by date_sollicitation desc limit 1) <> 4500 then
    raise exception 'ÉCHEC prix serveur'; end if;
  raise notice 'OK prix enregistré par le serveur : 4 500 FCFA';
end $$;

-- Le client ne peut ni baisser le prix ni accepter à la place du prestataire
select pg_temp.attendre_erreur(format($$update sollicitations set prix_total = 100 where id = %L$$, :'demande_id'), 'PRIX_PROTEGE');
select pg_temp.attendre_erreur(format($$update sollicitations set statut = 'accepte' where id = %L$$, :'demande_id'), 'TRANSITION_INTERDITE');

-- ===== Prestataire =====
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select count(*) as photos_visibles_prestataire from sollicitations where id = :'demande_id' and cardinality(photos) = 1;
select pg_temp.attendre_erreur(format($$update sollicitations set statut = 'termine' where id = %L$$, :'demande_id'), 'TRANSITION_INTERDITE');
update sollicitations set statut = 'accepte' where id = :'demande_id';
select pg_temp.attendre_erreur(format($$select demander_ajustement(%L, 0, 0, 'rien', null)$$, :'demande_id'), 'AJUSTEMENT_VIDE');
select demander_ajustement(:'demande_id', 60, 0, 'Une chambre de plus que déclaré',
  array['11111111-1111-1111-1111-111111111111/aj/1.jpg']) as ajustement_id \gset
select pg_temp.attendre_erreur(format($$select demander_ajustement(%L, 30, 0, 'Encore', null)$$, :'demande_id'), 'AJUSTEMENT_DEJA_EN_ATTENTE');
select pg_temp.attendre_erreur(format($$select repondre_ajustement(%L, true)$$, :'ajustement_id'), 'NON_AUTORISE');
select pg_temp.attendre_erreur(format($$select pointer_passage(%L)$$, :'demande_id'), 'PASSAGE_IMPOSSIBLE');

-- ===== Client accepte l'ajustement =====
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select prix_supp from ajustements where id = :'ajustement_id';
select repondre_ajustement(:'ajustement_id', true);
do $$ begin
  if (select prix_total from sollicitations order by date_sollicitation desc limit 1) <> 4500 + 1200 then
    raise exception 'ÉCHEC prix après ajustement'; end if;
  raise notice 'OK ajustement accepté : 4 500 + 1 200 = 5 700 FCFA';
end $$;
select pg_temp.attendre_erreur(format($$select repondre_ajustement(%L, false)$$, :'ajustement_id'), 'DEJA_REPONDU');

-- Un tiers ne voit rien
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
do $$ begin
  if exists (select 1 from sollicitations) or exists (select 1 from ajustements) then
    raise exception 'ÉCHEC : un tiers voit des demandes'; end if;
  raise notice 'OK un tiers ne voit ni demandes ni ajustements';
end $$;

-- ===== Abonnement hebdomadaire + passages =====
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select creer_demande('11111111-1111-1111-1111-111111111111','linge','abonnement','hebdomadaire',
  '{"paniers":2,"draps_delicats":true,"repassage":true,"pieces_repassage":10}', true,
  array['22222222-2222-2222-2222-222222222222/d2/1.jpg'], null, current_date, 'apres_midi') as abo_id \gset
select formule, frequence, prix_passage, prix_total from sollicitations where id = :'abo_id';
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
update sollicitations set statut = 'accepte' where id = :'abo_id';
select pointer_passage(:'abo_id') is not null as passage_pointe;
select pg_temp.attendre_erreur(format($$select pointer_passage(%L)$$, :'abo_id'), 'PASSAGE_DEJA_POINTE');
update sollicitations set statut = 'termine', date_fin = now() where id = :'demande_id';
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
update sollicitations set statut = 'archive' where id = :'demande_id';
reset role;
select 'Scénario terminé sans écart' as resultat;
