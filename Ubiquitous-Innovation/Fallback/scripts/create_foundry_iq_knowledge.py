"""Create a Foundry IQ Blob knowledge base from the ADLS Gen2 data container."""
from __future__ import annotations

import argparse
import json
import os
import time
from typing import Any

import requests
from azure.identity import ClientSecretCredential


SEARCH_API_VERSION = "2026-08-01-preview"
KNOWLEDGE_SOURCE_NAME = "caldova-docs-blob"
KNOWLEDGE_BASE_NAME = "caldova-docs-kb"
PROJECT_CONNECTION_NAME = "caldova-docs-kb-connection"
RETRYABLE_STATUS_CODES = {401, 403, 404, 409, 429, 500, 502, 503, 504}


def credential_from_environment() -> ClientSecretCredential:
    required = ("AZURE_TENANT_ID", "AZURE_CLIENT_ID", "AZURE_CLIENT_SECRET")
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise RuntimeError(f"Missing credential settings: {', '.join(missing)}")
    return ClientSecretCredential(
        tenant_id=os.environ["AZURE_TENANT_ID"],
        client_id=os.environ["AZURE_CLIENT_ID"],
        client_secret=os.environ["AZURE_CLIENT_SECRET"],
    )


def bearer_headers(credential: ClientSecretCredential, scope: str) -> dict[str, str]:
    token = credential.get_token(scope).token
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


def describe_response(response: requests.Response) -> str:
    try:
        return json.dumps(response.json(), separators=(",", ":"))
    except ValueError:
        return response.text.strip()


def request_json(
    method: str,
    url: str,
    headers: dict[str, str],
    payload: dict[str, Any] | None = None,
) -> tuple[requests.Response, dict[str, Any] | None]:
    response = requests.request(method, url, headers=headers, json=payload, timeout=60)
    try:
        body = response.json()
    except ValueError:
        body = None
    return response, body


def build_blob_knowledge_source(
    storage_resource_id: str,
    foundry_resource_uri: str,
    embedding_deployment_name: str,
) -> dict[str, Any]:
    return {
        "name": KNOWLEDGE_SOURCE_NAME,
        "kind": "azureBlob",
        "description": "Caldova supply-chain documents from the ADLS Gen2 data container.",
        "azureBlobParameters": {
            "connectionString": f"ResourceId={storage_resource_id}",
            "containerName": "data",
            "folderPath": None,
            "isADLSGen2": True,
            "ingestionParameters": {
                "networkAccessMode": "public",
                "identity": None,
                "disableImageVerbalization": True,
                "embeddingModel": {
                    "kind": "azureOpenAI",
                    "azureOpenAIParameters": {
                        "resourceUri": foundry_resource_uri,
                        "deploymentId": embedding_deployment_name,
                        "modelName": "text-embedding-3-small",
                    },
                },
                "contentExtractionMode": "minimal",
                "ingestionSchedule": None,
            },
        },
    }


def build_knowledge_base(
    foundry_resource_uri: str, chat_deployment_name: str
) -> dict[str, Any]:
    return {
        "name": KNOWLEDGE_BASE_NAME,
        "description": "Grounded Caldova supply-chain document knowledge for the Ubiquitous agent.",
        "retrievalInstructions": (
            "Use this source for Caldova policies, launch plans, manufacturing procedures, "
            "and other uploaded supply-chain documents."
        ),
        "answerInstructions": "Answer using retrieved documents and preserve source citations.",
        "outputMode": "answerSynthesis",
        "knowledgeSources": [{"name": KNOWLEDGE_SOURCE_NAME}],
        "models": [
            {
                "kind": "azureOpenAI",
                "azureOpenAIParameters": {
                    "resourceUri": foundry_resource_uri,
                    "deploymentId": chat_deployment_name,
                    "modelName": "gpt-5.4",
                },
            }
        ],
        "retrievalReasoningEffort": {"kind": "auto"},
    }


def build_project_connection(mcp_url: str) -> dict[str, Any]:
    return {
        "name": PROJECT_CONNECTION_NAME,
        "type": "Microsoft.MachineLearningServices/workspaces/connections",
        "properties": {
            "authType": "ProjectManagedIdentity",
            "category": "RemoteTool",
            "target": mcp_url,
            "isSharedToAll": True,
            "audience": "https://search.azure.com/",
            "metadata": {"ApiType": "Azure"},
        },
    }


def put_when_ready(
    url: str,
    headers: dict[str, str],
    payload: dict[str, Any],
    description: str,
) -> None:
    for attempt in range(1, 61):
        response, _ = request_json("PUT", url, headers, payload)
        if response.ok:
            return
        if response.status_code not in RETRYABLE_STATUS_CODES or attempt == 60:
            raise RuntimeError(
                f"Could not create {description} ({response.status_code}): {describe_response(response)}"
            )
        print(f"{description} is not ready; waiting 10 seconds (attempt {attempt}/60)...")
        time.sleep(10)


def sync_succeeded(last_sync: dict[str, Any]) -> bool:
    # Foundry IQ can omit the optional status property for a completed sync.
    # A run with no failures or errors is successful in that response shape.
    status = str(last_sync.get("status") or "success").casefold()
    failures = int(last_sync.get("itemsUpdatesFailed") or 0)
    return status == "success" and failures == 0 and not last_sync.get("errors")


def wait_for_initial_sync(search_url: str, headers: dict[str, str]) -> None:
    status_url = (
        f"{search_url}/knowledgesources/{KNOWLEDGE_SOURCE_NAME}/status"
        f"?api-version={SEARCH_API_VERSION}"
    )
    for attempt in range(1, 181):
        response, body = request_json("GET", status_url, headers)
        if not response.ok:
            if response.status_code in RETRYABLE_STATUS_CODES and attempt < 180:
                print(f"Foundry IQ indexing is not ready; waiting 10 seconds (attempt {attempt}/180)...")
                time.sleep(10)
                continue
            raise RuntimeError(
                f"Could not read Foundry IQ indexing status ({response.status_code}): {describe_response(response)}"
            )
        last_sync = (body or {}).get("lastSynchronizationState") or {}
        if last_sync.get("endTime"):
            if sync_succeeded(last_sync):
                return
            raise RuntimeError(
                "Foundry IQ indexing failed: "
                f"status={last_sync.get('status')}, "
                f"itemsUpdatesFailed={last_sync.get('itemsUpdatesFailed')}, "
                f"errors={last_sync.get('errors')}"
            )
        print(f"Foundry IQ is indexing the data container; waiting 10 seconds (attempt {attempt}/180)...")
        time.sleep(10)
    raise RuntimeError("Foundry IQ did not complete its initial document index within 30 minutes.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--subscription-id", required=True)
    parser.add_argument("--resource-group", required=True)
    parser.add_argument("--storage-account-name", required=True)
    parser.add_argument("--search-service-name", required=True)
    parser.add_argument("--foundry-account-name", required=True)
    parser.add_argument("--project-name", required=True)
    parser.add_argument("--chat-deployment-name", required=True)
    parser.add_argument("--embedding-deployment-name", required=True)
    args = parser.parse_args()

    credential = credential_from_environment()
    search_url = f"https://{args.search_service_name}.search.windows.net"
    foundry_resource_uri = f"https://{args.foundry_account_name}.services.ai.azure.com"
    storage_resource_id = (
        f"/subscriptions/{args.subscription_id}/resourceGroups/{args.resource_group}"
        f"/providers/Microsoft.Storage/storageAccounts/{args.storage_account_name}"
    )
    project_resource_id = (
        f"/subscriptions/{args.subscription_id}/resourceGroups/{args.resource_group}"
        f"/providers/Microsoft.CognitiveServices/accounts/{args.foundry_account_name}"
        f"/projects/{args.project_name}"
    )
    search_headers = bearer_headers(credential, "https://search.azure.com/.default")
    management_headers = bearer_headers(credential, "https://management.azure.com/.default")

    source_url = f"{search_url}/knowledgesources/{KNOWLEDGE_SOURCE_NAME}?api-version={SEARCH_API_VERSION}"
    put_when_ready(
        source_url,
        search_headers,
        build_blob_knowledge_source(
            storage_resource_id,
            foundry_resource_uri,
            args.embedding_deployment_name,
        ),
        "Foundry IQ Blob knowledge source",
    )
    wait_for_initial_sync(search_url, search_headers)

    knowledge_base_url = f"{search_url}/knowledgebases/{KNOWLEDGE_BASE_NAME}?api-version={SEARCH_API_VERSION}"
    put_when_ready(
        knowledge_base_url,
        search_headers,
        build_knowledge_base(foundry_resource_uri, args.chat_deployment_name),
        "Foundry IQ knowledge base",
    )
    mcp_url = f"{search_url}/knowledgebases/{KNOWLEDGE_BASE_NAME}/mcp?api-version={SEARCH_API_VERSION}"
    connection_url = (
        f"https://management.azure.com{project_resource_id}/connections/{PROJECT_CONNECTION_NAME}"
        "?api-version=2025-10-01-preview"
    )
    put_when_ready(
        connection_url,
        management_headers,
        build_project_connection(mcp_url),
        "Foundry IQ project connection",
    )
    print(
        json.dumps(
            {
                "knowledgeBaseName": KNOWLEDGE_BASE_NAME,
                "mcpUrl": mcp_url,
                "projectConnectionName": PROJECT_CONNECTION_NAME,
            }
        )
    )


if __name__ == "__main__":
    main()
