#!/usr/bin/env python3
"""把 krkr2 编出的各静态库拆成目标文件并按内容去重，放到一个文件夹里，供构建KiriKiri.sh 预链接。
插件的源文件会经 CMake 的接口依赖编进好几个库，同一个目标文件出现多次，直接一起链接会重复定义。
同一个库里也会有同名成员（例如好几个 main.cpp.o），ar x 会互相覆盖，所以这里自己解析 ar 格式。
用法：去重KiriKiri目标文件.py <输出文件夹> <静态库>..."""
import hashlib, os, sys


def members(path):
    data = open(path, "rb").read()
    assert data[:8] == b"!<arch>\n", path
    i = 8
    while i + 60 <= len(data):
        header = data[i:i + 60]
        name = header[:16].decode().strip()
        size = int(header[48:58].decode().strip())
        body = data[i + 60:i + 60 + size]
        if name.startswith("#1/"):
            # BSD 长文件名：名字放在内容开头
            length = int(name[3:])
            name = body[:length].rstrip(b"\0").decode()
            body = body[length:]
        yield name, body
        i += 60 + size + (size & 1)


out = sys.argv[1]
os.makedirs(out, exist_ok=True)
seen = set()
for archive in sys.argv[2:]:
    for name, body in members(archive):
        if not name.endswith(".o"):
            continue
        digest = hashlib.sha1(body).digest()
        if digest in seen:
            continue
        seen.add(digest)
        with open(os.path.join(out, f"{len(seen):04d}_{name}"), "wb") as f:
            f.write(body)
print(len(seen))
