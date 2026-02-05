# Docker fallback (hydra-node)

This skill includes `scripts/hydra-node.sh`, which runs `hydra-node` either:
- directly from your PATH, or
- inside Docker using `ghcr.io/cardano-scaling/hydra-node`.

Basic usage:
```bash
chmod +x scripts/hydra-node.sh
scripts/hydra-node.sh --help
scripts/hydra-node.sh gen-hydra-key --output-file hydra
```

For full multi-node demo/head operations, prefer the hydra.family Docker Compose demo.
