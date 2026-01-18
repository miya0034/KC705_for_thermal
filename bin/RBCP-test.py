#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SiTCP RBCP (UDP) CLI tool for EEPROM read/write and IP set.

Examples:
  # EEPROMのIP(FC18-1B)を読む
  python3 rbcp_tool.py --target 192.168.10.16 --port 4660 r --addr 0xFFFFFC18 --len 4

  # EEPROMのRBCPポート(FC22-23)を読む
  python3 rbcp_tool.py --target 192.168.10.16 r --addr 0xFFFFFC22 --len 2

  # 1バイト書き（例: FCFFに00）
  python3 rbcp_tool.py --target 192.168.10.16 w --addr 0xFFFFFCFF --data 00 --verify

  # IPを 192.168.10.20 に設定（FCFF->00, FC18-1B->C0A80A14, verify）
  python3 rbcp_tool.py --target 192.168.10.16 set-ip --new-ip 192.168.10.20

Notes:
  - 1回のRBCP転送でのデータ長は 1..255 byte。長い write は分割すること。
"""

import argparse
import socket
from dataclasses import dataclass
from typing import Optional


class RBCPError(RuntimeError):
    pass


@dataclass
class RBCPReply:
    cmd: int
    flag: int
    pkt_id: int
    length: int
    address: int
    data: bytes


class RBCPClient:
    # VER=0xF, TYPE=0xF => 0xFF
    VER_TYPE = 0xFF
    CMD_READ = 0xC
    CMD_WRITE = 0x8

    def __init__(
        self,
        ip: str,
        port: int = 4660,
        timeout_s: float = 0.3,
        retries: int = 3,
        bind: Optional[tuple[str, int]] = None,
    ):
        self.ip = ip
        self.port = port
        self.timeout_s = timeout_s
        self.retries = retries
        self._id = 0

        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.settimeout(self.timeout_s)
        if bind is not None:
            self.sock.bind(bind)

    def close(self):
        self.sock.close()

    def _next_id(self) -> int:
        self._id = (self._id + 1) & 0xFF
        return self._id

    @staticmethod
    def _pack_header(cmd4: int, flag4: int, pkt_id: int, length: int, address: int) -> bytes:
        if not (0 <= cmd4 <= 0xF):
            raise ValueError("cmd4 must be 4-bit")
        if not (0 <= flag4 <= 0xF):
            raise ValueError("flag4 must be 4-bit")
        if not (0 <= pkt_id <= 0xFF):
            raise ValueError("pkt_id must be 8-bit")
        if not (1 <= length <= 255):
            raise ValueError("length must be 1..255")
        if not (0 <= address <= 0xFFFFFFFF):
            raise ValueError("address must be 32-bit")

        b0 = 0xFF
        b1 = ((cmd4 & 0xF) << 4) | (flag4 & 0xF)
        return bytes([b0, b1, pkt_id & 0xFF, length & 0xFF]) + address.to_bytes(4, "big")

    @staticmethod
    def _parse_reply(pkt: bytes) -> RBCPReply:
        if len(pkt) < 8:
            raise RBCPError(f"short packet: {len(pkt)} bytes")
        if pkt[0] != 0xFF:
            raise RBCPError(f"unexpected VER/TYPE: 0x{pkt[0]:02X}")

        b1 = pkt[1]
        cmd = (b1 >> 4) & 0xF
        flag = b1 & 0xF
        pkt_id = pkt[2]
        length = pkt[3]
        address = int.from_bytes(pkt[4:8], "big")
        data = pkt[8:]
        return RBCPReply(cmd=cmd, flag=flag, pkt_id=pkt_id, length=length, address=address, data=data)

    def _xfer(self, payload: bytes, expect_id: int) -> RBCPReply:
        last_err: Optional[Exception] = None
        for _ in range(self.retries):
            try:
                self.sock.sendto(payload, (self.ip, self.port))
                pkt, _ = self.sock.recvfrom(4096)
                rep = self._parse_reply(pkt)

                if rep.pkt_id != expect_id:
                    raise RBCPError(f"ID mismatch: sent {expect_id}, got {rep.pkt_id}")

                # FLAG bit0: bus error
                if (rep.flag & 0x1) != 0:
                    raise RBCPError(
                        f"bus error (FLAG=0x{rep.flag:X}), len={rep.length}, addr=0x{rep.address:08X}"
                    )

                return rep
            except (socket.timeout, RBCPError) as e:
                last_err = e

        raise RBCPError(f"RBCP failed after {self.retries} tries: {last_err}")

    def read(self, address: int, length: int) -> bytes:
        pkt_id = self._next_id()
        hdr = self._pack_header(self.CMD_READ, 0x0, pkt_id, length, address)
        rep = self._xfer(hdr, pkt_id)
        if len(rep.data) < rep.length:
            raise RBCPError(f"reply data too short: need {rep.length}, got {len(rep.data)}")
        return rep.data[: rep.length]

    def write(self, address: int, data: bytes) -> bytes:
        if not data:
            raise ValueError("data must be non-empty")
        if len(data) > 255:
            raise ValueError("RBCP max length is 255 bytes; split your write.")
        pkt_id = self._next_id()
        hdr = self._pack_header(self.CMD_WRITE, 0x0, pkt_id, len(data), address)
        rep = self._xfer(hdr + data, pkt_id)
        if len(rep.data) < rep.length:
            raise RBCPError(f"reply data too short: need {rep.length}, got {len(rep.data)}")
        return rep.data[: rep.length]

    def read_u16be(self, address: int) -> int:
        b = self.read(address, 2)
        return (b[0] << 8) | b[1]

    def write_u8(self, address: int, value: int) -> None:
        self.write(address, bytes([value & 0xFF]))


def parse_int(s: str) -> int:
    # "0xFFFFFC18" も "4294966296" も通す
    return int(s, 0)


def parse_hex_bytes(s: str) -> bytes:
    # "C0A80A14" / "C0:A8:0A:14" / "c0 a8 0a 14" を許可
    cleaned = s.replace(":", "").replace(" ", "").replace("_", "")
    if len(cleaned) == 0 or (len(cleaned) % 2) != 0:
        raise argparse.ArgumentTypeError("hex bytes must have even length (e.g. C0A80A14)")
    try:
        return bytes.fromhex(cleaned)
    except ValueError as e:
        raise argparse.ArgumentTypeError(f"invalid hex bytes: {e}") from e


def parse_ipv4(s: str) -> bytes:
    parts = s.strip().split(".")
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("IPv4 must be like a.b.c.d")
    vals = []
    for p in parts:
        n = int(p, 10)
        if not (0 <= n <= 255):
            raise argparse.ArgumentTypeError("IPv4 octet out of range 0..255")
        vals.append(n)
    return bytes(vals)


def hexdump(b: bytes, base_addr: int = 0) -> str:
    # 簡易ダンプ（16byte/行）
    lines = []
    for i in range(0, len(b), 16):
        chunk = b[i : i + 16]
        hexpart = " ".join(f"{x:02X}" for x in chunk)
        asciipart = "".join(chr(x) if 32 <= x <= 126 else "." for x in chunk)
        lines.append(f"0x{(base_addr + i):08X}  {hexpart:<47}  {asciipart}")
    return "\n".join(lines)


def cmd_read(args) -> int:
    cli = RBCPClient(args.target, args.port, timeout_s=args.timeout, retries=args.retries)
    try:
        data = cli.read(args.addr, args.len)
        if args.raw_hex:
            print(data.hex())
        else:
            print(hexdump(data, base_addr=args.addr))
        return 0
    finally:
        cli.close()


def cmd_write(args) -> int:
    cli = RBCPClient(args.target, args.port, timeout_s=args.timeout, retries=args.retries)
    try:
        data = args.data
        if len(data) > 255:
            raise RBCPError("write data too long (>255). split it.")
        ack = cli.write(args.addr, data)
        if args.verify:
            rb = cli.read(args.addr, len(data))
            if rb != data:
                raise RBCPError(f"verify failed: wrote={data.hex()} readback={rb.hex()}")
        if args.quiet:
            return 0
        print(f"WROTE {len(data)} bytes to 0x{args.addr:08X}")
        print("ACK :", ack.hex())
        return 0
    finally:
        cli.close()


def cmd_set_ip(args) -> int:
    new_ip = parse_ipv4(args.new_ip)  # 4 bytes
    cli = RBCPClient(args.target, args.port, timeout_s=args.timeout, retries=args.retries)
    try:
        # 手順: FCFF に 00 を 1byte書き → FC18-1B に IP 4byte書き → readback verify
        cli.write_u8(0xFFFF_FCFF, 0x00)
        cli.write(0xFFFF_FC18, new_ip)
        rb = cli.read(0xFFFF_FC18, 4)
        if rb != new_ip:
            raise RBCPError(f"verify failed: wrote={new_ip.hex()} readback={rb.hex()}")
        if not args.quiet:
            print(f"EEPROM IP set to {args.new_ip} (FC18-1B = {new_ip.hex().upper()})")
            print("Power-cycle the board, then ping the new IP.")
        return 0
    finally:
        cli.close()


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="rbcp_tool.py", description="SiTCP RBCP EEPROM read/write tool (UDP).")
    p.add_argument("--target", required=True, help="Target board IPv4 (e.g. 192.168.10.16)")
    p.add_argument("--port", type=int, default=4660, help="RBCP UDP port (default: 4660)")
    p.add_argument("--timeout", type=float, default=0.3, help="UDP timeout seconds (default: 0.3)")
    p.add_argument("--retries", type=int, default=3, help="Retries on timeout/error (default: 3)")

    sub = p.add_subparsers(dest="cmd", required=True)

    pr = sub.add_parser("r", help="read: r --addr <hex> --len <n>")
    pr.add_argument("--addr", type=parse_int, required=True, help="Address (e.g. 0xFFFFFC18)")
    pr.add_argument("--len", type=int, required=True, help="Length 1..255")
    pr.add_argument("--raw-hex", action="store_true", help="Print bytes as one hex string")
    pr.set_defaults(func=cmd_read)

    pw = sub.add_parser("w", help="write: w --addr <hex> --data <hexbytes>")
    pw.add_argument("--addr", type=parse_int, required=True, help="Address (e.g. 0xFFFFFC18)")
    pw.add_argument("--data", type=parse_hex_bytes, required=True, help='Hex bytes: "00" or "C0A80A14" or "C0:A8:0A:14"')
    pw.add_argument("--verify", action="store_true", help="Read back and verify")
    pw.add_argument("--quiet", action="store_true", help="No stdout on success")
    pw.set_defaults(func=cmd_write)

    ps = sub.add_parser("set-ip", help="set EEPROM IP (FCFF->00 then FC18-1B->new IP)")
    ps.add_argument("--new-ip", required=True, help="New IPv4 like 192.168.10.20")
    ps.add_argument("--quiet", action="store_true", help="No stdout on success")
    ps.set_defaults(func=cmd_set_ip)

    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    # basic checks
    if args.cmd == "r":
        if not (1 <= args.len <= 255):
            raise SystemExit("len must be 1..255")
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
