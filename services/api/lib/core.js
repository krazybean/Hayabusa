function parseLimit(value, fallback = 50) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 1) return fallback;
  return Math.min(Math.floor(parsed), 200);
}

function limitFromUrl(reqUrl, fallback = 50) {
  return parseLimit(new URL(reqUrl, "http://localhost").searchParams.get("limit"), fallback);
}

function formatEventTimestamp(date) {
  const pad = (value, size = 2) => String(value).padStart(size, "0");
  return [
    date.getUTCFullYear(),
    pad(date.getUTCMonth() + 1),
    pad(date.getUTCDate()),
  ].join("-") + " " + [
    pad(date.getUTCHours()),
    pad(date.getUTCMinutes()),
    pad(date.getUTCSeconds()),
  ].join(":") + `.${pad(date.getUTCMilliseconds(), 3)}`;
}

function parseAllowedOrigins(value) {
  return new Set(
    value
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean),
  );
}

module.exports = {
  formatEventTimestamp,
  limitFromUrl,
  parseAllowedOrigins,
  parseLimit,
};
