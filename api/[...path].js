const crypto = require("crypto");

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const TABLES = {
  users: "token_racing_users",
  friends: "token_racing_friend_requests",
  usage: "token_racing_usage"
};

module.exports = async function handler(req, res) {
  setCors(res);
  if (req.method === "OPTIONS") return json(res, 200, {});

  try {
    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      return error(res, 503, "Hosted backend is not configured. Add SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in Vercel.");
    }

    const route = routePath(req);
    if (req.method === "GET" && route === "/health") {
      return json(res, 200, { ok: true, backend: "supabase" });
    }

    if (req.method === "POST" && route === "/users") return upsertUser(req, res);
    if (req.method === "GET" && route.startsWith("/friends/")) return fetchFriends(req, res, route.split("/").pop());
    if (req.method === "POST" && route === "/friends/request") return sendFriendRequest(req, res);
    if (req.method === "POST" && route === "/friends/respond") return respondToFriendRequest(req, res);
    if (req.method === "POST" && route === "/usage") return uploadUsage(req, res);
    if (req.method === "GET" && route.startsWith("/leaderboard/")) return fetchLeaderboard(req, res, route.split("/").pop());

    return error(res, 404, "Not found");
  } catch (err) {
    return error(res, err.statusCode || 500, err.message || "Server error");
  }
};

async function upsertUser(req, res) {
  const body = await readBody(req);
  const id = String(body.userId || crypto.randomUUID());
  const handle = normalizeHandle(body.handle);
  if (!handle) return error(res, 400, "Handle is required");

  const existingForHandle = await select(TABLES.users, { handle: `eq.${handle}`, select: "id" });
  if (existingForHandle[0] && existingForHandle[0].id !== id) {
    return error(res, 409, "Handle is already taken");
  }

  const existing = (await select(TABLES.users, { id: `eq.${id}`, select: "*" }))[0];
  const inviteCode = existing?.invite_code || String(body.inviteCode || generateInviteCode()).toUpperCase();
  const avatarDataURL = Object.prototype.hasOwnProperty.call(body, "avatarDataURL")
    ? sanitizeAvatarDataURL(body.avatarDataURL)
    : existing?.avatar_data_url || null;

  const rows = await requestTable(`${TABLES.users}?on_conflict=id`, {
    method: "POST",
    prefer: "resolution=merge-duplicates,return=representation",
    body: {
      id,
      handle,
      invite_code: inviteCode,
      avatar_data_url: avatarDataURL,
      created_at: existing?.created_at || new Date().toISOString()
    }
  });

  return json(res, 200, userDto(rows[0]));
}

async function fetchFriends(_req, res, userId) {
  await requireUser(userId);
  return json(res, 200, await friendRowsFor(userId));
}

async function sendFriendRequest(req, res) {
  const body = await readBody(req);
  const fromUserId = String(body.fromUserId || "");
  const lookup = String(body.handleOrInviteCode || "").trim();
  const normalizedLookup = normalizeHandle(lookup);
  const inviteLookup = lookup.toUpperCase();

  await requireUser(fromUserId, "Sender not found");
  const targetRows = await select(TABLES.users, {
    or: `(handle.eq.${normalizedLookup},invite_code.eq.${inviteLookup})`,
    select: "*"
  });
  const target = targetRows[0];
  if (!target) return error(res, 404, "Friend not found. Ask them for their exact handle or invite code after they open Token Racing once.");
  if (target.id === fromUserId) return error(res, 400, "You cannot add yourself");

  const existing = await select(TABLES.friends, {
    or: `(and(from_user_id.eq.${fromUserId},to_user_id.eq.${target.id}),and(from_user_id.eq.${target.id},to_user_id.eq.${fromUserId}))`,
    select: "*"
  });
  if (!existing[0]) {
    await requestTable(TABLES.friends, {
      method: "POST",
      prefer: "return=minimal",
      body: {
        id: crypto.randomUUID(),
        from_user_id: fromUserId,
        to_user_id: target.id,
        status: "pending",
        created_at: new Date().toISOString()
      }
    });
  }

  return json(res, 200, await friendRowsFor(fromUserId));
}

async function respondToFriendRequest(req, res) {
  const body = await readBody(req);
  const userId = String(body.userId || "");
  const friendId = String(body.friendId || "");
  const status = body.status === "accepted" ? "accepted" : "declined";

  await requireUser(userId);
  const rows = await select(TABLES.friends, {
    from_user_id: `eq.${friendId}`,
    to_user_id: `eq.${userId}`,
    status: "eq.pending",
    select: "*"
  });
  if (!rows[0]) return error(res, 404, "Pending inbound friend request not found");

  await requestTable(`${TABLES.friends}?id=eq.${rows[0].id}`, {
    method: "PATCH",
    prefer: "return=minimal",
    body: { status, responded_at: new Date().toISOString() }
  });

  return json(res, 200, await friendRowsFor(userId));
}

async function uploadUsage(req, res) {
  const body = await readBody(req);
  const userId = String(body.userId || "");
  await requireUser(userId);

  const rows = (body.aggregates || [])
    .map(aggregate => ({
      user_id: userId,
      app: String(aggregate.app || ""),
      timeframe: String(aggregate.timeframe || ""),
      period_start: aggregate.periodStart || new Date().toISOString(),
      tokens: Math.max(0, Number(aggregate.tokens || 0)),
      updated_at: new Date().toISOString()
    }))
    .filter(row => row.app && row.timeframe && Number.isFinite(row.tokens));

  if (rows.length > 0) {
    await requestTable(`${TABLES.usage}?on_conflict=user_id,timeframe,app`, {
      method: "POST",
      prefer: "resolution=merge-duplicates,return=minimal",
      body: rows
    });
  }

  return json(res, 200, {});
}

async function fetchLeaderboard(req, res, userId) {
  await requireUser(userId);
  const timeframe = String(queryValue(req, "timeframe") || "Today");
  const visibleIds = await visibleUserIds(userId);
  const users = await usersByIds(visibleIds);
  const usageRows = visibleIds.length
    ? await select(TABLES.usage, {
        user_id: `in.(${visibleIds.join(",")})`,
        timeframe: `eq.${timeframe}`,
        select: "*"
      })
    : [];

  const rows = users.map(user => {
    const breakdown = {};
    for (const row of usageRows.filter(usage => usage.user_id === user.id)) {
      breakdown[row.app] = Number(row.tokens || 0);
    }
    return {
      id: user.id,
      handle: user.handle,
      avatarDataURL: user.avatar_data_url || null,
      totalTokens: Object.values(breakdown).reduce((sum, tokens) => sum + Number(tokens || 0), 0),
      breakdown,
      isCurrentUser: user.id === userId,
      rank: 0
    };
  });

  rows.sort((a, b) => b.totalTokens - a.totalTokens);
  rows.forEach((row, index) => {
    row.rank = index + 1;
  });
  return json(res, 200, rows);
}

async function friendRowsFor(userId) {
  const requests = await select(TABLES.friends, {
    or: `(from_user_id.eq.${userId},to_user_id.eq.${userId})`,
    status: "neq.declined",
    select: "*"
  });
  const otherIds = [...new Set(requests.map(request => (request.to_user_id === userId ? request.from_user_id : request.to_user_id)))];
  const users = await usersByIds(otherIds);
  const usersById = Object.fromEntries(users.map(user => [user.id, user]));

  return requests
    .map(request => {
      const isInbound = request.to_user_id === userId;
      const other = usersById[isInbound ? request.from_user_id : request.to_user_id];
      if (!other) return null;
      return {
        id: other.id,
        handle: other.handle,
        inviteCode: other.invite_code,
        avatarDataURL: other.avatar_data_url || null,
        status: request.status,
        direction: isInbound ? "inbound" : "outbound"
      };
    })
    .filter(Boolean);
}

async function visibleUserIds(userId) {
  const accepted = await select(TABLES.friends, {
    or: `(from_user_id.eq.${userId},to_user_id.eq.${userId})`,
    status: "eq.accepted",
    select: "from_user_id,to_user_id"
  });
  return [
    userId,
    ...accepted.map(request => (request.to_user_id === userId ? request.from_user_id : request.to_user_id))
  ];
}

async function requireUser(userId, message = "User not found") {
  const user = (await select(TABLES.users, { id: `eq.${userId}`, select: "*" }))[0];
  if (!user) {
    const err = new Error(message);
    err.statusCode = 404;
    throw err;
  }
  return user;
}

async function usersByIds(ids) {
  if (!ids.length) return [];
  return select(TABLES.users, { id: `in.(${ids.join(",")})`, select: "*" });
}

async function select(table, params) {
  return requestTable(`${table}?${new URLSearchParams(params).toString()}`, { method: "GET" });
}

async function requestTable(path, options = {}) {
  const response = await fetch(`${SUPABASE_URL.replace(/\/$/, "")}/rest/v1/${path}`, {
    method: options.method || "GET",
    headers: {
      apikey: SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
      ...(options.prefer ? { Prefer: options.prefer } : {})
    },
    body: options.body === undefined ? undefined : JSON.stringify(options.body)
  });

  const text = await response.text();
  const payload = text ? JSON.parse(text) : null;
  if (!response.ok) {
    const err = new Error(payload?.message || payload?.hint || `Supabase HTTP ${response.status}`);
    err.statusCode = response.status;
    throw err;
  }
  return payload || [];
}

function routePath(req) {
  const pathname = new URL(req.url, "https://token.racing").pathname;
  return pathname.replace(/^\/api/, "") || "/";
}

function queryValue(req, name) {
  return new URL(req.url, "https://token.racing").searchParams.get(name);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", chunk => {
      data += chunk;
      if (data.length > 1_000_000) reject(new Error("Request body too large"));
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

function userDto(user) {
  return {
    id: user.id,
    handle: user.handle,
    inviteCode: user.invite_code,
    avatarDataURL: user.avatar_data_url || null,
    createdAt: user.created_at
  };
}

function normalizeHandle(handle) {
  return String(handle || "").trim().toLowerCase().replace(/[^a-z0-9_-]/g, "");
}

function generateInviteCode() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  return Array.from({ length: 8 }, () => alphabet[Math.floor(Math.random() * alphabet.length)]).join("");
}

function sanitizeAvatarDataURL(value) {
  if (!value) return null;
  const text = String(value);
  if (!/^data:image\/(png|jpeg|jpg|webp);base64,[a-zA-Z0-9+/=]+$/.test(text)) return null;
  return text.length > 150_000 ? null : text;
}

function setCors(res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,PATCH,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
}

function json(res, statusCode, payload) {
  res.status(statusCode).json(payload);
}

function error(res, statusCode, message) {
  json(res, statusCode, { error: message });
}
