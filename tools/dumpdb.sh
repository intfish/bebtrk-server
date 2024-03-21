#!/usr/bin/env bash
set -e

[ -x "$(command -v docker-compose)" ] && dco='docker-compose' || dco='docker compose'

source .env
DST_FILE="snapshot-${POSTGRES_DB:-bebtrk}-$(date +%Y%m%d%H%M).sql.gz"
CONTAINER=$($dco ps -q database)

echo "[+] Dumping database '${POSTGRES_DB:-bebtrk}' to ${DST_FILE}..."
docker exec -i -u postgres "$CONTAINER" pg_dump -U "${POSTGRES_USER:-bebtrk}" -d "${POSTGRES_DB:-bebtrk}" | gzip > "$DST_FILE"
echo "[+] Finished: $DST_FILE"
