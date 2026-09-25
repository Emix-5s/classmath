import { createFileRoute } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { useAccount, perksFor } from "@/lib/account";
import { fontClass, rarityClass, formatCoins } from "@/lib/clubhouse";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Nexus Clubhouse — chat, play, collect" },
      {
        name: "description",
        content:
          "Live chat rooms with coin rewards, a shop of skins, fonts and VIP ranks, mini-games, achievements and moderator tools.",
      },
      { property: "og:title", content: "Nexus Clubhouse — chat, play, collect" },
      {
        property: "og:description",
        content:
          "Live chat rooms with coin rewards, a shop of skins, fonts and VIP ranks, mini-games and achievements.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
  component: Clubhouse,
});

type ProfileRow = {
  id: string;
  username: string;
  coins: number;
  xp: number;
  level: number;
  name_color: string;
  font_key: string;
  vip_tier: string | null;
  muted_until: string | null;
  banned: boolean;
};

function Clubhouse() {
  const qc = useQueryClient();
  const { account, loading, signUp, signIn, signOut } = useAccount();
  const user = account;
  const [handle, setHandle] = useState("");
  const [password, setPassword] = useState("");
  const [mode, setMode] = useState<"in" | "up">("in");
  const [joining, setJoining] = useState(false);
  const [roomSlug, setRoomSlug] = useState("general");
  const [draft, setDraft] = useState("");
  const [modTarget, setModTarget] = useState<{ id: string; username: string } | null>(null);
  const [flipBet, setFlipBet] = useState(50);
  const [dicePick, setDicePick] = useState(3);
  const [codeInput, setCodeInput] = useState("");
  const [roomView, setRoomView] = useState<"chat" | "game">("chat");
  const scroller = useRef<HTMLDivElement>(null);
  const gameFrame = useRef<HTMLIFrameElement>(null);

  const profile = useQuery({
    queryKey: ["profile", user?.id],
    enabled: !!user,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("profiles")
        .select("*")
        .eq("id", user!.id)
        .maybeSingle();
      if (error) throw error;
      return data as ProfileRow | null;
    },
  });

  const isMod = useQuery({
    queryKey: ["is-mod", user?.id],
    enabled: !!user,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("user_roles")
        .select("role")
        .eq("user_id", user!.id);
      if (error) throw error;
      return (data ?? []).some((r) => r.role === "mod" || r.role === "admin");
    },
  });

  const rooms = useQuery({
    queryKey: ["rooms"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("rooms")
        .select("*")
        .order("sort_order");
      if (error) throw error;
      return data;
    },
  });

  const room = rooms.data?.find((r) => r.slug === roomSlug) ?? null;

  const messages = useQuery({
    queryKey: ["messages", room?.id],
    enabled: !!room,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("messages")
        .select("id, content, created_at, user_id, deleted, profiles(username, name_color, font_key, vip_tier)")
        .eq("room_id", room!.id)
        .order("created_at", { ascending: false })
        .limit(60);
      if (error) throw error;
      return (data ?? []).slice().reverse();
    },
  });

  useEffect(() => {
    if (!room) return;
    const channel = supabase
      .channel(`room-${room.id}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "messages", filter: `room_id=eq.${room.id}` },
        () => qc.invalidateQueries({ queryKey: ["messages", room.id] }),
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [room, qc]);

  useEffect(() => {
    scroller.current?.scrollTo({ top: scroller.current.scrollHeight });
  }, [messages.data]);

  const shop = useQuery({
    queryKey: ["shop"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("shop_items")
        .select("*")
        .order("sort_order");
      if (error) throw error;
      return data;
    },
  });

  const inventory = useQuery({
    queryKey: ["inventory", user?.id],
    enabled: !!user,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("inventory")
        .select("item_id")
        .eq("user_id", user!.id);
      if (error) throw error;
      return (data ?? []).map((r) => r.item_id);
    },
  });

  const achievements = useQuery({
    queryKey: ["achievements", user?.id],
    enabled: !!user,
    queryFn: async () => {
      const [all, mine] = await Promise.all([
        supabase.from("achievements").select("*").order("sort_order"),
        supabase.from("user_achievements").select("*").eq("user_id", user!.id),
      ]);
      if (all.error) throw all.error;
      if (mine.error) throw mine.error;
      return (all.data ?? []).map((a) => ({
        ...a,
        progress: mine.data?.find((m) => m.achievement_id === a.id)?.progress ?? 0,
        claimed: mine.data?.find((m) => m.achievement_id === a.id)?.claimed ?? false,
      }));
    },
  });

  const refreshAll = () => {
    qc.invalidateQueries({ queryKey: ["profile"] });
    qc.invalidateQueries({ queryKey: ["inventory"] });
    qc.invalidateQueries({ queryKey: ["achievements"] });
  };

  async function send() {
    const content = draft.trim();
    if (!content || !room || !user) return;
    setDraft("");
    const { error } = await supabase
      .from("messages")
      .insert({ room_id: room.id, user_id: user.id, content });
    if (error) {
      const msg = error.message ?? "";
      toast.error(
        /slow down|spam|repeating|characters/.test(msg)
          ? msg
          : "Message blocked — you may be muted or banned.",
      );
      setDraft(content);
      return;
    }
    qc.invalidateQueries({ queryKey: ["achievements"] });
  }

  async function playFlip(guess: "heads" | "tails") {
    if (!user) return;
    const { data, error } = await supabase.rpc("play_coin_flip", {
      _user: user.id,
      bet: flipBet,
      guess,
    });
    if (error) {
      toast.error(error.message);
      return;
    }
    const result = data as { flip: string; won: boolean };
    toast[result.won ? "success" : "error"](
      `${result.flip.toUpperCase()} — ${result.won ? `you won ◈ ${flipBet}` : `you lost ◈ ${flipBet}`}`,
    );
    refreshAll();
  }

  async function playDice() {
    if (!user) return;
    const { data, error } = await supabase.rpc("play_dice", {
      _user: user.id,
      bet: flipBet,
      pick: dicePick,
    });
    if (error) return void toast.error(error.message);
    const r = data as { roll: number; won: boolean };
    toast[r.won ? "success" : "error"](
      `Rolled ${r.roll} — ${r.won ? `5x payout on ◈ ${flipBet}` : "no luck"}`,
    );
    refreshAll();
  }

  async function playSlots() {
    if (!user) return;
    const { data, error } = await supabase.rpc("play_slots", {
      _user: user.id,
      bet: flipBet,
    });
    if (error) return void toast.error(error.message);
    const r = data as { reels: string[]; won: boolean; payout: number };
    toast[r.won ? "success" : "error"](
      `${r.reels.join(" ")} — ${r.won ? `${r.payout}x payout` : "no match"}`,
    );
    refreshAll();
  }

  async function playRps(pick: "rock" | "paper" | "scissors") {
    if (!user) return;
    const { data, error } = await supabase.rpc("play_rps", {
      _user: user.id,
      bet: flipBet,
      pick,
    });
    if (error) return void toast.error(error.message);
    const r = data as { house: string; result: string };
    toast[r.result === "win" ? "success" : r.result === "draw" ? "info" : "error"](
      `House played ${r.house} — ${r.result}`,
    );
    refreshAll();
  }

  async function playHilo(call: "higher" | "lower") {
    if (!user) return;
    const { data, error } = await supabase.rpc("play_hilo", {
      _user: user.id,
      bet: flipBet,
      call,
    });
    if (error) return void toast.error(error.message);
    const r = data as { card: number; next: number; result: string };
    toast[r.result === "win" ? "success" : r.result === "push" ? "info" : "error"](
      `${r.card} → ${r.next} — ${r.result}`,
    );
    refreshAll();
  }

  async function redeem() {
    if (!user || !codeInput.trim()) return;
    const { data, error } = await supabase.rpc("redeem_code", {
      _user: user.id,
      _code: codeInput.trim(),
    });
    if (error) return void toast.error(error.message);
    const r = data as { reward: number; note: string };
    setCodeInput("");
    toast.success(`Code accepted — ◈ ${r.reward} added`);
    refreshAll();
  }

  async function claimDaily() {
    if (!user) return;
    const { data, error } = await supabase.rpc("claim_daily", { _user: user.id });
    if (error) {
      toast.error(error.message);
      return;
    }
    const res = data as { reward: number; streak: number };
    toast.success(`Day ${res.streak} streak — ◈ ${res.reward} added`);
    refreshAll();
  }

  async function buy(itemId: string) {
    if (!user) return;
    const { error } = await supabase.rpc("buy_item", { _user: user.id, _item: itemId });
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success("Unlocked and equipped");
    refreshAll();
  }

  async function equip(itemId: string) {
    if (!user) return;
    const { error } = await supabase.rpc("equip_item", { _user: user.id, _item: itemId });
    if (error) return toast.error(error.message);
    toast.success("Equipped");
    refreshAll();
  }

  async function unequip(kind: string) {
    if (!user || kind === "vip") return;
    const { error } =
      kind === "font"
        ? await supabase.rpc("reset_font", { _user: user.id })
        : await supabase.rpc("equip_item", { _user: user.id, _item: null as unknown as string });
    if (error) return toast.error(error.message);
    toast.success("Back to default");
    refreshAll();
  }

  async function claimAchievement(id: string) {
    if (!user) return;
    const { error } = await supabase.rpc("claim_achievement", {
      _user: user.id,
      _achievement: id,
    });
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success("Reward claimed");
    refreshAll();
  }

  async function modAct(action: "mute" | "unmute" | "ban" | "unban") {
    if (!user) return;
    if (!modTarget) {
      toast.error("Tap a name in chat to pick someone first");
      return;
    }
    const { error } = await supabase.rpc("mod_action", {
      _actor: user.id,
      _target: modTarget.id,
      _action: action,
      _minutes: 10,
    });
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success(`${modTarget.username} — ${action}d`);
  }

  async function becomeMod() {
    if (!user) return;
    const code = window.prompt("Enter the moderator code");
    if (!code) return;
    const { error } = await supabase.rpc("claim_mod", { _user: user.id, _code: code });
    if (error) {
      toast.error("That code isn't right");
      return;
    }
    toast.success("Moderator powers unlocked");
    qc.invalidateQueries({ queryKey: ["is-mod"] });
  }

  if (loading) {
    return <div className="min-h-screen bg-background" />;
  }

  if (!user) {
    return (
      <div className="relative grid min-h-screen place-items-center overflow-hidden bg-background px-4 text-foreground">
        <div className="pointer-events-none absolute inset-0">
          <div className="absolute -top-40 -left-32 size-[520px] rounded-full bg-accent/20 blur-[120px]" />
          <div className="absolute bottom-[-160px] left-1/3 size-[420px] rounded-full bg-coin/10 blur-[120px]" />
        </div>
        <form
          onSubmit={async (e) => {
            e.preventDefault();
            setJoining(true);
            try {
              if (mode === "up") await signUp(handle, password);
              else await signIn(handle, password);
            } catch (err) {
              toast.error(err instanceof Error ? err.message : "Something went wrong");
            } finally {
              setJoining(false);
            }
          }}
          className="rise glass relative w-full max-w-sm rounded-2xl p-6"
        >
          <div className="font-display text-xl font-bold tracking-tight">Nexus Clubhouse</div>
          <p className="mt-1 font-mono text-[11px] uppercase tracking-[0.2em] text-mist">
            {mode === "up" ? "create your account" : "welcome back"}
          </p>
          <div className="mt-4 grid grid-cols-2 gap-1 rounded-xl bg-white/[0.04] p-1 ring-1 ring-white/10">
            {(["in", "up"] as const).map((m) => (
              <button
                key={m}
                type="button"
                onClick={() => setMode(m)}
                className={`rounded-lg px-3 py-1.5 font-mono text-[10px] uppercase tracking-wider transition-colors ${
                  mode === m ? "bg-accent/15 text-accent" : "text-mist hover:text-foreground"
                }`}
              >
                {m === "in" ? "sign in" : "sign up"}
              </button>
            ))}
          </div>
          <input
            value={handle}
            onChange={(e) => setHandle(e.target.value)}
            placeholder="Username"
            autoComplete="username"
            required
            maxLength={20}
            className="mt-3 w-full rounded-xl bg-white/[0.04] px-3 py-2.5 text-sm ring-1 ring-white/10 outline-none placeholder:text-mist focus:ring-accent/40"
          />
          <input
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            type="password"
            placeholder="Password"
            autoComplete={mode === "up" ? "new-password" : "current-password"}
            required
            minLength={4}
            className="mt-2 w-full rounded-xl bg-white/[0.04] px-3 py-2.5 text-sm ring-1 ring-white/10 outline-none placeholder:text-mist focus:ring-accent/40"
          />
          <button
            type="submit"
            disabled={joining}
            className="mt-3 w-full rounded-xl bg-accent px-3 py-2.5 font-display text-sm font-semibold text-accent-foreground transition-opacity hover:opacity-90 disabled:opacity-50"
          >
            {mode === "up" ? "Create account" : "Enter the clubhouse"}
          </button>
          <p className="mt-3 font-mono text-[10px] text-mist">
            Username and password only — no email needed.
          </p>
        </form>
      </div>
    );
  }

  const p = profile.data;
  const currentUserId = user.id;
  const xpFloor = ((p?.level ?? 1) - 1) * 500;
  const xpPct = p ? Math.min(100, ((p.xp - xpFloor) / 500) * 100) : 0;

  return (
    <div className="relative min-h-screen overflow-hidden bg-background text-foreground">
      <div className="pointer-events-none absolute inset-0">
        <div className="absolute -top-40 -left-32 size-[520px] rounded-full bg-accent/20 blur-[120px]" />
        <div className="absolute top-1/3 right-[-160px] size-[460px] rounded-full bg-vip/15 blur-[130px]" />
        <div className="absolute bottom-[-160px] left-1/3 size-[420px] rounded-full bg-coin/10 blur-[120px]" />
      </div>

      <div className="relative mx-auto max-w-[1440px] px-4 py-5 lg:px-8">
        {/* header */}
        <header className="rise glass flex flex-wrap items-center gap-3 rounded-2xl px-4 py-3">
          <div className="flex items-center gap-2.5">
            <div className="grid size-9 place-items-center rounded-xl bg-accent/15 font-display font-bold text-accent ring-1 ring-accent/40">
              N
            </div>
            <div className="leading-none">
              <div className="font-display text-lg font-bold tracking-tight">Nexus</div>
              <div className="font-mono text-[10px] uppercase tracking-[0.2em] text-mist">
                clubhouse
              </div>
            </div>
          </div>
          <div className="ml-auto flex items-center gap-2.5">
            <div className="flex items-center gap-2 rounded-full border border-coin/30 bg-coin/10 px-3 py-1.5">
              <span className="text-sm font-semibold text-coin">◈</span>
              <span className="coinpop font-mono text-sm font-medium text-coin">
                {formatCoins(p?.coins ?? 0)}
              </span>
              <span className="font-mono text-[10px] uppercase tracking-wider text-coin/60">
                coins
              </span>
            </div>
            <div className="hidden items-center gap-1.5 rounded-full border border-white/10 bg-white/[0.04] px-3 py-1.5 sm:flex">
              <span className="font-mono text-[10px] uppercase tracking-wider text-mist">
                Level
              </span>
              <span className="font-display text-sm font-bold">{p?.level ?? 1}</span>
            </div>
            {!isMod.data && (
              <button
                onClick={becomeMod}
                className="rounded-full bg-mod/10 px-3 py-1.5 font-mono text-[10px] uppercase tracking-wider text-mod ring-1 ring-mod/30 transition-colors hover:bg-mod/20"
              >
                mod code
              </button>
            )}
            <button
              onClick={signOut}
              className="grid size-9 place-items-center rounded-full bg-panel2 font-display text-sm font-bold ring-1 ring-white/10 transition-colors hover:bg-white/10"
              title="Sign out"
            >
              {(p?.username ?? "?").charAt(0).toUpperCase()}
            </button>
          </div>
        </header>

        <div className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-12">
          {/* left rail */}
          <aside className="rise space-y-4 lg:col-span-3">
            <div className="glass rounded-2xl p-4">
              <div className="flex items-center justify-between">
                <span className="font-mono text-[10px] uppercase tracking-[0.2em] text-mist">
                  Profile
                </span>
                {p?.vip_tier && (
                  <span className="shimmer rounded-full bg-vip/15 px-2 py-0.5 font-mono text-[10px] uppercase tracking-wider text-vip">
                    {p.vip_tier}
                  </span>
                )}
              </div>
              <div className="mt-3 flex items-center gap-3">
                <div className="grid size-12 place-items-center rounded-xl bg-panel2 font-display text-lg font-bold ring-1 ring-accent/30">
                  {(p?.username ?? "?").charAt(0).toUpperCase()}
                </div>
                <div>
                  <div
                    className={`text-sm font-semibold ${fontClass(p?.font_key)}`}
                    style={{ color: p?.name_color }}
                  >
                    {p?.username ?? "…"}
                  </div>
                  <div className="font-mono text-[11px] text-mist">
                    {isMod.data ? "rank · moderator" : "rank · member"}
                  </div>
                </div>
              </div>
              <div className="mt-4 h-1.5 overflow-hidden rounded-full bg-white/10">
                <div
                  className="h-full rounded-full bg-accent transition-all"
                  style={{ width: `${xpPct}%` }}
                />
              </div>
              <div className="mt-1.5 flex justify-between font-mono text-[10px] text-mist">
                <span>XP {formatCoins(p?.xp ?? 0)}</span>
                <span>{formatCoins(xpFloor + 500)}</span>
              </div>
            </div>

            <div className="glass rounded-2xl p-4">
              <div className="mb-3 font-mono text-[10px] uppercase tracking-[0.2em] text-mist">
                Rooms
              </div>
              <div className="space-y-1.5 text-sm">
                {(rooms.data ?? [])
                  .filter((r) => !r.mod_only || isMod.data)
                  .map((r) => (
                    <button
                      key={r.id}
                      onClick={() => setRoomSlug(r.slug)}
                      className={`flex w-full items-center justify-between rounded-lg px-3 py-2 ${
                        r.slug === roomSlug
                          ? "bg-accent/10 font-medium ring-1 ring-accent/30"
                          : "text-mist hover:bg-white/5"
                      }`}
                    >
                      <span>{r.name}</span>
                      {r.mod_only && (
                        <span className="font-mono text-[10px] text-mod">mod</span>
                      )}
                    </button>
                  ))}
              </div>
            </div>
          </aside>

          {/* chat */}
          <main className="rise glass flex flex-col overflow-hidden rounded-2xl lg:col-span-6">
            <div className="flex flex-wrap items-center justify-between gap-3 border-b border-white/10 px-4 py-3">
              <div className="flex items-center gap-2">
                <span className="size-2 rounded-full bg-mod" />
                <span className="font-display text-sm font-semibold"># {roomSlug}</span>
              </div>
              <div className="flex items-center gap-1 rounded-lg bg-white/[0.04] p-1 ring-1 ring-white/10">
                <button
                  type="button"
                  onClick={() => setRoomView("chat")}
                  className={`rounded-md px-3 py-1.5 font-mono text-[10px] uppercase tracking-wider transition-colors ${
                    roomView === "chat" ? "bg-accent/15 text-accent" : "text-mist hover:text-foreground"
                  }`}
                >
                  Chat
                </button>
                <button
                  type="button"
                  onClick={() => setRoomView("game")}
                  className={`rounded-md px-3 py-1.5 font-mono text-[10px] uppercase tracking-wider transition-colors ${
                    roomView === "game" ? "bg-vip/15 text-vip" : "text-mist hover:text-foreground"
                  }`}
                >
                  Synth Purge
                </button>
              </div>
            </div>
            {roomView === "chat" ? (
              <>
                <div ref={scroller} className="h-[420px] space-y-4 overflow-y-auto p-4">
                  {(messages.data ?? []).length === 0 && (
                    <p className="font-mono text-[11px] text-mist">
                      No messages yet — say something first.
                    </p>
                  )}
                  {(messages.data ?? []).map((m) => {
                    const author = m.profiles as unknown as {
                      username: string;
                      name_color: string;
                      font_key: string;
                      vip_tier: string | null;
                    } | null;
                    return (
                      <div key={m.id} className="group flex gap-3">
                        <div className="grid size-8 shrink-0 place-items-center rounded-lg bg-panel2 font-display text-xs font-bold ring-1 ring-white/10">
                          {(author?.username ?? "?").charAt(0).toUpperCase()}
                        </div>
                        <div className="min-w-0 flex-1">
                          <div className="flex items-center gap-2">
                            <button
                              onClick={() =>
                                setModTarget({
                                  id: m.user_id,
                                  username: author?.username ?? "user",
                                })
                              }
                              className={`text-sm font-semibold ${fontClass(author?.font_key)}`}
                              style={{ color: author?.name_color ?? undefined }}
                            >
                              {author?.username ?? "unknown"}
                            </button>
                            {author?.vip_tier && (
                              <span className="shimmer rounded bg-vip/15 px-1.5 py-0.5 font-mono text-[9px] uppercase tracking-wider text-vip">
                                {author.vip_tier}
                              </span>
                            )}
                            {(isMod.data || m.user_id === currentUserId) && !m.deleted && (
                              <button
                                onClick={async () => {
                                  const { error } =
                                    m.user_id === currentUserId
                                      ? await supabase.rpc("delete_own_message", {
                                          _user: currentUserId,
                                          _message: m.id,
                                        })
                                      : await supabase.rpc("delete_message", {
                                          _actor: currentUserId,
                                          _message: m.id,
                                        });
                                  if (error) toast.error(error.message);
                                  else qc.invalidateQueries({ queryKey: ["messages"] });
                                }}
                                className="ml-auto font-mono text-[9px] uppercase tracking-wider text-mist opacity-60 transition-opacity group-hover:opacity-100"
                              >
                                remove
                              </button>
                            )}
                          </div>
                          <p className="text-sm leading-snug text-foreground/80">{m.content}</p>
                        </div>
                      </div>
                    );
                  })}
                </div>
                <div className="border-t border-white/10 p-3">
                  <div className="flex items-center gap-2 rounded-xl bg-white/[0.04] px-3 py-2 ring-1 ring-white/10">
                    <input
                      value={draft}
                      onChange={(e) => setDraft(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === "Enter") send();
                      }}
                      placeholder={`Message #${roomSlug}…`}
                      maxLength={500}
                      className="flex-1 bg-transparent text-sm outline-none placeholder:text-mist"
                    />
                    <button
                      onClick={send}
                      className="font-mono text-[10px] uppercase tracking-wider text-mist hover:text-accent"
                    >
                      ⏎ send
                    </button>
                  </div>
                </div>
              </>
            ) : (
              <div className="relative h-[min(70vh,680px)] min-h-[480px] bg-ink">
                <iframe
                  ref={gameFrame}
                  src="/games/synth-purge/index.html"
                  title="Synth Purge"
                  allow="autoplay; fullscreen; gamepad"
                  sandbox="allow-scripts allow-same-origin allow-pointer-lock"
                  className="size-full border-0"
                />
                <button
                  type="button"
                  onClick={() => gameFrame.current?.requestFullscreen()}
                  className="absolute top-3 right-3 grid size-9 place-items-center rounded-lg bg-background/80 text-sm text-foreground ring-1 ring-white/20 backdrop-blur transition-colors hover:bg-background"
                  title="Play full screen"
                  aria-label="Play Synth Purge full screen"
                >
                  ⛶
                </button>
              </div>
            )}
          </main>

          {/* right rail */}
          <aside className="rise space-y-4 lg:col-span-3">
            {/* shop */}
            <div className="glass rounded-2xl p-4">
              <div className="mb-3 flex items-center justify-between">
                <span className="font-mono text-[10px] uppercase tracking-[0.2em] text-mist">
                  Shop
                </span>
                <span className="font-mono text-[10px] text-mist">rarity</span>
              </div>
              <div className="grid grid-cols-2 gap-2.5">
                {(shop.data ?? []).map((item) => {
                  const owned = inventory.data?.includes(item.id);
                  const equipped =
                    owned &&
                    ((item.kind === "skin" && p?.name_color === item.value) ||
                      (item.kind === "font" && p?.font_key === item.value) ||
                      (item.kind === "vip" && p?.vip_tier === item.value));
                  return (
                    <button
                      key={item.id}
                      onClick={() =>
                        !owned
                          ? buy(item.id)
                          : equipped
                            ? unequip(item.kind)
                            : equip(item.id)
                      }
                      className={`rounded-xl border bg-white/[0.04] p-3 text-left transition-transform duration-300 hover:-translate-y-1 ${equipped ? "border-coin/60" : "border-white/10"}`}
                    >
                      <div
                        className={`font-mono text-[10px] uppercase tracking-wider ${rarityClass(item.rarity)}`}
                      >
                        {item.rarity}
                      </div>
                      <div className="mt-1 font-display text-sm font-semibold">
                        {item.name}
                      </div>
                      <div className="mt-2 flex items-center gap-1 font-mono text-xs text-coin">
                        {!owned
                          ? `◈ ${formatCoins(item.price)}`
                          : equipped
                            ? item.kind === "vip"
                              ? "active"
                              : "equipped · tap to remove"
                            : "owned · tap to equip"}
                      </div>
                    </button>
                  );
                })}
              </div>
            </div>

            {/* vip perks */}
            <div className="rounded-2xl border border-vip/20 bg-vip/[0.06] p-4 backdrop-blur-xl">
              <div className="mb-2 flex items-center justify-between">
                <span className="font-mono text-[10px] uppercase tracking-[0.2em] text-mist">
                  VIP perks
                </span>
                <span className="shimmer rounded-full bg-vip/15 px-2 py-0.5 font-mono text-[10px] uppercase tracking-wider text-vip">
                  {p?.vip_tier ?? "no tier"}
                </span>
              </div>
              <ul className="space-y-1 font-mono text-[10px] text-mist">
                <li>
                  winnings ×{perksFor(p?.vip_tier).mult} on every game
                </li>
                <li>max bet ◈ {formatCoins(perksFor(p?.vip_tier).maxBet)}</li>
                <li>glowing VIP badge beside your name in chat</li>
                <li>{p?.vip_tier ? "priority in mod-desk requests" : "buy VIP in the shop to unlock"}</li>
              </ul>
            </div>

            {/* arcade */}
            <div className="glass rounded-2xl p-4">
              <div className="mb-3 flex items-center justify-between">
                <span className="font-mono text-[10px] uppercase tracking-[0.2em] text-mist">
                  Arcade
                </span>
                <span className="font-mono text-[10px] text-coin">bet ◈ {flipBet}</span>
              </div>
              <input
                type="range"
                min={10}
                max={perksFor(p?.vip_tier).maxBet}
                step={10}
                value={Math.min(flipBet, perksFor(p?.vip_tier).maxBet)}
                onChange={(e) => setFlipBet(Number(e.target.value))}
                className="w-full accent-coin"
              />

              <div className="mt-3 space-y-3">
                <div>
                  <div className="mb-1.5 text-sm font-medium">Coin Flip · 2x</div>
                  <div className="grid grid-cols-2 gap-2">
                    <button
                      onClick={() => playFlip("heads")}
                      className="rounded-lg bg-white/[0.04] px-3 py-2 text-xs font-medium ring-1 ring-white/10 transition-colors hover:bg-white/10"
                    >
                      Heads
                    </button>
                    <button
                      onClick={() => playFlip("tails")}
                      className="rounded-lg bg-white/[0.04] px-3 py-2 text-xs font-medium ring-1 ring-white/10 transition-colors hover:bg-white/10"
                    >
                      Tails
                    </button>
                  </div>
                </div>

                <div>
                  <div className="mb-1.5 text-sm font-medium">Dice Roll · 5x</div>
                  <div className="flex gap-1.5">
                    {[1, 2, 3, 4, 5, 6].map((n) => (
                      <button
                        key={n}
                        onClick={() => setDicePick(n)}
                        className={`flex-1 rounded-lg py-1.5 font-mono text-xs transition-colors ${
                          dicePick === n
                            ? "bg-accent/15 text-accent ring-1 ring-accent/40"
                            : "bg-white/[0.04] text-mist hover:bg-white/10"
                        }`}
                      >
                        {n}
                      </button>
                    ))}
                  </div>
                  <button
                    onClick={playDice}
                    className="mt-2 w-full rounded-lg bg-white/[0.04] px-3 py-2 text-xs font-medium ring-1 ring-white/10 transition-colors hover:bg-white/10"
                  >
                    Roll the dice
                  </button>
                </div>

                <div>
                  <div className="mb-1.5 text-sm font-medium">Neon Slots · up to 12x</div>
                  <button
                    onClick={playSlots}
                    className="w-full rounded-lg bg-coin/15 px-3 py-2 text-xs font-medium text-coin transition-colors hover:bg-coin/25"
                  >
                    ◈ ★ ☾ spin
                  </button>
                </div>

                <div>
                  <div className="mb-1.5 text-sm font-medium">Rock Paper Scissors · 2x</div>
                  <div className="grid grid-cols-3 gap-2">
                    {(["rock", "paper", "scissors"] as const).map((pick) => (
                      <button
                        key={pick}
                        onClick={() => playRps(pick)}
                        className="rounded-lg bg-white/[0.04] px-2 py-2 text-xs font-medium capitalize ring-1 ring-white/10 transition-colors hover:bg-white/10"
                      >
                        {pick}
                      </button>
                    ))}
                  </div>
                </div>

                <div>
                  <div className="mb-1.5 text-sm font-medium">Hi-Lo Cards · 2x</div>
                  <div className="grid grid-cols-2 gap-2">
                    {(["higher", "lower"] as const).map((call) => (
                      <button
                        key={call}
                        onClick={() => playHilo(call)}
                        className="rounded-lg bg-white/[0.04] px-3 py-2 text-xs font-medium capitalize ring-1 ring-white/10 transition-colors hover:bg-white/10"
                      >
                        {call}
                      </button>
                    ))}
                  </div>
                </div>

                <button
                  onClick={claimDaily}
                  className="w-full rounded-lg bg-coin/15 px-3 py-2 font-mono text-[10px] uppercase tracking-wider text-coin transition-colors hover:bg-coin/25"
                >
                  claim daily streak
                </button>
              </div>
            </div>

            {/* promo codes */}
            <div className="glass rounded-2xl p-4">
              <div className="mb-3 font-mono text-[10px] uppercase tracking-[0.2em] text-mist">
                Redeem a code
              </div>
              <div className="flex items-center gap-2 rounded-xl bg-white/[0.04] px-3 py-2 ring-1 ring-white/10">
                <input
                  value={codeInput}
                  onChange={(e) => setCodeInput(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") redeem();
                  }}
                  placeholder="enter code…"
                  className="flex-1 bg-transparent font-mono text-xs outline-none placeholder:text-mist"
                />
                <button
                  onClick={redeem}
                  className="font-mono text-[10px] uppercase tracking-wider text-coin hover:opacity-80"
                >
                  redeem
                </button>
              </div>
              <p className="mt-2 font-mono text-[10px] text-mist">
                Codes drop in chat and each one works once per account.
              </p>
            </div>

            {/* achievements */}
            <div className="glass rounded-2xl p-4">
              <div className="mb-3 font-mono text-[10px] uppercase tracking-[0.2em] text-mist">
                Achievements
              </div>
              <div className="space-y-2.5">
                {(achievements.data ?? []).map((a) => {
                  const done = a.progress >= a.goal;
                  return (
                    <div key={a.id} className="flex items-center gap-3">
                      <div className="grid size-8 place-items-center rounded-lg bg-coin/15 font-display text-xs font-bold text-coin">
                        {a.progress}
                      </div>
                      <div className="min-w-0 flex-1">
                        <div className="text-sm font-medium">{a.name}</div>
                        <div className="font-mono text-[10px] text-mist">
                          {a.description} · ◈ {a.reward}
                        </div>
                      </div>
                      {a.claimed ? (
                        <span className="font-mono text-[10px] text-mist">done</span>
                      ) : (
                        <button
                          disabled={!done}
                          onClick={() => claimAchievement(a.id)}
                          className="font-mono text-[10px] text-coin disabled:text-mist/50"
                        >
                          claim
                        </button>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>

            {/* mod tools */}
            {isMod.data && (
              <div className="rounded-2xl border border-mod/20 bg-mod/[0.06] p-4 backdrop-blur-xl">
                <div className="mb-3 flex items-center gap-2">
                  <span className="rounded bg-mod/15 px-2 py-0.5 font-mono text-[10px] uppercase tracking-wider text-mod">
                    MOD
                  </span>
                  <span className="font-mono text-[10px] uppercase tracking-[0.2em] text-mist">
                    {modTarget ? modTarget.username : "tools"}
                  </span>
                </div>
                <div className="grid grid-cols-2 gap-2">
                  {(["mute", "unmute", "ban", "unban"] as const).map((action) => (
                    <button
                      key={action}
                      onClick={() => modAct(action)}
                      className="rounded-lg bg-white/[0.04] px-3 py-2 text-xs font-medium capitalize ring-1 ring-white/10 transition-colors hover:bg-white/10"
                    >
                      {action}
                    </button>
                  ))}
                </div>
              </div>
            )}
          </aside>
        </div>
      </div>
    </div>
  );
}
