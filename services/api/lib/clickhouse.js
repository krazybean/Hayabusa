function createClickHouseClient(baseUrl) {
  const normalized = baseUrl.replace(/\/$/, "");

  return {
    async query(sql) {
      const resp = await fetch(`${normalized}/`, {
        method: "POST",
        body: sql,
      });

      const text = await resp.text();
      if (!resp.ok) {
        throw new Error(`ClickHouse ${resp.status}: ${text.trim()}`);
      }

      return text
        .split("\n")
        .filter(Boolean)
        .map((line) => JSON.parse(line));
    },
  };
}

module.exports = {
  createClickHouseClient,
};
