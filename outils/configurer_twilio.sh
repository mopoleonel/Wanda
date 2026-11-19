#!/usr/bin/env bash
# Configure l'envoi des codes WhatsApp (Twilio) sur le serveur WANDA.
#
#   bash outils/configurer_twilio.sh            # tout saisir
#   bash outils/configurer_twilio.sh --jeton    # seulement l'Auth Token (le
#                                               # reste est déjà sur le serveur)
#
# Les identifiants sont tapés ici (le jeton est masqué) et envoyés au serveur
# par SSH : ils ne sont écrits ni sur ce PC, ni dans le projet, ni sur GitHub.
set -euo pipefail

SERVEUR="${WANDA_SERVEUR:-root@89.167.100.113}"
CLE="${WANDA_CLE_SSH:-$HOME/.ssh/wanda_vps}"
JETON_SEUL=0
[[ "${1:-}" == "--jeton" ]] && JETON_SEUL=1

echo "Configuration de Twilio sur $SERVEUR"
echo "(Console Twilio > Account Info : Account SID et Auth Token)"
echo

if (( ! JETON_SEUL )); then
  read -rp "Account SID (commence par AC) : " SID
  [[ "$SID" =~ ^AC[0-9a-f]{32}$ ]] || { echo "Account SID invalide."; exit 1; }
fi

read -rsp "Auth Token (la saisie est masquée) : " JETON; echo
[[ "$JETON" =~ ^[0-9a-f]{32}$ ]] || { echo "Auth Token invalide (32 caractères 0-9 a-f)."; exit 1; }

if (( JETON_SEUL )); then
  LIGNES=("OTP_FOURNISSEUR=twilio" "TWILIO_AUTH_TOKEN=$JETON")
else
  read -rp "Numéro WhatsApp d'envoi (bac à sable : +14155238886) : " DE
  DE="${DE// /}"
  [[ "$DE" =~ ^\+[0-9]{8,15}$ ]] || { echo "Numéro invalide (format +XXXXXXXX)."; exit 1; }

  read -rp "Content SID du modèle approuvé (HX…, Entrée si bac à sable) : " CONTENU
  [[ -z "$CONTENU" || "$CONTENU" =~ ^HX[0-9a-f]{32}$ ]] || { echo "Content SID invalide."; exit 1; }

  LIGNES=("OTP_FOURNISSEUR=twilio" "TWILIO_ACCOUNT_SID=$SID" "TWILIO_AUTH_TOKEN=$JETON"
          "TWILIO_WHATSAPP_FROM=whatsapp:$DE" "TWILIO_CONTENT_SID=$CONTENU")
fi

printf '%s\n' "${LIGNES[@]}" |
ssh -i "$CLE" "$SERVEUR" '
  set -eu
  cd /opt/wanda/backend/deploiement
  umask 077
  cp .env .env.avant-twilio
  while IFS= read -r ligne; do
    cle=${ligne%%=*}
    grep -v -E "^#? ?$cle=" .env > .env.tmp || true
    mv .env.tmp .env
    printf "%s\n" "$ligne" >> .env
  done
  chmod 600 .env
  docker compose up -d api >/dev/null 2>&1
  echo "Serveur mis à jour et redémarré."
'
echo
echo "Fait. Demandez un code dans l'app avec un vrai numéro pour essayer."
