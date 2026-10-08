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

Servern läser Supabase-uppgifterna från `config/backend_config.tres` precis som spelet. Den behöver bara utgående anslutningar: WebSocket till Supabase Realtime och UDP för WebRTC. Inga portar behöver öppnas för spelarna. Kör den nära spelarna (t.ex. en billig VPS i Stockholm eller Frankfurt) för låg ping.

Hosting som fungerar: valfri Linux-VPS (Hetzner, DigitalOcean, Scaleway …), Fly.io eller Railway med Dockerfilen. En liten maskin (1–2 vCPU) räcker för många rum, eftersom varje rum bara kör en lätt simulering på 60 Hz.

## Testa lokalt utan internet

```bash
godot --headless -s res://tests/mock_realtime_server.gd -- --port 4000
godot --headless --path . res://server/server_main.tscn -- --realtime-url ws://127.0.0.1:4000/socket/websocket --no-stun
godot --headless --path . res://tests/online_test.tscn -- --role sclientA --dir /tmp/bp --realtime-url ws://127.0.0.1:4000/socket/websocket --no-stun
godot --headless --path . res://tests/online_test.tscn -- --role sclientB --dir /tmp/bp --realtime-url ws://127.0.0.1:4000/socket/websocket --no-stun
```

Båda klienterna hittar serverrummet i listan, den första blir ledare och startar, och klienterna skriver state-hashar som ska vara identiska.

## Nästa steg

- **Highscore-validering:** servern har hela input-loggen (`MatchController.input_log`) och kan spara poängen till Supabase med en service-nyckel i stället för att klienterna gör det. Då går det inte att fuska.
- **TURN:** spelare bakom strikta NAT:ar kan behöva en TURN-server i `BackendConfig.ice_servers`.
