#!/bin/sh
# Prépare le dossier d'une release à déposer à la main sur github.com : exe, DLL et manifeste.ini.
# Usage : ./tools/preparer-version.sh [dossier des fichiers compilés, par défaut la racine du projet, où compile l'IDE]
set -e
cd "$(dirname "$0")/.."
SOURCE="${1:-.}"
EXE="$SOURCE/Fractales.exe"
DLL="$SOURCE/fractal_kernel.dll"
for F in "$EXE" "$DLL"; do
  if [ ! -f "$F" ]; then
    echo "Fichier introuvable : $F (compilez d'abord dans l'IDE, ou donnez le dossier : ./tools/preparer-version.sh bin)"
    exit 1
  fi
done
# Version de l'exe lue dans sa partie numérique (VS_FIXEDFILEINFO), celle que compare le programme, et non dans le
# texte FileVersion qui peut en différer ; la sortie de PowerShell se termine par CR LF, qu'on retire
VERSION=$(powershell -NoProfile -Command "\$v = (Get-Item -LiteralPath '$(cygpath -w "$EXE")').VersionInfo;
  '{0}.{1}.{2}.{3}' -f \$v.FileMajorPart, \$v.FileMinorPart, \$v.FileBuildPart, \$v.FilePrivatePart" |
  tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
if [ -z "$VERSION" ] || [ "$VERSION" = '0.0.0.0' ]; then
  echo "Impossible de lire la version de $EXE (partie numérique absente)."
  exit 1
fi
TARGET="publication/$VERSION"
if [ -e "$TARGET" ]; then
  echo "Le dossier $TARGET existe déjà : supprimez-le ou changez le numéro de version."
  exit 1
fi
# Date des fichiers, pour repérer d'un coup d'œil un exe ou une DLL périmés
echo "Version $VERSION, fichiers pris dans $SOURCE :"
echo "  Fractales.exe       $(date -r "$EXE" '+%Y-%m-%d %H:%M')"
echo "  fractal_kernel.dll  $(date -r "$DLL" '+%Y-%m-%d %H:%M')"
EXE_HASH=$(sha256sum "$EXE" | cut -d ' ' -f 1)
DLL_HASH=$(sha256sum "$DLL" | cut -d ' ' -f 1)
printf 'Notes (une ligne, facultatif) : '
read -r NOTES || NOTES=''
printf 'Version obligatoire ? (o/N) : '
read -r ANSWER || ANSWER=''
case "$ANSWER" in
  o|O|oui|Oui|OUI) MANDATORY=1 ;;
  *) MANDATORY=0 ;;
esac
mkdir -p "$TARGET"
cp "$EXE" "$TARGET/Fractales.exe"
cp "$DLL" "$TARGET/fractal_kernel.dll"
# UTF-8 sans BOM, fins de ligne CRLF
{
  printf '[Version]\r\n'
  printf 'Numero=%s\r\n' "$VERSION"
  printf 'Obligatoire=%s\r\n' "$MANDATORY"
  printf 'Notes=%s\r\n' "$NOTES"
  printf '\r\n'
  printf '[Fichiers]\r\n'
  printf 'Fractales.exe=%s\r\n' "$EXE_HASH"
  printf 'fractal_kernel.dll=%s\r\n' "$DLL_HASH"
} > "$TARGET/manifeste.ini"
echo "Version $VERSION prête dans $TARGET :"
echo "  Fractales.exe, fractal_kernel.dll, manifeste.ini"
echo
echo "Marche à suivre sur github.com (Jf7Dee/Fractales) :"
echo "  1. Releases > Draft a new release, avec l'étiquette de votre choix (v0.5, v0.6...)."
echo "  2. Déposer les trois fichiers de $TARGET."
echo "  3. DÉCOCHER « Set as a pre-release »."
echo "  4. Publier en « Set as the latest release »."
