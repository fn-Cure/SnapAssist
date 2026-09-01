# SnapAssist

SnapAssist ergänzt das vorhandene macOS- oder Raycast-Snapping um eine Windows-artige Fensterauswahl und gekoppelte Trennlinien.

## Funktionen

- Erkennt linke/rechte Hälften, vertikale Drittel und 2x2-Eckviertel passiv.
- Zeigt für jede freie Layout-Zone die sichtbaren Fenster aller Displays an.
- Verwendet lokale ScreenCaptureKit-Vorschauen mit Icon-/Titel-Fallback.
- Unterstützt Maus, Tab, Pfeiltasten, Return und Escape.
- Justiert alle Fenster entlang einer gemeinsamen Trennlinie während des Resizes.
- Respektiert normale macOS-/Raycast-Fensterabstände.
- Führt beim ersten Start durch Berechtigungen und Bedienung; Einstellungen und Diagnose bleiben jederzeit über die Menüleiste erreichbar.
- Verifiziert Fensterplatzierungen mit begrenztem Read-back-Polling und setzt partielle Änderungen bei Fehlern zurück.

## Voraussetzungen

- Mac mit Apple Silicon oder Intel-Prozessor und macOS 15 oder neuer.
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
- Gekoppeltes Resizing ist in Version 0.3 bewusst **experimentell und standardmäßig deaktiviert**. Es kann im Menü eingeschaltet werden und propagiert erst nach dem Loslassen der Maus.

## Entwicklung

Das Package verwendet Swift 6.3 im Swift-6-Sprachmodus. AppKit-, Accessibility- und ScreenCaptureKit-Zugriffe sind am Main Actor isoliert; die reinen Layoutmodelle bleiben in `SnapAssistCore`.

```bash
swift test
swift build
scripts/build-app.sh
scripts/install-app.sh
scripts/build-fixture-app.sh
```

Ein abweichender Ausgabeordner kann gesetzt werden:

```bash
SNAPASSIST_OUTPUT_DIR=/vollständiger/pfad scripts/build-app.sh
```

Das Build-Skript verwendet automatisch die erste verfügbare Apple-Development-Code-Signing-Identität. Eine bestimmte Identität kann über `SNAPASSIST_CODE_SIGN_IDENTITY` vorgegeben werden. Ohne stabile Identität bricht der Build ab; nur eine explizite Entwicklungsfreigabe mit `SNAPASSIST_ALLOW_ADHOC=1` erlaubt eine Ad-hoc-Signatur.

Der Standard-Build ist Universal (`arm64` und `x86_64`) und aktiviert Hardened Runtime. Abweichende Architekturen können über `SNAPASSIST_ARCHS` gesetzt werden.

## Öffentliche Distribution

Die vollständige App benötigt systemweite Accessibility-APIs und kann deshalb nicht in der für neue Mac-App-Store-Apps verpflichtenden App Sandbox ausgeführt werden. Der unterstützte Veröffentlichungskanal ist eine direkt verteilte, notarisierte Developer-ID-Version. Details und Apple-Quellen stehen im [Distributionsaudit](docs/research/2026-08-31-app-store-distribution.md).

Für einen öffentlichen Release werden ein `Developer ID Application`-Zertifikat und ein gespeichertes Notary-Profil benötigt:

```bash
SNAPASSIST_NOTARY_PROFILE=SnapAssist-Notary scripts/package-release.sh
scripts/verify-release.sh outputs/release/SnapAssist.dmg
```

Ohne Developer-ID-Zertifikat oder Notary-Profil erzeugt das Release-Skript bewusst kein öffentliches Artefakt. Die lokale Datenschutzbeschreibung liegt unter [docs/privacy-policy.md](docs/privacy-policy.md); vor Veröffentlichung müssen ein öffentlicher Supportkontakt, ein Updateweg und eine stabile HTTPS-Version ergänzt werden.

## Integration Fixture

`SnapAssistFixture` erzeugt kontrollierte gleichnamige Fenster, Mindestgrößen, Modaldialoge, Titelwechsel und eine kurz blockierende UI. Sie dient ausschließlich der lokalen AX-/Picker-Abnahme und wird nicht in `SnapAssist.app` gebündelt.

## Bewusste Grenzen

- Es werden nur aktuell sichtbare Spaces berücksichtigt.
- Layout-Gruppen werden beim Neustart nicht gespeichert.
- Einzelne Apps können Accessibility-Größenänderungen ablehnen oder eigene Mindestgrößen erzwingen.
- Entwicklungsinstallationen werden mit dem lokal verfügbaren Apple-Development-Zertifikat signiert. Eine Ad-hoc-Signatur ist nur nach expliziter Freigabe möglich. Öffentliche Builds werden ohne Developer-ID-Zertifikat und erfolgreiche Notarisierung nicht erzeugt.
