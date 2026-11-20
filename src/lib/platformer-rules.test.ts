import { test, expect } from "vitest";
import { COINS_PER_RUN, upgradeCost, movement, coinPosition } from "./platformer-rules";

test("platformer awards a thirty-coin course", () => {
  expect(COINS_PER_RUN).toBe(30);
  expect(new Set(Array.from({ length: 30 }, (_, i) => coinPosition(i).x)).size).toBe(30);
});
test("upgrades cost 25, 50, and 75 coins and stop at three", () => {
  expect([0,1,2,3].map(upgradeCost)).toEqual([25,50,75,null]);
});
test("speed and jump upgrades affect their own movement", () => {
  expect(movement(3,0)).toEqual({speed:335,jump:430});
  expect(movement(0,3)).toEqual({speed:230,jump:520});
});