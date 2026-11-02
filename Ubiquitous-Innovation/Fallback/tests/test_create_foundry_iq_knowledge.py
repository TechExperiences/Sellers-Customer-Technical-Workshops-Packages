"""Regression tests for Foundry IQ knowledge-base request shapes."""
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "scripts" / "create_foundry_iq_knowledge.py"
SPEC = importlib.util.spec_from_file_location("create_foundry_iq_knowledge", MODULE_PATH)
assert SPEC and SPEC.loader
knowledge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(knowledge)


class FoundryIqKnowledgePayloadTests(unittest.TestCase):
    def test_blob_source_uses_managed_identity_and_the_data_container(self) -> None:
        source = knowledge.build_blob_knowledge_source(
            "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/adls",
            "https://foundry.services.ai.azure.com",
            "gpt54",
            "textembedding3small",
        )

        parameters = source["azureBlobParameters"]
        ingestion = parameters["ingestionParameters"]
        self.assertEqual(source["name"], "caldova-docs-blob")
        self.assertEqual(parameters["containerName"], "data")
        self.assertTrue(parameters["isADLSGen2"])
        self.assertEqual(
            parameters["connectionString"],
            "ResourceId=/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/adls",
        )
        self.assertEqual(
            ingestion["chatCompletionModel"]["azureOpenAIParameters"]["deploymentId"], "gpt54"
        )
        self.assertEqual(
            ingestion["embeddingModel"]["azureOpenAIParameters"]["deploymentId"],
            "textembedding3small",
        )

    def test_knowledge_base_and_connection_target_foundry_iq_mcp(self) -> None:
        knowledge_base = knowledge.build_knowledge_base(
            "https://foundry.services.ai.azure.com", "gpt54"
        )
        mcp_url = (
            "https://search.search.windows.net/knowledgebases/caldova-docs-kb/"
            "mcp?api-version=2026-08-01-preview"
        )
        connection = knowledge.build_project_connection(mcp_url)

        self.assertEqual(knowledge_base["name"], "caldova-docs-kb")
        self.assertEqual(knowledge_base["knowledgeSources"], [{"name": "caldova-docs-blob"}])
        self.assertEqual(connection["properties"]["category"], "RemoteTool")
        self.assertEqual(connection["properties"]["authType"], "ProjectManagedIdentity")
        self.assertEqual(connection["properties"]["target"], mcp_url)


if __name__ == "__main__":
    unittest.main()
