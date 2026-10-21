"""
ez_db_adapter.py - Shared Instance Data Mapper for Python Services (FastAPI / Celery)
"""

import os
import threading
from typing import Dict, Any, Optional
from ez_dbengine import EzDBEngine


class EzDbAdapter:
    _instance: Optional['EzDbAdapter'] = None
    _lock = threading.Lock()

    def __new__(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super(EzDbAdapter, cls).__new__(cls)
                    cls._instance._engine = EzDBEngine.get_instance()
                    cls._instance._handles: Dict[str, int] = {}
                    cls._instance._map_lock = threading.Lock()
        return cls._instance

    @classmethod
    def get_instance(cls) -> 'EzDbAdapter':
        return cls()

    def get_handle(self, table_name: str) -> int:
        file_path = os.path.join("data", f"{table_name}.ebf")
        if file_path not in self._handles:
            with self._map_lock:
                if file_path not in self._handles:
                    h = self._engine.use(file_path)
                    self._handles[file_path] = h
        return self._handles[file_path]

    def insert(self, table_name: str, data: Dict[str, Any]) -> int:
        h = self.get_handle(table_name)
        fdt = self._engine.get_fdt(h)

        values = [str(data.get(f["name"], "")) for f in fdt]
        csv_payload = ",".join(values)

        status = self._engine.append(h, csv_payload, 1, ",")
        if status != 0:
            raise RuntimeError(f"Atomic append failed on table: {table_name} | {self._engine.get_detailed_error(status)}")

        commit_status = self._engine.commit(h)
        if commit_status != 0:
            raise RuntimeError(f"Commit failed on table: {table_name} | {self._engine.get_detailed_error(commit_status)}")

        return self._engine.get_record_count(h)