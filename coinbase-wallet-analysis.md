# Coinbase Smart Wallet — Passkey Architecture Analysis

Reference analysis for zkCoins signup flow design. Researched May 2026.

## Two Wallet Types

**Smart Wallet (Passkey-based)** — the new default (since 2024, renamed to "Base App" July 2025):
- Created with Passkey (WebAuthn)
- No seed phrase needed
- Based on ERC-4337 (Account Abstraction)
- Wallet address is a Smart Contract, not an EOA
- P-256 public key registered as owner in the contract

**Traditional Wallet (EOA, Seed-Phrase-based)**:
- Classic 12-word BIP-39 seed phrase
- Creates an EOA (Externally Owned Account)

## Passkey Signup Flow

### Mobile (Base App):
1. Install app from store
2. "Create Smart Wallet"
3. System shows passkey creation prompt
4. User authenticates via Face ID / Touch ID / Android biometrics
5. Passkey stored in device passkey manager (Apple Keychain / Google PM)
6. Wallet ready

### Desktop (Browser):
1. Visit wallet.coinbase.com/smart-wallet
2. "Create a smart wallet"
3. WebAuthn ceremony triggered
4. Passkey options: biometrics (Windows Hello, Touch ID), hardware key (YubiKey), phone passkey via QR code
5. Smart Contract wallet deployed (lazily, on first transaction)

## Technical Architecture

### Smart Contract Wallet (ERC-4337):
- Not an EOA — a Smart Contract IS the wallet address
- Implements `validateUserOp` and execution functions
- Based on Solady's ERC4337, inspired by DaimoAccount and LightAccount
- Supports up to 2^256 simultaneous owners
- Each owner can independently execute transactions

### Passkey as Owner:
- Owners identified as `bytes` (supports both secp256k1 Ethereum addresses and secp256r1/P-256 passkey public keys)
- Smart contract hardcodes the passkey public key as authorized key
- Contract NOT deployed immediately — only on first transaction (gas savings)
- Wallet address computed deterministically from public key

### WebAuthn Configuration:
```
Algorithm:          -7 (ES256 = ECDSA with P-256 curve)
Resident Key:       required
User Verification:  preferred (security concern — should be "required")
Relying Party ID:   keys.coinbase.com
```

### Signature Flow:
1. Dapp creates transaction, requests passkey authentication
2. User confirms via biometrics
3. Biometrics decrypt the passkey on device
4. Passkey signs the UserOperation (not a classic ETH transaction)
5. UserOperation.signature = ABI-encoding of SignatureWrapper with ownerIndex + signatureData
6. signatureData for passkeys = ABI-encoding of WebAuthnAuth struct
7. UserOperation goes to alt-mempool
8. Bundler bundles multiple UserOperations into one EOA transaction
9. EntryPoint Contract (singleton) forwards to wallet contract
10. Smart Wallet verifies P-256 signature against registered public key

### Gas Sponsorship:
- On Base, gas fees are sponsored via Paymasters
- Users pay no gas fees initially

## Recovery Mechanisms

### Recovery Key:
- Must be generated WHILE you still have passkey access
- Creates a standard Ethereum private key (ECDSA/secp256k1)
- Its Ethereum address registered on-chain as additional owner
- Has equal rights as passkey owner at contract level
- Can add new passkeys if original is lost
- Functions like a seed phrase — must be stored securely
- Multiple recovery keys per wallet possible

### Cloud Backup:
- Passkeys sync via Apple Keychain / Google Password Manager
- Same Apple ID / Google Account on all devices = automatic access
- Different accounts on different devices = no sync

### Critical Risk:
Accidentally deleting the passkey in device settings without a recovery key = PERMANENT LOSS.

## Security Assessment

### Strengths:
- No seed phrase = no phishing risk for seed phrases
- Passkey bound to keys.coinbase.com = phishing-resistant
- Private key never leaves the device
- Biometric authentication
- Smart contract upgradeable (UUPS proxy)

### Weaknesses:
- `userVerification: preferred` instead of `required` — potentially insecure
- Dependency on device security and passkey provider (Apple/Google)
- No multi-passkey support implemented yet (though contract-level possible)
- If keys.coinbase.com is down, can't authenticate
- Users often don't understand their wallet access is in device settings
- No portability to other wallets (passkey bound to Coinbase)

### Not MPC:
Coinbase Smart Wallet is NOT an MPC wallet. MPC is only used at Coinbase Exchange/Custody. Smart Wallet is a pure smart contract wallet with passkey authentication.

## Key Difference from zkCoins

| | Coinbase | zkCoins |
|---|---|---|
| Blockchain | EVM (supports P-256 verification) | Bitcoin (secp256k1 only) |
| Wallet type | Smart Contract (ERC-4337) | HD Wallet (BIP-32) |
| Passkey role | Signs every transaction (P-256) | Unlocks wallet + derives seed (one-time) |
| Signing curve | P-256 (secp256r1) | secp256k1 (Bitcoin/Schnorr) |
| On-chain verification | Smart contract validates P-256 sig | No on-chain verification (CSV) |

## What We Adopted from Coinbase

1. Default to passkey — new users shouldn't need seed phrases
2. Biometric-first UX — Face ID / Touch ID as primary interaction
3. Recovery key as backup — prompt users to create backup while they have access
4. `userVerification: "required"` — always require biometric (unlike Coinbase's "preferred")
5. Domain binding — passkey bound to zkcoins.app prevents phishing

## Sources

- [Coinbase Smart Wallet GitHub](https://github.com/coinbase/smart-wallet)
- [Coinbase Help: Smart Wallet Passkeys](https://help.coinbase.com/en/wallet/getting-started/smart-wallet-passkeys)
- [Corbado: Smart Wallets and Passkeys](https://www.corbado.com/blog/smart-wallets-passkeys)
- [Splits.org: Passkeys in practice](https://splits.org/blog/coinbase-smart-wallet-passkeys/)
- [Base Recovery Keys Documentation](https://docs.base.org/smart-wallet/concepts/features/built-in/recovery-keys)
