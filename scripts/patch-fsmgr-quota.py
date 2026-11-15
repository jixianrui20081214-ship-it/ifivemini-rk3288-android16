#!/usr/bin/env python3
"""Keep ext4 quota on /data with the TrebleDroid GSI fs_mgr.

usage: patch-fsmgr-quota.py <file>   (32-bit ARM ELF, patched in place)

TrebleDroid's patch "Disable quotas on legacy devices with encryption disabled"
adds to tune_quota() in fs_mgr.cpp:

    if (!entry.fs_mgr_flags.file_encryption) {
        LINFO << "Disabling quotas on legacy devices with encryption disabled";
        want_quota = false;
    }

This tablet runs without file encryption, so every boot strips quota (and with
it the ext4 project feature) from /data, and vold cannot set project IDs on
Android/data. The kernel (4.19, CONFIG_QUOTA=y) handles quota fine.

The compiled check is a Thumb "lsls rX, rY, #23" (file_encryption flag bit)
followed by "bmi <want_quota = fstab quota flag>"; the fall-through logs the
message and clears want_quota. The bmi becomes an unconditional b, so
want_quota follows the fstab "quota" flag again, as in AOSP.
"""
import struct
import sys

MSG = b"Disabling quotas on legacy devices with encryption disabled"


def die(msg):
    print(f"STOP: {sys.argv[1]}: {msg}")
    sys.exit(1)


path = sys.argv[1]
d = bytearray(open(path, "rb").read())
if d[:4] != b"\x7fELF" or d[4] != 1 or d[18] != 40:
    die("not a 32-bit ARM ELF")

phoff, = struct.unpack_from("<I", d, 28)
phentsize, phnum = struct.unpack_from("<HH", d, 42)
loads = []
for i in range(phnum):
    p_type, p_offset, p_vaddr, _, p_filesz = struct.unpack_from("<5I", d, phoff + i * phentsize)
    if p_type == 1:
        loads.append((p_offset, p_vaddr, p_filesz))


def off2va(off):
    for o, v, n in loads:
        if o <= off < o + n:
            return v + off - o
    return None


def va2off(va):
    for o, v, n in loads:
        if v <= va < v + n:
            return o + va - v
    return None


def h(off):
    return struct.unpack_from("<H", d, off)[0]


s = d.find(MSG)
if s < 0:
    die("message not found; is this fs_mgr code?")
target = off2va(s)

# Thumb "ldr rD, [pc, #imm8*4]" (0x48xx) followed by "add rD, pc" (0x4478 | rD)
xrefs = []
for off in range(0, len(d) - 2, 2):
    hw = h(off)
    if hw & 0xFF78 != 0x4478:
        continue
    rd = hw & 7
    va = off2va(off)
    if va is None:
        continue
    for back in range(2, 40, 2):
        lw = h(off - back)
        if lw & 0xF800 == 0x4800 and (lw >> 8) & 7 == rd:
            lit = va2off(((off2va(off - back) + 4) & ~3) + (lw & 0xFF) * 4)
            if lit is not None and (struct.unpack_from("<I", d, lit)[0] + va + 4) & 0xFFFFFFFF == target:
                xrefs.append(off)
            break
if len(xrefs) != 1:
    die(f"expected one reference to the message, found {len(xrefs)}")

# nearest "lsls rX, rY, #23" + "bmi" before the reference
x = xrefs[0]
for off in range(x - 2, x - 160, -2):
    lsl, br = h(off), h(off + 2)
    if lsl & 0xF800 == 0 and (lsl >> 6) & 0x1F == 23 and br & 0xFF00 == 0xD400:
        imm8 = br & 0xFF
        if imm8 & 0x80:
            die("bmi branches backwards; unexpected layout")
        struct.pack_into("<H", d, off + 2, 0xE000 | imm8)
        open(path, "wb").write(d)
        print(f"   {path}: bmi at 0x{off2va(off + 2):x} -> b (quota follows the fstab flag)")
        sys.exit(0)
    if lsl & 0xFF00 == 0xE000 and (h(off - 2) >> 6) & 0x1F == 23:
        die("already patched")
die("file_encryption check (lsls #23 + bmi) not found before the message")
