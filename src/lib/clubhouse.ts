export const fontClass = (key: string | null | undefined) =>
  key === "display" ? "font-display" : key === "mono" ? "font-mono" : "font-body";

export const rarityClass = (rarity: string) =>
  rarity === "mythic"
    ? "text-vip"
    : rarity === "epic"
      ? "text-coin"
      : rarity === "rare"
        ? "text-accent"
        : "text-mist";

export const formatCoins = (n: number) => n.toLocaleString("en-US");
