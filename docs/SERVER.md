# Dedikerad server (headless Godot)

Servern är samma Godot-projekt som körs utan grafik. En process kör **många rum** samtidigt.

- Varje rum är en `RoomHost` (`net/room_host.gd`), samma klass som används när en spelare är host i spelet. Lobby, WebRTC, relä av inputs, hash-kontroll, frånkopplingar och kommandon finns bara på ett ställe.
- Under en match kör servern simuleringen med samma `MatchController` som spelet. Den kör bottarna, tar över platsen för spelare som lämnar och jämför klienternas state-hashar.
- Servern håller alltid `--min-open` publika rum öppna. När ett rum fylls eller startar öppnas ett nytt, upp till `--max-rooms`. Tomma rum stängs efter `--idle-close` sekunder.
- Alla rum syns i spelets publika rumslista ("Server" som host) via en enda Presence-post i lobbykanalen.
- **Rumsledare:** den första spelaren i ett serverrum styr läge, regler, bottar och start (som hosten gör i ett spelarrum). Om ledaren lämnar tar nästa spelare över. Efter en match går rummet tillbaka till lobbyn automatiskt efter 8 sekunder, eller tidigare om ledaren väljer det.

## Köra

```bash
# Lokalt med Godot 4.7
godot --headless --path . res://server/server_main.tscn -- --name "Block Pact EU" --max-rooms 20 --min-open 2

# Docker
docker build -t block-pact-server .
docker run --rm --restart unless-stopped block-pact-server --name "Block Pact EU" --max-rooms 20 --min-open 2
```

| Flagga | Standard | Betydelse |
|---|---|---|
| `--name` | `Server` | Namnet i rumslistan |
| `--max-rooms` | 20 | Max antal rum samtidigt |
| `--min-open` | 1 | Publika rum som alltid väntar på spelare |
| `--idle-close` | 60 | Sekunder innan ett tomt rum stängs |
| `--realtime-url` | – | Annan Realtime-server (lokala tester) |
| `--no-stun` | – | Ingen STUN (lokala tester) |
| `--verify-only` | – | Kontrollera bara highscores, inga rum |
| `--once` | – | Med `--verify-only`: avsluta när inget är kvar att kontrollera |
| `--supabase-url` | – | Annan Supabase-adress (lokala tester) |

Servern läser Supabase-uppgifterna från `config/backend_config.tres` precis som spelet. Den behöver bara utgående anslutningar: WebSocket till Supabase Realtime och UDP för WebRTC. Inga portar behöver öppnas för spelarna. Kör den nära spelarna (t.ex. en billig VPS i Stockholm eller Frankfurt) för låg ping.

Hosting som fungerar: valfri Linux-VPS (Hetzner, DigitalOcean, Scaleway …), Fly.io eller Railway med Dockerfilen. En liten maskin (1–2 vCPU) räcker för många rum, eftersom varje rum bara kör en lätt simulering på 60 Hz.

## Köra på din egen dator (Windows)

Enklast: öppna projektet i Godot, öppna `server/server_main.tscn` och tryck **F6** (Run Current Scene). Servern startar med standardinställningar (namnet "Server", ett öppet rum).

Eller dubbelklicka på `tools/run_server.bat` (servern får datorns namn). Om Godot inte hittas: sätt `GODOT` till sökvägen till `Godot_v4.7-stable_win64_console.exe`.

Öppna sedan spelet (t.ex. webbversionen i mobilen) → *Online*. Serverns rum syns i listan. Datorn måste vara igång, men inga portar behöver öppnas i routern.

## Testa lokalt utan internet

```bash
godot --headless -s res://tests/mock_realtime_server.gd -- --port 4000
godot --headless --path . res://server/server_main.tscn -- --realtime-url ws://127.0.0.1:4000/socket/websocket --no-stun
godot --headless --path . res://tests/online_test.tscn -- --role sclientA --dir /tmp/bp --realtime-url ws://127.0.0.1:4000/socket/websocket --no-stun
godot --headless --path . res://tests/online_test.tscn -- --role sclientB --dir /tmp/bp --realtime-url ws://127.0.0.1:4000/socket/websocket --no-stun
```

Båda klienterna hittar serverrummet i listan, den första blir ledare och startar, och klienterna skriver state-hashar som ska vara identiska.

## Highscore-verifiering

Servern kan också kontrollera highscores. Spelet laddar upp en replay av matchen, och servern spelar upp den headless och sparar bara poäng som den kan återskapa exakt (se *Verifierade highscores* i `docs/ARCHITECTURE.md`).

Verifieringen slås på när miljövariabeln `BLOCK_PACT_SERVICE_KEY` innehåller Supabase-projektets **service_role**-nyckel (Supabase → Project Settings → API keys). Nyckeln ger full åtkomst till databasen, så den får aldrig hamna i spelet eller i git.

- **Windows:** lägg nyckeln i `tools\service_key.local.txt` (git-ignorerad). `run_server.bat` läser den automatiskt.
- **Docker:** `docker run -e BLOCK_PACT_SERVICE_KEY=... block-pact-server`
- **Bara verifiering, inga rum:** `godot --headless --path . res://server/server_main.tscn -- --verify-only` (lägg till `--once` för att avsluta när kön är tom).
- **Utan egen server:** lägg nyckeln som repository secret `BLOCK_PACT_SERVICE_KEY` på GitHub (Settings → Secrets and variables → Actions). Då kör workflowen *Verify highscores* var 15:e minut. GitHub kör schemalagda jobb lite när det passar, så det kan dröja upp till en halvtimme innan poängen syns.

Utan någon verifierare skickas poängen fortfarande in, men de hamnar inte på topplistan förrän något kontrollerar dem.

## Nästa steg

- **TURN:** spelare bakom strikta NAT:ar kan behöva en TURN-server i `BackendConfig.ice_servers`.
