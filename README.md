# homelab-monitor

Observabilidade + failover de exit WireGuard. Broker ntfy na Railway; VPS e Pi como sensores.
Ver o plano completo em `plano-observabilidade-failover.md`.

## Estrutura

```
vps/
  gatus/           # status page + matriz de reachability (docker compose)
  wg-watchdog/     # detecta exit residencial morto (handshake) -> ntfy
  install.sh       # instala units systemd apontando pros scripts DESTE repo
pi/
  pi-watcher/        # detecta VPS/wg0 mudo -> ntfy (pela internet de casa)
  install.sh
```

## Deploy — VPS

```bash
sudo git clone <SEU_REMOTE> /opt/homelab-monitor
cd /opt/homelab-monitor/vps

# 1) watchdog (systemd)
./install.sh                      # cria units + pede o NTFY_TOKEN
sudo nano /etc/wg-watchdog/env    # cola NTFY_TOKEN=tk_...
sudo systemctl restart wg-watchdog.timer

# 2) gatus (docker)
cd gatus
cp .env.example .env && nano .env # cola NTFY_TOKEN=tk_...
docker compose up -d
```

## Deploy — Pi

```bash
sudo git clone <SEU_REMOTE> /opt/homelab-monitor
cd /opt/homelab-monitor/pi
./install.sh
sudo nano /etc/pi-watcher/env       # cola NTFY_TOKEN=tk_...
sudo systemctl restart pi-watcher.timer
```

## Atualizar (o ponto de tudo isto)

```bash
cd /opt/homelab-monitor && git pull
# scripts .sh atualizam SOZINHOS (units apontam pro repo).
# Só re-rode ./install.sh se mudar um .service/.timer.
# Gatus: cd vps/gatus && docker compose up -d
```

## Segredos

O `NTFY_TOKEN` (usuário `pub`, write-only) vive só em `/etc/*/env` e `vps/gatus/.env`,
todos fora do git. No repo ficam apenas os `*.example`.

## Notas

- `wg-watchdog` usa **idade do handshake** do `wgprovider` (host não roteia pelo túnel).
  Confirme que o `wgprovider` tem `PersistentKeepalive = 25`, senão o handshake pode
  envelhecer com tráfego ocioso e gerar falso "caiu".
- Fase atual: **1 (read-only)**. Nada troca rota ainda.
