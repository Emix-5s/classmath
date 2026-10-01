const KEY = "nexus-hwid";

function makeId() {
  const rand =
    typeof crypto !== "undefined" && "randomUUID" in crypto
      ? crypto.randomUUID()
      : Math.random().toString(36).slice(2) + Date.now().toString(36);
  return `hwid_${rand}`;
}

/** Stable per-device id, kept in both localStorage and a long-lived cookie. */
export function deviceId(): string {
  if (typeof window === "undefined") return "";
  let id = "";
  try {
    id = localStorage.getItem(KEY) ?? "";
  } catch {
    /* storage can be blocked */
  }
  if (!id) {
    const m = document.cookie.match(/(?:^|;\s*)nexus_hwid=([^;]+)/);
    if (m?.[1]) id = decodeURIComponent(m[1]);
  }
  if (!id) id = makeId();
  try {
    localStorage.setItem(KEY, id);
  } catch {
    /* ignore */
  }
  document.cookie = `nexus_hwid=${encodeURIComponent(id)}; path=/; max-age=31536000; samesite=lax`;
  return id;
}
