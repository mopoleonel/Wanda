#!/usr/bin/env bash
# Rejoue les migrations 005 → 013 et le scénario des services ménagers sur
# un PostgreSQL 15 jetable (Docker), sans toucher à la base Supabase.
#   bash supabase/tests/lancer.sh
# Prérequis : Docker démarré. Le conteneur est supprimé à la fin.
set -euo pipefail
cd "$(dirname "$0")/../.."
NOM=wanda-pg-test
docker rm -f $NOM >/dev/null 2>&1 || true
docker run -d --name $NOM -e POSTGRES_PASSWORD=test postgres:15-alpine >/dev/null
trap 'docker rm -f $NOM >/dev/null 2>&1 || true' EXIT
for i in $(seq 1 30); do docker exec $NOM pg_isready -U postgres >/dev/null 2>&1 && break; sleep 2; done
run() { docker exec -i $NOM psql -U postgres -v ON_ERROR_STOP=1 -q -X "$@"; }
run < supabase/tests/00_mini_supabase.sql
for f in supabase/sql/00[5-9]_*.sql supabase/sql/01[0-9]_*.sql; do
  run < "$f" >/dev/null && echo "OK  $f"
done
# Les scripts des services ménagers (008 et suivants) doivent être
# relançables. (005 à 007 sont antérieurs à la refonte : ne pas les relancer
# après 008, la vue de 005 relit l'ancienne colonne service_propose.)
for f in supabase/sql/00[89]_*.sql supabase/sql/01[0-9]_*.sql; do
  run < "$f" >/dev/null
done
echo "OK  008 et suivantes relancées"
run < supabase/tests/20_scenario_services.sql 2>&1 | grep -E "OK |ÉCHEC|ERROR|Scénario terminé"
