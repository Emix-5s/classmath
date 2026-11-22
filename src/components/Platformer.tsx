import { useEffect, useRef, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { ArrowLeft, ArrowRight, ArrowUp, RotateCcw, ShoppingBag } from "lucide-react";
import { Button } from "@/components/ui/button";
import { supabase } from "@/lib/club-client";
import { clubToken } from "@/lib/club-session";
import { VerifiedAccess } from "./VerifiedAccess";
import { coinPosition, COINS_PER_RUN, movement, upgradeCost } from "@/lib/platformer-rules";
import valley from "@/assets/platformer-valley.jpg";

export function Platformer({ account, balance }: { account: { id: string; username: string }; balance: number }) {
  const qc = useQueryClient();
  const host = useRef<HTMLDivElement>(null);
  const controls = useRef({ left: false, right: false, jump: false });
  const levels = useRef({ speed: 0, jump: 0 });
  const [token, setToken] = useState<string | null>(null);
  const [restart, setRestart] = useState(0);
  const [ready, setReady] = useState(false);
  const [count, setCount] = useState(0);
  const [error, setError] = useState("");
  const [shop, setShop] = useState(false);
  const [upgrades, setUpgrades] = useState({ speed: 0, jump: 0 });
  const [busy, setBusy] = useState(false);
  const [won, setWon] = useState(false);
  useEffect(() => setToken(clubToken(account.id)), [account.id]);
  useEffect(() => {
    if (!token || !host.current) return;
    let cancelled = false;
    let game: import("phaser").Game | undefined;
    setReady(false); setCount(0); setWon(false); setError("");
    const mount = host.current;
    async function load() {
      const { data, error } = await supabase.rpc("platformer_open", { _token: token ?? "" });
      if (error) throw error;
      const run = data as unknown as { run: string; upgrades: { speed: number; jump: number } };
      if (cancelled) return;
      levels.current = run.upgrades; setUpgrades(run.upgrades);
      const { default: Phaser } = await import("phaser");
      if (cancelled) return;
      class Valley extends Phaser.Scene {
        player?: import("phaser").Physics.Arcade.Sprite;
        cursors: import("phaser").Types.Input.Keyboard.CursorKeys | undefined;
        wasd?: Record<string, import("phaser").Input.Keyboard.Key>;
        lastJump = false;
        checkpoint = 65;
        preload() { this.load.image("valley", valley); }
        create() {
          const colors = getComputedStyle(mount);
          const pixelColor = (name: string) => {
            const canvas = document.createElement("canvas"); const ctx = canvas.getContext("2d");
            if (!ctx) return 0;
            ctx.fillStyle = colors.getPropertyValue(name).trim(); ctx.fillRect(0,0,1,1);
            const p = ctx.getImageData(0,0,1,1).data; return ((p[0] ?? 0) << 16) | ((p[1] ?? 0) << 8) | (p[2] ?? 0);
          };
          const green = pixelColor("--mod"), dark = pixelColor("--panel"), gold = pixelColor("--coin"), light = pixelColor("--foreground"), coral = pixelColor("--vip");
          const art = this.make.graphics({ x: 0, y: 0 });
          art.fillStyle(dark); art.fillRect(0,0,64,32); art.fillStyle(green); art.fillRect(0,0,64,8); for(let x=0;x<64;x+=12) { art.fillStyle(green,.25); art.fillRect(x,18,8,4); } art.generateTexture("ground",64,32); art.clear();
          art.fillStyle(gold); art.fillCircle(10,10,10); art.fillStyle(light); art.fillRect(9,4,3,12); art.generateTexture("coin",20,20); art.clear();
          art.fillStyle(coral); art.fillRoundedRect(3,9,22,23,4); art.fillStyle(light); art.fillRect(8,2,15,16); art.fillStyle(dark); art.fillRect(19,7,4,4); art.fillRect(4,32,8,7); art.fillRect(17,32,8,7); art.generateTexture("runner",28,40); art.clear();
          art.fillStyle(coral); art.fillTriangle(0,20,12,0,24,20); art.generateTexture("spike",24,20); art.destroy();
          this.add.image(400,240,"valley").setDisplaySize(800,480).setScrollFactor(0);
          this.physics.world.setBounds(0,0,3300,620);
          const platforms = this.physics.add.staticGroup();
          for(let section=0;section<11;section++) {
            for(let x=section*300;x<section*300+256;x+=64) platforms.create(x+32,455,"ground");
            if(section>0) for(let x=0;x<3;x++) platforms.create(section*300+70+x*64,415-(section%3)*28,"ground");
          }
          this.player = this.physics.add.sprite(65,400,"runner").setCollideWorldBounds(true);
          this.player.setSize(23,38); this.physics.add.collider(this.player,platforms);
          const coins = this.physics.add.staticGroup();
          for(let i=0;i<COINS_PER_RUN;i++) { const pos=coinPosition(i); const c=coins.create(pos.x,pos.y,"coin"); c.setData("id",i); }
          this.physics.add.overlap(this.player,coins,(_p,obj) => {
            const c = obj as import("phaser").Physics.Arcade.Sprite;
            if(c.getData("pending")) return;
            c.setData("pending",true);
            void supabase.rpc("platformer_collect", { _token: token ?? "", _run: run.run, _coin: c.getData("id") as number }).then(({error}) => {
              if(cancelled) return;
              if(error) { c.setData("pending",false); setError(error.message); return; }
              c.destroy(); setCount(n => n+1); setError(""); void qc.invalidateQueries({queryKey:["profile"]});
            });
          });
          const hazards = this.physics.add.staticGroup();
          for(let i=2;i<10;i+=2) hazards.create(i*300+20,428,"spike");
          this.physics.add.overlap(this.player,hazards,() => this.respawn());
          this.add.rectangle(3190,376,8,124,light);
          this.add.rectangle(3220,322,60,32,green);
          this.cameras.main.setBounds(0,0,3300,480).startFollow(this.player,true,.12,.12);
          this.cursors = this.input.keyboard?.createCursorKeys();
          this.wasd = this.input.keyboard?.addKeys("W,A,D") as Record<string, import("phaser").Input.Keyboard.Key>;
          setReady(true);
          if(import.meta.env.DEV) (window as unknown as { __platformer: unknown }).__platformer = this;
        }
        respawn() { this.player?.setPosition(this.checkpoint,360); this.player?.setVelocity(0,0); }
        override update() {
          const p=this.player; if(!p) return;
          const body=p.body as import("phaser").Physics.Arcade.Body;
          const input=controls.current, tuning=movement(levels.current.speed,levels.current.jump);
          const left=input.left || this.cursors?.left.isDown || this.wasd?.["A"]?.isDown;
          const right=input.right || this.cursors?.right.isDown || this.wasd?.["D"]?.isDown;
          const jump=input.jump || this.cursors?.space.isDown || this.cursors?.up.isDown || this.wasd?.["W"]?.isDown || false;
          p.setVelocityX(left ? -tuning.speed : right ? tuning.speed : 0);
          if(left || right) p.setFlipX(!!left);
          if(jump && !this.lastJump && body.blocked.down) p.setVelocityY(-tuning.jump);
          this.lastJump=jump;
          if(body.blocked.down && p.x>this.checkpoint+500) this.checkpoint=p.x;
          if(p.y>540) this.respawn();
          if(p.x>3170) { setWon(true); p.setVelocityX(0); }
        }
      }
      game = new Phaser.Game({ type: Phaser.AUTO, parent: mount, width:800,height:480, pixelArt:true, scale:{mode:Phaser.Scale.FIT,autoCenter:Phaser.Scale.CENTER_BOTH}, physics:{default:"arcade",arcade:{gravity:{x:0,y:1000},debug:false}},scene:Valley, input:{keyboard:true} });
    }
    void load().catch(e => { if(!cancelled) setError((e as {message?:string}).message ?? "Could not start the game"); });
    return () => { cancelled=true; game?.destroy(true); controls.current={left:false,right:false,jump:false}; };
  }, [token, restart, qc]);
  async function buy(kind: "speed" | "jump") {
    if(!token) return; setBusy(true);
    const {data,error}=await supabase.rpc("platformer_buy",{_token:token,_kind:kind});
    if(error) setError(error.message);
    else { const result=data as {level:number}; levels.current={...levels.current,[kind]:result.level}; setUpgrades(levels.current); setError(""); await qc.invalidateQueries({queryKey:["profile"]}); }
    setBusy(false);
  }
  if(!token) return <VerifiedAccess account={account} onVerified={setToken} />;
  return <section className="bg-background">
    <header className="flex flex-wrap items-center justify-between gap-2 border-b border-border p-3"><div><h2 className="font-display">Summit Sprint</h2><p className="text-xs text-coin">◈ {balance.toLocaleString()} · {count}/30 collected</p></div><div className="flex gap-2"><Button variant="outline" size="icon" title="Restart run" aria-label="Restart run" onClick={() => setRestart(n=>n+1)}><RotateCcw /></Button><Button variant="secondary" onClick={() => setShop(!shop)}><ShoppingBag /> Upgrades</Button></div></header>
    {error && <div role="alert" className="p-3 text-sm text-destructive">{error}<Button variant="ghost" onClick={() => setToken(null)}>Verify again</Button></div>}
    {shop && <div className="flex flex-wrap gap-3 border-b border-border p-3">{(["speed","jump"] as const).map(kind => <div key={kind} className="flex items-center gap-3"><span className="text-sm capitalize">{kind} · {upgrades[kind]}/3</span><Button size="sm" disabled={busy || upgrades[kind]>=3 || balance<(upgradeCost(upgrades[kind]) ?? 0)} onClick={() => void buy(kind)}>{upgrades[kind]>=3 ? "Maxed" : `◈ ${upgradeCost(upgrades[kind])}`}</Button></div>)}</div>}
    <div className="relative"><div ref={host} data-scene-ready={ready || undefined} className="aspect-[5/3] w-full overflow-hidden" />{!ready && !error && <p className="absolute inset-0 grid place-items-center">Loading valley…</p>}{won && <div className="absolute inset-x-0 top-4 text-center"><span className="rounded-md bg-background/90 px-4 py-2 font-display">Summit reached! · {count} coins</span></div>}</div>
    <div className="flex justify-between p-3 touch-none">{(["left","right","jump"] as const).map(key => <Button key={key} variant="secondary" aria-label={key === "jump" ? "Jump" : `Move ${key}`} className="size-16 touch-none" onPointerDown={e => { e.currentTarget.setPointerCapture(e.pointerId); controls.current[key]=true; }} onPointerUp={() => { controls.current[key]=false; }} onPointerCancel={() => { controls.current[key]=false; }} onLostPointerCapture={() => { controls.current[key]=false; }}>{key === "left" ? <ArrowLeft /> : key === "right" ? <ArrowRight /> : <ArrowUp />}</Button>)}</div>
  </section>;
}