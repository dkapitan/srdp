"""Abstract base class for pluggable storage backends."""

from abc import ABC, abstractmethod

import duckdb


class StorageBackend(ABC):
    """Base class for DuckLake storage backends.

    Each backend defines where DuckLake stores its Parquet data files
    and how DuckDB connects to that storage.
    """

    @abstractmethod
    def get_base_path(self) -> str:
        """Return the root path for DuckLake file storage.

        For local storage this is a filesystem path.
        For cloud storage this is a URI (e.g. ``s3://bucket/prefix/``).

        Returns:
            The root path or URI used as DuckLake's DATA_PATH.
        """

    @abstractmethod
    def configure_duckdb(self, conn: duckdb.DuckDBPyConnection) -> None:
        """Configure a DuckDB connection to access this storage.

        Install and load any required extensions and set any credentials
        needed to reach the storage location.

        Args:
            conn: An open DuckDB connection to configure.
        """
