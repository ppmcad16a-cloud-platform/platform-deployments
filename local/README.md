# Run the whole shop locally (Docker Desktop)

> **In plain words:** this starts every microservice, a private MongoDB and the website on your
> laptop, built exactly the way CI builds them. Use it to try changes before they go to the cloud.

## Steps

```powershell
# from repos/platform-deployments/local
copy .env.example .env      # then put a long random JWT_SECRET and a SEED_ADMIN_PASSWORD in it
                            # python -c "import secrets; print(secrets.token_urlsafe(48))"

# identity-service is Java: build its JAR first (CI does this for you in the pipeline)
cd ..\..\identity-service; .\mvnw.cmd -B package -DskipTests; cd ..\platform-deployments\local

docker compose up --build -d                       # build + start everything (first time: several minutes)
docker compose ps                                  # wait until every service shows "healthy"
docker compose --profile seed run --rm seed        # one-time: admin user + 100 sample products
```

Open **http://localhost:8080** and log in with `SEED_ADMIN_EMAIL` / `SEED_ADMIN_PASSWORD` from `.env`.

## Useful commands

| What | Command |
|---|---|
| Is everything up? (asks every backend) | `curl http://localhost:3000/api/health` |
| Logs of one service (JSON) | `docker compose logs -f catalog` |
| Metrics of the gateway | `curl http://localhost:3000/metrics` |
| Rebuild one service after a code change | `docker compose up --build -d catalog` |
| Stop (keep data) | `docker compose down` |
| Stop and delete the local database | `docker compose down -v` |

## What runs

| Service | Port (inside Docker) | Exposed on your laptop |
|---|---|---|
| client-service (nginx) | 8080 | `127.0.0.1:8080` |
| api-gateway-service | 3000 | `127.0.0.1:3000` |
| identity / catalog / commerce / notification | 3101 / 3102 / 3103 / 3104 | not exposed (only via the gateway) |
| mongo | 27017 | not exposed |

Ports are bound to `127.0.0.1` only, so nobody else on your network can reach them.
The backends are reachable only through the gateway - the same layout as in Kubernetes.
