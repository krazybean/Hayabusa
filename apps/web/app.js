const apiBase = window.HAYABUSA_API_URL || "http://localhost:8080";
const refreshMs = 7000;

const alertsBody = document.getElementById("alerts-body");
const eventsList = document.getElementById("events-list");
const refreshButton = document.getElementById("refresh-button");
const statusDot = document.getElementById("status-dot");
const statusText = document.getElementById("status-text");
const lastRefresh = document.getElementById("last-refresh");

function fmtTime(value) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString();
}

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

async function getJson(path) {
  const resp = await fetch(`${apiBase}${path}`, { cache: "no-store" });
  if (!resp.ok) {
    throw new Error(`${path} failed with ${resp.status}`);
  }
  return resp.json();
}

function renderAlerts(alerts) {
  if (!alerts.length) {
    alertsBody.innerHTML = '<tr><td colspan="5" class="empty">No alerts yet. Trigger suspicious login activity to populate this table.</td></tr>';
    return;
  }

  alertsBody.innerHTML = alerts
    .map((alert) => {
      const severity = escapeHtml(alert.severity || "unknown").toLowerCase();
      return `
        <tr>
          <td>${escapeHtml(fmtTime(alert.time))}</td>
          <td>${escapeHtml(alert.rule_name || alert.rule_id || alert.alert_type || "")}</td>
          <td><span class="severity ${severity}">${escapeHtml(severity)}</span></td>
          <td>${escapeHtml(alert.endpoint_id || "-")}</td>
          <td>${escapeHtml(alert.summary || "-")}</td>
        </tr>
      `;
    })
    .join("");
}

function renderEvents(events) {
  if (!events.length) {
    eventsList.innerHTML = '<p class="empty">No normalized auth events yet.</p>';
    return;
  }

  eventsList.innerHTML = events
    .slice(0, 8)
    .map(
      (event) => `
        <article class="event-card">
          <strong>${escapeHtml(event.status || "auth")} ${escapeHtml(event.user || "-")} from ${escapeHtml(event.src_ip || "-")}</strong>
          <span>${escapeHtml(fmtTime(event.time))} · ${escapeHtml(event.host || "-")} · ${escapeHtml(event.source_kind || event.ingest_source || "-")}</span>
        </article>
      `,
    )
    .join("");
}

function setStatus(ok, message) {
  statusDot.classList.toggle("ok", ok);
  statusDot.classList.toggle("error", !ok);
  statusText.textContent = ok ? "Live" : "API error";
  lastRefresh.textContent = message;
}

async function refresh() {
  try {
    const [alerts, events] = await Promise.all([
      getJson("/alerts?limit=25"),
      getJson("/events?limit=12"),
    ]);
    renderAlerts(alerts.alerts || []);
    renderEvents(events.events || []);
    setStatus(true, `Updated ${new Date().toLocaleTimeString()}`);
  } catch (err) {
    setStatus(false, err.message);
  }
}

refreshButton.addEventListener("click", refresh);
refresh();
setInterval(refresh, refreshMs);
