#!/bin/sh
# Hook PostToolUse : formate le fichier Swift qui vient d'être édité.
# swift-format tourne en local (contrairement à swiftlint qui exige Xcode complet),
# donc on formate au fil de l'eau au lieu d'attendre le rouge CI (cf. CLAUDE.md §5).
#
# Claude Code passe le JSON de l'appel outil sur stdin ; on en extrait tool_input.file_path.
file=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)

case "$file" in
  *.swift)
    if command -v swift-format >/dev/null 2>&1 && [ -f "$file" ]; then
      swift-format format -i "$file" 2>/dev/null
    fi
    ;;
esac

exit 0
