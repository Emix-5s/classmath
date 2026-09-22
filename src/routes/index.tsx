import { createFileRoute } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { useGuest } from "@/lib/guest";
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
  const { guest, loading, join, leave } = useGuest();
  const user = guest;
  const [handle, setHandle] = useState("");
  const [joining, setJoining] = useState(false);
  const [roomSlug, setRoomSlug] = useState("general");
  const [draft, setDraft] = useState("");
  const [modTarget, setModTarget] = useState<{ id: string; username: string } | null>(null);
  const [flipBet, setFlipBet] = useState(50);
  const scroller = useRef<HTMLDivElement>(null);

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
      toast.error("Message blocked — you may be muted or banned.");
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

  if (!loading && !user) {
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
              await join(handle);
            } catch (err) {
              toast.error(err instanceof Error ? err.message : "Try another handle");
            } finally {
              setJoining(false);
            }
          }}
          className="rise glass relative w-full max-w-sm rounded-2xl p-6"
        >
          <div className="font-display text-xl font-bold tracking-tight">Nexus Clubhouse</div>
          <p className="mt-1 font-mono text-[11px] uppercase tracking-[0.2em] text-mist">
            pick a handle to enter
          </p>
          <input
            value={handle}
            onChange={(e) => setHandle(e.target.value)}
            placeholder="Handle (e.g. astra)"
            required
            maxLength={20}
            className="mt-5 w-full rounded-xl bg-white/[0.04] px-3 py-2.5 text-sm ring-1 ring-white/10 outline-none placeholder:text-mist focus:ring-accent/40"
          />
          <button
            type="submit"
            disabled={joining}
            className="mt-3 w-full rounded-xl bg-accent px-3 py-2.5 font-display text-sm font-semibold text-accent-foreground transition-opacity hover:opacity-90 disabled:opacity-50"
          >
            Enter the clubhouse
          </button>
          <p className="mt-3 font-mono text-[10px] text-mist">
            No password — your handle is saved on this device.
          </p>
        </form>
      </div>
    );
  }

  const p = profile.data;
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
            <button
              onClick={async () => {
                await supabase.auth.signOut();
                navigate({ to: "/auth" });
              }}
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
            <div className="flex items-center justify-between border-b border-white/10 px-4 py-3">
              <div className="flex items-center gap-2">
                <span className="size-2 rounded-full bg-mod" />
                <span className="font-display text-sm font-semibold"># {roomSlug}</span>
              </div>
              <span className="font-mono text-[10px] uppercase tracking-wider text-mist">
                {messages.data?.length ?? 0} recent
              </span>
            </div>
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
                        {isMod.data && !m.deleted && (
                          <button
                            onClick={async () => {
                              const { error } = await supabase.rpc("delete_message", {
                                _message: m.id,
                              });
                              if (error) toast.error(error.message);
                            }}
                            className="ml-auto font-mono text-[9px] uppercase tracking-wider text-mist opacity-0 transition-opacity group-hover:opacity-100"
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
                  return (
                    <button
                      key={item.id}
                      onClick={() => buy(item.id)}
                      disabled={owned}
                      className="rounded-xl border border-white/10 bg-white/[0.04] p-3 text-left transition-transform duration-300 hover:-translate-y-1 disabled:translate-y-0 disabled:opacity-50"
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
                        {owned ? "owned" : `◈ ${formatCoins(item.price)}`}
                      </div>
                    </button>
                  );
                })}
              </div>
            </div>

            {/* earn coins */}
            <div className="glass rounded-2xl p-4">
              <div className="mb-3 font-mono text-[10px] uppercase tracking-[0.2em] text-mist">
                Earn coins
              </div>
              <div className="space-y-3">
                <div className="flex items-center gap-3">
                  <div className="grid size-8 place-items-center rounded-lg bg-coin/15 font-display text-xs font-bold text-coin">
                    ◈
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="text-sm font-medium">Coin Flip</div>
                    <div className="font-mono text-[10px] text-mist">bet ◈ {flipBet}</div>
                  </div>
                  <input
                    type="range"
                    min={10}
                    max={500}
                    step={10}
                    value={flipBet}
                    onChange={(e) => setFlipBet(Number(e.target.value))}
                    className="w-16 accent-coin"
                  />
                </div>
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
                <button
                  onClick={claimDaily}
                  className="w-full rounded-lg bg-coin/15 px-3 py-2 font-mono text-[10px] uppercase tracking-wider text-coin transition-colors hover:bg-coin/25"
                >
                  claim daily streak
                </button>
              </div>
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
