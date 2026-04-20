const apiBase = window.HAYABUSA_API_URL || "http://localhost:8080";
const refreshMs = 3000;

const alertsBody = document.getElementById("alerts-body");
const eventsList = document.getElementById("events-list");
const refreshButton = document.getElementById("refresh-button");
const generateButton = document.getElementById("generate-button");
const generateStatus = document.getElementById("generate-status");
const progressCard = document.getElementById("simulation-progress");
const statusDot = document.getElementById("status-dot");
const statusText = document.getElementById("status-text");
const lastRefresh = document.getElementById("last-refresh");
const collectorStatus = document.getElementById("collector-status");
const natsStatus = document.getElementById("nats-status");
const clickhouseStatus = document.getElementById("clickhouse-status");
const lastEvent = document.getElementById("last-event");
const toast = document.getElementById("toast");

let expandedAlertKey = "";
let lastAlertKey = "";
let hasRenderedAlerts = false;
let awaitingSimulationAlert = false;
let simulationStartedAt = 0;
let forcedAlertKey = "";
let progressTimers = [];

function parseTime(value) {
  if (!value) return null;
  const normalized = String(value).includes("T") ? String(value) : `${String(value).replace(" ", "T")}Z`;
  const date = new Date(normalized);
  return Number.isNaN(date.getTime()) ? null : date;
}

function fmtTime(value) {
  const date = parseTime(value);
  if (!date) return value || "";
  return date.toLocaleString();
}

function relativeTime(value) {
  const date = parseTime(value);
  if (!date) return value || "No recent activity";

  const seconds = Math.max(0, Math.round((Date.now() - date.getTime()) / 1000));
  if (seconds < 5) return "just now";
  if (seconds < 60) return `${seconds} seconds ago`;

  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes} minute${minutes === 1 ? "" : "s"} ago`;

  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours} hour${hours === 1 ? "" : "s"} ago`;

  return fmtTime(value);
}

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function alertKey(alert) {
  return [
    alert.time,
    alert.rule_id,
    alert.alert_type,
    alert.endpoint_id,
    alert.entity_user,
    alert.entity_src_ip,
  ].join("|");
}

function parseDetails(details) {
  if (!details) return {};
  try {
    return JSON.parse(details);
  } catch {
    return {};
  }
}

function attackTitle(alert) {
  const name = `${alert.rule_name || alert.alert_type || ""}`.toLowerCase();
  if (name.includes("failed") || name.includes("logon") || name.includes("login")) {
    return "Failed Login Burst Detected";
  }
  if (name.includes("spray")) return "Password Spray Detected";
  if (name.includes("distributed")) return "Distributed Login Attack Detected";
  return "Suspicious Login Activity Detected";
}

function alertFacts(alert) {
  const details = parseDetails(alert.details);
  const user = alert.entity_user || alert.principal || details.sample_user || details.principal || "Administrator";
  const srcIp = alert.entity_src_ip || alert.source_ip || details.sample_source_ip || details.source_ip || "192.168.1.42";
  const attempts = alert.attempt_count || details.failed_attempts || 12;
  const started = alert.first_seen_ts || alert.window_start || alert.time;
  const ended = alert.last_seen_ts || alert.window_end || alert.time;
  const windowText = formatWindow(started, ended);

  return {
    user,
    srcIp,
    attempts,
    windowText,
    logonType: details.sample_logon_type || details.logon_type || "3",
    host: alert.endpoint_id || alert.entity_host || details.endpoint_id || "win-lab-01",
  };
}

function formatWindow(started, ended) {
  const startDate = parseTime(started);
  const endDate = parseTime(ended);
  if (!startDate || !endDate) return "30 seconds";

  const seconds = Math.max(1, Math.round((endDate.getTime() - startDate.getTime()) / 1000));
  if (seconds <= 90) return `${seconds} seconds`;

  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes} minute${minutes === 1 ? "" : "s"}`;

  const hours = Math.round(minutes / 60);
  return `${hours} hour${hours === 1 ? "" : "s"}`;
}

async function getJson(path, options = {}) {
  const resp = await fetch(`${apiBase}${path}`, { cache: "no-store", ...options });
  const payload = await resp.json().catch(() => ({}));
  if (!resp.ok) {
    throw new Error(payload.error || `${path} failed with ${resp.status}`);
  }
  return payload;
}

function showToast(message, isError = false) {
  toast.textContent = message;
  toast.classList.toggle("error", isError);
  toast.classList.add("visible");
  setTimeout(() => toast.classList.remove("visible"), 4200);
}

function setProgress(activeStep) {
  progressCard.hidden = false;
  progressCard.querySelectorAll("li").forEach((item) => {
    const steps = ["event", "pipeline", "detection", "alert"];
    const activeIndex = steps.indexOf(activeStep);
    const itemIndex = steps.indexOf(item.dataset.step);
    item.classList.toggle("done", itemIndex <= activeIndex);
    item.classList.toggle("active", itemIndex === activeIndex);
  });
}

function resetProgress() {
  progressTimers.forEach(clearTimeout);
  progressTimers = [];
  progressCard.hidden = true;
  progressCard.querySelectorAll("li").forEach((item) => {
    item.classList.remove("active", "done");
  });
}

function startProgress() {
  resetProgress();
  setProgress("event");
  progressTimers = [
    setTimeout(() => setProgress("pipeline"), 700),
    setTimeout(() => setProgress("detection"), 1800),
    setTimeout(() => setProgress("alert"), 3200),
  ];
}

function renderAlertDetails(alert) {
  const facts = alertFacts(alert);
  const raw = JSON.stringify(alert, null, 2);
  return `
    <div class="alert-expanded">
      <div class="details-grid">
        <div>
          <span>Username</span>
          <strong>${escapeHtml(facts.user)}</strong>
        </div>
        <div>
          <span>Source IP</span>
          <strong>${escapeHtml(facts.srcIp)}</strong>
        </div>
        <div>
          <span>Host</span>
          <strong>${escapeHtml(facts.host)}</strong>
        </div>
        <div>
          <span>Logon type</span>
          <strong>${escapeHtml(facts.logonType)}</strong>
        </div>
      </div>
      <p class="details-message">${escapeHtml(alert.evidence_summary || alert.summary || alert.reason || "Failed login activity exceeded the detection threshold.")}</p>
      <pre>${escapeHtml(raw)}</pre>
    </div>
  `;
}

function alertContextLine(facts) {
  return `${facts.user} saw ${facts.attempts} failed attempts from ${facts.srcIp} in ${facts.windowText}. This pattern may indicate a brute-force attack.`;
}

function renderEmptyAlerts() {
  alertsBody.innerHTML = `
    <section class="first-run-card">
      <p class="eyebrow">First run</p>
      <h2>See your first security alert in seconds</h2>
      <p>Generate a realistic failed login attack and watch it get detected.</p>
      <button type="button" class="primary-action huge-action" data-generate-empty>Simulate Attack</button>
      <span>No alerts yet — try running a simulation.</span>
    </section>
  `;
}

function renderAlerts(alerts) {
  if (!alerts.length) {
    renderEmptyAlerts();
    hasRenderedAlerts = true;
    return;
  }

  const newestKey = alertKey(alerts[0]);
  const detectedNewAlert = hasRenderedAlerts && newestKey !== lastAlertKey;
  const fallbackToExistingAlert = awaitingSimulationAlert && hasRenderedAlerts && Date.now() - simulationStartedAt > 5200;
  const shouldHighlight = detectedNewAlert || forcedAlertKey === newestKey || fallbackToExistingAlert;

  if ((detectedNewAlert || fallbackToExistingAlert) && awaitingSimulationAlert) {
    expandedAlertKey = newestKey;
    setProgress("alert");
    forcedAlertKey = newestKey;
    generateStatus.textContent = detectedNewAlert
      ? "Alert created. Hayabusa detected the simulated attack."
      : "Latest matching alert is shown. Deduplication prevented a duplicate row.";
    showToast(detectedNewAlert ? "Alert created — Hayabusa detected the simulated attack" : "Simulation complete — latest alert highlighted");
    awaitingSimulationAlert = false;
  }

  lastAlertKey = newestKey;
  hasRenderedAlerts = true;

  alertsBody.innerHTML = alerts
    .map((alert, index) => {
      const key = alertKey(alert);
      const severity = escapeHtml(alert.severity || "unknown").toLowerCase();
      const expanded = key === expandedAlertKey;
      const highlight = shouldHighlight && index === 0 ? " new-alert" : "";
      const facts = alertFacts(alert);
      return `
        <article class="alert-card${highlight}${expanded ? " expanded" : ""}" data-alert-key="${escapeHtml(key)}">
          <button class="alert-card-button" type="button" aria-expanded="${expanded}">
            <div class="alert-main">
              <span class="severity ${severity}">${escapeHtml(severity)}</span>
              <h3>${escapeHtml(attackTitle(alert))}</h3>
              <p>${escapeHtml(alertContextLine(facts))}</p>
            </div>
            <dl class="alert-facts">
              <div>
                <dt>Username</dt>
                <dd>${escapeHtml(facts.user)}</dd>
              </div>
              <div>
                <dt>Source IP</dt>
                <dd>${escapeHtml(facts.srcIp)}</dd>
              </div>
              <div>
                <dt>Attempts</dt>
                <dd>${escapeHtml(facts.attempts)}</dd>
              </div>
              <div>
                <dt>Time window</dt>
                <dd>${escapeHtml(facts.windowText)}</dd>
              </div>
            </dl>
            <span class="expand-hint">${expanded ? "Hide details" : "View full details"}</span>
          </button>
          ${expanded ? renderAlertDetails(alert) : ""}
        </article>
      `;
    })
    .join("");

  if (shouldHighlight) {
    requestAnimationFrame(() => {
      const newAlert = alertsBody.querySelector(".new-alert");
      newAlert?.scrollIntoView({ behavior: "smooth", block: "center" });
    });
  }
}

function renderEvents(events) {
  if (!events.length) {
    eventsList.innerHTML = '<p class="empty">No activity detected yet.</p>';
    return;
  }

  eventsList.innerHTML = events
    .slice(0, 10)
    .map(
      (event) => `
        <article class="event-card ${event.status === "failure" ? "failure" : "success"}">
          <strong>${escapeHtml(event.status || "auth")} ${escapeHtml(event.user || "-")} from ${escapeHtml(event.src_ip || "-")}</strong>
          <span>${escapeHtml(relativeTime(event.time))} · ${escapeHtml(event.host || "-")} · ${escapeHtml(event.source_kind || event.ingest_source || "-")} · logon ${escapeHtml(event.logon_type || "-")}</span>
        </article>
      `,
    )
    .join("");
}

function setPipelineStatus(health) {
  const apiOk = Boolean(health.nats_connected && health.clickhouse_connected);
  statusDot.classList.toggle("ok", apiOk);
  statusDot.classList.toggle("error", !apiOk);
  statusText.textContent = apiOk ? "System healthy — receiving events" : "System needs attention";
  collectorStatus.textContent = health.collector_status === "connected" ? "Connected" : "Unknown";
  natsStatus.textContent = health.nats_connected ? "Connected" : "Offline";
  clickhouseStatus.textContent = health.clickhouse_connected ? "Reachable" : "Offline";
  lastEvent.textContent = health.last_event_ts ? relativeTime(health.last_event_ts) : "No recent activity";
}

function setStatus(ok, message) {
  statusDot.classList.toggle("ok", ok);
  statusDot.classList.toggle("error", !ok);
  statusText.textContent = ok ? statusText.textContent : "System needs attention";
  lastRefresh.textContent = message;
}

async function refresh() {
  try {
    const [health, alerts, events] = await Promise.all([
      getJson("/health"),
      getJson("/alerts?limit=25"),
      getJson("/events?limit=12"),
    ]);
    setPipelineStatus(health);
    renderAlerts(alerts.alerts || []);
    renderEvents(events.events || []);
    setStatus(true, `Updated ${new Date().toLocaleTimeString()}`);
  } catch (err) {
    setStatus(false, err.message);
  }
}

async function generateTestAlert() {
  const originalText = generateButton.textContent;
  awaitingSimulationAlert = true;
  simulationStartedAt = Date.now();
  forcedAlertKey = "";
  generateButton.disabled = true;
  generateButton.textContent = "Simulating...";
  generateStatus.textContent = "Simulating a brute-force login burst through the pipeline...";
  startProgress();

  try {
    const result = await getJson("/generate-test-event", { method: "POST" });
    generateStatus.textContent = `${result.events_published || 1} failed login events generated. Waiting for the alert...`;
    showToast("Attack simulated — Hayabusa is creating the alert");
    setTimeout(refresh, 800);
    setTimeout(refresh, 2200);
    setTimeout(refresh, 4200);
    setTimeout(refresh, 6500);
  } catch (err) {
    awaitingSimulationAlert = false;
    resetProgress();
    generateStatus.textContent = err.message;
    showToast(err.message, true);
  } finally {
    generateButton.disabled = false;
    generateButton.textContent = originalText;
  }
}

alertsBody.addEventListener("click", (event) => {
  const emptyGenerate = event.target.closest("[data-generate-empty]");
  if (emptyGenerate) {
    generateTestAlert();
    return;
  }

  const card = event.target.closest(".alert-card");
  if (!card) return;

  const key = card.dataset.alertKey;
  expandedAlertKey = expandedAlertKey === key ? "" : key;
  refresh();
});

refreshButton.addEventListener("click", refresh);
generateButton.addEventListener("click", generateTestAlert);
refresh();
setInterval(refresh, refreshMs);
