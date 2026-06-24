// crypto.randomUUID() only exists in secure contexts (HTTPS or localhost).
// This site is served over plain http:// on its IP address, so the browser
// throws "crypto.randomUUID is not a function" — this falls back to a
// manual UUID v4 generator that works anywhere. Backend decodes these IDs
// as Swift UUID, so the format must stay RFC 4122 compliant.
export function newUUID(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}
