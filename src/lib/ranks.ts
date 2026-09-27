export const RANK_LEVEL: Record<string, number> = {
  owner: 4,
  co_owner: 3,
  admin: 3,
  super_mod: 2,
  mod: 1,
  user: 0,
};

export type RankInfo = { label: string; short: string; className: string };

export const RANKS: Record<number, RankInfo> = {
  4: {
    label: "Owner",
    short: "OWNER",
    className: "bg-rose-500/15 text-rose-300 ring-1 ring-rose-400/40",
  },
  3: {
    label: "Co-Owner",
    short: "CO-OWNER",
    className: "bg-amber-400/15 text-amber-300 ring-1 ring-amber-300/40",
  },
  2: {
    label: "Super Mod",
    short: "SUPER MOD",
    className: "bg-violet-500/15 text-violet-300 ring-1 ring-violet-400/40",
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
  1: 100000,
  2: 500000,
  3: 1000000,
  4: 2000000000,
};
