import { describe as group, expect, it } from "vitest";
import { countWords, describe, perthDate } from "./sighting";

group("countWords", () => {
  it("spells out up to ten", () => {
    expect(countWords(1)).toBe("one");
    expect(countWords(10)).toBe("ten");
  });
  it("uses figures above ten", () => {
    expect(countWords(42)).toBe("42");
    expect(countWords(11)).toBe("11");
  });
  it("refuses a part or a negative quokka", () => {
    expect(() => countWords(1.5)).toThrow(RangeError);
    expect(() => countWords(-1)).toThrow(RangeError);
  });
});

group("perthDate", () => {
  it("reads the date in Perth, eight hours ahead of UTC", () => {
    expect(perthDate("2026-11-02T17:30:00Z")).toBe("3 November 2026");
  });
  it("refuses what is not a date", () => {
    expect(() => perthDate("yesterday")).toThrow(RangeError);
  });
});

group("describe", () => {
  it("makes one sentence of a sighting", () => {
    expect(describe({ id: 1, where: "Thomson Bay", count: 2, created: "2026-11-03T01:00:00Z" })).toBe(
      "Two quokkas at Thomson Bay on 3 November 2026.",
    );
  });
  it("keeps one quokka singular", () => {
    expect(describe({ id: 2, where: " The Basin ", count: 1, created: "2026-11-03T01:00:00Z" })).toBe(
      "One quokka at The Basin on 3 November 2026.",
    );
  });
});
