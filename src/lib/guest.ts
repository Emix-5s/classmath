import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

export type Guest = { id: string; username: string };

const KEY = "nexus-guest";

export function useGuest() {
  const [guest, setGuest] = useState<Guest | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    try {
      const raw = localStorage.getItem(KEY);
      if (raw) setGuest(JSON.parse(raw) as Guest);
    } catch {
      /* ignore */
    }
    setLoading(false);
  }, []);

  const join = useCallback(async (username: string) => {
    const { data, error } = await supabase.rpc("create_guest", { _username: username });
    if (error) throw error;
    const row = data as unknown as { id: string; username: string };
    const next = { id: row.id, username: row.username };
    localStorage.setItem(KEY, JSON.stringify(next));
    setGuest(next);
    return next;
  }, []);

  const leave = useCallback(() => {
    localStorage.removeItem(KEY);
    setGuest(null);
  }, []);

  return { guest, loading, join, leave };
}
