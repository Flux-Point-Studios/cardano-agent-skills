# Cardano Devnet-in-a-Box (Hydra demo + Ogmios + Kupo)

This folder gives you a **one-command local rehearsal environment**:

- **cardano-node** (fast local devnet)
- **hydra-node** (3-node demo cluster: Alice/Bob/Carol)
- **ogmios** (WS API for chain sync / tx submission)
- **kupo** (chain-index)

It vendors **Hydra’s official demo** under `devnet-in-a-box/.vendor/hydra` and drops a `docker-compose.override.yml` into the upstream `hydra/demo` so you get Ogmios + Kupo alongside the canonical setup.

## Requirements

- Docker + Docker Compose
- Git

## Quickstart

From this folder:

```bash
./run.sh up
```

Then:

```bash
./run.sh tui 1
```

In other terminals:

```bash
./run.sh tui 2
./run.sh tui 3
```


## Deterministic rehearsal (green/red)

This is the "no vibes" end-to-end check: smoke test + Hydra open/close + one contract interaction (a tiny always-true Plutus script UTxO committed and spent inside the head).

```bash
cd devnet-in-a-box
./run.sh rehearsal
```

If it succeeds you get **GREEN**. If anything flakes, you get **RED** + the failing step.

You can also run the lightweight health check:

```bash
./run.sh smoke
```

## Endpoints

- Ogmios (WS): `ws://localhost:1337`
- Kupo (HTTP): `http://localhost:1442`
- Hydra API:
  - Alice: `http://localhost:4001`
  - Bob:   `http://localhost:4002`
  - Carol: `http://localhost:4003`

Optional monitoring:

```bash
./run.sh monitor
# Grafana: http://localhost:3000 (admin/admin)
```

## Reset / cleanup

```bash
./run.sh down
./run.sh reset
```

`reset` removes containers, volumes, and deletes the generated `hydra/demo/devnet` directory.

## Why this approach?

Hydra’s demo scripts (`prepare-devnet.sh`, `seed-devnet.sh`, etc.) are the “known good” path for:

- generating a local devnet with the right genesis start time
- publishing Hydra scripts
- funding the demo parties

So we **reuse that**, and just bolt on the two dApp-facing services you actually want for app rehearsal: Ogmios + Kupo.
