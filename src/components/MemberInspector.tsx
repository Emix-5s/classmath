import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Users, Search } from "lucide-react";
import { supabase } from "@/lib/club-client";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { VerifiedAccess } from "./VerifiedAccess";
import { clubToken } from "@/lib/club-session";

type RecordData = { profile: { id: string; username: string; coins: number; xp: number; level: number; vip: string | null; rank: string; banned: boolean; muted_until: string | null; device_id: string | null; created_at: string }; messages: { id: string; content: string; deleted: boolean; created_at: string; room: string }[]; total: number };

export function MemberInspector({ account }: { account: { id: string; username: string } }) {
  const [open, setOpen] = useState(false);
  const [token, setToken] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [target, setTarget] = useState("");
  const [page, setPage] = useState(0);
  useEffect(() => { if (open) setToken(clubToken(account.id)); }, [open, account.id]);
  const members = useQuery({ queryKey: ["inspector-members", search], enabled: open && !!token, queryFn: async () => {
    const { data, error } = await supabase.from("profiles").select("id,username").ilike("username", `%${search.replace(/[%_]/g, "")}%`).order("username").limit(100);
    if (error) throw error; return data ?? [];
  }});
  const record = useQuery({ queryKey: ["member-record", target, page, token], enabled: open && !!token && !!target, retry: false, queryFn: async () => {
    if (!token) throw new Error("Verify your account");
    const { data, error } = await supabase.rpc("inspect_member", { _token: token, _target: target, _offset: page * 50 });
    if (error) throw error; return data as unknown as RecordData;
  }});
  const p = record.data?.profile;
  return <>
    <Button onClick={() => setOpen(true)} variant="secondary" className="mb-3 w-full"><Users /> Member records</Button>
    <Dialog open={open} onOpenChange={setOpen}><DialogContent className="max-h-[90dvh] w-[calc(100%-24px)] max-w-3xl overflow-y-auto">
      <DialogTitle>Owner · Member records</DialogTitle>
      <DialogDescription>Account details and available message history.</DialogDescription>
      {!token ? <VerifiedAccess account={account} onVerified={setToken} /> : <div className="space-y-4">
        <label className="flex items-center gap-2 rounded-md border border-input px-3"><Search className="size-4" /><input aria-label="Search members" value={search} onChange={e => setSearch(e.target.value)} placeholder="Search username" className="min-w-0 flex-1 bg-transparent py-2 outline-none" /></label>
        <select aria-label="Select member" value={target} onChange={e => { setTarget(e.target.value); setPage(0); }} className="w-full rounded-md border border-input bg-background p-2"><option value="">Select a member</option>{members.data?.map(m => <option key={m.id} value={m.id}>{m.username}</option>)}</select>
        {record.isFetching && <p>Loading records…</p>}
        {record.error && <p role="alert" className="text-destructive">{record.error.message}<Button variant="ghost" onClick={() => setToken(null)}>Verify again</Button></p>}
        {p && <>
          <h3 className="font-display text-xl">{p.username}</h3>
          <dl className="grid grid-cols-2 gap-3 text-sm">{[["Rank", p.rank], ["Coins", p.coins.toLocaleString()], ["Level / XP", `${p.level} / ${p.xp}`], ["VIP", p.vip ?? "None"], ["Status", p.banned ? "Banned" : "Active"], ["Muted until", p.muted_until ? new Date(p.muted_until).toLocaleString() : "Not muted"], ["Joined", new Date(p.created_at).toLocaleString()]].map(([k,v]) => <div key={k}><dt className="text-muted-foreground">{k}</dt><dd>{v}</dd></div>)}</dl>
          <div className="text-sm"><span className="text-muted-foreground">Browser device ID (HWID)</span><p className="break-all font-mono">{p.device_id ?? "Not recorded"}</p></div>
          <div className="text-sm text-muted-foreground">{record.data?.total} messages · Permanently erased text cannot be recovered.</div>
          <div className="max-h-80 divide-y divide-border overflow-y-auto">{record.data?.messages.map(m => <article className="py-3" key={m.id}><div className="text-xs text-muted-foreground">{m.room} · {new Date(m.created_at).toLocaleString()}{m.deleted ? " · Deleted" : ""}</div><p className="break-words whitespace-pre-wrap text-sm">{m.content}</p></article>)}{record.data?.total === 0 && <p>No messages.</p>}</div>
          <div className="flex items-center justify-between"><Button variant="outline" disabled={page === 0} onClick={() => setPage(n => n-1)}>Previous</Button><span className="text-sm">Page {page + 1}</span><Button variant="outline" disabled={(page+1)*50 >= (record.data?.total ?? 0)} onClick={() => setPage(n => n+1)}>Next</Button></div>
        </>}
      </div>}
    </DialogContent></Dialog>
  </>;
}