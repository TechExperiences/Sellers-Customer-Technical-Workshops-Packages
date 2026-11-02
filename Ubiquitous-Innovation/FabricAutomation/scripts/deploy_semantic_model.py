"""Deploy a Direct Lake semantic model for the Ubiquitous Innovation Lakehouse."""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
import uuid

import requests

FABRIC_API = "https://api.fabric.microsoft.com/v1"
LINEAGE_NAMESPACE = uuid.UUID("c51ee716-a8e0-5ab9-a34d-1dc5a09898d6")

# These definitions match the six CSV-backed Delta tables written by
# ingest_to_lakehouse.py into the Lakehouse dbo schema.
LAKEHOUSE_TABLES: dict[str, dict[str, object]] = {
    "EquipmentQualification": {"entity": "EquipmentQualification", "columns": [
        ("QualificationID", "string"), ("PlantID", "string"), ("EquipmentID", "string"),
        ("EquipmentName", "string"), ("QualificationStatus", "string"), ("QualificationExpiryDate", "dateTime"),
    ]},
    "Inventory": {"entity": "Inventory", "columns": [
        ("InventoryID", "string"), ("ProductID", "string"), ("PlantID", "string"),
        ("AvailableQuantity", "int64"), ("ReservedQuantity", "int64"), ("InventoryDate", "dateTime"),
    ]},
    "Plant": {"entity": "DimPlant", "columns": [
        ("PlantID", "string"), ("PlantName", "string"), ("Location", "string"),
        ("Country", "string"), ("PlantObservationDate", "dateTime"),
    ]},
    "PlantCapacity": {"entity": "PlantCapacity", "columns": [
        ("CapacityID", "string"), ("PlantID", "string"), ("CapacityMonth", "dateTime"),
        ("AvailableCapacity", "int64"), ("UsedCapacity", "int64"), ("CapacityUnit", "string"),
    ]},
    "Product": {"entity": "Product", "columns": [
        ("ProductID", "string"), ("ProductName", "string"), ("Market", "string"),
        ("LaunchDate", "dateTime"), ("RequiredQuantity", "int64"),
    ]},
    "ProductionPlan": {"entity": "ProductionPlan", "columns": [
        ("PlanID", "string"), ("ProductID", "string"), ("PlantID", "string"), ("BatchNumber", "string"),
        ("PlannedQuantity", "int64"), ("PlannedStartDate", "dateTime"), ("PlannedEndDate", "dateTime"),
        ("Status", "string"),
    ]},
}

# The dimension side is always the final table/column in each tuple.
RELATIONSHIPS = [
    ("Inventory", "ProductID", "Product", "ProductID"),
    ("Inventory", "PlantID", "Plant", "PlantID"),
    ("PlantCapacity", "PlantID", "Plant", "PlantID"),
    ("ProductionPlan", "ProductID", "Product", "ProductID"),
    ("ProductionPlan", "PlantID", "Plant", "PlantID"),
    ("EquipmentQualification", "PlantID", "Plant", "PlantID"),
]

LAKEHOUSE_TABLE_READY_ATTEMPTS = 120
DIRECT_LAKE_REFRESH_ATTEMPTS = 20
RETRY_DELAY_SECONDS = 5
REFRESH_RETRY_DELAY_SECONDS = 15


def token(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"{name} is missing. Run this script through .\\up.ps1.")
    return value


class FabricRequestError(RuntimeError):
    """A Fabric REST failure that preserves the status code for retry decisions."""

    def __init__(self, method: str, path: str, status_code: int, response_text: str) -> None:
        super().__init__(f"{method} {path} -> {status_code}: {response_text}")
        self.status_code = status_code


class FabricApi:
    def __init__(self, access_token: str) -> None:
        self.session = requests.Session()
        self.session.headers.update({"Authorization": f"Bearer {access_token}", "Content-Type": "application/json"})

    def request(self, method: str, path: str, body: dict | None = None) -> dict:
        response = self.session.request(method, f"{FABRIC_API}{path}", json=body, timeout=60)
        if not response.ok:
            raise FabricRequestError(method, path, response.status_code, response.text)
        if response.status_code == 202 and response.headers.get("x-ms-operation-id"):
            return self.wait(response.headers["x-ms-operation-id"])
        return response.json() if response.content else {}

    def wait(self, operation_id: str) -> dict:
        for _ in range(120):
            operation = self.request("GET", f"/operations/{operation_id}")
            if operation.get("status") == "Succeeded":
                return operation
            if operation.get("status") in {"Failed", "Cancelled"}:
                raise RuntimeError(json.dumps(operation, indent=2))
            time.sleep(5)
        raise TimeoutError("Fabric operation did not complete within ten minutes.")

    def list_all(self, path: str) -> list[dict]:
        items: list[dict] = []
        next_path = path
        while next_path:
            response = self.request("GET", next_path)
            items.extend(response.get("value", []))
            continuation = response.get("continuationToken")
            next_path = f"{path}?continuationToken={continuation}" if continuation else ""
        return items


def encode(value: object) -> str:
    return base64.b64encode(json.dumps(value, separators=(",", ":")).encode("utf-8")).decode("utf-8")


def lineage_id(*parts: str) -> str:
    return str(uuid.uuid5(LINEAGE_NAMESPACE, "/".join(parts)))


def platform_part(display_name: str) -> str:
    return encode({
        "$schema": "https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json",
        "metadata": {"type": "SemanticModel", "displayName": display_name},
        "config": {"version": "2.0", "logicalId": "00000000-0000-0000-0000-000000000000"},
    })


def model_bim(workspace_id: str, lakehouse_id: str) -> dict:
    tables = []
    for table_name, source in LAKEHOUSE_TABLES.items():
        entity_name = str(source["entity"])
        columns = source["columns"]
        tables.append({
            "name": table_name,
            "lineageTag": lineage_id("table", table_name),
            "columns": [
                {
                    "name": column_name,
                    "dataType": data_type,
                    "sourceColumn": column_name,
                    "lineageTag": lineage_id("table", table_name, "column", column_name),
                }
                for column_name, data_type in columns
            ],
            "partitions": [{
                "name": table_name,
                "mode": "directLake",
                "source": {
                    "type": "entity",
                    "entityName": entity_name,
                    "schemaName": "dbo",
                    "expressionSource": "LakehouseQuery",
                },
            }],
        })

    return {
        "name": "model",
        "compatibilityLevel": 1604,
        "model": {
            "culture": "en-US",
            "defaultPowerBIDataSourceVersion": "powerBI_V3",
            "sourceQueryCulture": "en-US",
            "dataAccessOptions": {"legacyRedirects": True, "returnErrorValuesAsNull": True},
            "expressions": [{
                "name": "LakehouseQuery",
                "kind": "m",
                "lineageTag": lineage_id("expression", "LakehouseQuery"),
                "expression": [
                    "let",
                    f"    Source = AzureStorage.DataLake(\"https://onelake.dfs.fabric.microsoft.com/{workspace_id}/{lakehouse_id}\", [HierarchicalNavigation=true])",
                    "in",
                    "    Source",
                ],
                "annotations": [{"name": "PBI_IncludeFutureArtifacts", "value": "False"}],
            }],
            "tables": tables,
            "relationships": [
                {
                    "name": lineage_id("relationship", from_table, from_column, to_table, to_column),
                    "fromTable": from_table,
                    "fromColumn": from_column,
                    "toTable": to_table,
                    "toColumn": to_column,
                }
                for from_table, from_column, to_table, to_column in RELATIONSHIPS
            ],
            "annotations": [{"name": "PBI_QueryOrder", "value": json.dumps(list(LAKEHOUSE_TABLES))}],
        },
    }


def find_semantic_model(items: list[dict], display_name: str) -> dict | None:
    return next(
        (item for item in items if item.get("displayName") == display_name and item.get("type") == "SemanticModel"),
        None,
    )


def expected_source_entities() -> set[str]:
    """Return the physical Lakehouse entities required by the Direct Lake model."""
    return {str(source["entity"]) for source in LAKEHOUSE_TABLES.values()}


def missing_source_entities(tables: list[dict]) -> set[str]:
    """Return Direct Lake source entities not yet surfaced by the Lakehouse API."""
    available = {
        str(table["name"])
        for table in tables
        if table.get("name")
    }
    return expected_source_entities() - available


def wait_for_lakehouse_tables(fabric: FabricApi, workspace_id: str, lakehouse_id: str) -> None:
    """Wait for the Lakehouse catalog to expose every Direct Lake source entity."""
    path = f"/workspaces/{workspace_id}/lakehouses/{lakehouse_id}/tables"
    last_missing = expected_source_entities()
    for attempt in range(1, LAKEHOUSE_TABLE_READY_ATTEMPTS + 1):
        try:
            tables = fabric.list_all(path)
        except FabricRequestError as error:
            if error.status_code == 400 and "UnsupportedOperationForSchemasEnabledLakehouse" in str(error):
                # The Lakehouse tables API does not support schema-enabled Lakehouses (this pipeline creates one),
                # so the catalog cannot be polled here. The refresh retry below handles the propagation delay.
                print("Lakehouse table listing is not supported for schema-enabled Lakehouses; relying on refresh retries.", file=sys.stderr, flush=True)
                return
            if error.status_code not in {404, 409, 429, 500, 502, 503, 504}:
                raise
            tables = []
        missing = missing_source_entities(tables)
        if not missing:
            return
        last_missing = missing
        print(
            "Lakehouse table metadata is not ready for Direct Lake; waiting "
            f"{RETRY_DELAY_SECONDS} seconds (attempt {attempt}/{LAKEHOUSE_TABLE_READY_ATTEMPTS}). "
            f"Missing: {', '.join(sorted(missing))}",
            file=sys.stderr, flush=True,
        )
        time.sleep(RETRY_DELAY_SECONDS)
    raise TimeoutError(
        "Lakehouse table metadata did not become ready for Direct Lake within ten minutes. "
        f"Missing: {', '.join(sorted(last_missing))}."
    )


def wait_for_semantic_model(fabric: FabricApi, workspace_id: str, display_name: str) -> dict:
    for _ in range(24):
        item = find_semantic_model(fabric.list_all(f"/workspaces/{workspace_id}/items"), display_name)
        if item and item.get("id"):
            return item
        time.sleep(5)
    raise TimeoutError(f"Semantic model {display_name!r} did not appear within two minutes.")


def deploy_semantic_model(fabric: FabricApi, workspace_id: str, lakehouse_id: str, display_name: str) -> str:
    definition = {
        "parts": [
            {"path": "model.bim", "payload": encode(model_bim(workspace_id, lakehouse_id)), "payloadType": "InlineBase64"},
            {"path": "definition.pbism", "payload": encode({"version": "4.0"}), "payloadType": "InlineBase64"},
            {"path": ".platform", "payload": platform_part(display_name), "payloadType": "InlineBase64"},
        ],
    }
    existing = find_semantic_model(fabric.list_all(f"/workspaces/{workspace_id}/items"), display_name)
    if existing:
        fabric.request("POST", f"/workspaces/{workspace_id}/items/{existing['id']}/updateDefinition", {"definition": definition})
        return existing["id"]
    fabric.request("POST", f"/workspaces/{workspace_id}/semanticModels", {"displayName": display_name, "definition": definition})
    return wait_for_semantic_model(fabric, workspace_id, display_name)["id"]


def is_transient_direct_lake_source_error(refresh: dict) -> bool:
    """Recognize Fabric's temporary Direct Lake table-catalog propagation error."""
    details = json.dumps(refresh, sort_keys=True).casefold()
    return (
        "modelrefresh_shortmessage_processingerror" in details
        and "source tables either do not exist or access was denied" in details
    )


def refresh_semantic_model(workspace_id: str, semantic_model_id: str) -> None:
    """Refresh Direct Lake framing, retrying only temporary table-readiness failures."""
    base = f"https://api.powerbi.com/v1.0/myorg/groups/{workspace_id}/datasets/{semantic_model_id}"
    session = requests.Session()
    session.headers.update({"Authorization": f"Bearer {token('AZURE_POWERBI_ACCESS_TOKEN')}", "Content-Type": "application/json"})
    last_failure: dict | None = None
    for refresh_attempt in range(1, DIRECT_LAKE_REFRESH_ATTEMPTS + 1):
        response = session.post(f"{base}/refreshes", json={"type": "full"}, timeout=60)
        if not response.ok:
            raise RuntimeError(f"POST {base}/refreshes -> {response.status_code}: {response.text}")
        for _ in range(24):
            time.sleep(RETRY_DELAY_SECONDS)
            response = session.get(f"{base}/refreshes", timeout=60)
            response.raise_for_status()
            refreshes = response.json().get("value", [])
            latest = refreshes[0] if refreshes else None
            if latest and latest.get("status") == "Completed":
                return
            if latest and latest.get("status") == "Failed":
                last_failure = latest
                if not is_transient_direct_lake_source_error(latest):
                    raise RuntimeError(f"Semantic model refresh failed: {json.dumps(latest, indent=2)}")
                break
        else:
            raise TimeoutError("Semantic model refresh did not complete within two minutes.")

        if refresh_attempt < DIRECT_LAKE_REFRESH_ATTEMPTS:
            print(
                "Direct Lake table metadata is still propagating; retrying semantic model refresh "
                f"in {REFRESH_RETRY_DELAY_SECONDS} seconds (attempt {refresh_attempt}/{DIRECT_LAKE_REFRESH_ATTEMPTS}).",
                file=sys.stderr, flush=True,
            )
            time.sleep(REFRESH_RETRY_DELAY_SECONDS)

    raise RuntimeError(
        "Semantic model refresh could not read the Lakehouse tables after retrying metadata propagation. "
        "Verify that the service principal owns or has read access to the Lakehouse. "
        f"Last refresh result: {json.dumps(last_failure, indent=2)}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace-id", required=True)
    parser.add_argument("--lakehouse-id", required=True)
    parser.add_argument("--semantic-model-name", default="Ubiquitous_Innovation_SemanticModel")
    args = parser.parse_args()

    fabric = FabricApi(token("AZURE_FABRIC_ACCESS_TOKEN"))
    wait_for_lakehouse_tables(fabric, args.workspace_id, args.lakehouse_id)
    semantic_model_id = deploy_semantic_model(fabric, args.workspace_id, args.lakehouse_id, args.semantic_model_name)
    refresh_semantic_model(args.workspace_id, semantic_model_id)
    print(json.dumps({"semanticModelId": semantic_model_id}))


if __name__ == "__main__":
    main()
