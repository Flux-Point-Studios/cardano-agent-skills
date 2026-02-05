# Docker fallback (cardano-cli)

This skill includes `scripts/cardano-cli.sh`, which runs `cardano-cli` either:
- directly from your PATH, or
- inside Docker using `ghcr.io/intersectmbo/cardano-node`.

Basic usage:
```bash
chmod +x scripts/cardano-cli.sh
scripts/cardano-cli.sh version
```

If you have a node socket locally:
```bash
export CARDANO_NODE_SOCKET_PATH=/path/to/node.socket
scripts/cardano-cli.sh query tip --mainnet
```

Override container tag:
```bash
CARDANO_DOCKER_IMAGE=ghcr.io/intersectmbo/cardano-node:10.6.1 scripts/cardano-cli.sh version
```
