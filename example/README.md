Generate a new keypair: 

```bash
docker run ghcr.io/spruceid/didkit-cli:latest key generate ed25519 > issuer_key.jwk
```

edit:  ../.env - set DIDKIT_HTTP_ISSUER_KEYS=[{JWK JSON}]

run: in the root dir run `docker compose up -d`

run: in example dir `chomod +x test.sh`

run: in example dir `./test.sh`

