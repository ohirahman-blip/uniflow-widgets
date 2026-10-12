# UniFlow Widgets for macOS

Ein **separates macOS-Widget-Projekt** für die bestehende UniFlow-Webapp. Keine Änderungen am UniFlow-React-Projekt oder an Supabase sind erforderlich.

**Stand:** Prototyp / Quellprojekt, keine bereits signierte App. Die native macOS-Anwendung wurde in dieser Umgebung **nicht** mit Xcode gebaut oder auf einem Mac getestet. Die reine Swift-Terminlogik und Syntax sind geprüft.

## Was ist enthalten?

- **Kleines Widget:** laufende Veranstaltung mit Lehrperson, Raum und Ende. **30 Minuten vor der nächsten** Veranstaltung gewinnt der kommende Termin, selbst wenn gerade eine andere läuft. Wenn heute nichts mehr ansteht, werden **morgige Termine als Uhrzeit links + Titel rechts** angezeigt.
- **Breites macOS-Medium-Widget (~2:1):** Terminübersicht links, nächste Klausur mit Countdown in Kalendertagen rechts.
- **Zeitleiste:** Über kleine Pfeile vor-/zurückblättern (App Intents). **Freies Scrollen innerhalb von WidgetKit-Widgets ist nicht möglich.**
- **Benachrichtigungen:** Die kleine Begleit-App kann 30 Minuten vor jedem der nächsten 50 geplanten Termine lokale macOS-Benachrichtigungen planen – auch wenn zu diesem Zeitpunkt eine andere Veranstaltung läuft. Der Mac muss dafür Benachrichtigungen erlauben.
- **Design:** dezentes dunkles Design, weiche transparente Flächen und systemkompatibler Widget-Hintergrund; auf neueren macOS-Versionen berücksichtigt das System die Liquid-Glass-Erscheinung.
- **Supabase:** Bestehendes UniFlow-Konto über E-Mail-Einmalcode anmelden; `private_workspaces.payload` abrufen (RLS aktiv), den Workspace ohne Zugriffstoken in der App Group speichern. **Tokens liegen ausschließlich im macOS-Schlüsselbund** der Begleit-App.
- **DMG-Build:** GitHub Actions erzeugt ein **unsigniertes Test-DMG** mit GitHub-gehostetem macOS-Runner. Kein lokaler Xcode-Download erforderlich, um diesen Build auszulösen.

## Dateien

```text
project.yml                        XcodeGen-Projektdefinition
Shared/CalendarEngine.swift        Termine, Ausnahmen, Überschneidungen, Klausuren, Priorität
Shared/WidgetStorage.swift         Gemeinsamer Workspace-Snapshot per App Group
UniFlowWidgetsApp/                 Winzige Anmelde-/Sync-/Erinnerungs-App
Widgets/WidgetViews.swift          WidgetKit: quadratisch und medium/breit
Tests/CalendarEngineTests.swift    Swift-Tests für die Terminlogik
.github/workflows/macos-dmg.yml    Build und DMG als Workflow-Artefakt
```

## GitHub vorbereiten

1. Erstelle ein **neues Repository**, z. B. `uniflow-widgets`, unabhängig von deinem bisherigen Repository `uniflow`.
2. Lade den **entpackten** Inhalt dieses ZIPs hoch (Dateistruktur erhalten) und committe ihn auf `main`.
3. Öffne **Settings → Secrets and variables → Actions → New repository secret** und lege an:
   - `UNIFLOW_SUPABASE_URL` = derselbe Wert wie `VITE_SUPABASE_URL` deiner UniFlow-Webapp.
   - `UNIFLOW_SUPABASE_KEY` = derselbe **öffentliche Publishable Key** wie `VITE_SUPABASE_PUBLISHABLE_KEY`.
4. **Niemals** `service_role`, Private Keys, Benutzer-Tokens oder Supabase-Admin-Schlüssel eintragen! Die App benötigt nur öffentliche Verbindungswerte; RLS muss für die Tabelle `private_workspaces` aktiv bleiben.
5. Unter **Actions → Build UniFlow Widgets DMG → Run workflow** den Build starten. Unter **Artifacts** erscheint `UniFlow-Widgets-unsigned-DMG`, sofern das native Projekt auf GitHub erfolgreich baut.

⚠️ **Wichtig zu macOS / App Groups:** Ein unsigniertes DMG ist ein technisches Build-Artefakt, **keine garantiert funktionsfähige Widget-Installation**. WidgetKit-Erweiterungen und die gemeinsame App Group benötigen für zuverlässige Installation und gemeinsame Datenhaltung passende **Apple-Code-Signing-Entitlements und Provisioning Profiles** für **App und Extension**. Für eine problemlos an Dritte verteilte App sind **Developer-ID-Signatur und Notarisierung** empfohlen und in der Regel die Apple-Developer-Mitgliedschaft erforderlich. Diese Vorbereitungen können nicht durch Umbenennen der DMG umgangen werden.

## Auf dem Mac mit Xcode öffnen (optional)

Wer Xcode später installieren möchte, kann mit `brew install xcodegen` und `xcodegen generate` ein Xcode-Projekt erzeugen, beide Targets mit dem eigenen Team signieren und die App Group `group.com.uniflow.widgets` in den Developer-Einstellungen registrieren. Bundle-IDs und App Group bitte bei Bedarf für das eigene Team anpassen (in `project.yml`, `Shared/WidgetStorage.swift` und den beiden `.entitlements`).

## Wichtige Grenzen

- **Kein echtes Widget-Scrolling:** Apple erlaubt keine gewöhnliche frei scrollbare Liste. Die Pfeile blättern über `AppIntent` und bitten WidgetKit um Aktualisierung. WidgetKit bestimmt selbst, wann die Oberfläche tatsächlich neu gerendert wird.
- **Widget-Updates sind nicht permanent live:** Wenn die Begleit-App läuft, wird Supabase ungefähr alle 5 Minuten aktualisiert, inklusive lokaler Erinnerungsliste. Ist die App geschlossen, bleibt der zuletzt synchronisierte Stand sichtbar. **„Beim Anmelden starten“** kann aktiviert werden. Benachrichtigungen, die bereits geplant wurden, werden unabhängig von der App durch macOS ausgelöst.
- **Kein Supabase-Admin-Zugriff:** Alle Daten stammen aus der eigenen authentifizierten Tabelle. Die App kann nur die Daten lesen, die RLS für den eingeloggten Nutzer erlaubt.
- **Tests:** `./scripts/check-engine.sh` läuft mit Swift auf Linux und Mac, prüft aber **nicht** den nativen WidgetKit-Build. Für die komplette Prüfung sind der GitHub-Actions-Build und ein macOS-Gerät nötig.
- **MacOS-Anforderungen:** macOS 14+ (für interaktive Widget-Schaltflächen); systemweites Liquid Glass hängt von der macOS-Version und den Widget-Darstellungseinstellungen ab.

## Zeitpunkt-Logik

1. Steht ein Termin in **höchstens 30 Minuten** an, erscheint dieser als nächster Termin, auch wenn eine andere Veranstaltung noch läuft.
2. Sonst bleibt die **laufende Veranstaltung bis zu ihrem Ende** sichtbar.
3. Falls gerade nichts läuft, erscheint der nächste **heutige** Termin, mit In-X-Minuten-Hinweis (insbesondere bei <= 2 Stunden).
4. Sind für heute keine Termine mehr übrig, erscheinen **die morgigen** Termine oder „Morgen frei“.
5. Das breite Widget zeigt zusätzlich die **nächste Klausur** und einen Tages-Countdown.

**Hinweis:** GitHub Actions kann öffentliche Supabase-Werte ins App-Bundle einbetten. Der Publishable Key ist kein Geheimnis; die Sicherheit der Daten entsteht durch Authentifizierung und RLS.
