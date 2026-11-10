import { useState } from "react";
import { Button } from "@/components/ui/button";
import { verifyClubAccount } from "@/lib/club-session";

export function VerifiedAccess({ account, onVerified }: { account: { id: string; username: string }; onVerified: (token: string) => void }) {
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  return <form className="space-y-3 p-4" onSubmit={async e => {
    e.preventDefault(); setBusy(true); setError("");
    try { onVerified(await verifyClubAccount(account.username, password, account.id)); setPassword(""); }
    catch (e) { setError((e as { message?: string }).message ?? "Verification failed"); }
    finally { setBusy(false); }
  }}>
    <p className="font-display">Confirm your account · {account.username}</p>
    <input aria-label="Account password" type="password" autoComplete="current-password" required value={password} onChange={e => setPassword(e.target.value)} className="w-full rounded-md border border-input bg-background px-3 py-2" placeholder="Password" />
    {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    <Button disabled={busy} type="submit">{busy ? "Verifying…" : "Unlock"}</Button>
  </form>;
}