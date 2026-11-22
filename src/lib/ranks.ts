export const RANK_LEVEL: Record<string, number> = { user: 0, mod: 1, admin: 2, owner: 3 };

export type RankInfo = { label: string; short: string; className: string };

export const RANKS: Record<number, RankInfo> = {
  3: {
    label: "Owner",
    short: "OWNER",
    className: "bg-vip/15 text-vip ring-1 ring-vip/30",
  },
  2: {
    label: "Admin",
    short: "ADMIN",
    className: "bg-accent/15 text-accent ring-1 ring-accent/30",
  },
  1: {
    label: "Moderator",
    short: "MOD",
    className: "bg-mod/15 text-mod ring-1 ring-mod/30",
  },
};

export function rankInfo(level: number): RankInfo | null {
  return RANKS[level] ?? null;
}

export function rankLabel(level: number): string {
  return RANKS[level]?.label ?? "Member";
}

export const GRANT_CAP: Record<number, number> = {
  1: 0,
  2: 10000000,
  3: 2000000000,
};
