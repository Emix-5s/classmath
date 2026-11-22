import { supabase } from "@/lib/club-client";

export function clubToken(userId: string) {
  return sessionStorage.getItem(`club-session:${userId}`);
}

export async function verifyClubAccount(username: string, password: string, userId: string) {
  const { data, error } = await supabase.rpc("open_club_session", { _username: username, _password: password });
  if (error) throw error;
  if (!data) throw new Error("Sign in failed");
  sessionStorage.setItem(`club-session:${userId}`, data);
  sessionStorage.setItem("club-active-token", data);
  return data;
}