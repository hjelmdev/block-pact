# Arkitektur

```
         ┌──────────── Input ────────────┐
Keyboard / Joypad / Touch / Bot / (Network) → InputSource.gather(tick) → int-bitmask
                                                        │
                                   MatchController (Node, 60 Hz fixed tick)
                                                        │ step(inputs[])
                                         MatchSimulation (ren data, deterministisk)
                                                        │ signals
       ┌──────────────┬──────────────┬──────────────────┼──────────────┐
   BoardView     PlayerPanel    LineClearEffect      MatchAudio     ResultsPanel
 (BlockSkin)    (HUD, count-up)  (färg flyger till   (SoundLibrary)  (Progress → Supabase)
                                  poängbanken)
```

## Lager

| Mapp | Ansvar | Beroenden |
|---|---|---|
| `core/` | Simulering: `BoardState`, `ActivePiece`, `PieceBag`, `MatchSimulation`, regler (`ScoreRules`, `WinCondition`, `MatchRule`), datadefinitioner (`PieceShape`, `GameModeConfig`, `SpecialBlockType`) | Inga noder och ingen rendering |
| `input/` | `InputSource` och implementationerna för tangentbord, gamepad, touch, kombinerad och skriptad input | `core` |
| `ai/` | `BotBrain` (bedömning), `BotInputSource`, `BotProfile`, `BotTrainer` (GA), `BotLearning` (online-ES) | `core`, `input` |
| `presentation/` | `BoardView` med lager, HUD, effekter, ljudmappning och touch | Lyssnar bara på signaler |
| `scenes/` | Boot, menyer, match (`MatchController` och `match_screen`) | Allt ovan |
| `services/` | Autoloads: `GameSettings`, `Platform`, `ControlSchemes`, `Assets`, `AudioManager`, `Auth`, `Progress`, `Router` | |
| `net/` | `NetworkSession`, ett abstrakt gränssnitt för online som ännu inte är implementerat | |
| `data/` | Spellägen, klossar, specialblock och achievements (`.tres`) | |
| `skins/`, `audio/`, `ui/`, `config/` | Utbytbara assets och konfiguration | |

## Viktiga principer

- **Simulation ≠ presentation.** `MatchSimulation` vet inget om grafik, ljud eller tid. Animationer kan aldrig påverka spelet.
- **Determinism.** Seedad RNG (per spelare och för specialblock), bara heltal i spelreglerna och turordning som roterar varje tick. Samma `MatchSetup` och samma inputs per tick ger exakt samma match. Testet `same seed + inputs => identical state` bevakar det.
- **En kodväg för alla lägen.** Singleplayer, bottar, lokal multiplayer och framtida online skiljer sig bara i vilka `InputSource` som sitter på platserna.
- **Datadrivna spellägen.** Ett nytt läge är en ny `GameModeConfig.tres` (spelplanens storlek per antal spelare, gravitation, lag, poängmodell, vinstvillkor och specialblock). Nya regler (powerups, events) är `MatchRule`-resurser med hooks (`on_tick`, `on_piece_locked`, `on_lines_cleared` …).
- **Ägarskap separat från färg.** Cellerna lagrar `owner`, `special` och `piece_id`. Färg och mönster kommer från `PlayerPalette` via spelarens `color_index`.

## Designbeslut i MVP:n (lätta att ändra)

| Fråga | Beslut | Var |
|---|---|---|
| Kolliderar aktiva klossar? | Ja. Den som hård-droppar på en annan fallande kloss hovrar och låser när den landar | `GameModeConfig.active_piece_collision` |
| Game over | Alla förlorar, högst poäng vinner (lag- och co-op-ranking per läge) | `WinCondition` |
| Spawn | Egen kolumn per spelare. Om den är (nästan) begravd spawnar klossen på närmaste lediga plats, och det blir game over först när hela toppen är full | `MatchSimulation._find_spawn_x` |
| Poäng | 100 × (1/3/5/8) per rensning, fördelat efter ägd andel. +50 per rad till den som slutför raden. Combo +50/steg. Allt × level | `ScoreRules` |
| x5 | Modell A: multiplicerar ägarens andel av raden | `ScoreRules.special_mode` |
| Sekvens | 7-bag med egen seed per spelare (valbart gemensam) | `GameModeConfig.shared_sequence` |
| Spelplan | 1p 10×20 · 2p 16×24 · 3p 20×24 · 4p 24×26 · 6p 32×26 · 8p 40×28 | `data/modes/*.tres` |

## Online (nästa steg)

`net/network_session.gd` beskriver planen: deterministisk lockstep där hosten skickar `MatchSetup.to_dict()` (inklusive seed) och varje peer skickar sina input-bitmasks per tick. Fjärrplatserna använder en `NetworkInputSource` som returnerar `InputCommand.NOT_READY` tills ramen har kommit, och då väntar `MatchController` automatiskt. WebSocket (relay) och WebRTC (med Supabase Realtime som signalering) fungerar båda i webbläsare. `MatchController.input_log` sparar redan alla inputs för replays och serverside-validering av highscores.

## Kända begränsningar och nästa steg

- Bottarna är bra i 1–2 spelare men har svårare att samarbeta på stora brädor (6–8 spelare), där rader med enstaka hål blir kvar. Spelplanens storlek och gravitation för många spelare behöver speltestas.
- Powerups finns som utbyggnadspunkt (`MatchRule`) men inget innehåll ännu.
- Inloggning från desktop/editor använder en lokal callback-server på port 43117.
- Highscores skickas från klienten och kan fuskas. Se kommentaren i SQL-migrationen om validering via replay.
