import { useCallback, useEffect, useState } from "react";
import { supabase, activeClubToken } from "@/lib/club-client";
import { verifyClubAccount } from "@/lib/club-session";

export type Account = { id: string; username: string };

const KEY = "nexus-account";

export function useAccount() {
  const [account, setAccount] = useState<Account | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    try {
      const raw = localStorage.getItem(KEY) ?? localStorage.getItem("nexus-guest");
      if (raw && activeClubToken()) setAccount(JSON.parse(raw) as Account);
    } catch {
      /* ignore */
    }
    setLoading(false);
  }, []);

  const persist = useCallback((row: { id: string; username: string }) => {
    const next = { id: row.id, username: row.username };
    localStorage.setItem(KEY, JSON.stringify(next));
    setAccount(next);
    return next;
  }, []);

  const signUp = useCallback(
    async (username: string, password: string) => {
      const { data, error } = await supabase.rpc("signup_user", {
        _username: username,
        _password: password,
      });
      if (error) throw error;
      const row = data as unknown as Account;
      await verifyClubAccount(row.username, password, row.id);
      return persist(data as unknown as Account);
    },
    [persist],
  );

  const signIn = useCallback(
    async (username: string, password: string) => {
      const { data, error } = await supabase.rpc("login_user", {
        _username: username,
        _password: password,
      });
      if (error) throw error;
      const row = data as unknown as Account;
      await verifyClubAccount(row.username, password, row.id);
      return persist(data as unknown as Account);
    },
    [persist],
  );

  const signOut = useCallback(() => {
    localStorage.removeItem(KEY);
    localStorage.removeItem("nexus-guest");
    sessionStorage.removeItem("club-active-token");
    if (account) sessionStorage.removeItem(`club-session:${account.id}`);
    setAccount(null);
  }, [account]);

  return { account, loading, signUp, signIn, signOut };
}

const DEFAULT_PERKS = { mult: 1, maxBet: 500 };

export const VIP_PERKS: Record<string, { mult: number; maxBet: number }> = {
  none: DEFAULT_PERKS,
  VIP: { mult: 1.25, maxBet: 1500 },
  "VIP+": { mult: 1.5, maxBet: 5000 },
};

export const perksFor = (tier: string | null | undefined) =>
  VIP_PERKS[tier ?? "none"] ?? DEFAULT_PERKS;
