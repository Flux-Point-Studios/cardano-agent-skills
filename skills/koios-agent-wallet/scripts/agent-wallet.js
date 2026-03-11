#!/usr/bin/env node
"use strict";

const fs = require("fs");

const usage = `
Agent wallet template (MeshJS + Koios)

Required env (for signing):
  PAYMENT_SKEY_CBOR_HEX   Cardano CLI payment.skey in CBOR hex
  STAKE_SKEY_CBOR_HEX     Cardano CLI stake.skey in CBOR hex (required for staking)

Alternative key modes:
  ROOT_XPRV_BECH32        Root private key (bech32) for MeshWallet
  ADDRESS_ONLY            Read-only address (no signing)

General env:
  MODE                    status | send | stake | sign-submit (default: status)
  KOIOS_NETWORK           api | preprod | preview | guild (default: api)
  KOIOS_API_KEY           Optional Koios API key
  NETWORK_ID              1 (mainnet) or 0 (testnet) (default: 1)

Send env:
  RECIPIENT_ADDR          Address to send ADA to
  SEND_LOVELACE           Amount in lovelace (default: 1000000)

Stake env:
  POOL_ID                 Pool id: bech32 (pool1...) or hex (56 chars); hex is auto-converted
  REGISTER_STAKE          1 to include stake registration
  (Staking with CLI keys uses CSL for dual-key signing; requires @emurgo/cardano-serialization-lib-nodejs. Hex POOL_ID requires bech32.)

Sign/submit env:
  TX_CBOR_HEX            Unsigned tx cbor hex (from dApp builder)
  TX_FILE                Path to file containing unsigned tx cbor hex
  PRINT_SIGNED           1 to print signed tx cbor hex

Confirm env:
  CONFIRM                 1 to poll for tx confirmation
  CONFIRM_RETRIES         Poll attempts (default: 6)
  CONFIRM_DELAY_MS        Delay between polls (default: 10000)

Self test:
  SELF_TEST=1             Print usage and exit (no dependencies)
`;

if (process.env.SELF_TEST === "1") {
  console.log(usage.trim());
  process.exit(0);
}

const mode = process.env.MODE || "status";
const network = process.env.KOIOS_NETWORK || "api";
const apiKey = process.env.KOIOS_API_KEY || "";
const networkId = Number(process.env.NETWORK_ID || "1");

const payment = process.env.PAYMENT_SKEY_CBOR_HEX || "";
const stake = process.env.STAKE_SKEY_CBOR_HEX || "";
const root = process.env.ROOT_XPRV_BECH32 || "";
const addressOnly = process.env.ADDRESS_ONLY || "";

const recipient = process.env.RECIPIENT_ADDR || "";
const sendAmount = process.env.SEND_LOVELACE || "1000000";

const poolId = process.env.POOL_ID || "";
const registerStake = process.env.REGISTER_STAKE === "1";

const txCborHex = process.env.TX_CBOR_HEX || "";
const txFile = process.env.TX_FILE || "";
const printSigned = process.env.PRINT_SIGNED === "1";

const confirm = process.env.CONFIRM === "1";
const confirmRetries = Number(process.env.CONFIRM_RETRIES || "6");
const confirmDelayMs = Number(process.env.CONFIRM_DELAY_MS || "10000");

function requireEnv(value, name) {
  if (!value) {
    console.error(`Missing ${name}`);
    console.error(usage.trim());
    process.exit(1);
  }
}

function buildKeyConfig() {
  if (payment) {
    return { type: "cli", payment, stake: stake || undefined };
  }
  if (root) {
    return { type: "root", bech32: root };
  }
  if (addressOnly) {
    return { type: "address", address: addressOnly };
  }
  console.error("No key material provided.");
  console.error(usage.trim());
  process.exit(1);
}

function loadUnsignedTxHex() {
  if (txCborHex) return String(txCborHex).trim();
  if (txFile) return fs.readFileSync(txFile, "utf8").trim();
  return "";
}

async function waitForTx(provider, txHash) {
  for (let attempt = 1; attempt <= confirmRetries; attempt += 1) {
    try {
      const info = await provider.fetchTxInfo(txHash);
      if (info) {
        return info;
      }
    } catch (err) {
      // Ignore until confirmed
    }
    await new Promise((resolve) => setTimeout(resolve, confirmDelayMs));
  }
  throw new Error(
    `Tx not confirmed after ${confirmRetries} attempts: ${txHash}`
  );
}

/**
 * Sign an unsigned tx with one or more CLI keys using CSL.
 * Preserves existing witness set (scripts, redeemers, datums) and auxiliary data.
 * Uses FixedTransaction for tx hash (CSL 15.x+).
 * Requires @emurgo/cardano-serialization-lib-nodejs.
 */
async function signTxWithCsl(unsignedTxHex, cborHexKeys) {
  const CSL = await import("@emurgo/cardano-serialization-lib-nodejs");
  const fromBytes =
    CSL.PrivateKey.from_normal_bytes ?? CSL.PrivateKey.fromNormalBytes;

  // Parse unsigned tx (body + witness set + optional auxiliary_data)
  const parseTx = CSL.Transaction.from_hex ?? CSL.Transaction.fromHex;
  const unsignedTx = parseTx
    ? parseTx(unsignedTxHex)
    : CSL.Transaction.from_bytes(
        new Uint8Array(Buffer.from(unsignedTxHex, "hex"))
      );
  const txBody = unsignedTx.body();
  const auxiliaryData = unsignedTx.auxiliary_data
    ? unsignedTx.auxiliary_data()
    : unsignedTx.auxiliaryData
    ? unsignedTx.auxiliaryData()
    : undefined;

  const witnessSet = unsignedTx.witness_set
    ? unsignedTx.witness_set()
    : unsignedTx.witnessSet
    ? unsignedTx.witnessSet()
    : CSL.TransactionWitnessSet.new();

  let txHash;
  const FixedTransaction = CSL.FixedTransaction;
  const fixedFromHex = FixedTransaction?.from_hex ?? FixedTransaction?.fromHex;
  if (fixedFromHex) {
    const fixedTx = fixedFromHex(unsignedTxHex);
    const getHash =
      fixedTx.transaction_hash ?? fixedTx.transactionHash ?? undefined;
    if (!getHash) {
      throw new Error("FixedTransaction is missing transaction_hash().");
    }
    txHash = getHash.call(fixedTx);
  } else {
    const hashTx = CSL.hash_transaction ?? CSL.hashTransaction;
    if (!hashTx) {
      throw new Error("CSL missing FixedTransaction and hash_transaction.");
    }
    txHash = hashTx(txBody);
  }

  const makeWitness = CSL.make_vkey_witness ?? CSL.makeVkeyWitness;
  const Vkeywitnesses = CSL.Vkeywitnesses ?? CSL.VkeyWitnesses;
  const vkeys = Vkeywitnesses.new();

  const existingVkeys =
    typeof witnessSet.vkeys === "function" ? witnessSet.vkeys() : undefined;
  if (existingVkeys) {
    for (let i = 0; i < existingVkeys.len(); i += 1) {
      vkeys.add(existingVkeys.get(i));
    }
  }

  const keys = Array.isArray(cborHexKeys) ? cborHexKeys : [cborHexKeys];
  for (const keyHex of keys) {
    const hex = String(keyHex || "");
    if (!hex.startsWith("5820") || hex.length !== 68) {
      throw new Error(
        "Invalid skey cborHex: expected 5820 + 64 hex chars (32 bytes)."
      );
    }
    const keyBytes = Buffer.from(hex.slice(4), "hex");
    if (keyBytes.length !== 32) {
      throw new Error("Invalid skey cborHex: expected 32-byte key.");
    }
    const privKey = fromBytes(new Uint8Array(keyBytes));
    const witness = makeWitness(txHash, privKey);
    vkeys.add(witness);
  }

  witnessSet.set_vkeys
    ? witnessSet.set_vkeys(vkeys)
    : witnessSet.setVkeys(vkeys);

  const signedTx = CSL.Transaction.new(txBody, witnessSet, auxiliaryData);
  return (signedTx.to_hex ?? signedTx.toHex).call(signedTx);
}

/**
 * Normalize pool ID: accept hex (56 hex chars) and convert to bech32 (pool1...).
 * deserializePoolId() expects bech32; many APIs return hex.
 */
function normalizePoolId(poolId) {
  const s = String(poolId).trim();
  if (/^pool1[a-z0-9]+$/i.test(s)) return s;
  if (/^[0-9a-fA-F]{56}$/.test(s)) {
    try {
      const { bech32 } = require("bech32");
      const bytes = Buffer.from(s, "hex");
      const words = bech32.toWords(bytes);
      return bech32.encode("pool", words);
    } catch (err) {
      throw new Error(
        "Hex pool ID requires the 'bech32' package. Install: npm install bech32"
      );
    }
  }
  return s;
}

/**
 * Get unsigned transaction as hex from MeshTxBuilder.complete() result.
 * Mesh uses CSL under the hood; the result may be a CSL Transaction or wrapper.
 */
function getUnsignedTxHex(unsignedTx) {
  if (typeof unsignedTx === "string") return unsignedTx;
  const toHex = (o) =>
    o &&
    (typeof o.to_hex === "function"
      ? o.to_hex()
      : typeof o.toHex === "function"
      ? o.toHex()
      : undefined);
  const h = unsignedTx && toHex(unsignedTx);
  if (h) return h;
  const inner = unsignedTx?.tx ?? unsignedTx?.transaction ?? unsignedTx?.body;
  if (inner && toHex(inner)) return toHex(inner);
  if (unsignedTx?.hex && typeof unsignedTx.hex === "string")
    return unsignedTx.hex;
  if (unsignedTx?.cbor && typeof unsignedTx.cbor === "string")
    return unsignedTx.cbor;
  throw new Error(
    "Could not get tx hex from Mesh unsigned tx. Staking requires @emurgo/cardano-serialization-lib-nodejs and a Mesh version that exposes tx hex (e.g. .to_hex() on the complete() result)."
  );
}

async function main() {
  const mesh = await import("@meshsdk/core");
  const { KoiosProvider, MeshWallet, MeshTxBuilder, deserializePoolId } = mesh;

  const provider = new KoiosProvider(network, apiKey || undefined);
  const keyConfig = buildKeyConfig();

  const wallet = new MeshWallet({
    networkId,
    fetcher: provider,
    submitter: provider,
    key: keyConfig,
  });

  await wallet.init();
  const changeAddress = await wallet.getChangeAddress();

  if (mode === "status") {
    const utxos = await provider.fetchAddressUTxOs(changeAddress);
    const rewardAddresses = await wallet.getRewardAddresses();
    const rewardAddress = rewardAddresses[0];
    const accountInfo = rewardAddress
      ? await provider.fetchAccountInfo(rewardAddress)
      : null;

    console.log({
      network,
      changeAddress,
      utxoCount: utxos.length,
      rewardAddress: rewardAddress || null,
      accountInfo,
    });
    return;
  }

  if (mode === "send") {
    requireEnv(recipient, "RECIPIENT_ADDR");
    if (keyConfig.type === "address") {
      throw new Error("Read-only wallet cannot sign transactions.");
    }

    const txBuilder = new MeshTxBuilder({ fetcher: provider });
    const utxos = await wallet.getUtxos();

    const unsignedTx = await txBuilder
      .txOut(recipient, [{ unit: "lovelace", quantity: sendAmount }])
      .changeAddress(changeAddress)
      .selectUtxosFrom(utxos)
      .complete();

    const signedTx = await wallet.signTx(unsignedTx);
    const txHash = await wallet.submitTx(signedTx);
    console.log({ txHash });

    if (confirm) {
      const info = await waitForTx(provider, txHash);
      console.log({ confirmed: true, info });
    }
    return;
  }

  if (mode === "stake") {
    requireEnv(poolId, "POOL_ID");
    if (keyConfig.type !== "cli" && keyConfig.type !== "root") {
      throw new Error("Staking requires a signing wallet (cli or root).");
    }
    if (keyConfig.type === "cli" && !stake) {
      throw new Error("Staking requires STAKE_SKEY_CBOR_HEX.");
    }

    const txBuilder = new MeshTxBuilder({ fetcher: provider, verbose: true });
    const utxos = await wallet.getUtxos();
    const rewardAddresses = await wallet.getRewardAddresses();
    const rewardAddress = rewardAddresses[0];
    if (!rewardAddress) {
      throw new Error("No reward address available for staking.");
    }

    const poolIdBech32 = normalizePoolId(poolId);
    const poolIdHash = deserializePoolId(poolIdBech32);

    let builder = txBuilder;
    if (registerStake) {
      builder = builder.registerStakeCertificate(rewardAddress);
    }
    builder = builder.delegateStakeCertificate(rewardAddress, poolIdHash);

    const unsignedTx = await builder
      .selectUtxosFrom(utxos)
      .changeAddress(changeAddress)
      .complete();

    // MeshWallet.signTx() only signs with payment key; stake certs need stake key witness.
    // Use CSL FixedTransaction to sign with both keys when using CLI keys.
    let signedTx;
    if (keyConfig.type === "cli" && payment && stake) {
      try {
        const unsignedTxHex = getUnsignedTxHex(unsignedTx);
        const signedTxHex = await signTxWithCsl(unsignedTxHex, [
          payment,
          stake,
        ]);
        signedTx = signedTxHex;
      } catch (err) {
        const msg = err?.message || String(err);
        console.error(
          "Stake signing failed (stake certs need both payment and stake key witnesses). Ensure @emurgo/cardano-serialization-lib-nodejs is installed. Error:",
          msg
        );
        throw err;
      }
    } else {
      signedTx = await wallet.signTx(unsignedTx);
    }

    const txHash = await wallet.submitTx(signedTx);
    console.log({ txHash });

    if (confirm) {
      const info = await waitForTx(provider, txHash);
      console.log({ confirmed: true, info });
    }
    return;
  }

  if (mode === "sign-submit") {
    if (keyConfig.type === "address") {
      throw new Error("Read-only wallet cannot sign transactions.");
    }
    const unsignedTxHex = loadUnsignedTxHex();
    requireEnv(unsignedTxHex, "TX_CBOR_HEX or TX_FILE");

    let signedTx;
    if (keyConfig.type === "cli" && payment) {
      try {
        signedTx = await signTxWithCsl(unsignedTxHex, [payment]);
      } catch (err) {
        const msg = err?.message || String(err);
        console.error(
          "Signing failed (CLI keys require @emurgo/cardano-serialization-lib-nodejs). Error:",
          msg
        );
        throw err;
      }
    } else {
      signedTx = await wallet.signTx(unsignedTxHex);
    }

    if (printSigned) {
      console.log({ signedTx });
    }

    const txHash = await wallet.submitTx(signedTx);
    console.log({ txHash });

    if (confirm) {
      const info = await waitForTx(provider, txHash);
      console.log({ confirmed: true, info });
    }
    return;
  }

  console.error(`Unknown MODE: ${mode}`);
  console.error(usage.trim());
  process.exit(1);
}

main().catch((err) => {
  console.error(err?.message || err);
  process.exit(1);
});
