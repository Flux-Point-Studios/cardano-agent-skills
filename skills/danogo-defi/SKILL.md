---
name: danogo-defi
description: "Danogo DeFi on Cardano: concentrated-liquidity stablecoin DEX (CLMM swaps, LP positions), lending/borrowing pools, and on-chain price feeds. Supports USDA, DJED, iUSD, USDCx, USDM stablecoin pairs via Ogmios UTxO queries and local pool math."
allowed-tools:
  - Bash(curl:*)
  - Bash(node:*)
  - Bash(npx:*)
  - Read
  - Write
user-invocable: true
context:
  - "!curl -s https://app.danogo.xyz --max-time 5 -o /dev/null -w '%{http_code}' 2>&1"
metadata: {"openclaw":{"emoji":"🔄"}}
---

# danogo-defi

Danogo is a Cardano-native concentrated-liquidity (CL) DEX focused on stablecoin pairs, with integrated lending/borrowing. It uses on-chain UTxO pool state queryable via Ogmios.

## When to use

- Swapping between Cardano stablecoins (USDA, DJED, iUSD, USDCx, USDM)
- Providing concentrated liquidity to stablecoin CL pools
- Borrowing or lending stablecoins
- Querying on-chain stablecoin prices and pool state
- Building stablecoin arbitrage strategies across Danogo and other DEXes

## Operating rules (must follow)

- Always query fresh pool state from Ogmios before quoting prices. Stale pool data causes failed swaps.
- Danogo CL pools use a **square-root price model** (similar to Uniswap V3). The on-chain datum stores `sqrtPrice` — you must square it to get the actual price ratio.
- Pool UTxOs are identified by the pool NFT policy ID in the datum. Use Ogmios `queryLedgerState/utxo` filtered by the pool script address.
- **Do NOT double-sqrt**: The SDK had a bug where `sqrt(sqrtPrice)` was applied instead of `sqrtPrice^2`. If prices look wrong (e.g., 0.0001 instead of 1.0), check for double-sqrt.
- **OutRef staleness**: Pool UTxOs change after every swap. Always re-query before building a transaction. Using a consumed UTxO causes "UTxO not found" errors.
- Minimum swap amounts vary by pool. Check the pool datum's `minSwap` field.
- For lending/borrowing, collateral ratios are enforced on-chain. Under-collateralized borrows will fail validation.
- Confirm target network (mainnet vs preprod) before querying. Pool addresses differ per network.

## Architecture

```
Agent
  ├── Ogmios (UTxO queries for pool state)
  │     └── queryLedgerState/utxo → pool datum → sqrtPrice, liquidity, ticks
  ├── Local Math (price calculation from pool state)
  │     └── sqrtPrice^2 → price ratio → quote amount (with fees + slippage)
  └── Transaction Builder (cardano-cli or MeshJS)
        └── Build swap/LP/lend tx → sign → submit via submit-api or MCP
```

## Key concepts

### Concentrated Liquidity (CL) Pools

Danogo CL pools work like Uniswap V3 on Cardano:
- Liquidity is concentrated in **tick ranges** (price bands)
- LPs earn more fees per unit of capital vs traditional AMMs
- Each pool has a `currentTick` and `sqrtPrice` in its datum
- Swaps move the price along the curve, potentially crossing tick boundaries

### Pool State (from UTxO datum)

```typescript
interface DanogoPoolDatum {
  sqrtPrice: bigint;      // Square root of price (Plutus integer)
  liquidity: bigint;      // Active liquidity in current tick range
  currentTick: number;    // Current price tick index
  feeRate: number;        // Fee in basis points (e.g., 30 = 0.3%)
  tokenA: string;         // Policy ID + asset name (hex)
  tokenB: string;         // Policy ID + asset name (hex)
  minSwap: bigint;        // Minimum swap amount
  tickSpacing: number;    // Granularity of tick ranges
}
```

### Price Calculation

```typescript
// Convert sqrtPrice from datum to actual price
const sqrtPriceNum = Number(datum.sqrtPrice) / 2 ** 64; // Q64.64 fixed-point
const price = sqrtPriceNum * sqrtPriceNum; // Square it to get price ratio

// Quote: how much tokenB for swapping amountA of tokenA
const amountOut = amountA * price * (1 - feeRate / 10000);
```

**Common mistake**: Do NOT take `sqrt()` of the datum value. It's already a sqrt — you need to square it.

## Workflows

### 1. Query stablecoin pool price

```bash
# Query pool UTxO via Ogmios
curl -s http://localhost:1337 -H "Content-Type: application/json" -d '{
  "jsonrpc": "2.0",
  "method": "queryLedgerState/utxo",
  "params": {
    "addresses": ["addr1_DANOGO_POOL_SCRIPT_ADDRESS"]
  }
}' | jq '.result[] | select(.value.assets | keys[] | contains("POOL_NFT_POLICY"))'
```

### 2. Execute a stablecoin swap

1. Query fresh pool state (get current sqrtPrice + liquidity)
2. Calculate expected output using local math
3. Apply slippage tolerance (recommend 0.5-1% for stablecoins)
4. Build transaction with swap redeemer
5. Sign and submit

### 3. Provide concentrated liquidity

1. Choose tick range (price band) for your liquidity
2. Calculate token amounts needed for the range
3. Build add-liquidity transaction
4. Receive LP NFT representing your position

### 4. Lending/borrowing

1. Query lending pool state
2. For lending: deposit tokens, receive interest-bearing receipt
3. For borrowing: deposit collateral, borrow up to collateral ratio
4. Monitor health factor — liquidation occurs below minimum ratio

## Known stablecoin pairs (mainnet)

| Pair | Fee | Notes |
|------|-----|-------|
| USDA/DJED | 0.05% | Tightest spread, highest volume |
| USDA/iUSD | 0.05% | Indigo synthetic USD |
| USDCx/USDA | 0.05% | Wrapped USDC bridge |
| USDM/USDA | 0.1% | Moneta stablecoin |

## Danogo SDK (danogo-clmm)

If an official TypeScript SDK is available (check Danogo docs for the correct package name), it provides helpers for pool queries and quote calculations. **Always verify the package name from official Danogo documentation before installing** to avoid typosquatted packages.

```typescript
// Example pattern (verify actual SDK package name from Danogo docs)
import { DanogoPool, getQuote } from '<danogo-sdk-package>';

const pool = await DanogoPool.fromOgmios(ogmiosUrl, poolId);
const quote = getQuote(pool, inputAmount, 'tokenA-to-tokenB');
console.log(`Expected output: ${quote.outputAmount} (fee: ${quote.feeAmount})`);
```

**Known SDK issues (as of 2026-04):**
- `outRef` staleness: Pool UTxO reference becomes invalid after any swap in the pool. Always re-query.
- Double-sqrt bug in older versions: `getPrice()` applied `Math.sqrt()` to an already-sqrt value. Check changelog for fix version.
- Always pin SDK version after verifying it works correctly.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Price shows 0.0001 instead of ~1.0 | Double-sqrt bug | Square the sqrtPrice, don't sqrt it |
| "UTxO not found" on swap | Stale outRef | Re-query pool UTxO before building tx |
| Swap tx fails validation | Amount below minSwap | Check pool datum minSwap field |
| Huge slippage on small swap | Low liquidity in tick range | Check active liquidity before swapping |

## References

- [Danogo App](https://app.danogo.xyz)
- [Danogo Docs](https://docs.danogo.xyz) (if available)
- Shared: [PRINCIPLES.md](../../shared/PRINCIPLES.md)
