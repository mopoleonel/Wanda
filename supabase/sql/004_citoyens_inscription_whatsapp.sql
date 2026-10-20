-- Inscription citoyen par numéro WhatsApp (code OTP) : à la création du
-- compte, seul le téléphone vérifié est connu. Nom, prénom et email sont
-- complétés plus tard depuis le profil (voir LoginCitoyenPage et
-- ServicePage._updateProfile), donc ces colonnes doivent accepter NULL.
--
-- À exécuter une fois dans l'éditeur SQL de ton projet Supabase
-- (Dashboard > SQL Editor > New query). Sans danger si les colonnes
-- acceptent déjà NULL.

alter table public.citoyens
  alter column nom drop not null,
  alter column prenom drop not null,
  alter column email drop not null;
