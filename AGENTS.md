<!-- LOVABLE:BEGIN -->
> [!IMPORTANT]
> This project is connected to [Lovable](https://lovable.dev). Avoid rewriting
> published git history — force pushing, or rebasing/amending/squashing commits
> that are already pushed — as it rewrites history on Lovable's side and the
> user will likely lose their project history.
>
> Commits you push to the connected branch sync back to Lovable and show up in
> the editor, so keep the branch in a working state.
<!-- LOVABLE:END -->

- New member-inspector and platformer RPCs authenticate opaque, expiring club session tokens created only after password verification; never authorize them from client-supplied account IDs.
- Platformer physics use Phaser loaded inside an effect; React owns the wallet and menus, and database RPCs own reward deduplication and upgrade purchases.
- Profile reads must explicitly select public fields; browser device identifiers are excluded from direct profile SELECT grants.
