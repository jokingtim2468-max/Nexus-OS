# FreeForm — VM data encryption

Every VM workspace is fully encrypted, with **per-VM isolated keys** so that
cracking one VM never exposes the others. Built on proven tools (LUKS + openssl),
no hand-rolled crypto.

## The key hierarchy (two-factor / split key)

```
  VM login password            device key  (random, stays on THIS machine;
  (you know it; never stored)  ↘          ↙ ideally TPM-sealed, never leaves)
                     password + device key
        │   openssl PBKDF2-SHA256, 600,000 iterations, random salt PER VM
        ▼
  wrapped key file   workspaces/<id>/vault/vmkey.enc     (one per VM, chmod 600)
        │   unwrapped only at launch → ephemeral keyfile, deleted after boot
        ▼
  VM disk key   (random 256-bit, 64 hex chars, every char independent)
        │
        ▼
  disk.qcow2   encrypted with LUKS / AES-256-XTS
```

### The password only gets you INTO the VM — not the raw files
Unwrapping a VM key needs **both** the password **and** the machine's device key
(`~/.config/freeform/device.key`). So:
- **Stolen password + stolen disk, taken elsewhere → cannot decrypt.** They lack
  the device key, which never leaves the machine (seal it to the TPM and it
  can't even be copied off).
- On your real machine, password + device key together unlock → boot the VM.

Honest caveat: on the *running* machine, someone with your password who is
sitting at it can use the VM (that's unavoidable — the password's whole job is
to let *you* in). The property this guarantees is the one you asked for: the
password **by itself** can't turn raw stolen files back into data.

### Why this meets the requirement
- **Random, no pattern:** each VM key is 256 bits of CSPRNG output (`secrets`),
  i.e. 64 hex characters where every character is independent — "get one letter"
  tells you nothing about the next. This is far stronger than a 12-character
  password.
- **Per-VM isolation:** each VM key is wrapped in its **own** file under your
  master login, with a **random salt per VM**. If an attacker steals and cracks
  one VM's `vmkey.enc`, they get **only that VM's disk** — the other VMs use
  different, independent keys.
- **The master is never stored.** It only exists in memory while you unlock.
  Lose it and the data is unrecoverable (that's the point).

## Tools

| Layer | Tool | Algorithm |
|-------|------|-----------|
| Disk at rest | LUKS (via qcow2 `encrypt.format=luks`) | AES-256-XTS |
| Key wrap | `openssl enc` | AES-256-CBC + PBKDF2-SHA256 (600k iters) |
| Randomness | Python `secrets` | OS CSPRNG |

The index (`workspaces/vault-index.csv`) records **metadata only** — vm id,
cipher, KDF, keyfile path, date. **No secret ever touches the CSV**, and the
whole `workspaces/` tree is git-ignored, so keys never leave the machine or hit
the repo.

## Deleting a VM = crypto-shred (instant, no disk wipe)

Pressing delete in the VM manager does **not** wipe the multi-GB disk. It
destroys the tiny key — the disk instantly becomes permanent random noise:

```bash
python3 apps/vmhub/vault.py shred kali            # plan (shows what happens)
python3 apps/vmhub/vault.py shred kali --confirm  # securely erase the key
python3 apps/vmhub/vault.py shred kali --confirm --rm-disk   # also delete the (useless) disk
```

`--confirm` securely overwrites `vmkey.enc` with random bytes and removes it +
its index row. After that the encrypted `disk.qcow2` can be left, trashed, or
deleted lazily — it can never be decrypted again. (Moving the *key* to the trash
is NOT enough; it must be securely erased, which shred does.)

> SSD caveat: overwriting a file can leave remnants on flash (wear-leveling).
> But `vmkey.enc` is itself ciphertext needing your password **and** device key,
> so a remnant is useless. For maximum assurance, keep the device key TPM-sealed
> and the ephemeral unlocked key on tmpfs (RAM) only.

## Password strength

`vault.py init` estimates the password's entropy and **rejects weak ones**
(<~60 bits) unless you pass `--force`. Generate a strong one:

```bash
python3 apps/vmhub/vault.py genpass    # ~128–144-bit random passphrase
```

## Usage

```bash
# 1. Create an isolated, two-factor encrypted key for a VM
FREEFORM_MASTER='your-long-passphrase' python3 apps/vmhub/vault.py init kali

# 2. Unlock it to an ephemeral keyfile just before launch
FREEFORM_MASTER='your-long-passphrase' \
  python3 apps/vmhub/vault.py unlock kali --out /run/freeform/kali.key

# 3. Create/boot the encrypted workspace with that key
python3 apps/vmhub/vmhub.py create kali --key /run/freeform/kali.key --run
python3 apps/vmhub/vmhub.py launch kali --iso kali.iso --key /run/freeform/kali.key --run

# 4. Shred the ephemeral key after boot
shred -u /run/freeform/kali.key

python3 apps/vmhub/vault.py status      # CSV index (no secrets)
python3 apps/vmhub/vault.py selftest    # proves wrap/unwrap + wrong-pw reject
```

## Verified
`vault.py selftest` confirms: wrap→unwrap round-trips, a wrong master password is
rejected, and the key is 256-bit. The stored `vmkey.enc` is openssl salted
ciphertext — unreadable without the master.

## Honest notes
- Put the ephemeral keyfile on a **tmpfs** (`/run`, RAM-backed) so it never
  touches persistent disk, and `shred` it after boot.
- A strong **master passphrase** is the whole game — use a long one; PBKDF2 at
  600k iters slows brute force but can't save a weak password.
- `cryptsetup`/`qemu` must be installed on the target (they install via the
  conversion kit); this cloud box only runs the key-management + planning.
- Pairs with **NetGuard** (Mullvad + Tor + kill switch) for data-in-transit;
  this doc is data-at-rest.
