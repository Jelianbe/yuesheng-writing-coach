import { describe, expect, it } from "vitest";
import { layoutRelations } from "../RelationWeb";

describe("layoutRelations", () => {
  it("lays out up to 6 satellites and reports overflow for the rest", () => {
    const rels = Array.from({ length: 8 }, (_, i) => ({ targetLabel: `t${i}`, type: "rel" }));
    const { nodes, overflow } = layoutRelations(rels, 300, 150);
    expect(nodes).toHaveLength(6);
    expect(overflow).toBe(2);
    nodes.forEach((n) => {
      expect(n.x).toBeGreaterThanOrEqual(0);
      expect(n.x).toBeLessThanOrEqual(300);
      expect(n.y).toBeGreaterThanOrEqual(0);
      expect(n.y).toBeLessThanOrEqual(150);
    });
  });

  it("places a single satellite straight above the center", () => {
    const { nodes, overflow } = layoutRelations([{ targetLabel: "x", type: "rel" }], 300, 150);
    expect(overflow).toBe(0);
    expect(nodes[0].x).toBeCloseTo(150, 1);
    expect(nodes[0].y).toBeCloseTo(150 / 2 - 0.3 * 150, 1); // cy + ry*sin(-90°)
  });
});
