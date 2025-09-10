import os, time
import psycopg2
from typing import Tuple

# ENV (подтягиваем из .env)
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "postgres")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASS = os.getenv("DB_PASS", "")
INTERVAL_SEC = float(os.getenv("INTERVAL_SEC", "1.0"))
DISK_PATH = os.getenv("DISK_PATH", "/host_root")

# Пути хоста, смонтированные в контейнер
PROC = "/host_proc"
MEMINFO = f"{PROC}/meminfo"
STAT    = f"{PROC}/stat"
NETDEV  = f"{PROC}/net/dev"

SQL_INSERT = """
INSERT INTO server.metrics (
  "timestamp",
  cpu_usage,
  ram_total, ram_used, ram_free, ram_available, ram_cache, ram_usage_percent,
  swap_total, swap_used, swap_free, swap_usage_percent,
  disk_total_gb, disk_used_gb, disk_usage_percent,
  net_rx_mb, net_tx_mb
) VALUES (
  NOW(),
  %s,
  %s, %s, %s, %s, %s, %s,
  %s, %s, %s, %s,
  %s, %s, %s,
  %s, %s
);
"""

def kb_to_mb(x): return int(round(x / 1024)) if x is not None else None

def read_meminfo():
    kv = {}
    with open(MEMINFO, "r") as f:
        for line in f:
            parts = line.split()
            key = parts[0].rstrip(':')
            if len(parts) >= 2 and parts[1].isdigit():
                kv[key] = int(parts[1])  # kB
    mem_total = kb_to_mb(kv.get("MemTotal"))
    mem_free  = kb_to_mb(kv.get("MemFree"))
    mem_avail = kb_to_mb(kv.get("MemAvailable"))
    cached    = kb_to_mb(kv.get("Cached"))
    mem_used  = (mem_total - mem_avail) if (mem_total and mem_avail) else None
    ram_pct   = round((mem_used / mem_total) * 100, 1) if (mem_used and mem_total) else None

    swap_total = kb_to_mb(kv.get("SwapTotal"))
    swap_free  = kb_to_mb(kv.get("SwapFree"))
    swap_used  = (swap_total - swap_free) if (swap_total is not None and swap_free is not None) else None
    swap_pct   = round((swap_used / swap_total) * 100, 1) if (swap_used and swap_total) else None

    return {
        "ram_total": mem_total, "ram_used": mem_used, "ram_free": mem_free,
        "ram_available": mem_avail, "ram_cache": cached, "ram_usage_percent": ram_pct,
        "swap_total": swap_total, "swap_used": swap_used, "swap_free": swap_free,
        "swap_usage_percent": swap_pct,
    }

def read_net_counters_mb() -> Tuple[int,int]:
    rx = 0; tx = 0
    with open(NETDEV, "r") as f:
        lines = f.readlines()[2:]
        for line in lines:
            parts = line.replace(":", " ").split()
            if len(parts) < 17: continue
            iface = parts[0]
            if iface == "lo": continue
            rx_bytes = int(parts[1]); tx_bytes = int(parts[9])
            rx += rx_bytes; tx += tx_bytes
    return int(rx / (1024*1024)), int(tx / (1024*1024))

def read_disk_gb() -> Tuple[float,float,float]:
    s = os.statvfs(DISK_PATH)
    total_gb = (s.f_frsize * s.f_blocks) / (1024**3)
    free_gb  = (s.f_frsize * s.f_bfree) / (1024**3)
    used_gb  = total_gb - free_gb
    pct = round((used_gb / total_gb) * 100, 1) if total_gb > 0 else None
    return round(total_gb, 6), round(used_gb, 6), pct

def read_cpu_times():
    with open(STAT, "r") as f:
        fields = f.readline().split()
        nums = list(map(int, fields[1:]))
    user,nice,system,idle,iowait,irq,softirq,steal,*_ = nums + [0]*(10-len(nums))
    idle_all = idle + iowait
    non_idle = user + nice + system + irq + softirq + steal
    total = idle_all + non_idle
    return total, idle_all

def connect_db():
    return psycopg2.connect(
        host=DB_HOST, port=DB_PORT, dbname=DB_NAME, user=DB_USER, password=DB_PASS
    )

def main():
    prev_total, prev_idle = read_cpu_times()
    time.sleep(0.25)  # пауза перед первой дельтой
    conn = None; cur = None

    while True:
        try:
            total, idle = read_cpu_times()
            dt_total = total - prev_total
            dt_idle  = idle - prev_idle
            prev_total, prev_idle = total, idle
            cpu_pct = None
            if dt_total > 0:
                cpu_pct = round((1.0 - (dt_idle / dt_total)) * 100.0, 1)

            mem = read_meminfo()
            total_gb, used_gb, disk_pct = read_disk_gb()
            rx_mb, tx_mb = read_net_counters_mb()

            if conn is None or conn.closed:
                conn = connect_db()
                conn.autocommit = True
                cur = conn.cursor()

            cur.execute(SQL_INSERT, (
                cpu_pct,
                mem["ram_total"], mem["ram_used"], mem["ram_free"], mem["ram_available"], mem["ram_cache"], mem["ram_usage_percent"],
                mem["swap_total"], mem["swap_used"], mem["swap_free"], mem["swap_usage_percent"],
                total_gb, used_gb, disk_pct,
                rx_mb, tx_mb
            ))
        except Exception as e:
            print("metrics-agent error:", e, flush=True)
            try:
                if cur: cur.close()
                if conn: conn.close()
            except: pass
            conn = None; cur = None
            time.sleep(1.0)
        finally:
            time.sleep(INTERVAL_SEC)

if __name__ == "__main__":
    main()
