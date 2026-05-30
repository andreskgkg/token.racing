#!/usr/bin/env node

const http = require("http");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const url = require("url");

const PORT = Number(process.env.PORT || 8787);
const DATA_PATH = process.env.TOKEN_RACING_DB || path.join(__dirname, "token-racing-db.json");

const emptyDb = {
  users: {},
  handles: {},
  inviteCodes: {},
  friendRequests: {},
  usage: {}
};

let db = loadDb();

function loadDb() {
  try {
    return JSON.parse(fs.readFileSync(DATA_PATH, "utf8"));
  } catch {
    return structuredClone(emptyDb);
  }
}

function saveDb() {
  fs.writeFileSync(DATA_PATH, JSON.stringify(db, null, 2));
}

function json(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type"
  });
  res.end(body);
}

function error(res, statusCode, message) {
  json(res, statusCode, { error: message });
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", chunk => {
      data += chunk;
      if (data.length > 1_000_000) {
        reject(new Error("Request body too large"));
        req.destroy();
      }
    });
    req.on("end", () => {
      try {
        resolve(data ? JSON.parse(data) : {});
      } catch (err) {
        reject(err);
      }
    });
  });
}

function normalizeHandle(handle) {
  return String(handle || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]/g, "");
}

function inviteCode() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  return Array.from({ length: 8 }, () => alphabet[Math.floor(Math.random() * alphabet.length)]).join("");
}

function sanitizeAvatarDataURL(value) {
  if (!value) return null;
  const text = String(value);
  const isImage = /^data:image\/(png|jpeg|jpg|webp);base64,[a-zA-Z0-9+/=]+$/.test(text);
  if (!isImage) return null;
  if (text.length > 150_000) return null;
  return text;
}

function userDto(user) {
  return {
    id: user.id,
    handle: user.handle,
    inviteCode: user.inviteCode,
    avatarDataURL: user.avatarDataURL || null,
    createdAt: user.createdAt
  };
}

function friendRowsFor(userId) {
  return Object.values(db.friendRequests)
    .filter(request => request.fromUserId === userId || request.toUserId === userId)
    .filter(request => request.status !== "declined")
    .map(request => {
      const isInbound = request.toUserId === userId;
      const otherUserId = isInbound ? request.fromUserId : request.toUserId;
      const other = db.users[otherUserId];
      return {
        id: other.id,
        handle: other.handle,
        inviteCode: other.inviteCode,
        avatarDataURL: other.avatarDataURL || null,
        status: request.status,
        direction: isInbound ? "inbound" : "outbound"
      };
    });
}

function areAcceptedFriends(userId, otherUserId) {
  return Object.values(db.friendRequests).some(request => {
    const samePair =
      (request.fromUserId === userId && request.toUserId === otherUserId) ||
      (request.fromUserId === otherUserId && request.toUserId === userId);
    return samePair && request.status === "accepted";
  });
}

function visibleUserIds(userId) {
  return Object.keys(db.users).filter(otherUserId => otherUserId === userId || areAcceptedFriends(userId, otherUserId));
}

function aggregateKey(timeframe, app) {
  return `${timeframe}:${app}`;
}

function leaderboardRows(userId, timeframe) {
  return visibleUserIds(userId)
    .map(id => {
      const user = db.users[id];
      const aggregates = db.usage[id] || {};
      const breakdown = {};
      for (const [key, value] of Object.entries(aggregates)) {
        const [storedTimeframe, app] = key.split(":");
        if (storedTimeframe === timeframe) {
          breakdown[app] = Number(value.tokens || 0);
        }
      }
      const totalTokens = Object.values(breakdown).reduce((sum, tokens) => sum + Number(tokens || 0), 0);
      return {
        id: user.id,
        handle: user.handle,
        avatarDataURL: user.avatarDataURL || null,
        totalTokens,
        breakdown,
        isCurrentUser: id === userId,
        rank: 0
      };
    })
    .sort((a, b) => b.totalTokens - a.totalTokens)
    .map((row, index) => ({ ...row, rank: index + 1 }));
}

async function handle(req, res) {
  const parsed = url.parse(req.url, true);

  if (req.method === "OPTIONS") {
    return json(res, 200, {});
  }

  if (req.method === "GET" && parsed.pathname === "/health") {
    return json(res, 200, { ok: true });
  }

  if (req.method === "POST" && parsed.pathname === "/users") {
    const body = await readBody(req);
    const id = String(body.userId || crypto.randomUUID());
    const handle = normalizeHandle(body.handle);
    if (!handle) return error(res, 400, "Handle is required");

    const existingForHandle = db.handles[handle];
    if (existingForHandle && existingForHandle !== id) {
      return error(res, 409, "Handle is already taken");
    }

    const existing = db.users[id] || {};
    const code = existing.inviteCode || String(body.inviteCode || inviteCode()).toUpperCase();
    const avatarDataURL = Object.prototype.hasOwnProperty.call(body, "avatarDataURL")
      ? sanitizeAvatarDataURL(body.avatarDataURL)
      : existing.avatarDataURL || null;
    db.users[id] = {
      id,
      handle,
      inviteCode: code,
      avatarDataURL,
      createdAt: existing.createdAt || new Date().toISOString()
    };
    db.handles[handle] = id;
    db.inviteCodes[code] = id;
    saveDb();
    return json(res, 200, userDto(db.users[id]));
  }

  if (req.method === "GET" && parsed.pathname.startsWith("/friends/")) {
    const userId = parsed.pathname.split("/").pop();
    if (!db.users[userId]) return error(res, 404, "User not found");
    return json(res, 200, friendRowsFor(userId));
  }

  if (req.method === "POST" && parsed.pathname === "/friends/request") {
    const body = await readBody(req);
    const fromUserId = String(body.fromUserId || "");
    const lookup = String(body.handleOrInviteCode || "").trim();
    const normalizedLookup = normalizeHandle(lookup);
    const toUserId = db.handles[normalizedLookup] || db.inviteCodes[lookup.toUpperCase()];

    if (!db.users[fromUserId]) return error(res, 404, "Sender not found");
    if (!toUserId || !db.users[toUserId]) return error(res, 404, "Friend handle or invite code not found");
    if (fromUserId === toUserId) return error(res, 400, "You cannot add yourself");

    const existing = Object.values(db.friendRequests).find(request => {
      return (
        (request.fromUserId === fromUserId && request.toUserId === toUserId) ||
        (request.fromUserId === toUserId && request.toUserId === fromUserId)
      );
    });

    if (existing) {
      return json(res, 200, friendRowsFor(fromUserId));
    }

    const requestId = crypto.randomUUID();
    db.friendRequests[requestId] = {
      id: requestId,
      fromUserId,
      toUserId,
      status: "pending",
      createdAt: new Date().toISOString()
    };
    saveDb();
    return json(res, 200, friendRowsFor(fromUserId));
  }

  if (req.method === "POST" && parsed.pathname === "/friends/respond") {
    const body = await readBody(req);
    const userId = String(body.userId || "");
    const friendId = String(body.friendId || "");
    const status = body.status === "accepted" ? "accepted" : "declined";

    const request = Object.values(db.friendRequests).find(candidate => {
      return candidate.fromUserId === friendId && candidate.toUserId === userId && candidate.status === "pending";
    });

    if (!request) return error(res, 404, "Pending inbound friend request not found");
    request.status = status;
    request.respondedAt = new Date().toISOString();
    saveDb();
    return json(res, 200, friendRowsFor(userId));
  }

  if (req.method === "POST" && parsed.pathname === "/usage") {
    const body = await readBody(req);
    const userId = String(body.userId || "");
    if (!db.users[userId]) return error(res, 404, "User not found");

    db.usage[userId] = db.usage[userId] || {};
    for (const aggregate of body.aggregates || []) {
      const app = String(aggregate.app || "");
      const timeframe = String(aggregate.timeframe || "");
      const tokens = Math.max(0, Number(aggregate.tokens || 0));
      if (!app || !timeframe || !Number.isFinite(tokens)) continue;
      db.usage[userId][aggregateKey(timeframe, app)] = {
        tokens,
        periodStart: aggregate.periodStart,
        updatedAt: new Date().toISOString()
      };
    }
    saveDb();
    return json(res, 200, {});
  }

  if (req.method === "GET" && parsed.pathname.startsWith("/leaderboard/")) {
    const userId = parsed.pathname.split("/").pop();
    const timeframe = String(parsed.query.timeframe || "Today");
    if (!db.users[userId]) return error(res, 404, "User not found");
    return json(res, 200, leaderboardRows(userId, timeframe));
  }

  return error(res, 404, "Not found");
}

const server = http.createServer((req, res) => {
  handle(req, res).catch(err => {
    error(res, 500, err.message || "Server error");
  });
});

server.listen(PORT, () => {
  console.log(`Token Racing sync server listening on http://127.0.0.1:${PORT}`);
  console.log("Synced data is limited to handles, friend graph, invite codes, and aggregate token counts.");
});
