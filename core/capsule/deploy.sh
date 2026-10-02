#!/usr/bin/env bash
set -euo pipefail

IMAGE="ubuntu:24.04"
HOST_PORT=8080

# Запускає контейнер, ставить утиліти і стартує HTTP-сервер.
# Усі аргументи після імені передаються в docker run (наприклад -p 8080:80).
start_box() {
  local name="$1"; shift
  echo ">>> Запуск $name"
  docker run -d "$@" --name "$name" "$IMAGE" sleep infinity >/dev/null
  docker exec "$name" bash -c '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends python3 curl git procps iproute2
  ' >/dev/null
  docker exec -d "$name" python3 -m http.server 80
}

# --- Ідемпотентність: прибрати все, що могло лишитися від минулого запуску ---
docker rm -f devbox devbox2 devbox3 >/dev/null 2>&1 || true

# --- Кроки 2-5: ізоляція процесів (спостереження) ---
docker run -d --name devbox "$IMAGE" sleep infinity >/dev/null
echo "PID 1 у контейнері: $(docker exec devbox sed -n 's/^Pid:[[:space:]]*//p' /proc/1/status)"
echo "Процесів у контейнері: $(docker exec devbox sh -c 'ls -d /proc/[0-9]* | wc -l')"
echo "Процесів на хості:     $(ls -d /proc/[0-9]* | wc -l)"
docker rm -f devbox >/dev/null

# --- Крок 6: з пробросом порту ---
start_box devbox2 -p "${HOST_PORT}:80"
ok=0
for _ in $(seq 1 20); do
  if curl -fsS -o /dev/null "http://localhost:${HOST_PORT}/"; then ok=1; break; fi
  sleep 1
done
if [ "$ok" -ne 1 ]; then
  echo "ПОМИЛКА: порт ${HOST_PORT} недоступний" >&2
  exit 1
fi
curl -sI "http://localhost:${HOST_PORT}/" | head -n 1
docker rm -f devbox2 >/dev/null

# --- Крок 7: без -p, звернення з хоста має впасти ---
start_box devbox3
if curl -sS --max-time 3 -o /dev/null "http://localhost:${HOST_PORT}/" 2>/dev/null; then
  echo "ПОМИЛКА: порт доступний без -p" >&2
  exit 1
else
  echo "OK: без -p з'єднання відхилено (curl exit $?)"
fi

echo ">>> Готово. Контейнер devbox3 працює (без проброшеного порту)."