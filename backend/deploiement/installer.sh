#!/bin/sh
# Installation de WANDA sur un VPS Ubuntu neuf (en root), après copie du
# dossier backend dans /opt/wanda/backend. Relançable : met à jour.
set -eu
cd /opt/wanda/backend/deploiement

# 1. Docker (script officiel) et mises à jour de sécurité automatiques.
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi
apt-get install -y -q unattended-upgrades ufw >/dev/null

# 2. Pare-feu : SSH et web seulement.
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443 >/dev/null
ufw --force enable >/dev/null

# 3. Réglages : générés une seule fois, secrets aléatoires.
if [ ! -f .env ]; then
  IP=$(curl -fsS https://api.ipify.org)
  DOMAINE="${DOMAINE:-$(echo "$IP" | tr . -).sslip.io}"
  cat > .env <<FIN
# Généré par installer.sh — ne jamais committer ni partager.
DOMAINE=$DOMAINE
POSTGRES_PASSWORD=$(openssl rand -hex 24)
DJANGO_SECRET_KEY=$(openssl rand -base64 48 | tr -d '\n/+=')
DJANGO_DEBUG=0
DJANGO_ALLOWED_HOSTS=$DOMAINE
DJANGO_CSRF_TRUSTED_ORIGINS=https://$DOMAINE
DJANGO_HSTS_SECONDS=3600
# Codes de connexion : « console » écrit le code dans le journal du serveur
# tant que Twilio (WhatsApp) n'est pas configuré.
OTP_FOURNISSEUR=console
OTP_NUMEROS_TEST=+237690000001=123456,+237690000002=123456
# TWILIO_ACCOUNT_SID=
# TWILIO_AUTH_TOKEN=
# TWILIO_WHATSAPP_FROM=
# GROQ_API_KEY=
# FCM_COMPTE_SERVICE=
FIN
  chmod 600 .env
fi

# 4. Démarrage (construction de l'image de l'API).
docker compose up -d --build

# 5. Sauvegarde chaque nuit à 3 h.
chmod +x sauvegarde.sh
echo "0 3 * * * root /opt/wanda/backend/deploiement/sauvegarde.sh >> /var/log/wanda-sauvegarde.log 2>&1" > /etc/cron.d/wanda-sauvegarde

. ./.env
echo "WANDA en ligne : https://$DOMAINE/api/"
