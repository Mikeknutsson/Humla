import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { projectVerifiedVehicleCosts, type ImportedCostRow } from "./verified-vehicle-cost-projection";

const base: ImportedCostRow = {
  id: "row-1", batchId: "batch-1", batchStatus: "completed",
  rowNumber: 1, projectReference: "243", occurredOn: "2026-10-13",
  amount: "200", sourceContentHash: "abc", sourceDocumentId: "15D8213",
  sourceDocumentLineId: "1", sourceSystem: "next", costCenter: "30",
  vehicleRegistration: null, employeeProject: "243"
};
const mappings = [{ projectReference: "243", vehicleRegistration: "GJT66B", validFrom: "2026-10-13", validTo: null, enabled: true }];
describe("verified vehicle cost projection", () => {
  it("accepts a unique completed transaction with a confirmed vehicle", () => {
    assert.equal(projectVerifiedVehicleCosts([base], mappings)[0].vehicle, "GJT66B");
    assert.equal(projectVerifiedVehicleCosts([base], mappings)[0].state, "ready");
  });
  it("does not post failed imports", () => {
    assert.equal(projectVerifiedVehicleCosts([{...base, batchStatus:"failed"}], mappings)[0].state, "review");
  });
  it("does not post ambiguous voucher-only rows", () => {
    assert.equal(projectVerifiedVehicleCosts([{...base, sourceDocumentLineId:null}], mappings)[0].state, "review");
  });
  it("does not assign a vehicle before mapping validity", () => {
    assert.equal(projectVerifiedVehicleCosts([{...base, occurredOn:"2026-07-01"}], mappings)[0].state, "review");
  });
  it("holds repeated source document lines for review", () => {
    const rows = [base,{...base,id:"row-2",batchId:"batch-2"}];
    assert.equal(projectVerifiedVehicleCosts(rows,mappings)[1].state, "review");
  });
});
