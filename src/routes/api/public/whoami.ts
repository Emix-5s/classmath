import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/public/whoami")({
  server: {
    handlers: {
      GET: async ({ request }) => {
        const h = request.headers;
        const ip =
          h.get("cf-connecting-ip") ??
          h.get("x-real-ip") ??
          (h.get("x-forwarded-for") ?? "").split(",")[0]?.trim() ??
          "";
        return new Response(JSON.stringify({ ip }), {
          headers: { "content-type": "application/json" },
        });
      },
    },
  },
});
