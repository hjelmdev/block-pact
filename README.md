# Block Pact

Tetris-inspirerat spel på en gemensam spelplan: *din färg = dina block = dina poäng*.
Godot 4.7, GL Compatibility, byggt för webbläsare (desktop och mobil).

## Kom igång

1. Öppna mappen `block-pact` i Godot 4.7 och tryck **F5**.
2. Spela **Solo**, **Spela mot bottar** eller **Lokal multiplayer** (två spelare på samma tangentbord, eller gamepads).
3. Spelet fungerar utan konto, då som gäst. Inloggning aktiveras när Supabase är konfigurerat (se nedan).

### Kontroller

| | Tangentbord (solo) | Vänster spelare | Höger spelare | Gamepad |
|---|---|---|---|---|
| Flytta | ← → / A D | A D | ← → | D-pad / spak |
| Mjukt fall | ↓ / S | S | ↓ | D-pad ned |
| Hårt fall | Mellanslag | W | ↑ | D-pad upp |
| Rotera | ↑ X W / Z Ctrl Q | E / Q | . / , | A / B |
| Hold | C Shift E | Shift | - | LB/RB |
| Powerup | V F Enter | R | Enter | Y |
| Paus | Esc / P | | | Start |

På mobil och surfplatta styr du med **svep** (standard):

| Gest | Gör |
|---|---|
| Dra åt sidan | Klossen följer fingret, en kolumn per ruta (aldrig snabbare än tangentbordets auto-repeat) |
| Dra nedåt och håll | Mjukt fall |
| Snabbt svep uppåt | Hårt drop |
| Tryck | Rotera medurs |
| Tryck med två fingrar | Rotera moturs |
| Håll stilla | Hold (spara klossen) |
| Blixtknappen | Använd powerup |

Under *Inställningar → Touchstil* kan du byta till knappar på skärmen, och justera svepavståndet per kolumn.

## Webb-export

1. *Editor → Manage Export Templates*: installera mallarna för 4.7.
2. *Project → Export → Web* (förinställningen finns redan): exportera till `build/web/`.
3. Testa lokalt med Godots "Run in browser" eller valfri statisk server. Thread support är avstängt, så det behövs inga COOP/COEP-headers och spelet kan hostas var som helst (t.ex. Netlify, Vercel, GitHub Pages eller itch.io).

### GitHub Pages

`.github/workflows/deploy-web.yml` bygger webbexporten och publicerar den vid varje push till `main`. Spelet hamnar på https://hjelmdev.github.io/block-pact/. Workflowen kan också köras manuellt under *Actions*. Engångsinställning: *Settings → Pages → Source: GitHub Actions*.

## Byta grafik, ljud och tema (utan kod)

Allt utseende går via **`res://config/game_assets.tres`**:

| Vad | Resurs | Hur du byter |
|---|---|---|
| Block, glow, ghost, specialikoner | `skins/default/default_block_skin.tres` (`BlockSkin`) | Byt texturer eller shader i inspektorn, eller gör en ny skin och peka om `game_assets.tres` |
| Spelarfärger och färgblindmönster | `skins/default/default_palette.tres` (`PlayerPalette`) | Ändra färger och mönster per spelarplats |
| Ljud och musik | `audio/default_sound_library.tres` (`SoundLibrary`) | Byt fil per event (`lock`, `line_4`, `special_x` …), lägg till varianter och justera volym |
| UI-tema | `ui/theme/main_theme.tres` | Vanligt Godot-tema, så du kan lägga till en pixelfont här |
| Ikoner (touch och paus) | `game_assets.tres → icons` | Peka om till nya texturer |

Blocktexturen är en *gråskalekarta* som shadern färgar med spelarens färg: 0 = mörk kant, 0,5 = spelarfärgen, 1 = highlight. Om du hellre vill använda färdigfärgade sprites stänger du av `tint_with_shader` i skinnet.

Platshållarna genereras av `tools/generate_assets.py` och `tools/build_asset_resources.gd`. Du behöver aldrig köra dem igen om du byter till egna assets.

## Specialblock och powerups

I lobbyn väljer du *Specialblock* (lägets egna, alla eller av) och *Powerups*. Specialblock utlöses när raden de ligger i rensas: x2/x3/x5, bomb, megabomb, laser, färg (stjäl block), guld och powerup-block. Powerups aktiveras med **V** (eller F/Enter), **R** för vänster spelare, **Enter** för höger spelare, **Y** på gamepad och blixtknappen på touch. Nya typer läggs till som `.tres` i `data/specials/` och `data/powerups/`.

## Bottar som lär sig

Varje bot har en **svårighetsgrad** (hur bra och snabbt den spelar) och en **personlighet** (vad den vill): Byggare, Tjuv, Girig eller Sabotör. Båda väljs i lobbyn. Personligheterna är `.tres`-filer i `data/bots/`, så du kan justera dem eller lägga till nya utan kod.

- `ai/profiles/{easy,normal,hard,adaptive}.tres`: vikter (hur boten bedömer en placering) och skill (reaktionstid, tempo och misstag).
- **Träna nya vikter** med en genetisk algoritm via självspel på den gemensamma spelplanen:
  `godot --headless --path . -s res://tools/train_bots.gd -- --generations 10 --population 10`
  Det går också via *Inställningar → Bot trainer (dev)* i debug-läge på desktop. Resultatet sparas i `user://bots/` och används då före de levererade profilerna.
- **Adaptive-boten** lär sig under spelets gång: varje match provar den en lite muterad variant och behåller den om den presterade bättre (`ai/bot_learning.gd`).

## Online-multiplayer

*Online* i huvudmenyn: skapa ett publikt eller privat rum, dela rumskoden eller gå med i ett publikt rum från listan. Hosten väljer läge, lägger till bottar och startar. Lobbyn och signaleringen går via **Supabase Realtime** och själva spelet peer-to-peer via **WebRTC** (se `docs/ARCHITECTURE.md`).

- I Supabase: *Project Settings → Realtime* ska ha **"Allow public access"** påslaget (standard). Inga tabeller behövs.
- I editorn/desktop används `addons/webrtc`. I webbläsaren är WebRTC inbyggt.
- Lokalt test utan internet, i tre terminaler:
  `godot --headless -s res://tests/mock_realtime_server.gd -- --port 4000`
  `godot --path . res://tests/online_test.tscn -- --role host --dir /tmp/bp --realtime-url ws://127.0.0.1:4000/socket/websocket --no-stun`
  samma kommando med `--role client`.
- Spela mot dig själv: starta två fönster med `--realtime-url` som ovan, eller öppna spelet i två webbläsarflikar.

## Konton (Supabase)

Inget är uppsatt ännu. Spelet startar och fungerar som gäst. Gör så här när det är dags:

1. Skapa ett Supabase-projekt och kör migrationerna i `supabase/migrations/` i nummerordning i SQL-editorn.
2. *Authentication → Providers*: aktivera **Google** och **Discord** (client id/secret från respektive utvecklarportal).
3. *Authentication → URL Configuration*: lägg in webbadressen där spelet hostas och `http://localhost:43117/` (för inloggning från editorn/desktop) under Redirect URLs.
4. Skapa `config/backend_config.local.tres` (git-ignorerad, typ `BackendConfig`) eller fyll i `config/backend_config.tres`: `supabase_url` och `supabase_anon_key` (den publika nyckeln).

Gäster kan spela allt och se topplistan, men highscore, achievements och nickname-profil sparas bara för inloggade. Topplistan delas upp per läge och regler: *Klassiskt* och *Party* (specialblock eller powerups påslagna).

## Tester

- Simulering, poäng, determinism och bottar:
  `godot --headless --path . -s res://tests/run_tests.gd`
- Visuell rökprovning med skärmdumpar (kräver en skärm eller `xvfb-run`):
  `godot --path . res://tests/visual_test.tscn -- --out /tmp/shots`

Se `docs/ARCHITECTURE.md` för hur delarna hänger ihop.
