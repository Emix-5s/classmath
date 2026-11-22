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
- All clubhouse reads and mutations use club-client to attach expiring password-issued sessions; database policies and callable functions verify them to prevent account-ID impersonation.
- user_roles.role_key is the canonical four-role field; legacy enum values remain only for migration compatibility, and database rank_level retains internal numeric levels for existing power dispatchers.
- Owner alone manages ranks, private member records, devices and global/destructive powers; Admin manages lower-ranked accounts and rewards, and Moderator only moderates member chat.
