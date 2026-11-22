import { createClient } from "@supabase/supabase-js";
import type { Database } from "@/integrations/supabase/types";

// The saved account is display state only. Every request proves identity with
// a password-issued, expiring token which the database verifies independently.
export function activeClubToken(): string | null {
  if (typeof window === "undefined") return null;
  return sessionStorage.getItem("club-active-token");
}

let client: ReturnType<typeof createClient<Database>> | undefined;
function getClient() {
  if (client) return client;
  const url = import.meta.env["VITE_SUPABASE_URL"];
  const key = import.meta.env["VITE_SUPABASE_PUBLISHABLE_KEY"];
  if (!url || !key) throw new Error("Account service unavailable");
  client = createClient<Database>(url, key, {
    auth: { persistSession: false, autoRefreshToken: false, storageKey: "club-custom-auth" },
    global: { fetch: (input, init) => {
      const headers = new Headers(init?.headers);
      if (headers.get("Authorization") === `Bearer ${key}`) headers.delete("Authorization");
      headers.set("apikey", key);
      const token = activeClubToken();
      if (token) headers.set("x-club-token", token);
      return fetch(input, { ...init, headers });
    } },
  });
  return client;
}
export const supabase = new Proxy({} as ReturnType<typeof getClient>, {
  get(_target, prop) { return Reflect.get(getClient(), prop); },
});