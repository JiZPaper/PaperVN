#!/usr/bin/env python3
"""把静态库里最低系统版本高于目标的成员改标成目标版本，只改版本号，代码不动。

Live2D 官方的 Cubism Core（5-r.5）标的是 iOS 26.2，链接时每个成员都报
“built for newer 'iOS' version”。它只依赖 libc 基础函数，所以直接改标记。
Live2D 协议第 6.1 条限制修改软件，换 Core 版本时先看新版标的版本，能不改就不改。

用法：修正静态库最低系统版本.py <libxxx.a> <版本，如 18.0>
原地修改，文件大小和成员位置都不变。
"""
import struct
import sys

MH_MAGIC_64 = b"\xcf\xfa\xed\xfe"
LC_BUILD_VERSION = 0x32
AR_HEADER_SIZE = 60


def encode_version(text):
    parts = [int(part) for part in text.split(".")] + [0, 0]
    return parts[0] << 16 | parts[1] << 8 | parts[2]


def decode_version(value):
    return f"{value >> 16}.{value >> 8 & 0xff}"


def members(data):
    """逐个给出成员的（名称，内容起点，内容长度）。"""
    if data[:8] != b"!<arch>\n":
        raise SystemExit("error: 不是单一架构的静态库")
    offset = 8
    while offset < len(data):
        header = data[offset:offset + AR_HEADER_SIZE]
        if header[58:60] != b"`\n":
            raise SystemExit(f"error: 偏移 {offset} 处的成员头损坏")
        name = header[:16].decode("ascii").rstrip()
        size = int(header[48:58].decode("ascii"))
        start = offset + AR_HEADER_SIZE
        length = size
        if name.startswith("#1/"):  # BSD 长文件名：名称放在内容开头
            name_length = int(name[3:])
            name = data[start:start + name_length].rstrip(b"\0").decode("utf-8")
            start += name_length
            length -= name_length
        yield name, start, length
        offset += AR_HEADER_SIZE + size + size % 2


def patch_member(data, start, length, target):
    """改掉一个成员的 LC_BUILD_VERSION，返回原来的版本；不需要改时返回 None。"""
    if length < 32 or data[start:start + 4] != MH_MAGIC_64:
        return None
    command_count = struct.unpack_from("<I", data, start + 16)[0]
    command = start + 32
    for _ in range(command_count):
        kind, size = struct.unpack_from("<II", data, command)
        if kind == LC_BUILD_VERSION:
            minos = struct.unpack_from("<I", data, command + 12)[0]
            if minos <= target:
                return None
            struct.pack_into("<I", data, command + 12, target)
            return minos
        command += size
    return None


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    path, target = sys.argv[1], encode_version(sys.argv[2])
    with open(path, "rb") as file:
        data = bytearray(file.read())
    patched = []
    for name, start, length in members(data):
        old = patch_member(data, start, length, target)
        if old is not None:
            patched.append(f"{name}（{decode_version(old)}）")
    if patched:
        with open(path, "r+b") as file:
            file.write(data)
    print(f"{path}：修正 {len(patched)} 个成员 → {decode_version(target)}")
    for item in patched:
        print(f"  {item}")


if __name__ == "__main__":
    main()
