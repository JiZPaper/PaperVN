#!/usr/bin/env python3
"""通过 R2 的 S3 兼容 API 上传文件（分段上传，没有 300 MB 限制）。

凭据从环境变量读取，不写进仓库：
  R2_ACCOUNT_ID         Cloudflare 账户 ID
  R2_ACCESS_KEY_ID      R2 API 令牌的 Access Key ID
  R2_SECRET_ACCESS_KEY  R2 API 令牌的 Secret Access Key
  R2_BUCKET             存储桶名称

用法：
  .build/smart-search-venv/bin/python Tools/上传到R2.py .build/smart-search-model/PaperVNSmartSearch.pvss Resources/PaperVNSmartSearch.pvss
"""

from __future__ import annotations

import os
import sys
import threading
from pathlib import Path

import boto3
from boto3.s3.transfer import TransferConfig
from botocore.config import Config


def 环境变量(名称: str) -> str:
    值 = os.environ.get(名称)
    if not 值:
        sys.exit(f"缺少环境变量 {名称}")
    return 值


class 进度:
    def __init__(self, 总字节: int):
        self.总字节 = 总字节
        self.已上传 = 0
        self.锁 = threading.Lock()

    def __call__(self, 字节: int):
        with self.锁:
            self.已上传 += 字节
            print(f"\r{self.已上传 / 1e6:.1f} / {self.总字节 / 1e6:.1f} MB", end="", flush=True)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    文件 = Path(sys.argv[1])
    对象键 = sys.argv[2].lstrip("/")
    客户端 = boto3.client(
        "s3",
        endpoint_url=f"https://{环境变量('R2_ACCOUNT_ID')}.r2.cloudflarestorage.com",
        aws_access_key_id=环境变量("R2_ACCESS_KEY_ID"),
        aws_secret_access_key=环境变量("R2_SECRET_ACCESS_KEY"),
        region_name="auto",
        config=Config(retries={"max_attempts": 10, "mode": "standard"}),
    )
    客户端.upload_file(
        str(文件),
        环境变量("R2_BUCKET"),
        对象键,
        ExtraArgs={"ContentType": "application/octet-stream"},
        Config=TransferConfig(multipart_threshold=64 * 1024 * 1024, multipart_chunksize=64 * 1024 * 1024),
        Callback=进度(文件.stat().st_size),
    )
    print(f"\n已上传到 {对象键}")


if __name__ == "__main__":
    main()
