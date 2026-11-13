"""备份脚本：真的跑一遍 gpg 加密，再解开核对内容。"""
import os
import shutil
import sqlite3
import subprocess
import sys
import tarfile
import time

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
pytestmark = pytest.mark.skipif(not shutil.which("gpg"), reason="本机没有 gpg")


def run_backup(env):
    return subprocess.run([sys.executable, os.path.join(ROOT, "backup.py")],
                          env={**os.environ, **env}, capture_output=True, text=True)


@pytest.fixture
def setup(tmp_path):
    db_path = tmp_path / "totp.db"
    db = sqlite3.connect(db_path)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("CREATE TABLE accounts(id INTEGER PRIMARY KEY, name TEXT)")
    db.execute("INSERT INTO accounts(name) VALUES ('fake-account')")
    db.commit()
    db.close()
    (tmp_path / "env").write_text("FERNET_KEY=fake-key-for-test\n")
    (tmp_path / "backup.pass").write_text("test-passphrase-0123456789\n")
    env = {"DATABASE_PATH": str(db_path), "ENV_FILE": str(tmp_path / "env"),
           "BACKUP_DIR": str(tmp_path / "out"), "BACKUP_PASSPHRASE_FILE": str(tmp_path / "backup.pass"),
           "BACKUP_KEEP_DAYS": "30", "BACKUP_KEEP_MIN": "2"}
    return tmp_path, env


def test_backup_roundtrip(setup):
    tmp_path, env = setup
    r = run_backup(env)
    assert r.returncode == 0, r.stderr
    files = sorted((tmp_path / "out").glob("totp-share-*.tar.gpg"))
    assert len(files) == 1 and oct(files[0].stat().st_mode)[-3:] == "600"
    assert not list((tmp_path / "out").glob(".work-*"))            # 临时目录清干净了
    assert b"fake-account" not in files[0].read_bytes()             # 确实加密了
    assert b"fake-key-for-test" not in files[0].read_bytes()

    restored = tmp_path / "restored"
    restored.mkdir()
    gnupg = tmp_path / "gnupg"
    gnupg.mkdir(mode=0o700)
    subprocess.run(["gpg", "--batch", "--quiet", "--pinentry-mode", "loopback",
                    "--passphrase-file", env["BACKUP_PASSPHRASE_FILE"],
                    "--decrypt", "-o", str(restored / "b.tar"), str(files[0])],
                   env={**os.environ, "GNUPGHOME": str(gnupg)}, check=True)
    with tarfile.open(restored / "b.tar") as tar:
        assert sorted(tar.getnames()) == ["env", "totp.db"]
        tar.extractall(restored, filter="data")
    assert (restored / "env").read_text() == "FERNET_KEY=fake-key-for-test\n"
    db = sqlite3.connect(restored / "totp.db")
    assert db.execute("SELECT name FROM accounts").fetchall() == [("fake-account",)]
    db.close()


def test_backup_prunes_old_but_keeps_minimum(setup):
    tmp_path, env = setup
    out = tmp_path / "out"
    out.mkdir()
    old = time.time() - 90 * 86400
    for i in range(4):
        f = out / f"totp-share-2020010{i}-000000Z.tar.gpg"
        f.write_bytes(b"x")
        os.utime(f, (old, old))
    assert run_backup(env).returncode == 0
    names = sorted(p.name for p in out.glob("totp-share-*.tar.gpg"))
    # 4 份过期旧备份 + 1 份新备份；至少保留最新 2 份 → 留下最新的旧备份和刚生成的这份
    assert len(names) == 2 and names[0] == "totp-share-20200103-000000Z.tar.gpg"


def test_backup_fails_clearly_without_passphrase(setup):
    tmp_path, env = setup
    os.remove(env["BACKUP_PASSPHRASE_FILE"])
    r = run_backup(env)
    assert r.returncode == 1 and "口令文件" in r.stderr
    assert not list((tmp_path / "out").glob("*")) if (tmp_path / "out").exists() else True
