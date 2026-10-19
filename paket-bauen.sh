#!/bin/bash
# Baut das Einrichtungspaket für Kunden: bash paket-bauen.sh <version>   (z. B. v1.0.0)
# Der Fingerabdruck stammt immer aus dem hochgeladenen main – so bauen spätere signierte Updates darauf auf.
set -eu
cd "$(dirname "$0")"
vers=${1:?Version angeben, z. B. v1.0.0}
[[ "$vers" =~ ^v[0-9]+(\.[0-9]+)*$ ]] || { echo "Version muss wie v1.0.0 aussehen"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Erst committen – das Paket muss einen hochgeladenen Stand zeigen"; exit 1; }
git fetch -q origin main
commit=$(git rev-parse HEAD)
[ "$commit" = "$(git rev-parse origin/main)" ] || { echo "Lokaler Stand ist nicht hochgeladen (git push)"; exit 1; }
ziel="$(cd .. && pwd)/gg-sicherung-auslieferung"; rm -rf "$ziel/GG-Sicherung"; mkdir -p "$ziel/GG-Sicherung/vertrauen"
cp installieren.sh lib.sh LIES-MICH.md "$ziel/GG-Sicherung/"; cp vertrauen/allowed_signers "$ziel/GG-Sicherung/vertrauen/"
echo "$vers $commit" >"$ziel/GG-Sicherung/version.txt"
(cd "$ziel" && rm -f GG-Sicherung-Einrichtung.zip && zip -qr GG-Sicherung-Einrichtung.zip GG-Sicherung -x '*.DS_Store')
echo "Paket: $ziel/GG-Sicherung-Einrichtung.zip ($vers, $commit)"
