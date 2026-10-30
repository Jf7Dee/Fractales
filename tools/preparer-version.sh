#!/bin/sh
# Prépare le dossier d'une release à déposer à la main sur github.com : exe, DLL et manifeste.ini.
# Usage : ./tools/preparer-version.sh [dossier des fichiers compilés, par défaut bin]
set -e
cd "$(dirname "$0")/.."
SOURCE="${1:-bin}"
EXE="$SOURCE/Fractales.exe"
DLL="$SOURCE/fractal_kernel.dll"
for F in "$EXE" "$DLL"; do
  if [ ! -f "$F" ]; then
    echo "Fichier introuvable : $F (compilez d'abord : ./build.sh app)"
    exit 1
  fi
done
# FileVersion de l'exe ; la sortie de PowerShell se termine par CR LF, qu'on retire
VERSION=$(powershell -NoProfile -Command "(Get-Item -LiteralPath '$(cygpath -w "$EXE")').VersionInfo.FileVersion" |
  tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
if [ -z "$VERSION" ]; then
  echo "Impossible de lire la version de $EXE (FileVersion vide)."
  exit 1
fi
TARGET="publication/$VERSION"
if [ -e "$TARGET" ]; then
  echo "Le dossier $TARGET existe déjà : supprimez-le ou changez le numéro de version."
  exit 1
fi
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
