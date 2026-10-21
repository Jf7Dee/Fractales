#!/bin/sh
# Compilation en ligne de commande (Delphi 2010).  Usage : ./build.sh tests | app | smoke | bench
set -e
cd "$(dirname "$0")"
DCC="/c/Program Files (x86)/Embarcadero/RAD Studio/7.0/bin/dcc32.exe"
BDS='C:\Program Files (x86)\Embarcadero\RAD Studio\7.0'
mkdir -p bin dcu
case "$1" in
  tests)
    # DLL factice en version 1 (sans fk_compute_row_perturbed), puis en version 2
    (cd tests && "$DCC" -B -Q -N0../dcu -E../bin -DFAKE_ABI1 FakeKernel.dpr)
    mv -f bin/FakeKernel.dll bin/FakeKernelAbi1.dll
    (cd tests && "$DCC" -B -Q -N0../dcu -E../bin FakeKernel.dpr)
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
  bench)
    (cd bench && "$DCC" -B -Q -N0../dcu -E../bin FractalesBench.dpr)
    ./bin/FractalesBench.exe ;;
  *)
    echo "Usage : $0 tests|app|smoke|bench"
    exit 2 ;;
esac
