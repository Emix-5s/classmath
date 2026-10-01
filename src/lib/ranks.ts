export const RANK_LEVEL: Record<string, number> = {
  ton618: 6,
  coverstar: 5,
  owner: 4,
  co_owner: 3,
  admin: 3,
  super_mod: 2,
  mod: 1,
  user: 0,
};

export type RankInfo = { label: string; short: string; className: string };

export const RANKS: Record<number, RankInfo> = {
  6: {
    label: "TON 618",
    short: "TON 618",
    className:
      "bg-gradient-to-r from-fuchsia-500/25 to-indigo-500/25 text-fuchsia-200 ring-1 ring-fuchsia-300/50",
  },
  5: {
    label: "COVERST4R",
    short: "COVERST4R",
    className:
      "bg-gradient-to-r from-rose-500/20 to-amber-400/20 text-rose-200 ring-1 ring-rose-300/50",
  },
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
  3: 10000000,
  4: 2000000000,
  5: 2000000000,
  6: 2000000000,
};
