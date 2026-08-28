# SnapAssist

SnapAssist ergänzt das vorhandene macOS- oder Raycast-Snapping um eine Windows-artige Fensterauswahl und gekoppelte Trennlinien.

## Funktionen

- Erkennt linke/rechte Hälften, vertikale Drittel und 2x2-Eckviertel passiv.
- Zeigt für jede freie Layout-Zone die sichtbaren Fenster aller Displays an.
- Verwendet lokale ScreenCaptureKit-Vorschauen mit Icon-/Titel-Fallback.
- Unterstützt Maus, Tab, Pfeiltasten, Return und Escape.
- Justiert alle Fenster entlang einer gemeinsamen Trennlinie während des Resizes.
- Respektiert normale macOS-/Raycast-Fensterabstände.

## Voraussetzungen

- Apple-Silicon-Mac mit macOS 15 oder neuer.
- **Bedienungshilfen** sind zwingend erforderlich, damit SnapAssist Fenster lesen und positionieren kann.
- **Bildschirmaufnahme** ist optional und wird nur für lokale Fenstervorschauen verwendet. Ohne diese Berechtigung funktionieren Icon und Fenstertitel weiter.

SnapAssist verarbeitet keine Fensterinhalte außerhalb des Macs und enthält keine Netzwerk- oder Analysefunktion.

## Installation

1. `scripts/install-app.sh` ausführen; das Skript baut, signiert und installiert `/Applications/SnapAssist.app`.
2. App öffnen; sie erscheint ausschließlich in der Menüleiste.
3. Die angeforderte Bedienungshilfen-Berechtigung erteilen.
4. Optional Bildschirmaufnahme erlauben und SnapAssist danach neu starten.
5. Ein Fenster mit macOS oder Raycast an eine unterstützte Position snappen.

## Bedienung

- Fensterkarte anklicken oder mit den Pfeiltasten auswählen und Return drücken.
- Mit Tab zwischen freien Zielzonen wechseln.
- Mit Escape oder einem Klick außerhalb abbrechen.
- Bei vollständig belegten Layouts eine gemeinsame Fensterkante ziehen, um die gesamte Trennlinie anzupassen.

## Entwicklung

```bash
swift test
swift build
scripts/build-app.sh
scripts/install-app.sh
```

Ein abweichender Ausgabeordner kann gesetzt werden:

```bash
SNAPASSIST_OUTPUT_DIR=/vollständiger/pfad scripts/build-app.sh
```

Das Build-Skript verwendet automatisch die erste verfügbare Apple-Development-Code-Signing-Identität und fällt andernfalls auf eine Ad-hoc-Signatur zurück. Eine bestimmte Identität kann über `SNAPASSIST_CODE_SIGN_IDENTITY` vorgegeben werden.

## Bewusste Grenzen des MVP

- Es werden nur aktuell sichtbare Spaces berücksichtigt.
- Layout-Gruppen werden beim Neustart nicht gespeichert.
- Einzelne Apps können Accessibility-Größenänderungen ablehnen oder eigene Mindestgrößen erzwingen.
- Die installierte App wird mit dem lokal verfügbaren Apple-Development-Zertifikat signiert; ohne Zertifikat fällt der Build auf Ad-hoc zurück. Sie ist nicht für eine öffentliche Verteilung notarisiert.
