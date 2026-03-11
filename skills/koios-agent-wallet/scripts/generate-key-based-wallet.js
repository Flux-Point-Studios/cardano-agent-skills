#!/usr/bin/env node
"use strict";

/**
 * Generate a new Cardano wallet using MeshJS + Koios only (no mnemonic, no cardano-cli).
 * Produces payment + stake keypairs and base/stake addresses for use with
 * agent-wallet.js (MeshWallet type: cli). Staking-ready.
 *
 * Requires: @meshsdk/core (and network access for Koios address derivation).
 * Optional: @noble/ed25519 — when installed and WALLET_DIR set, writes .vkey files too.
 *
 * Env:
 *   NETWORK   mainnet | preprod | preview (default: mainnet)
 *   KOIOS_API_KEY  Optional Koios API key
 *   WALLET_DIR     Optional; writes addresses.json, .skey, and (if @noble/ed25519) .vkey
 */

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const network = (process.env.NETWORK || "mainnet").toLowerCase();
const apiKey = process.env.KOIOS_API_KEY || "";
const walletDir = process.env.WALLET_DIR || null;

const KOIOS_NETWORK = network === "mainnet" ? "api" : network;
const NETWORK_ID = network === "mainnet" ? 1 : 0;

if (!["mainnet", "preprod", "preview"].includes(network)) {
  console.error("NETWORK must be mainnet, preprod, or preview");
  process.exit(1);
}

/** Cardano CLI-style signing key cborHex: byte string (58 20) + 32-byte key. */
function toCborHex(secretBytes) {
  if (secretBytes.length !== 32) throw new Error("Key must be 32 bytes");
  return "5820" + secretBytes.toString("hex");
}

/** Cardano .vkey cborHex: 5820 + 32-byte public key hex. */
function vkeyCborHex(publicKeyBytes) {
  if (publicKeyBytes.length !== 32)
    throw new Error("Public key must be 32 bytes");
  return "5820" + Buffer.from(publicKeyBytes).toString("hex");
}

/** Derive Ed25519 public key from 32-byte seed; requires @noble/ed25519. */
async function getPublicKeyFromSeed(seedBytes) {
  const ed = await import("@noble/ed25519");
  const pub = await ed.getPublicKeyAsync(seedBytes);
  return pub;
}

async function main() {
  console.log("Generating payment keypair (MeshJS-compatible)...");
  const paymentSecret = crypto.randomBytes(32);
  const paymentCborHex = toCborHex(paymentSecret);

  console.log("Generating stake keypair (MeshJS-compatible)...");
  const stakeSecret = crypto.randomBytes(32);
  const stakeCborHex = toCborHex(stakeSecret);

  const { KoiosProvider, MeshWallet } = await import("@meshsdk/core");
  const provider = new KoiosProvider(KOIOS_NETWORK, apiKey || undefined);

  const wallet = new MeshWallet({
    networkId: NETWORK_ID,
    fetcher: provider,
    submitter: provider,
    key: {
      type: "cli",
      payment: paymentCborHex,
      stake: stakeCborHex,
    },
  });

  await wallet.init();
  const baseAddr = await wallet.getChangeAddress();
  const rewardAddresses = await wallet.getRewardAddresses();
  const stakeAddr = rewardAddresses[0] || "";

  if (!stakeAddr) {
    console.error("Could not derive stake address from wallet.");
    process.exit(1);
  }

  if (walletDir) {
    const absDir = path.resolve(walletDir);
    if (!fs.existsSync(absDir)) fs.mkdirSync(absDir, { recursive: true });
    fs.writeFileSync(
      path.join(absDir, "addresses.json"),
      JSON.stringify(
        { network: network, baseAddress: baseAddr, stakeAddress: stakeAddr },
        null,
        2
      )
    );
    const paymentSkeyPath = path.join(absDir, "payment.skey");
    const stakeSkeyPath = path.join(absDir, "stake.skey");
    fs.writeFileSync(
      paymentSkeyPath,
      JSON.stringify(
        {
          type: "PaymentSigningKeyShelley_ed25519",
          description: "Payment Signing Key",
          cborHex: paymentCborHex,
        },
        null,
        2
      )
    );
    fs.writeFileSync(
      stakeSkeyPath,
      JSON.stringify(
        {
          type: "StakeSigningKeyShelley_ed25519",
          description: "Stake Signing Key",
          cborHex: stakeCborHex,
        },
        null,
        2
      )
    );
    try {
      fs.chmodSync(paymentSkeyPath, 0o600);
      fs.chmodSync(stakeSkeyPath, 0o600);
    } catch {
      /* non-unix: skip chmod */
    }
    let wroteVkey = false;
    try {
      const paymentPub = await getPublicKeyFromSeed(paymentSecret);
      const stakePub = await getPublicKeyFromSeed(stakeSecret);
      fs.writeFileSync(
        path.join(absDir, "payment.vkey"),
        JSON.stringify(
          {
            type: "PaymentVerificationKeyShelley_ed25519",
            description: "Payment Verification Key",
            cborHex: vkeyCborHex(paymentPub),
          },
          null,
          2
        )
      );
      fs.writeFileSync(
        path.join(absDir, "stake.vkey"),
        JSON.stringify(
          {
            type: "StakeVerificationKeyShelley_ed25519",
            description: "Stake Verification Key",
            cborHex: vkeyCborHex(stakePub),
          },
          null,
          2
        )
      );
      wroteVkey = true;
    } catch (_) {
      /* @noble/ed25519 not installed: skip .vkey */
    }
    console.log(
      wroteVkey
        ? `Wrote ${absDir}/addresses.json, payment.skey, stake.skey, payment.vkey, stake.vkey. Secure .skey (chmod 600).`
        : `Wrote ${absDir}/addresses.json, payment.skey, stake.skey. Secure .skey (chmod 600). Install @noble/ed25519 for .vkey files.`
    );
  }

  console.log("\n=== Agent Wallet Dossier ===");
  console.log(`Network: ${network} (${KOIOS_NETWORK})`);
  console.log(`Payment Address (base): ${baseAddr}`);
  console.log(`Stake Address: ${stakeAddr}`);
  console.log(`Koios Provider: ${KOIOS_NETWORK}`);
  console.log(
    "Stake Status: unregistered (register + delegate via agent-wallet.js)"
  );
  console.log("Delegated Pool: none");
  console.log("");

  console.log("--- Use with agent-wallet.js (staking) ---");
  console.log(`export PAYMENT_SKEY_CBOR_HEX="${paymentCborHex}"`);
  console.log(`export STAKE_SKEY_CBOR_HEX="${stakeCborHex}"`);
  console.log(
    `# Status: KOIOS_NETWORK=${KOIOS_NETWORK} MODE=status PAYMENT_SKEY_CBOR_HEX=$PAYMENT_SKEY_CBOR_HEX STAKE_SKEY_CBOR_HEX=$STAKE_SKEY_CBOR_HEX node scripts/agent-wallet.js`
  );
  console.log(
    `# Stake:  KOIOS_NETWORK=${KOIOS_NETWORK} MODE=stake POOL_ID=pool1... REGISTER_STAKE=1 PAYMENT_SKEY_CBOR_HEX=$PAYMENT_SKEY_CBOR_HEX STAKE_SKEY_CBOR_HEX=$STAKE_SKEY_CBOR_HEX node scripts/agent-wallet.js`
  );
  console.log("");
  console.log(
    "Fund the base address, then run stake mode with REGISTER_STAKE=1 and your POOL_ID."
  );
}

main().catch((err) => {
  console.error(err?.message || err);
  process.exit(1);
});
