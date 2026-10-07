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
| Kolliderar aktiva klossar? | Nej som standard (val i lobbyn). Låser en kloss där en annan fallande kloss är, lyfts den fallande klossen upp | `GameModeConfig.active_piece_collision`, `MatchSetup.rule_overrides` |
| Game over | Alla förlorar, högst poäng vinner (lag- och co-op-ranking per läge) | `WinCondition` |
| Spawn | Egen kolumn per spelare, utspridda över mittersta 60 % av brädet (`spawn_spread`) så att spelarna hamnar nära varandra. Om den är (nästan) begravd spawnar klossen på närmaste lediga plats, och det blir game over först när hela toppen är full | `MatchSimulation._find_spawn_x` |
| Poäng | 100 × (1/3/5/8) per rensning, fördelat efter ägd andel. +50 per rad till den som slutför raden. Combo +50/steg. Allt × level | `ScoreRules` |
| x5 | Modell A: multiplicerar ägarens andel av raden | `ScoreRules.special_mode` |
| Sekvens | 7-bag med egen seed per spelare (valbart gemensam) | `GameModeConfig.shared_sequence` |
| Spelplan | 1p 10×20 · 2p 16×24 · 3p 20×24 · 4p 24×26 · 6p 32×26 · 8p 40×28 | `data/modes/*.tres` |

## Konfliktkänsla ("battle")

- **Radmätare** bredvid varje rad i ledarens färg. Rader som är nästan fulla pulserar (`BoardView.draw_meters_layer`, inställningar i `BlockSkin`).
- **Utrop på brädet**: STULEN, flera rader, x5 och combo, plus en banner och ett ljud när någon tar ledningen (`presentation/effects/board_callouts.gd`).
- **Placering (#1–#8)** och en guldram för ledaren i spelarpanelerna.
- **Bot-personligheter** (`data/bots/*.tres`, `BotPersonality`) läggs ovanpå svårighetsgraden: *Byggare*, *Tjuv* (avslutar andras rader, `w_steal`), *Girig* (egna rader och x5) och *Sabotör* (täcker luckor i andras rader, `w_sabotage`).

## Online (peer-to-peer med host)

```
 Supabase Realtime (WebSocket)                 WebRTC (datakanaler, stjärna)
 ┌──────────────────────────────┐             ┌──────────── Host (peer 1) ────────────┐
 │ bp-lobbies  – Presence:       │             │  kör simuleringen + bottarna          │
 │   publika rum (kod, läge, n)  │             │  reläar alla inputs till alla         │
 │ bp-room-KOD – Presence: vem   │   signal    │  jämför state-hash var 120:e tick     │
 │   Broadcast: hello/welcome,   │ ──────────► └──────▲───────────────▲────────────────┘
 │   sdp, ice (WebRTC-signaler)  │                    │ input-bits    │
 └──────────────────────────────┘             Klient (peer 2)    Klient (peer 3)
```

- **`services/net_service.gd` (autoload `Net`)**: rum, lobby och signalering. Hosten är auktoritet för lobbyn (läge, platser, bottar och krock-inställningen) och skickar `MSG_START` med `MatchSetup.to_dict()` inklusive seed.
- **`net/realtime_client.gd`**: en minimal Supabase Realtime-klient (Phoenix-protokoll 1.0.0) med Broadcast och Presence. Den kräver inga tabeller.
- **`net/net_lockstep.gd`**: deterministisk lockstep. Lokala platser samplas `delay` ticks i förväg (3–12 ticks, baserat på ping), och simuleringen tar tick T först när alla platsers input för T finns. Bottar körs bara hos hosten och deras inputs skickas som en människas.
- **Frånkoppling**: lämnar en klient tar hosten över platsen med tomma inputs från exakt den tick den senast reläade, så matchen fortsätter. Lämnar hosten avslutas matchen för alla.
- **Desync-skydd**: klienterna skickar en state-hash var 120:e tick och hosten jämför. Vid avvikelse visas en varning.
- **WebRTC på desktop/editor** kräver GDExtensionen `addons/webrtc` (webrtc-native 1.1.0, Windows/Linux/macOS). Webbläsare har WebRTC inbyggt, så addonen exkluderas från webbexporten.
- **NAT**: STUN (Google) används som standard. Spelare bakom strikta NAT:ar kan behöva en TURN-server, som läggs till i `BackendConfig.ice_servers`.
- **Dedikerad server senare**: samma meddelanden (`NetProtocol`) kan implementeras av en headless Godot-server som tar host-rollen (peer 1). Då behövs ingen spelare som host, och servern kan validera highscores genom att spela upp input-loggen.

Test utan internet: `tests/mock_realtime_server.gd` är en lokal Realtime-ersättare, och `tests/online_test.tscn` kör en host och en klient mot den. Båda spelar en match och skriver state-hashar som jämförs.

## Kända begränsningar och nästa steg

- Bottarna är bra i 1–2 spelare men har svårare att samarbeta på stora brädor (6–8 spelare), där rader med enstaka hål blir kvar. Spelplanens storlek och gravitation för många spelare behöver speltestas.
- Powerups finns som utbyggnadspunkt (`MatchRule`) men inget innehåll ännu.
- Inloggning från desktop/editor använder en lokal callback-server på port 43117.
- Online: om hostens webbläsarflik ligger i bakgrunden pausar webbläsaren spelet och alla får vänta. Det finns ingen TURN-server ännu.
- Highscores skickas från klienten och kan fuskas. Se kommentaren i SQL-migrationen om validering via replay.
