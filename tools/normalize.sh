#!/bin/sh
# Normalise les sources Delphi 2010 : UTF-8 avec BOM pour .pas/.dpr, fins de ligne CRLF pour tout.
for f in "$@"; do
  case "$f" in
    *.pas|*.dpr)
      if [ "$(head -c3 "$f" | od -An -tx1 | tr -d ' \n')" != "efbbbf" ]; then
        printf '\357\273\277' | cat - "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      fi ;;
  esac
  unix2dos -q "$f"
done
