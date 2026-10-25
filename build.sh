#!/bin/sh
# Compilation en ligne de commande (Delphi 2010 ou Delphi récent, CE compris).
# Usage : ./build.sh tests | app | smoke | bench
# Compilateur : la variable DCC (et BDS, dossier d'installation) s'il est donné, sinon Delphi 2010, sinon le Delphi
# le plus récent de « Embarcadero\Studio ».
set -e
cd "$(dirname "$0")"
D2010_DIR='/c/Program Files (x86)/Embarcadero/RAD Studio/7.0'
STUDIO_DIR='/c/Program Files (x86)/Embarcadero/Studio'
# Delphi XE2 et suivants : unités préfixées (Vcl.Graphics, Winapi.Windows) ; le code garde les noms courts de D2010
UNIT_SCOPES='-NSSystem;Xml;Data;Datasnap;Web;Soap;Winapi;System.Win;Vcl;Vcl.Imaging'
NS=''
if [ -n "$DCC" ]; then
  if [ -z "$BDS" ]; then
    echo "BDS (dossier de Delphi, par exemple C:\\...\\Studio\\37.0) doit accompagner DCC."
    exit 3
  fi
  [ "$(dirname "$(dirname "$DCC")")" = "$D2010_DIR" ] || NS="$UNIT_SCOPES"
elif [ -x "$D2010_DIR/bin/dcc32.exe" ]; then
  DCC="$D2010_DIR/bin/dcc32.exe"
  BDS='C:\Program Files (x86)\Embarcadero\RAD Studio\7.0'
else
  VERSION=$(ls "$STUDIO_DIR" 2>/dev/null | sort -V | tail -n 1)
  if [ -z "$VERSION" ] || [ ! -x "$STUDIO_DIR/$VERSION/bin/dcc32.exe" ]; then
    echo "Aucun compilateur Delphi trouvé (dcc32.exe) : ni Delphi 2010 ni $STUDIO_DIR/<version>/bin."
    echo "Donnez son chemin : DCC=/c/.../bin/dcc32.exe BDS='C:\\...' ./build.sh $1"
    exit 3
  fi
  DCC="$STUDIO_DIR/$VERSION/bin/dcc32.exe"
  BDS="C:\\Program Files (x86)\\Embarcadero\\Studio\\$VERSION"
  NS="$UNIT_SCOPES"
fi
echo "Compilateur : $DCC"
mkdir -p bin dcu
case "$1" in
  tests)
    # DLL factice en version 1 (sans fk_compute_row_perturbed), en version 2 (sans fk_perturbation_supported), en
    # version 3 (sans fk_compute_row_perturbed2), puis en version 4
    (cd tests && "$DCC" -B -Q $NS -N0../dcu -E../bin -DFAKE_ABI1 FakeKernel.dpr)
    mv -f bin/FakeKernel.dll bin/FakeKernelAbi1.dll
    (cd tests && "$DCC" -B -Q $NS -N0../dcu -E../bin -DFAKE_ABI2 FakeKernel.dpr)
    mv -f bin/FakeKernel.dll bin/FakeKernelAbi2.dll
    (cd tests && "$DCC" -B -Q $NS -N0../dcu -E../bin -DFAKE_ABI3 FakeKernel.dpr)
    mv -f bin/FakeKernel.dll bin/FakeKernelAbi3.dll
    (cd tests && "$DCC" -B -Q $NS -N0../dcu -E../bin FakeKernel.dpr)
    (cd tests && "$DCC" -B -Q $NS -N0../dcu -E../bin -U"$BDS\source\dUnit\src" FractalesTests.dpr)
    ./bin/FractalesTests.exe ;;
  app)
    "$DCC" -B -Q $NS -N0dcu -Ebin Fractales.dpr ;;
  smoke)
    "$DCC" -B -Q $NS -N0dcu -Ebin Fractales.dpr
    rm -f bin/smoke.png bin/smoke.png.log
    set +e
    ./bin/Fractales.exe -smoketest bin/smoke.png
    code=$?
    cat bin/smoke.png.log
    exit $code ;;
  bench)
    (cd bench && "$DCC" -B -Q $NS -N0../dcu -E../bin FractalesBench.dpr)
    ./bin/FractalesBench.exe ;;
  *)
    echo "Usage : $0 tests|app|smoke|bench"
    exit 2 ;;
esac
