#!/usr/bin/env python3
"""TOTP-Share 加密备份。

把「数据库的一致性快照 + 密钥文件」打成一个包，用口令做 AES-256 加密（GnuPG 对称加密），
写到备份目录，并清理过期的旧备份。由 systemd 定时器每天执行一次，也可以手动跑：

    sudo systemctl start totp-share-backup        # 或直接: sudo python3 backup.py

为什么要把密钥文件一起备份：数据库里的 TOTP 密钥是用 FERNET_KEY 加密的，
只有数据库没有密钥文件，等于什么都没有。

恢复（在任何装了 gpg 的机器上，会提示输入口令）：

    gpg --decrypt totp-share-20261113-201000Z.tar.gpg | tar -x
    # 得到 totp.db（数据库）和 env（密钥文件）

口令保存在服务器的 BACKUP_PASSPHRASE_FILE 里。请把它另外抄一份放到密码管理器：
服务器整台丢失时，光有备份文件没有口令同样解不开。

只依赖 Python 标准库和系统自带的 gpg。配置全部来自环境变量：
    DATABASE_PATH            数据库路径（必填，与应用共用同一个环境文件）
    ENV_FILE                 密钥文件，默认 /etc/totp-share/env
    BACKUP_DIR               备份目录，默认 /var/backups/totp-share
    BACKUP_PASSPHRASE_FILE   口令文件，默认 /etc/totp-share/backup.pass
    BACKUP_KEEP_DAYS         保留天数，默认 30
    BACKUP_KEEP_MIN          不论多旧至少保留的份数，默认 7
"""
import glob
import hashlib
import os
import shutil
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
import time

PREFIX = "totp-share-"
SUFFIX = ".tar.gpg"


def fail(msg):
    print(f"备份失败：{msg}", file=sys.stderr)
    sys.exit(1)


def snapshot_database(src_path, dst_path):
    """用 SQLite 的在线备份接口取快照：应用正在读写也能得到一致的副本。"""
    src = sqlite3.connect(f"file:{src_path}?mode=ro", uri=True, timeout=30)
    dst = sqlite3.connect(dst_path)
    try:
        src.backup(dst)
        result = dst.execute("PRAGMA integrity_check").fetchone()[0]
    finally:
        dst.close()
        src.close()
    if result != "ok":
        fail(f"快照完整性检查未通过：{result}")
    # 以 root 身份读库时，SQLite 会把它新建的 -wal/-shm 文件属主对齐到数据库文件；
    # 这里再核对一遍，避免留下应用用户读写不了的文件把线上服务卡住。
    owner = os.stat(src_path)
    for side in glob.glob(src_path + "-*"):
        st = os.stat(side)
        if (st.st_uid, st.st_gid) != (owner.st_uid, owner.st_gid):
            os.chown(side, owner.st_uid, owner.st_gid)


def gpg(args, workdir, **kw):
    env = dict(os.environ, GNUPGHOME=os.path.join(workdir, "gnupg"))
    os.makedirs(env["GNUPGHOME"], mode=0o700, exist_ok=True)
    return subprocess.run(["gpg", "--batch", "--yes", "--quiet", "--no-tty",
                           "--pinentry-mode", "loopback"] + args,
                          env=env, check=True, **kw)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def prune(backup_dir, keep_days, keep_min):
    files = sorted(glob.glob(os.path.join(backup_dir, PREFIX + "*" + SUFFIX)))
    cutoff = time.time() - keep_days * 86400
    removed = 0
    for path in files[:-keep_min] if keep_min else files:
        if os.path.getmtime(path) < cutoff:
            os.remove(path)
            removed += 1
    return removed


def main():
    db_path = os.environ.get("DATABASE_PATH") or fail("没有设置 DATABASE_PATH")
    env_file = os.environ.get("ENV_FILE", "/etc/totp-share/env")
    backup_dir = os.environ.get("BACKUP_DIR", "/var/backups/totp-share")
    pass_file = os.environ.get("BACKUP_PASSPHRASE_FILE", "/etc/totp-share/backup.pass")
    keep_days = int(os.environ.get("BACKUP_KEEP_DAYS", "30"))
    keep_min = int(os.environ.get("BACKUP_KEEP_MIN", "7"))

    for path, what in ((db_path, "数据库"), (env_file, "密钥文件"), (pass_file, "口令文件")):
        if not os.path.isfile(path):
            fail(f"找不到{what} {path}")
    if os.path.getsize(pass_file) < 16:
        fail(f"口令文件 {pass_file} 内容太短（至少 16 个字符）")
    if not shutil.which("gpg"):
        fail("系统里没有 gpg，请先安装 gnupg")

    os.umask(0o077)
    os.makedirs(backup_dir, mode=0o700, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%SZ", time.gmtime())
    final = os.path.join(backup_dir, f"{PREFIX}{stamp}{SUFFIX}")

    work = tempfile.mkdtemp(prefix=".work-", dir=backup_dir)
    try:
        snapshot_database(db_path, os.path.join(work, "totp.db"))
        shutil.copyfile(env_file, os.path.join(work, "env"))
        plain = os.path.join(work, "backup.tar")
        with tarfile.open(plain, "w") as tar:
            tar.add(os.path.join(work, "totp.db"), arcname="totp.db")
            tar.add(os.path.join(work, "env"), arcname="env")

        encrypted = os.path.join(work, "backup.tar.gpg")
        gpg(["--passphrase-file", pass_file, "--symmetric", "--cipher-algo", "AES256",
             "--s2k-digest-algo", "SHA512", "--s2k-count", "65011712",
             "-o", encrypted, plain], work)

        # 回读校验：解不开或内容对不上的备份等于没有备份
        check = os.path.join(work, "check.tar")
        gpg(["--passphrase-file", pass_file, "--decrypt", "-o", check, encrypted], work)
        if sha256(check) != sha256(plain):
            fail("加密后的备份解密出来与原始内容不一致")

        os.chmod(encrypted, 0o600)
        os.replace(encrypted, final)
    except subprocess.CalledProcessError as e:
        fail(f"gpg 执行出错（退出码 {e.returncode}）")
    finally:
        shutil.rmtree(work, ignore_errors=True)

    removed = prune(backup_dir, keep_days, keep_min)
    total = len(glob.glob(os.path.join(backup_dir, PREFIX + "*" + SUFFIX)))
    print(f"备份完成：{final}（{os.path.getsize(final)} 字节），"
          f"清理过期 {removed} 份，现存 {total} 份")


if __name__ == "__main__":
    main()
