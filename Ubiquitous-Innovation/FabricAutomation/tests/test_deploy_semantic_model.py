"""Regression tests for Direct Lake source-table readiness handling."""
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch


MODULE_PATH = Path(__file__).parents[1] / "scripts" / "deploy_semantic_model.py"
SPEC = importlib.util.spec_from_file_location("deploy_semantic_model", MODULE_PATH)
assert SPEC and SPEC.loader
semantic_model = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(semantic_model)


class DirectLakeReadinessTests(unittest.TestCase):
    def test_missing_source_entities_uses_physical_dim_plant_name(self) -> None:
        tables = [{"name": name} for name in semantic_model.expected_source_entities() - {"DimPlant"}]
        self.assertEqual(semantic_model.missing_source_entities(tables), {"DimPlant"})

    def test_missing_source_entities_is_empty_when_all_entities_are_visible(self) -> None:
        tables = [{"name": name} for name in semantic_model.expected_source_entities()]
        self.assertEqual(semantic_model.missing_source_entities(tables), set())

    def test_recognizes_only_temporary_direct_lake_table_error(self) -> None:
        refresh = {
            "serviceExceptionJson": (
                '{"errorCode":"ModelRefresh_ShortMessage_ProcessingError",'
                '"errorDescription":"We cannot refresh this semantic model because one or multiple '
                'source tables either do not exist or access was denied."}'
            )
        }
        self.assertTrue(semantic_model.is_transient_direct_lake_source_error(refresh))
        self.assertFalse(semantic_model.is_transient_direct_lake_source_error({"status": "Failed"}))

    def test_wait_for_lakehouse_tables_retries_empty_catalog(self) -> None:
        class DelayedCatalog:
            calls = 0

            def list_all(self, _: str) -> list[dict]:
                self.calls += 1
                if self.calls == 1:
                    return []
                return [{"name": name} for name in semantic_model.expected_source_entities()]

        catalog = DelayedCatalog()
        with patch.object(semantic_model.time, "sleep"):
            semantic_model.wait_for_lakehouse_tables(catalog, "workspace", "lakehouse")
        self.assertEqual(catalog.calls, 2)

    def test_wait_for_lakehouse_tables_does_not_mask_forbidden_access(self) -> None:
        class ForbiddenCatalog:
            def list_all(self, _: str) -> list[dict]:
                raise semantic_model.FabricRequestError("GET", "/tables", 403, "forbidden")

        with self.assertRaises(semantic_model.FabricRequestError):
            semantic_model.wait_for_lakehouse_tables(ForbiddenCatalog(), "workspace", "lakehouse")


if __name__ == "__main__":
    unittest.main()
