---
title: "Self-Host Vaultwarden"
description: "How to self-host vaultwarden locally using docker-rootless and Nginx reverse proxy."
draft: false
date: 2026-02-20
tags: [ "linux", "security", "docker", "nginx", "reverse-proxy", "ufw", "systemd" ]
summary: "How to self-host vaultwarden locally using docker-rootless and Nginx reverse proxy."
---

## VAULTWARDEN INSTALLATION 
A complete guide to **self-hosting Vaultwarden** — a lightweight, open-source password manager compatible with Bitwarden clients — using Docker rootless for better security isolation. This setup includes a dedicated system user, Nginx reverse proxy with SSL, Argon2 hashed admin token, firewall hardening with UFW and portainer agent for checking container status.   
{{< icon "github" >}} [Vaultwarden](https://github.com/dani-garcia/vaultwarden)

### Prerequisites 
- systemd 
- nginx
- docker-rootless
- portainer 
- openssl 
- ufw 
- argon2

#### Create a dedicated user and enable linger.
By default, `systemd` kills all user processes on logout. Enabling linger keeps the user's services running in the background even without an active session — essential for Docker rootless containers to stay up.
After you enable linger you have to watch content of `/run/user/USER-ID`, this checks that the user's runtime directory exists, which confirms that linger is **active** and systemd has **started the user session**. This directory contains essential runtime resources like the `D-Bus socket` and the `Docker rootless socket`. If it doesn't exist, Docker rootless won't be able to start.

```bash 
# add user 
sudo useradd -r -m -s /usr/sbin/nologin -d /home/vaultwarden vaultwarden

# enable linger 
sudo loginctl enable-linger vaultwarden

# check 
ls /run/user/$(id -u vaultwarden)
```
#### Create directories.

Directory `data` will contain everything.
Directory `portainer-agent` will contain agent.

```bash 
sudo -u vaultwarden mkdir -p /home/vaultwarden/vaultwarden/data 
sudo -u vaultwarden mkdir -p /home/vaultwarden/vaultwarden/portainer-agent  

# Final stucture 
sudo tree -a /home/vaultwarden/vaultwarden/

/home/vaultwarden/vaultwarden
├── data
│   ├── db.sqlite3
│   ├── db.sqlite3-shm
│   ├── db.sqlite3-wal
│   ├── rsa_key.pem
│   └── tmp
├── docker-compose.yml
├── .env
└── portainer-agent
    └── docker-compose.yml
4 directories, 7 files
```

#### Create token for admin panel.

Create `/home/vaultwarden/vaultwarden/.env` and `ADMIN_TOKEN`.
Using Argon2, you can hash the admin password so it's never stored in plain text.

<details>
<summary> Argon2 flags explained </summary>

- `argon2`: the hashing tool
- `"$(openssl rand -base64 32)"`: generates a random 32-byte salt encoded in base64
- `-e`: output the hash in encoded format (PHC string)
- `-id`: use the Argon2id variant (combines Argon2i and Argon2d for better security)
- `-k 65540`: memory cost in KiB (~64MB of RAM used during hashing)
- `-t 3`: time cost (3 iterations)
- `-p 4`: parallelism (4 threads)

</details>



```bash
# token creation
ADMIN_TOKEN=$(echo -n "your_admin_password" | argon2 "$(openssl rand -base64 32)" -e -id -k 65540 -t 3 -p 4)

printf "ADMIN_TOKEN='%s'\n" "$ADMIN_TOKEN" | sudo -u vaultwarden tee /home/vaultwarden/vaultwarden/.env

# permissions settings 
sudo chmod 600 /home/vaultwarden/vaultwarden/.env
```

{{< alert >}} After you set up nginx navigate to https://YOUR-IP:4080/admin and enter the password you used to generate the Argon2 hash. {{< /alert >}}

#### Create docker compose with these settings.

Put `SIGNUPS_ALLOWED=false` after registration.
Put `DOMAIN` to `.env` file.

```bash 
# docker-compose.yml

services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    ports:
      - "5080:80"
    volumes:
      - ./data:/data
    env_file:
      - .env
    environment:
      - SIGNUPS_ALLOWED=true 
      - LOG_LEVEL=warn
      - SENDS_ALLOWED=true
      - EMERGENCY_ACCESS_ALLOWED=true
      - WEB_VAULT_ENABLED=true
      - SHOW_PASSWORD_HINT=false
      - INVITATIONS_ALLOWED=false
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: "1.0"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

#### Configure SUBUID and SUBGID.
Docker rootless uses user namespaces to map container `UIDs/GIDs` to unprivileged ranges on the host. The `/etc/subuid` and `/etc/subgid` files define which `UID/GID` ranges each user is allowed to use. Without these entries, the container can't create isolated users internally and will fail to start.

```bash
# write to file /etc/subuid and /etc/subgid 
sudo usermod --add-subuids 200000-265535 --add-subgids 200000-265535 vaultwarden

# check if everything works 
grep vaultwarden /etc/subuid /etc/subgid
```
#### Start docker service.

Start docker and check if it runs.

```bash 
# start 
sudo -u vaultwarden XDG_RUNTIME_DIR=/run/user/$(id -u vaultwarden) systemctl start docker 

# check 
sudo -u vaultwarden XDG_RUNTIME_DIR=/run/user/$(id -u vaultwarden) systemctl status docker 
```

#### Start docker compose. 

```bash 
# launch docker as user vaultwarden and recreate 
sudo -u vaultwarden -H /bin/bash -lc '\''
export DOCKER_HOST=unix:///run/user/$(id -u vaultwarden)/docker.sock
cd /home/vaultwarden/vaultwarden/
docker compose up -d --force-recreate'
```

#### Generate certificates.

Generate auto-signed certificates for encrypted communication with `openssl` command.

<details>
<summary> OpenSSL flags explained </summary>

- `-x509`: generate a self-signed certificate instead of a certificate signing request
- `-nodes`: don't encrypt the private key with a passphrase
- `-days 3650`: certificate validity (10 years)
- `-newkey rsa:2048`: create a new 2048-bit RSA private key
- `-keyout`: path for the private key file
- `-out`: path for the certificate file
- `-subj "/CN=..."`: set the Common Name without interactive prompts
- `-addext "subjectAltName=..."`: add SANs (IP addresses and DNS names) so clients accept the certificate when connecting by IP or hostname

</details>

```bash 
sudo mkdir -p /etc/nginx/ssl

# gen certificate 
sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/vaultwarden.key \
  -out /etc/nginx/ssl/vaultwarden.crt \
  -subj "/CN=<name>" \
  -addext "subjectAltName=IP:<Insert-Your-IP>,IP:<Insert-Your-IP>,DNS:<Insert-Your-DomainName>"
```

#### Configure nginx reverse proxy.
Create file on dir `/etc/nginx/sites-enabled/reverse-proxy`.

```bash 
# write config 
sudo tee -a /etc/nginx/sites-enabled/reverse-proxy <<'EOF'

server {
    listen 4080 ssl;
    server_name <IP-ADDRESS>;

    ssl_certificate     /etc/nginx/ssl/vaultwarden.crt;
    ssl_certificate_key /etc/nginx/ssl/vaultwarden.key;

    client_max_body_size 525M;

    location / {
        proxy_pass http://127.0.0.1:5080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /notifications/hub {
        proxy_pass http://127.0.0.1:5080;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

EOF
```

#### Start nginx.
Run nginx and see if it's running.

```bash
# check syntax
sudo nginx -t 

# check if it's already running
systemctl status nginx

# if it's running reload
sudo systemctl reload nginx 

# if it's not running start nginx 
sudo systemctl enable --now nginx 

# see if nginx is running 
sudo systemctl status nginx 

# check possible errors 
sudo journalctl -u nginx -f 
```

#### Enable ufw Connection.

If you are in lan run this command.
```bash
sudo ufw allow in on <INTERFACE-LAN> from <NET-ADDRESS>/24 to any port 4080 proto tcp comment "Vaultarden from lan"
```

#### Install certificate on client.
Copy `*.crt` file and install on your client (IPhone/Mac/Android)

```bash
sudo cp /etc/nginx/ssl/vaultwarden.crt /tmp/
cd /tmp && python3 -m http.server 8080 
```

On client go to `http://<IP-SERVER>:8080/vaultwarden.crt` and your client will download certificate.
Install using settings of your client.

#### Application settings.
Install `Bitwarden` on your client, open it and add `https://<IP-SERVER>:4080`.
After insert mail and password you insert on server.

#### Disable registration. 
Change `SIGNUPS_ALLOWED=true` to `SIGNUPS_ALLOWED=false` on `docker-compose.yml` and relaunch container with [command](#start-docker-compose).

#### Install agent.
Create `docker-compose.yml` with a port is not used on your system.

```bash
# check what port to map to agent if you just use other agent 
sudo ss -tulpn | grep -E ':9[0-9]{3}'

# select port 
AGENT_PORT="<AVAILABLE_PORT>"

# content of docker-compose.yml
VAULT_UID=$(id -u vaultwarden)

sudo -u vaultwarden tee /home/vaultwarden/portainer-agent/docker-compose.yml <<EOF
services:
  agent:
    image: portainer/agent:latest
    container_name: portainer-agent
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    ports:
      - "${AGENT_PORT}:9001"
    volumes:
      - /run/user/${VAULT_UID}/docker.sock:/var/run/docker.sock
      - /home/vaultwarden/.local/share/docker/volumes:/var/lib/docker/volumes
EOF
```

``` bash
sudo ufw allow from 127.0.0.1 to any port <AVAILABLE_PORT>
```

Launch portainer agent.
```bash
sudo -u vaultwarden -H /bin/bash -lc '\''
export DOCKER_HOST=unix:///run/user/$(id -u vaultwarden)/docker.sock
cd /home/vaultwarden/vaultwarden/portainer-agent/
docker compose up -d --force-recreate'
```

Go to the Portainer dashboard, navigate to Environments → Add environment, select Docker Standalone → Agent, and enter your server IP with the agent port (e.g. 192.168.1.21:9003) as the Environment URL.

#### Backup

The `./data` directory contains the SQLite database with all your vault entries. Schedule a regular backup to avoid data loss.

```bash
# create backup directory
sudo -u vaultwarden mkdir -p /home/vaultwarden/backups

# edit vaultwarden crontab
sudo crontab -u vaultwarden -e
```

Add these lines to schedule a daily backup at 3 AM and auto-delete backups older than 30 days.

```bash
# daily backup at 3 AM
0 3 * * * tar czf /home/vaultwarden/backups/vaultwarden-$(date +\%Y\%m\%d).tar.gz -C /home/vaultwarden/vaultwarden data/

# delete backups older than 30 days
0 4 * * * find /home/vaultwarden/backups -name \"*.tar.gz\" -mtime +30 -delete
```

### Conclusion
You now have a fully self-hosted password manager running in a security-hardened environment — Docker rootless, dedicated user, SSL encryption, Argon2 hashed admin token, and firewall rules. Your passwords never leave your network and you have full control over your data.
