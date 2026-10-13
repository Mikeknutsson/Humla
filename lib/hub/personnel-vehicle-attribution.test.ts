import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { attributeCostLine, attributeUniqueCostLines } from "./personnel-vehicle-attribution";
const mappings = [
  { projectReference: "243", vehicleRegistration: "GJT66B", validFrom: "2026-10-13", validTo: null, enabled: true },
  { projectReference: "227", vehicleRegistration: "LZP91Z", validFrom: "2026-10-13", validTo: null, enabled: true },
];
describe("personnel vehicle attribution", () => {
  it("uses confirmed personnel mapping after effective date", () => {
    assert.equal(attributeCostLine({source:"next",sourceLineId:"1",date:"2026-10-13",personnelProject:"243"}, mappings).vehicle, "GJT66B");
  });
  it("does not retroactively assign old transactions", () => {
    assert.equal(attributeCostLine({source:"next",sourceLineId:"2",date:"2026-09-10",personnelProject:"243"}, mappings).method, "review");
  });
  it("prioritizes actual registration over personnel", () => {
    assert.equal(attributeCostLine({source:"next",sourceLineId:"3",date:"2026-10-13",personnelProject:"243",registration:"LZP91Z"}, mappings).vehicle, "LZP91Z");
  });
  it("deduplicates identical source line IDs", () => {
    const line = {source:"next",sourceLineId:"4",date:"2026-10-13",personnelProject:"243"};
    assert.equal(attributeUniqueCostLines([line,line],mappings).length, 1);
  });
  it("holds conflicting versions of a source line for review", () => {
    const line = {source:"next",sourceLineId:"5",date:"2026-10-13",personnelProject:"243"};
    assert.equal(attributeUniqueCostLines([line,{...line,registration:"LZP91Z"}],mappings)[0].method, "review");
  });
});
