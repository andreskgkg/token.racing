#!/usr/bin/env node

const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const port = 19000 + Math.floor(Math.random() * 1000);
const baseURL = `http://127.0.0.1:${port}`;
const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "token-racing-smoke-"));
const dbPath = path.join(tempDir, "db.json");

const server = childProcess.spawn(process.execPath, ["server.js"], {
  cwd: __dirname,
  env: {
    ...process.env,
    PORT: String(port),
    TOKEN_RACING_DB: dbPath
  },
  stdio: ["ignore", "pipe", "pipe"]
});

let logs = "";
server.stdout.on("data", chunk => {
  logs += chunk.toString();
});
server.stderr.on("data", chunk => {
  logs += chunk.toString();
});

async function request(pathname, options = {}) {
  const response = await fetch(`${baseURL}${pathname}`, {
    headers: { "Content-Type": "application/json" },
    ...options
  });
  const body = await response.json();
  if (!response.ok) {
    throw new Error(`${response.status} ${JSON.stringify(body)}`);
  }
  return body;
}

async function waitForServer() {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    try {
      await request("/health");
      return;
    } catch {
      await new Promise(resolve => setTimeout(resolve, 100));
    }
  }
  throw new Error(`Server did not start. Logs:\n${logs}`);
}

async function main() {
  await waitForServer();

  const alice = await request("/users", {
    method: "POST",
    body: JSON.stringify({
      userId: "11111111-1111-4111-8111-111111111111",
      handle: "Alice",
      inviteCode: "ALICE123"
    })
  });
  assert.equal(alice.handle, "alice");

  const bob = await request("/users", {
    method: "POST",
    body: JSON.stringify({
      userId: "22222222-2222-4222-8222-222222222222",
      handle: "bob",
      inviteCode: "BOB22222"
    })
  });
  assert.equal(bob.handle, "bob");

  const aliceFriends = await request("/friends/request", {
    method: "POST",
    body: JSON.stringify({
      fromUserId: alice.id,
      handleOrInviteCode: bob.inviteCode
    })
  });
  assert.equal(aliceFriends.length, 1);
  assert.equal(aliceFriends[0].status, "pending");
  assert.equal(aliceFriends[0].direction, "outbound");

  const bobFriends = await request(`/friends/${bob.id}`);
  assert.equal(bobFriends[0].direction, "inbound");

  const accepted = await request("/friends/respond", {
    method: "POST",
    body: JSON.stringify({
      userId: bob.id,
      friendId: alice.id,
      status: "accepted"
    })
  });
  assert.equal(accepted[0].status, "accepted");

  await request("/usage", {
    method: "POST",
    body: JSON.stringify({
      userId: alice.id,
      handle: alice.handle,
      aggregates: [
        { app: "Cursor", timeframe: "Today", periodStart: "2026-05-29T00:00:00Z", tokens: 1200 },
        { app: "Claude Code", timeframe: "Today", periodStart: "2026-05-29T00:00:00Z", tokens: 800 },
        { app: "Codex", timeframe: "Today", periodStart: "2026-05-29T00:00:00Z", tokens: 100 }
      ]
    })
  });

  await request("/usage", {
    method: "POST",
    body: JSON.stringify({
      userId: bob.id,
      handle: bob.handle,
      aggregates: [
        { app: "Cursor", timeframe: "Today", periodStart: "2026-05-29T00:00:00Z", tokens: 300 },
        { app: "Claude Code", timeframe: "Today", periodStart: "2026-05-29T00:00:00Z", tokens: 4000 },
        { app: "Codex", timeframe: "Today", periodStart: "2026-05-29T00:00:00Z", tokens: 0 }
      ]
    })
  });

  const leaderboard = await request(`/leaderboard/${alice.id}?timeframe=Today`);
  assert.equal(leaderboard.length, 2);
  assert.equal(leaderboard[0].handle, "bob");
  assert.equal(leaderboard[0].totalTokens, 4300);
  assert.equal(leaderboard[1].handle, "alice");
  assert.equal(leaderboard[1].breakdown.Cursor, 1200);

  console.log("Backend smoke test passed.");
}

main()
  .finally(() => {
    server.kill();
    fs.rmSync(tempDir, { recursive: true, force: true });
  })
  .catch(err => {
    console.error(err);
    process.exitCode = 1;
  });
