#!/bin/bash
# Avvia il backend Roam e installa l'app sull'iPhone associato.
# Uso: ./start.sh            backend + build/installazione su iPhone
#      ./start.sh --no-ios   solo backend
# Variabili: ROAM_HOST (default IP Tailscale del Mac), ROAM_PORT (default 8000), ROAM_DEVICE (vedi ios/install.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
HOST="${ROAM_HOST:-100.90.158.14}"
PORT="${ROAM_PORT:-8000}"
LOG="$ROOT/backend/server.log"
START_TIMEOUT="${ROAM_START_TIMEOUT:-120}"
if ! [[ "$START_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  echo "✗ ROAM_START_TIMEOUT deve essere un numero intero positivo." >&2
  exit 1
fi

cd "$ROOT/backend"
if [ ! -x .venv/bin/python ]; then
  echo "→ Creo l'ambiente Python…"
  python3 -m venv .venv
  .venv/bin/pip install -q -r requirements.txt
fi

echo "→ Test del backend…"
if ! .venv/bin/python -m pytest -q >/tmp/roam-pytest.log 2>&1; then
  echo "✗ Test non superati, backend non riavviato:" >&2
  tail -30 /tmp/roam-pytest.log >&2
  exit 1
fi
tail -1 /tmp/roam-pytest.log

# Ferma un backend già in ascolto sulla porta, così parte con il codice aggiornato.
if PIDS=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN); then
  echo "→ Fermo il backend precedente ($PIDS)…"
  kill $PIDS
  for _ in {1..20}; do lsof -tiTCP:"$PORT" -sTCP:LISTEN >/dev/null || break; sleep 0.25; done
fi

echo "→ Avvio il backend su http://$HOST:$PORT (log: backend/server.log)…"
# Il runtime standard evita il caricamento dei componenti nativi opzionali.
# Il controllo locale ignora i proxy HTTP configurati sul Mac.
nohup .venv/bin/python -u -c '
print("Caricamento del server…", flush=True)
import uvicorn
print("Avvio del servizio…", flush=True)
import sys
uvicorn.run("main:app", host=sys.argv[1], port=int(sys.argv[2]), loop="asyncio", http="h11", ws="none", access_log=False)
' "$HOST" "$PORT" >"$LOG" 2>&1 </dev/null &
BACKEND_PID=$!
DEADLINE=$((SECONDS + START_TIMEOUT))
NEXT_NOTICE=$((SECONDS + 10))
READY=false
while (( SECONDS < DEADLINE )); do
  if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
    wait "$BACKEND_PID" || true
    echo "✗ Il processo del backend si è interrotto. Dettagli:" >&2
    tail -30 "$LOG" >&2
    exit 1
  fi
  if curl --noproxy '*' -fsS --connect-timeout 1 --max-time 1 "http://$HOST:$PORT/health" >/dev/null 2>&1; then
    READY=true
    break
  fi
  if (( SECONDS >= NEXT_NOTICE )); then
    echo "→ Backend ancora in avvio…"
    tail -2 "$LOG"
    NEXT_NOTICE=$((SECONDS + 10))
  fi
  sleep 0.5
done
if [ "$READY" != true ]; then
  echo "✗ Avvio non completato entro ${START_TIMEOUT}s (PID $BACKEND_PID). Ultime righe del log:" >&2
  tail -30 "$LOG" >&2
  kill "$BACKEND_PID" 2>/dev/null || true
  wait "$BACKEND_PID" 2>/dev/null || true
  exit 1
fi
echo "✓ Backend attivo (PID $BACKEND_PID)"

if [ "${1:-}" != "--no-ios" ]; then
  echo "→ Build e installazione sull'iPhone…"
  if "$ROOT/ios/install.sh" >"$ROOT/ios/install.log" 2>&1; then
    echo "✓ App installata e avviata"
  elif grep -q "App installed" "$ROOT/ios/install.log"; then
    echo "⚠ App installata ma non avviata: sblocca l'iPhone e aprila a mano."
  else
    echo "✗ Build o installazione non riuscita (log: ios/install.log):" >&2
    grep -E "error:|ERROR" "$ROOT/ios/install.log" | head -20 >&2 || tail -20 "$ROOT/ios/install.log" >&2
    exit 1
  fi
fi
