#!/bin/sh
# Compilation en ligne de commande (Delphi 2010).  Usage : ./build.sh tests | app | smoke
set -e
cd "$(dirname "$0")"
DCC="/c/Program Files (x86)/Embarcadero/RAD Studio/7.0/bin/dcc32.exe"
BDS='C:\Program Files (x86)\Embarcadero\RAD Studio\7.0'
mkdir -p bin dcu
case "$1" in
  tests)
    (cd tests && "$DCC" -B -Q -N0../dcu -E../bin -U"$BDS\source\dUnit\src" FractalesTests.dpr)
    ./bin/FractalesTests.exe ;;
  app)
    "$DCC" -B -Q -N0dcu -Ebin Fractales.dpr ;;
  smoke)
    "$DCC" -B -Q -N0dcu -Ebin Fractales.dpr
    rm -f bin/smoke.png bin/smoke.png.log
    set +e
    ./bin/Fractales.exe -smoketest bin/smoke.png
    code=$?
    cat bin/smoke.png.log
    exit $code ;;
  *)
    echo "Usage : $0 tests|app|smoke"
    exit 2 ;;
esac
