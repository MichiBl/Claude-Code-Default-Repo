---
name: fix
description: Fast Lane für Bugfixes, kleine Refactorings und Doku-Updates — Ursache finden, Regressionstest, minimaler Fix. Nutze dies, wenn der User `/fix <beschreibung>` tippt oder eine klar umrissene Korrektur möchte ("behebe …", "korrigiere …"), die keine Requirements-/Architektur-Diskussion braucht. NICHT für neue Features oder Änderungen über viele Dateien (-> /feature) und nicht für reine Fragen.
---

# /fix — Fast Lane für kleine Änderungen

Du behebst eine klar umrissene Änderung **direkt** — ohne Requirements-Gate,
ohne Architektur-Gate, ohne Subagenten. Die Qualitätssicherung übernimmt der
Stop-Hook (`.claude/hooks/verify.sh`): Er lintet und testet automatisch am
Ende jeder Antwort. Baue **keine** eigenen Gates nach.

## Wann nutzen / wann nicht

**Nutzen:** Bugfix mit klarer Symptombeschreibung, kleines Refactoring
(1–3 Dateien), Doku-Update, Konfigurations-Korrektur.

**Nicht nutzen:** neues Feature, Refactor über viele Dateien, alles was
Schema + Backend + UI zugleich berührt (-> `/feature`), reine Fragen
(direkt beantworten). Reiner Typo/Einzeiler: einfach fixen, dieser Workflow
wäre schon Overhead.

## Workflow

1. **Ursache statt Symptom.** Lokalisiere die tatsächliche Ursache
   (Lesen/Grep, ggf. Reproduktion). Fixe nie nur die Stelle, an der der
   Fehler sichtbar wird, wenn die Ursache woanders liegt.
2. **Regressionstest zuerst (bei Bugs).** Schreibe einen Test, der den Bug
   reproduziert und **rot** ist. Ausnahmen: keine Test-Infrastruktur
   vorhanden oder nicht sinnvoll testbar (z. B. Doku, Kommentar, Config) —
   dann in einem Satz begründen, warum kein Test.
3. **Minimale Änderung.** Setze den kleinsten Fix um, der die Ursache
   behebt und den Test grün macht. Respektiere Konventionen und harte
   Grenzen aus `CLAUDE.md`. Keine Gelegenheits-Refactorings im selben Fix.
4. **Verifikation läuft automatisch.** `verify.sh` (Stop-Hook) führt
   Lint/Typecheck/Tests aus und blockt, bis alles grün ist — nicht manuell
   duplizieren.
5. **Commit.** Conventional Commit (`fix:` / `docs:` / `chore:` /
   `refactor:`). Kein Artefakt unter `docs/features/` — das ist der
   Pipeline vorbehalten.

## Eskalation

Stellt sich mittendrin heraus, dass die Änderung größer ist als gedacht
(neue Dependencies, Schema-Änderung, > ~3 Dateien Produktivcode, unklare
Anforderungen): **stoppe**, sag dem User warum, und schlage `/feature` vor.
