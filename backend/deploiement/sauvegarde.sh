#!/bin/sh
# Sauvegarde quotidienne (lancée par cron) : base + photos, 14 jours gardés.
set -eu
DOSSIER=/opt/wanda/sauvegardes
JOUR=$(date +%Y-%m-%d)
mkdir -p "$DOSSIER"
cd /opt/wanda/backend/deploiement
docker compose exec -T base pg_dump -U wanda -d wanda | gzip > "$DOSSIER/base-$JOUR.sql.gz"
docker run --rm -v wanda_photos:/photos:ro -v "$DOSSIER":/sortie alpine \
  tar czf "/sortie/photos-$JOUR.tar.gz" -C /photos .
find "$DOSSIER" -name '*.gz' -mtime +14 -delete
