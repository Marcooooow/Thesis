"""
Thread-safe in-memory TTL cache for analytics aggregations.
"""
import time
import threading
import logging
from typing import Any, Optional, Tuple

logger = logging.getLogger("intellibreak.cache")
if not logger.handlers:
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s"))
    logger.addHandler(handler)
logger.setLevel(logging.INFO)


class TTLCache:
    """Thread-safe in-memory TTL cache with automatic expiration and prefix invalidation."""
    def __init__(self, default_ttl: int = 60, max_size: int = 1000):
        self.default_ttl = default_ttl
        self.max_size = max_size
        self._store = {}
        self._lock = threading.Lock()

    def get(self, key: tuple) -> Optional[Any]:
        with self._lock:
            entry = self._store.get(key)
            key_hash = hash(key)
            if not entry:
                logger.info("CACHE MISS | key_hash=%s", key_hash)
                return None
            val, expiry = entry
            if time.time() > expiry:
                logger.info("CACHE EXPIRED | key_hash=%s", key_hash)
                del self._store[key]
                return None
            logger.info("CACHE HIT | key_hash=%s", key_hash)
            return val

    def set(self, key: tuple, value: Any, ttl: Optional[int] = None):
        with self._lock:
            if len(self._store) >= self.max_size:
                now = time.time()
                expired_keys = [k for k, (v, exp) in self._store.items() if now > exp]
                for k in expired_keys:
                    del self._store[k]
                if len(self._store) >= self.max_size:
                    self._store.pop(next(iter(self._store)))

            expiry = time.time() + (ttl if ttl is not None else self.default_ttl)
            self._store[key] = (value, expiry)

    def invalidate(self, prefix: Optional[tuple] = None):
        with self._lock:
            if prefix is None:
                self._store.clear()
                logger.info("CACHE INVALIDATED | scope=all")
            else:
                keys_to_del = [k for k in self._store.keys() if k[:len(prefix)] == prefix]
                for k in keys_to_del:
                    del self._store[k]
                logger.info("CACHE INVALIDATED | scope=prefix prefix_len=%d removed_count=%d", len(prefix), len(keys_to_del))


# Singleton analytics cache instance (60-second TTL)
analytics_cache = TTLCache(default_ttl=60)
