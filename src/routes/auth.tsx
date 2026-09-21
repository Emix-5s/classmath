import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { lovable } from "@/integrations/lovable/index";
import { useAuth } from "@/lib/useAuth";

export const Route = createFileRoute("/auth")({
  head: () => ({
    meta: [
      { title: "Sign in — Nexus Clubhouse" },
      {
        name: "description",
        content: "Create your Nexus handle to chat, earn coins and unlock skins.",
      },
      { property: "og:title", content: "Sign in — Nexus Clubhouse" },
      {
        property: "og:description",
        content: "Create your Nexus handle to chat, earn coins and unlock skins.",
      },
    ],
  }),
  component: AuthPage,
});

function AuthPage() {
  const navigate = useNavigate();
  const { session } = useAuth();
  const [mode, setMode] = useState<"signin" | "signup">("signup");
  const [username, setUsername] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [checkEmail, setCheckEmail] = useState(false);

  useEffect(() => {
    if (session) navigate({ to: "/" });
  }, [session, navigate]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      if (mode === "signup") {
        const { data, error } = await supabase.auth.signUp({
          email,
          password,
          options: {
            emailRedirectTo: window.location.origin,
            data: { username },
          },
        });
        if (error) throw error;
        if (!data.session) setCheckEmail(true);
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Something went wrong");
    } finally {
      setBusy(false);
    }
  }

  async function google() {
    const result = await lovable.auth.signInWithOAuth("google", {
      redirect_uri: window.location.origin,
    });
    if (result.error) {
      toast.error("Google sign-in failed");
      return;
    }
  }

  return (
    <div className="relative min-h-screen overflow-hidden bg-background text-foreground">
      <div className="pointer-events-none absolute inset-0">
        <div className="absolute -top-40 -left-32 size-[520px] rounded-full bg-accent/20 blur-[120px]" />
        <div className="absolute top-1/3 right-[-160px] size-[460px] rounded-full bg-vip/15 blur-[130px]" />
        <div className="absolute bottom-[-160px] left-1/3 size-[420px] rounded-full bg-coin/10 blur-[120px]" />
      </div>

      <div className="relative mx-auto flex min-h-screen max-w-md flex-col justify-center px-4 py-10">
        <div className="rise glass rounded-2xl p-6">
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

          {checkEmail ? (
            <div className="mt-6 space-y-3">
              <p className="font-display text-sm font-semibold">Check your email</p>
              <p className="text-sm text-mist">
                We sent a confirmation link to {email}. Open it to finish creating your
                handle.
              </p>
            </div>
          ) : (
            <>
              <div className="mt-5 flex gap-1 rounded-xl bg-white/[0.04] p-1 ring-1 ring-white/10">
                {(["signup", "signin"] as const).map((m) => (
                  <button
                    key={m}
                    type="button"
                    onClick={() => setMode(m)}
                    className={`flex-1 rounded-lg px-3 py-1.5 font-mono text-[11px] uppercase tracking-wider transition-colors ${
                      mode === m ? "bg-accent/15 text-accent" : "text-mist hover:text-foreground"
                    }`}
                  >
                    {m === "signup" ? "Join" : "Sign in"}
                  </button>
                ))}
              </div>

              <form onSubmit={submit} className="mt-4 space-y-3">
                {mode === "signup" && (
                  <input
                    value={username}
                    onChange={(e) => setUsername(e.target.value)}
                    placeholder="Handle (e.g. astra)"
                    required
                    maxLength={20}
                    className="w-full rounded-xl bg-white/[0.04] px-3 py-2.5 text-sm ring-1 ring-white/10 outline-none placeholder:text-mist focus:ring-accent/40"
                  />
                )}
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="Email"
                  required
                  className="w-full rounded-xl bg-white/[0.04] px-3 py-2.5 text-sm ring-1 ring-white/10 outline-none placeholder:text-mist focus:ring-accent/40"
                />
                <input
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Password"
                  required
                  minLength={6}
                  className="w-full rounded-xl bg-white/[0.04] px-3 py-2.5 text-sm ring-1 ring-white/10 outline-none placeholder:text-mist focus:ring-accent/40"
                />
                <button
                  type="submit"
                  disabled={busy}
                  className="w-full rounded-xl bg-accent px-3 py-2.5 font-display text-sm font-semibold text-accent-foreground transition-opacity hover:opacity-90 disabled:opacity-50"
                >
                  {mode === "signup" ? "Create handle" : "Enter the clubhouse"}
                </button>
              </form>

              <button
                type="button"
                onClick={google}
                className="mt-3 w-full rounded-xl bg-white/[0.04] px-3 py-2.5 text-sm font-medium ring-1 ring-white/10 transition-colors hover:bg-white/10"
              >
                Continue with Google
              </button>
            </>
          )}
        </div>

        <Link
          to="/"
          className="mt-4 text-center font-mono text-[11px] uppercase tracking-wider text-mist hover:text-foreground"
        >
          back home
        </Link>
      </div>
    </div>
  );
}
