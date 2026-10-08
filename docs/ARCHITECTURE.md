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
| `services/` | Autoloads: `GameSettings`, `Platform`, `ControlSchemes`, `Assets`, `AudioManager`, `Auth`, `Progress`, `Router`, `Net` | |
| `net/` | Online: `RealtimeClient`, `RoomHost` (host-logik för ett rum), `NetLockstep`, `NetProtocol`, `ChatFilter` | `core`, `scenes/match` |
| `server/` | Dedikerad headless-server som kör många `RoomHost` (se `docs/SERVER.md`) | `net` |
| `data/` | Spellägen, klossar, specialblock, powerups, bot-personligheter, achievements (`.tres`) och chattens ordlista | |
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
| Game over | Alla förlorar, högst poäng vinner (lag- och co-op-ranking per läge). *Knockout*: 3 liv, dina block försvinner när du förlorar ett, sista kvar vinner | `WinCondition`, `KnockoutWinCondition` |
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

## Specialblock och powerups

- **Specialblock** (`SpecialBlockType`, `data/specials/`) utlöses när raden de ligger i rensas: *x2/x3/x5* (multiplikator), *Bomb* (3×3), *Megabomb* (5×5), *Laser* (hela kolumnen), *Färg* (målar om 3×3 i ägarens färg), *Guld* (fast bonus till den som slutför raden) och *Powerup* (den som slutför raden får en powerup). Effekten påverkar bara rader som inte rensas, och körs innan raderna faller ihop (`MatchSimulation._apply_special_effects`).
- **Uppsättningar** (`SpecialSet`, `data/specials/sets/`): lobbyvalet *Specialblock* väljer lägets egna, `all` eller `off` via `GameModeConfig.special_preset`.
- **Powerups** (`PowerupType`, `data/powerups/`): man håller en åt gången och aktiverar med `InputCommand.USE_POWER` (V/F/Enter, R för vänster spelare, Enter för höger, Y på gamepad, blixtknappen på touch). *Bomb* (din kloss sprängs när den landar), *Slow-mo* (3× långsammare fall), *Dubbla poäng*, *Jordbävning* (blocken faller ner i hålen, hela rader rensas åt dig) och *Rush* (alla andra faller 3× snabbare).
- Allt går genom simuleringen och är deterministiskt, så det fungerar online. Presentationen lyssnar på `board_effect`, `powerup_changed` och `powerup_used`.
- Lobbyvalen (krock, specialblock, powerups) är en gemensam komponent, `scenes/menus/match_options.gd`, som både den lokala lobbyn och online-lobbyn använder.

## Läsbarhet, avatarer och touch

- Namnetiketter ovanför fallande klossar (din egen = "DU"), spår vid hårt drop, landningsdamm och röd pulserande kant när stapeln närmar sig toppen (`BoardView`). Utrop staplas i stället för att överlappa.
- Avatarer: genererade pixel-figurer i `ui/avatars/` (mappen anges i `GameAssets.avatar_dir`) som färgas i spelarens färg (`AvatarView`). Valet sparas lokalt och i `profiles.avatar`.
- Touch: svepgester är standard (`presentation/touch/gesture_controls.gd`). Sidosvep köar exakta kolumnsteg i `TouchInputSource` som släpps i tangentbordets ARR-takt. Knappar finns kvar som inställning.

## Online (peer-to-peer med host eller dedikerad server)

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
- **Flik i bakgrunden**: webbläsare kör inte spelet i en dold flik. `Platform.page_visibility_changed` kommer synkront från `visibilitychange`, så ett meddelande hinner ut innan spelet fryser. En klient lämnar då över sin plats (`MSG_AWAY`, `NetLockstep.go_away()`), och hosten matar den med tomma inputs från exakt nästa osända tick, precis som vid en frånkoppling. De andra spelar vidare. När fliken syns igen spelar klienten upp det den missade i snabbspolning (upp till 120 ticks per frame). När den är ikapp skickar den `MSG_BACK`, och hosten lämnar tillbaka platsen från en bestämd tick (`release()`, `MSG_SEAT_BACK`, `resume()`). Alla får exakt samma input-historik. Om hostens egen flik göms kan ingen fortsätta, men alla får se varför (`MSG_AWAY_INFO`). I serverrum finns det problemet inte.
- **Chatt och emotes** går som Realtime Broadcast i rummets kanal (`chat`, `emote`), helt vid sidan av lockstep. Både avsändare och mottagare kör `ChatFilter` (längd, markup, ordlista i `data/chat_blocklist.txt`). Det finns en enkel hastighetsbegränsning, och man kan tysta spelare lokalt. Samma kanal fungerar oavsett om hosten är en spelare eller en server.
- **Desync-skydd**: klienterna skickar en state-hash var 120:e tick och hosten jämför. Vid avvikelse visas en varning.
- **WebRTC på desktop/editor** kräver GDExtensionen `addons/webrtc` (webrtc-native 1.1.0, Windows/Linux/macOS). Webbläsare har WebRTC inbyggt, så addonen exkluderas från webbexporten.
- **NAT och TURN**: STUN (Google) används som standard. För spelare bakom strikta NAT:ar hämtar `TurnCredentials` (`net/turn_credentials.gd`) TURN-servrar med kortlivade inloggningsuppgifter från Edge Function `turn-credentials` (Cloudflare TURN). Den lägger in dem i `ice_servers`-listan, som spelet och servern redan använder, och förnyar dem innan de går ut. Om funktionen inte är uppsatt blir det ingen skillnad.
- **`net/room_host.gd` (`RoomHost`)**: all host-logik för ett rum. `Net` använder en när spelaren är host, och den dedikerade servern kör många (se `docs/SERVER.md`). `MatchController` pratar med en *lockstep-endpoint*, antingen `Net` (spelare) eller en `RoomHost` (server).
- **Rumsledare**: i serverrum styr den första spelaren läge, regler, bottar och start via `MSG_CMD`. I spelarrum är hosten alltid ledare.

Test utan internet: `tests/mock_realtime_server.gd` är en lokal Realtime-ersättare, och `tests/online_test.tscn` kör en host och en klient mot den. Båda spelar en match och skriver state-hashar som jämförs.

## Verifierade highscores

Klienten skickar aldrig in en poäng direkt. Den laddar upp en **replay** till tabellen `score_submissions`, och poängen hamnar på topplistan först när servern har kunnat återskapa den.

1. `MatchController.make_replay()` packar ihop `MatchSetup` och varje ticks inputs (lokal input-logg eller `NetLockstep.input_log` online). Det blir en `MatchReplay` (`core/match_replay.gd`) med en byte per plats och tick, deflate-komprimerad och base64-kodad. En minut spel tar ungefär 1 kB.
2. `Progress` laddar upp replayn med den poäng klienten fick och frågar sedan efter status några gånger, så att resultatskärmen kan visa "Nytt personbästa", "kunde inte återskapas" eller "kontrolleras senare".
3. `ScoreVerifier` (`server/score_verifier.gd`) hämtar väntande inskick med `claim_score_submissions()`. Den validerar setupen (bara lägen i `data/modes/`, bara lobbyns regelval, ingen egen brädstorlek, inte en botplats, rätt simuleringsversion) och spelar upp matchen headless med samma `MatchSimulation`. Uppspelningen sprids över flera frames så att rummen på samma server inte hackar.
4. Om matchen tar slut på exakt samma tick och platsen får exakt den poäng som skickades in, skriver `finish_score_submission()` poängen med **serverns** värden. Annars blir inskicket `rejected` (eller `unsupported` om spelversionen är äldre).

I databasen kan bara service-rollen skriva i `scores`, och den nyckeln finns bara hos servern (`BLOCK_PACT_SERVICE_KEY`). Samma replay kan bara skickas in en gång per användare, och antalet inskick per timme är begränsat.

Verifieraren körs i den dedikerade servern när nyckeln finns, eller fristående med `--verify-only --once`. GitHub-workflowen `verify-scores.yml` gör det var 15:e minut, så topplistan fungerar även utan en server som är igång. `MatchReplay.SIM_VERSION` följer `NetProtocol.VERSION`: när simuleringen ändras kan gamla replays inte längre återskapas, och de markeras som `unsupported`.

Achievements låses fortfarande upp på klienten. De syns bara för spelaren själv, så där finns inget att vinna på att fuska.

## Kända begränsningar och nästa steg

- Bottar på stora brädor: en bot kollar brädet igen precis innan den släpper klossen, om någon annan hunnit lägga en kloss sedan den planerade. Det höjde effektiviteten (rensade celler / lagda celler) för 8 svåra bottar från 38 % till 80 %, och de överlever ungefär 3 gånger längre. Normala bottar ligger kvar runt 65 % vid 8 spelare, eftersom de rör sig långsamt och oftare krockar med andras klossar. Spelplanens storlek och gravitation för många spelare behöver fortfarande speltestas med människor.
- Inloggning från desktop/editor använder en lokal callback-server på port 43117.
- Online: om hostens webbläsarflik ligger i bakgrunden står spelet still för alla tills den är tillbaka (spelarflikar hanteras, se ovan). Använd serverrum för att slippa det.
- Highscore-verifieringen stoppar påhittade poäng och manipulerade matcher, men inte en "perfekt" spelare som i själva verket är ett program som skapar giltiga inputs (TAS). Det skyddet kräver att matchen spelas på servern.
- Svepkontrollerna är testade med simulerade touch-händelser, inte på riktiga telefoner än.
