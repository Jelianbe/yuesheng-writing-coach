var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// src/types.ts
var WorkBuddyCloudConfigError = class extends Error {
  static {
    __name(this, "WorkBuddyCloudConfigError");
  }
  constructor(message) {
    super(message);
    this.name = "WorkBuddyCloudConfigError";
  }
};

// src/http/fetch.ts
var PUBLISHABLE_KEY_HEADER = "x-wb-webapp-access-key";
function createCloudFetch(config, getSessionToken) {
  return async (input, init) => {
    const headers = new Headers(init?.headers);
    headers.set(PUBLISHABLE_KEY_HEADER, config.publishableKey);
    if (!headers.has("Authorization")) {
      const token = await getSessionToken();
      if (token) {
        headers.set("Authorization", `Bearer ${token}`);
      }
    }
    return config.fetch(input, {
      ...init,
      headers
    });
  };
}
__name(createCloudFetch, "createCloudFetch");
var anonymousTokenProvider = /* @__PURE__ */ __name(() => Promise.resolve(void 0), "anonymousTokenProvider");

// src/paths.ts
var CLOUD_PATH_PREFIX = "/.cloud";
var CLOUD_MODULE_PATHS = Object.freeze({
  auth: `${CLOUD_PATH_PREFIX}/auth`,
  database: `${CLOUD_PATH_PREFIX}/database/rest`,
  storage: `${CLOUD_PATH_PREFIX}/storage`,
  llm: `${CLOUD_PATH_PREFIX}/llm`
});

// src/modules/auth/session-store.ts
var STORAGE_KEY_PREFIX = "workbuddy-cloud.session.";
function createMemoryStorage() {
  const map = /* @__PURE__ */ new Map();
  return {
    getItem: /* @__PURE__ */ __name((k) => map.get(k) ?? null, "getItem"),
    setItem: /* @__PURE__ */ __name((k, v) => void map.set(k, v), "setItem"),
    removeItem: /* @__PURE__ */ __name((k) => void map.delete(k), "removeItem")
  };
}
__name(createMemoryStorage, "createMemoryStorage");
function resolveStorage(candidate) {
  if (candidate) {
    return candidate;
  }
  try {
    const probe = "__workbuddy_probe__";
    globalThis.localStorage.setItem(probe, "1");
    globalThis.localStorage.removeItem(probe);
    return globalThis.localStorage;
  } catch {
    return createMemoryStorage();
  }
}
__name(resolveStorage, "resolveStorage");
var SessionStore = class {
  static {
    __name(this, "SessionStore");
  }
  storage;
  key;
  constructor(storage, publishableKey) {
    this.storage = storage;
    this.key = STORAGE_KEY_PREFIX + publishableKey;
  }
  /**
   * 读当前会话。
   *
   * 任何解析失败都当作「没有会话」并**顺手清掉**那条脏记录：残留的坏 JSON
   * 会让每次读都失败一次，而用户永远不知道该去清哪个 key。
   * 触发场景真实存在 —— 用户手改 localStorage、SDK 升级换了存储格式。
   */
  read() {
    let raw;
    try {
      raw = this.storage.getItem(this.key);
    } catch {
      return null;
    }
    if (!raw) {
      return null;
    }
    try {
      const parsed = JSON.parse(raw);
      return isStoredSession(parsed) ? parsed : this.discard();
    } catch {
      return this.discard();
    }
  }
  write(session) {
    try {
      this.storage.setItem(this.key, JSON.stringify(session));
    } catch {
    }
  }
  clear() {
    try {
      this.storage.removeItem(this.key);
    } catch {
    }
  }
  discard() {
    this.clear();
    return null;
  }
};
function isStoredSession(value) {
  if (!value || typeof value !== "object") {
    return false;
  }
  const s = value;
  return typeof s.accessToken === "string" && s.accessToken !== "" && typeof s.refreshToken === "string" && typeof s.expiresAt === "number" && !!s.user && typeof s.user === "object";
}
__name(isStoredSession, "isStoredSession");

// src/modules/auth/pkce.ts
var VERIFIER_KEY_PREFIX = "workbuddy-cloud.pkce.workbuddy.";
var CONSUMED_KEY_PREFIX = "workbuddy-cloud.pkce-done.workbuddy.";
function base64UrlEncode(bytes) {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
__name(base64UrlEncode, "base64UrlEncode");
function hasWebCrypto() {
  const c = globalThis.crypto;
  return typeof c?.getRandomValues === "function" && typeof c?.subtle?.digest === "function" && typeof globalThis.btoa === "function";
}
__name(hasWebCrypto, "hasWebCrypto");
function createCodeVerifier() {
  const bytes = new Uint8Array(32);
  globalThis.crypto.getRandomValues(bytes);
  return base64UrlEncode(bytes);
}
__name(createCodeVerifier, "createCodeVerifier");
async function computeS256Challenge(verifier) {
  const data = new TextEncoder().encode(verifier);
  const digest = await globalThis.crypto.subtle.digest("SHA-256", data);
  return base64UrlEncode(new Uint8Array(digest));
}
__name(computeS256Challenge, "computeS256Challenge");
var WorkBuddyPkceStore = class {
  static {
    __name(this, "WorkBuddyPkceStore");
  }
  verifierKey;
  consumedKey;
  constructor(publishableKey) {
    this.verifierKey = VERIFIER_KEY_PREFIX + publishableKey;
    this.consumedKey = CONSUMED_KEY_PREFIX + publishableKey;
  }
  /** sessionStorage 是否真的可读写（隐私模式、部分 WebView 下访问即抛）。 */
  usable() {
    const storage = this.storage();
    if (!storage) {
      return false;
    }
    try {
      const probe = `${this.verifierKey}.probe`;
      storage.setItem(probe, "1");
      storage.removeItem(probe);
      return true;
    } catch {
      return false;
    }
  }
  /** 写入失败返回 false —— 调用方据此拒绝发起登录。 */
  saveVerifier(verifier) {
    try {
      const storage = this.storage();
      if (!storage) {
        return false;
      }
      storage.setItem(this.verifierKey, verifier);
      storage.removeItem(this.consumedKey);
      return true;
    } catch {
      return false;
    }
  }
  readVerifier() {
    try {
      return this.storage()?.getItem(this.verifierKey) ?? null;
    } catch {
      return null;
    }
  }
  clearVerifier() {
    try {
      this.storage()?.removeItem(this.verifierKey);
    } catch {
    }
  }
  /**
   * 记下刚兑换成功的那个 state。
   *
   * 回调处理在应用里常被调两次（框架的严格模式、路由二次挂载）。第二次时
   * verifier 已经清掉了，如果不认这个标记就会报「缺少证明」，看起来像登录失败，
   * 而其实会话已经建好了。记下 state 才能把第二次识别成重复回调、直接返回空。
   */
  markConsumed(state) {
    try {
      this.storage()?.setItem(this.consumedKey, state);
    } catch {
    }
  }
  isConsumed(state) {
    try {
      return !!state && this.storage()?.getItem(this.consumedKey) === state;
    } catch {
      return false;
    }
  }
  storage() {
    try {
      return globalThis.sessionStorage ?? null;
    } catch {
      return null;
    }
  }
};

// src/modules/auth/protocol.ts
var AUTH_PATHS = {
  signUp: "/v1/signup",
  signIn: "/v1/signin",
  signInWithProvider: "/v1/signin/with/provider",
  /** 本地续期端点（服务端不转发上游）。 */
  token: "/v1/token",
  /** 小程序微信登录：本地认人后仍需用 custom 票据换取 TCB session。 */
  loginWechat: "/v1/login-wechat",
  /** 网页微信扫码：Relay 回调后换 Genie session。 */
  loginWechatWeb: "/v1/login-wechat-web",
  /** WorkBuddy 统一登录：Relay 回调后带 PKCE verifier 换 Genie session。 */
  loginWorkBuddy: "/v1/login-workbuddy",
  /** WorkBuddy 小程序授权码换应用会话；不经过 Web Relay callback。 */
  loginWorkBuddyMiniProgram: "/v1/login-workbuddy-miniprogram",
  signOut: "/v1/user/signout",
  userMe: "/v1/user/me",
  /** 发码。 */
  verification: "/v1/verification",
  /** 验码，返回一次性的 verification_token（**不是**会话）。 */
  verificationVerify: "/v1/verification/verify",
  /** 忘记密码最终更新。 */
  resetPassword: "/v1/reset",
  /** 登录后改密的二次校验。 */
  sudo: "/v1/user/sudo",
  /** 登录后更新密码。 */
  userPassword: "/v1/user/password"
};
function parseSession(payload, receivedAt) {
  const raw = payload ?? {};
  const accessToken = typeof raw.access_token === "string" ? raw.access_token : "";
  if (!accessToken) {
    throw sessionShapeError("response has no access_token");
  }
  const refreshToken = typeof raw.refresh_token === "string" ? raw.refresh_token : "";
  const expiresInSec = typeof raw.expires_in === "number" ? raw.expires_in : 0;
  return {
    accessToken,
    refreshToken,
    expiresAt: receivedAt + expiresInSec * 1e3,
    user: userFromSessionPayload(raw)
  };
}
__name(parseSession, "parseSession");
function userFromSessionPayload(raw) {
  const isAnonymous = raw.is_anonymous === true;
  return {
    id: typeof raw.sub === "string" ? raw.sub : "",
    name: pickString(raw.name),
    avatarUrl: pickString(raw.avatar_url),
    isAnonymous,
    raw
  };
}
__name(userFromSessionPayload, "userFromSessionPayload");
function parseUser(payload) {
  const raw = payload ?? {};
  const id = typeof raw.sub === "string" ? raw.sub : typeof raw.uid === "string" ? raw.uid : "";
  const metadata = raw.user_metadata ?? {};
  return {
    id,
    email: pickString(raw.email) ?? pickString(metadata.email),
    phone: pickString(raw.phone_number) ?? pickString(raw.phone),
    name: pickString(raw.name),
    avatarUrl: pickString(raw.avatar_url),
    // 两处都判：上游在不同端点上用过不同字段表达匿名。
    isAnonymous: raw.is_anonymous === true || raw.scope === "anonymous",
    raw
  };
}
__name(parseUser, "parseUser");
function pickString(v) {
  return typeof v === "string" && v !== "" ? v : void 0;
}
__name(pickString, "pickString");
function normalizeHttpError(status, payload) {
  const raw = payload ?? {};
  const code = typeof raw.error === "string" ? raw.error : void 0;
  const message = pickString(raw.error_description) ?? pickString(raw.message) ?? pickString(raw.msg) ?? `HTTP ${status}`;
  return {
    kind: errorKind(status, code),
    message,
    status,
    code,
    cause: payload
  };
}
__name(normalizeHttpError, "normalizeHttpError");
function errorKind(status, code) {
  if (code === "invalid_grant") {
    return "unauthenticated";
  }
  switch (status) {
    case 400:
      return "invalid-request";
    case 401:
      return "unauthenticated";
    case 403:
      return "permission-denied";
    case 404:
      return "not-found";
    case 429:
      return "rate-limited";
    case 501:
      return "unimplemented";
    case 503:
      return "backend-unavailable";
    default:
      return status >= 500 ? "backend-unavailable" : "unknown";
  }
}
__name(errorKind, "errorKind");
function normalizeNetworkError(err) {
  const message = err instanceof Error ? err.message : String(err);
  return {
    kind: "network",
    message: `request failed before a response was received: ${message}`,
    status: 0,
    cause: err
  };
}
__name(normalizeNetworkError, "normalizeNetworkError");
function sessionShapeError(reason) {
  const e = new Error(`workbuddy-cloud auth: ${reason}`);
  e.kind = "unknown";
  e.status = 0;
  return e;
}
__name(sessionShapeError, "sessionShapeError");

// src/modules/auth/session-manager.ts
var EXPIRY_MARGIN_MS = 9e4;
var REFRESH_FAILURE_COOLDOWN_MS = 6e4;
var SessionManager = class {
  static {
    __name(this, "SessionManager");
  }
  store;
  refresh;
  emit;
  isCredentialsRejected;
  now;
  /** 在途的续期。并发调用共享同一个 Promise（第 1 层保护）。 */
  inflight = null;
  /**
   * 登出计数（第 3 层保护）。
   *
   * 在任何 await **之前**同步自增，续期流程在写入前后各读一次；若期间发生过
   * 登出，就把刚拿到的新会话丢弃。否则「用户点了登出 + 一个在途续期」会让
   * 用户在登出之后被重新登入。
   */
  signOutEpoch = 0;
  /** 上次续期失败的句柄与时刻（第 4 层保护）。 */
  lastFailure = null;
  constructor(opts) {
    this.store = opts.store;
    this.refresh = opts.refresh;
    this.emit = opts.emit;
    this.isCredentialsRejected = opts.isCredentialsRejected;
    this.now = opts.now ?? Date.now;
  }
  /** 读当前会话（不触发续期）。总是从 storage 重读，见 session-store.ts。 */
  peek() {
    return this.store.read();
  }
  /**
   * 取一个**当前可用**的会话，必要时先续期。
   *
   * 这是 database / storage 请求路径上的入口，所以它必须「要么给一个能用的
   * token，要么给 null」，不能给一个即将过期的 token 让调用方去撞 401。
   */
  async ensure() {
    const current = this.store.read();
    if (!current) {
      return null;
    }
    if (!this.isExpiring(current)) {
      return current;
    }
    if (!current.refreshToken) {
      return this.abandon();
    }
    return this.refreshOnce(current);
  }
  /**
   * 强制续期一次，无论是否临近过期。
   *
   * 对外暴露给 `auth.refreshSession()` —— 应用有时需要在拿到「权限刚变更」
   * 的信号后立刻换一份新 token。
   */
  async forceRefresh() {
    const current = this.store.read();
    if (!current?.refreshToken) {
      return null;
    }
    return this.refreshOnce(current, {
      ignoreCooldown: true
    });
  }
  /** 登录成功后落盘并广播。 */
  commitSignIn(session) {
    this.lastFailure = null;
    this.store.write(session);
    this.emit("SIGNED_IN", session);
    return session;
  }
  /** 用户信息变更（如匿名升级重签了 token）后落盘并广播。 */
  commitUserUpdate(session) {
    this.store.write(session);
    this.emit("USER_UPDATED", session);
    return session;
  }
  /**
   * 清掉本地会话并广播登出。
   *
   * 同步自增 epoch 是关键（见 signOutEpoch 注释）——必须在任何 await 之前。
   */
  clear() {
    this.signOutEpoch += 1;
    this.lastFailure = null;
    this.inflight = null;
    this.store.clear();
    this.emit("SIGNED_OUT", null);
  }
  /** 是否已进入「该续期」的窗口。 */
  isExpiring(session) {
    if (typeof session.expiresAt !== "number") {
      return true;
    }
    return session.expiresAt - this.now() < EXPIRY_MARGIN_MS;
  }
  /** 单飞入口：在途则复用，否则起一次。 */
  refreshOnce(current, opts = {}) {
    if (this.inflight) {
      return this.inflight;
    }
    if (!opts.ignoreCooldown && this.inCooldown(current.refreshToken)) {
      return Promise.resolve(null);
    }
    const task = this.doRefresh(current).finally(() => {
      this.inflight = null;
    });
    this.inflight = task;
    return task;
  }
  inCooldown(refreshToken) {
    const f = this.lastFailure;
    return f !== null && f.token === refreshToken && this.now() - f.at < REFRESH_FAILURE_COOLDOWN_MS;
  }
  /** 实际续期，含 commit guard 与 epoch 复核。 */
  async doRefresh(current) {
    const epochBefore = this.signOutEpoch;
    const handleBefore = current.refreshToken;
    let next;
    try {
      next = await this.refresh(handleBefore);
    } catch (err) {
      return this.onRefreshFailed(handleBefore, err);
    }
    if (this.signOutEpoch !== epochBefore) {
      this.store.clear();
      return null;
    }
    const latest = this.store.read();
    if (latest && latest.refreshToken !== handleBefore) {
      return latest;
    }
    this.lastFailure = null;
    this.store.write(next);
    this.emit("TOKEN_REFRESHED", next);
    return next;
  }
  /**
   * 续期失败的分流。
   *
   * 「凭据被拒」与「网络/服务端故障」必须区别对待：
   *  - 凭据被拒（invalid_grant）→ 会话已不可能恢复，清掉并广播登出。留着它
   *    只会让每个后续请求都先白跑一次续期。
   *  - 其它（网络、5xx）→ **保留**会话，只记冷却。这类失败会自愈，清掉等于
   *    把一次网络抖动升级成用户被强制登出。
   */
  onRefreshFailed(handle, err) {
    if (this.isCredentialsRejected(err)) {
      return this.abandon();
    }
    this.lastFailure = {
      token: handle,
      at: this.now()
    };
    return null;
  }
  /** 会话已不可恢复：清本地并广播登出。 */
  abandon() {
    this.store.clear();
    this.lastFailure = null;
    this.emit("SIGNED_OUT", null);
    return null;
  }
};

// src/modules/auth/identifier.ts
function resolveAuthIdentifier(credentials, operation) {
  const email = credentials.email ?? "";
  const phone = credentials.phone ?? "";
  if (Boolean(email) === Boolean(phone)) {
    return {
      data: null,
      error: {
        kind: "invalid-request",
        message: `${operation} requires exactly one of email or phone`,
        status: 0
      }
    };
  }
  return {
    data: email ? {
      kind: "email",
      value: email,
      username: email
    } : {
      kind: "phone",
      value: phone,
      username: normalizePhone(phone)
    },
    error: null
  };
}
__name(resolveAuthIdentifier, "resolveAuthIdentifier");
function normalizePhone(phone) {
  const digits = phone.replace(/\D/g, "");
  let local = digits;
  if (local.startsWith("0086")) {
    local = local.slice(4);
  } else if (local.startsWith("86") && local.length === 13) {
    local = local.slice(2);
  }
  return /^1\d{10}$/.test(local) ? `+86 ${local}` : phone;
}
__name(normalizePhone, "normalizePhone");

// src/modules/auth/workbuddy-miniprogram.ts
var OFFICIAL_APP_ID = "wx907c65e5e107ddcf";
var AUTHORIZE_PATH = "subpackages/secondary/oauth-authorize/index";
var LOGIN_TTL_MS = 10 * 60 * 1e3;
var WorkBuddyMiniProgramAuth = class {
  static {
    __name(this, "WorkBuddyMiniProgramAuth");
  }
  storage;
  platform;
  exchange;
  key;
  starting;
  exchanges = /* @__PURE__ */ new Map();
  constructor(publishableKey, storage, platform, exchange) {
    this.storage = storage;
    this.platform = platform;
    this.exchange = exchange;
    this.key = `workbuddy-cloud.miniprogram-workbuddy.${publishableKey}`;
  }
  async signIn(options) {
    if (this.starting) return this.starting;
    const task = this.start(options);
    this.starting = task;
    try {
      return await task;
    } finally {
      this.starting = void 0;
    }
  }
  async start(options) {
    if (typeof options?.redirectPath !== "string" || !options.redirectPath.trim()) {
      return failure("invalid_request", "WorkBuddy login requires redirectPath");
    }
    const applicationId = this.platform.applicationId;
    if (typeof applicationId !== "string" || !applicationId.trim()) {
      return failure("invalid_request", "WorkBuddy login requires publicConfig.workBuddyOAuthClientId");
    }
    try {
      const returnEnvVersion = this.platform.getEnvVersion?.();
      const state = await this.platform.createState();
      const pending = {
        state,
        appId: OFFICIAL_APP_ID,
        expiresAt: Date.now() + LOGIN_TTL_MS
      };
      const raw = JSON.stringify(pending);
      this.storage.setItem(this.key, raw);
      if (this.storage.getItem(this.key) !== raw) {
        return failure("storage_unavailable", "Could not persist WorkBuddy login; sign in again");
      }
      const navigation = await this.platform.navigate({
        appId: OFFICIAL_APP_ID,
        path: `${AUTHORIZE_PATH}?client_id=${encodeURIComponent(applicationId)}&redirect_uri=${encodeURIComponent(options.redirectPath)}&state=${encodeURIComponent(state)}` + (returnEnvVersion ? `&envVersion=${returnEnvVersion}` : ""),
        envVersion: "release"
      });
      if (navigation.error) this.storage.removeItem(this.key);
      return navigation;
    } catch (cause) {
      return failure("miniprogram_login_failed", describe(cause));
    }
  }
  async handleCallback(options) {
    const referrer = options?.referrerInfo;
    const data = record(referrer?.extraData);
    if (!data || !data.code && !data.error) return {
      data: null,
      error: null
    };
    const inflight = typeof data.state === "string" ? this.exchanges.get(data.state) : void 0;
    if (inflight) {
      return referrer?.appId === inflight.appId ? inflight.task : failure("invalid_request", "WorkBuddy callback does not match the login source");
    }
    let pending;
    try {
      pending = this.readPending();
    } catch (cause) {
      return failure("storage_unavailable", describe(cause));
    }
    if (!pending) return {
      data: null,
      error: null
    };
    if (typeof data.state !== "string" || !data.state) {
      return failure("invalid_request", "WorkBuddy callback requires state");
    }
    if (referrer?.appId !== pending.appId || data.state !== pending.state) {
      return failure("invalid_request", "WorkBuddy callback does not match the login source or state");
    }
    if (!(typeof data.code === "string" && data.code) && !(typeof data.error === "string" && data.error)) {
      return failure("invalid_request", "WorkBuddy callback has no authorization code");
    }
    if (!data.error && (typeof data.redirect_uri !== "string" || !data.redirect_uri.trim())) {
      return failure("invalid_request", "WorkBuddy callback requires redirect_uri");
    }
    try {
      this.storage.removeItem(this.key);
      if (this.storage.getItem(this.key) !== null) {
        return failure("storage_unavailable", "Could not consume WorkBuddy login; sign in again");
      }
    } catch (cause) {
      return failure("storage_unavailable", describe(cause));
    }
    if (pending.expiresAt <= Date.now()) {
      return failure("invalid_grant", "WorkBuddy login expired; sign in again", "unauthenticated");
    }
    if (data.error) {
      return failure(String(data.error), typeof data.error_description === "string" ? data.error_description : "WorkBuddy authorization was not completed", "permission-denied");
    }
    const task = this.exchange({
      code: data.code,
      state: pending.state,
      // 保留已部署 BaaS 的字段名；签码回调地址必须原样透传。
      shortlink: data.redirect_uri
    });
    this.exchanges.set(pending.state, {
      appId: pending.appId,
      task
    });
    try {
      return await task;
    } finally {
      this.exchanges.delete(pending.state);
    }
  }
  readPending() {
    const raw = this.storage.getItem(this.key);
    if (!raw) return null;
    const parsed = record(JSON.parse(raw));
    if (!parsed || typeof parsed.state !== "string" || typeof parsed.appId !== "string" || typeof parsed.expiresAt !== "number") {
      throw new Error("Invalid saved WorkBuddy login; sign in again");
    }
    return parsed;
  }
};
function record(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value : null;
}
__name(record, "record");
function failure(code, message, kind = "invalid-request") {
  return {
    data: null,
    error: {
      kind,
      code,
      message,
      status: 0
    }
  };
}
__name(failure, "failure");
function describe(cause) {
  return cause instanceof Error ? cause.message : String(cause);
}
__name(describe, "describe");

// src/modules/auth/index.ts
var OAUTH_ERROR_MESSAGE_MAX = 200;
function truncateMessage(message, max) {
  const chars = Array.from(message);
  return chars.length <= max ? message : `${chars.slice(0, max).join("")}\u2026`;
}
__name(truncateMessage, "truncateMessage");
function oauthProviderRejectMessage(params) {
  const error = params.get("error");
  if (!error) {
    return null;
  }
  const description = params.get("error_description");
  const message = description ? `oauth provider rejected the request: ${error}: ${description}` : `oauth provider rejected the request: ${error}`;
  return truncateMessage(message, OAUTH_ERROR_MESSAGE_MAX);
}
__name(oauthProviderRejectMessage, "oauthProviderRejectMessage");
var AuthModule = class {
  static {
    __name(this, "AuthModule");
  }
  fetch;
  /** 该模块的数据面基址。 */
  baseUrl;
  sessions;
  storage;
  oauthRelayBaseUrl;
  /** WorkBuddy PKCE 证明的暂存处，按应用隔离。 */
  workBuddyPkce;
  workBuddyMiniProgram;
  /**
   * 正在进行中的 WorkBuddy 兑换，按 state 单飞。
   *
   * 只靠 `isConsumed(state)` 挡不住**并发**：两次调用会在第一次写下成功标记之前
   * 都读到「未消费」，于是第二次拿不到已被清掉的 verifier，报
   * 「no local PKCE verifier」—— 登录其实成功了，却同时弹一条错误。
   * 应用侧只要在 StrictMode 下挂两个 effect，或路由守卫与入口各调一次，就会撞上。
   */
  workBuddyExchanges = /* @__PURE__ */ new Map();
  listeners = /* @__PURE__ */ new Map();
  nextListenerId = 1;
  /**
   * @param fetch 必须是**不带 session provider** 的 fetch。
   *
   * 原因：本模块的 `/v1/token` 就是续期端点；若它走「取 token（必要时先续期）」
   * 那条出口，续期就会调用自己 —— 死锁。CloudBase 的 OAuth2Client 为同一个
   * 问题留了逃生口，注释里直接写了 "may cause deadlock during initialization"。
   * 装配见 client.ts。
   */
  constructor(config, fetch2, opts = {}) {
    this.fetch = fetch2;
    this.baseUrl = `${config.endpoint}${CLOUD_MODULE_PATHS.auth}`;
    this.oauthRelayBaseUrl = config.oauthRelayBaseUrl;
    this.storage = resolveStorage(opts.storage);
    this.workBuddyPkce = new WorkBuddyPkceStore(config.publishableKey);
    this.sessions = new SessionManager({
      store: new SessionStore(this.storage, config.publishableKey),
      refresh: /* @__PURE__ */ __name((handle) => this.exchangeRefreshHandle(handle), "refresh"),
      emit: /* @__PURE__ */ __name((event, session) => this.notify(event, session), "emit"),
      isCredentialsRejected: /* @__PURE__ */ __name((err) => isCloudError(err) && rejectedCredentials(err), "isCredentialsRejected")
    });
    if (opts.workBuddyMiniProgram) {
      this.workBuddyMiniProgram = new WorkBuddyMiniProgramAuth(config.publishableKey, this.storage, opts.workBuddyMiniProgram, (body) => this.postForSession(AUTH_PATHS.loginWorkBuddyMiniProgram, body));
    }
  }
  // ------------------------------------------------------------------
  // 供 client.ts 装配共享 fetch 用
  // ------------------------------------------------------------------
  /**
   * 取一个当前可用的 access token，必要时先续期。无会话返回 undefined。
   *
   * database / storage 的每个请求都会调它 —— 返回 undefined 表示匿名，
   * 那是合法状态不是错误（服务端按 anon 角色处理）。
   */
  async getAccessToken() {
    const session = await this.sessions.ensure();
    return session?.accessToken;
  }
  // ------------------------------------------------------------------
  // 登录
  // ------------------------------------------------------------------
  /** 在用户点击时跳转 WorkBuddy 官方小程序；成功仅表示已发起跳转。 */
  async signInWithWorkBuddyMiniProgram(options) {
    if (!this.workBuddyMiniProgram) return fail({
      kind: "unimplemented",
      status: 0,
      message: "Use createMiniProgramWorkBuddyCloud for WorkBuddy mini program login"
    });
    return this.workBuddyMiniProgram.signIn(options);
  }
  /** 由 App.onShow 传入完整启动参数；普通启动或已处理的回调返回 data: null。 */
  async handleWorkBuddyMiniProgramCallback(options) {
    if (!this.workBuddyMiniProgram) return fail({
      kind: "unimplemented",
      status: 0,
      message: "Use createMiniProgramWorkBuddyCloud for WorkBuddy mini program login"
    });
    return this.workBuddyMiniProgram.handleCallback(options);
  }
  /** 邮箱或手机号 + 密码登录。 */
  async signInWithPassword(credentials) {
    if (!credentials.password) {
      return fail(badRequest("signInWithPassword requires a password"));
    }
    const identifier = resolveAuthIdentifier(credentials, "signInWithPassword");
    if (identifier.error) {
      return fail(identifier.error);
    }
    return this.postForSession(AUTH_PATHS.signIn, {
      username: identifier.data.username,
      password: credentials.password
    });
  }
  /**
   * 小程序 wx.login 的 code 换 Genie session。
   * 试用与正式是两套独立小程序，必须带当前账号的 appid
   *（`wx.getAccountInfoSync().miniProgram.appId`）。
   * 成功后 session.user.id 为 TCB custom uid：`wx:` + 微信 openid（长度需 ≤32）。
   */
  async signInWithWechat(code, appid) {
    if (!code) {
      return fail(badRequest("signInWithWechat requires code"));
    }
    if (!appid) {
      return fail(badRequest("signInWithWechat requires appid"));
    }
    return this.postForSession(AUTH_PATHS.loginWechat, {
      code,
      appid
    });
  }
  /**
   * 注册。
   *
   * 上游要求先完成验证码验证，所以必须带一个 `verificationToken`（来自
   * `verifyOtp`）。只有用户名+密码的注册会被上游明确拒绝。
   *
   * 账号标识用 `email` 或 `phone`（二选一，与发码渠道一致）。
   */
  async signUp(credentials) {
    const identifier = resolveAuthIdentifier(credentials, "signUp");
    if (identifier.error) {
      return fail(identifier.error);
    }
    if (!credentials.verificationToken) {
      return fail(badRequest("signUp requires a verificationToken; run sendOtp + verifyOtp first (the provider rejects username+password-only signup)"));
    }
    const body = {
      verification_token: credentials.verificationToken
    };
    if (identifier.data.kind === "phone") {
      body.phone_number = identifier.data.username;
    } else {
      body.email = identifier.data.username;
    }
    if (credentials.password) body.password = credentials.password;
    return this.postForSession(AUTH_PATHS.signUp, body);
  }
  /**
   * 发验证码（邮箱或短信，由 `credentials` 传的字段决定）。
   *
   * 这一步**不产生会话**，只返回一个 `verificationId`。发码由上游完成，
   * 我方不实现发码逻辑。
   *
   * 返回的 `isExistingUser` 决定验码之后走登录还是注册 —— 该判断由上游给出，
   * SDK 不猜。
   *
   * 两条渠道的请求体差异是刻意的（runtime-auth-design §3.1）：
   * - 邮箱：`{ email, usage: 'email' }`，与上游 `VerificationUsage.EMAIL` 的值一致，区分大小写。
   * - 手机：`{ phone_number, target: 'ANY' }` —— **不带 `usage`**（普通短信登录
   *   发码时省略即可，上游没有对应的短信枚举值），`target: 'ANY'` 表示新老用户
   *   都允许发码。
   */
  async sendOtp(credentials) {
    const identifier = resolveAuthIdentifier(credentials, "sendOtp");
    if (identifier.error) {
      return fail(identifier.error);
    }
    const body = {};
    if (identifier.data.kind === "phone") {
      body.phone_number = identifier.data.username;
      body.target = "ANY";
    } else {
      body.email = identifier.data.username;
      body.usage = "email";
      if (credentials.emailRedirectTo) {
        body.email_redirect_to = credentials.emailRedirectTo;
      }
    }
    const res = await this.request(AUTH_PATHS.verification, {
      method: "POST",
      body
    });
    if (res.error) {
      return fail(res.error);
    }
    const payload = res.data ?? {};
    const verificationId = typeof payload.verification_id === "string" ? payload.verification_id : "";
    if (!verificationId) {
      return fail(badRequest("provider returned no verification_id"));
    }
    return ok({
      verificationId,
      isExistingUser: payload.is_user === true
    });
  }
  /** gotrue 风格的 OTP 入口：发码后由 challenge.verify 完成登录。 */
  async signInWithOtp(credentials) {
    const resolved = resolveAuthIdentifier(credentials, "signInWithOtp");
    if (resolved.error) {
      return fail(resolved.error);
    }
    const sent = await this.sendOtp(credentials);
    if (sent.error) {
      return fail(sent.error);
    }
    const { verificationId, isExistingUser } = sent.data;
    const identifier = resolved.data.kind === "phone" ? {
      phone: resolved.data.username
    } : {
      email: resolved.data.username
    };
    return ok({
      verificationId,
      isExistingUser,
      isUser: isExistingUser,
      verify: /* @__PURE__ */ __name(({ token, password }) => this.verifyOtp({
        verificationId,
        token,
        ...identifier,
        isExistingUser,
        password
      }), "verify")
    });
  }
  /**
   * 验码并登录（或注册后登录）。
   *
   * 两步：先用验证码换一个**一次性** `verification_token`，再用它换会话。
   * 中间那个 token 不是会话 —— 拿它当 Bearer 会被拒。
   *
   * 走登录还是注册由 `isExistingUser` 决定（`sendOtp` 的返回值）。刻意不做
   * 「先试登录失败再试注册」的兜底：那会把「密码错」这类真实错误掩盖成一次
   * 莫名的注册尝试。
   *
   * 登录侧邮箱与手机号共用 `username` 字段 —— 上游 `SignInRequest.username`
   * 承载邮箱/手机/用户名三种形态（runtime-auth-design §3.2）。
   */
  async verifyOtp(params) {
    const identifier = resolveAuthIdentifier(params, "verifyOtp");
    if (identifier.error) {
      return fail(identifier.error);
    }
    if (!params.verificationId || !params.token) {
      return fail(badRequest("verifyOtp requires verificationId and token"));
    }
    const verified = await this.request(AUTH_PATHS.verificationVerify, {
      method: "POST",
      body: {
        verification_id: params.verificationId,
        verification_code: params.token
      }
    });
    if (verified.error) {
      return fail(verified.error);
    }
    const vt = verified.data ?? {};
    const verificationToken = typeof vt.verification_token === "string" ? vt.verification_token : "";
    if (!verificationToken) {
      return fail(badRequest("provider returned no verification_token"));
    }
    if (params.isExistingUser) {
      return this.postForSession(AUTH_PATHS.signIn, {
        username: identifier.data.username,
        verification_token: verificationToken
      });
    }
    const signUpCredentials = identifier.data.kind === "phone" ? {
      phone: identifier.data.value,
      password: params.password
    } : {
      email: identifier.data.value,
      password: params.password
    };
    return this.signUp({
      ...signUpCredentials,
      verificationToken
    });
  }
  // ------------------------------------------------------------------
  // OAuth
  // ------------------------------------------------------------------
  /**
   * 发起第三方登录，返回该把用户送去的地址。
   *
   * 走 Cloud Backend Service OAuth Relay。IdP 回调白名单只登记平台统一域名。
   * SDK 不自己跳转：返回 url 交调用方 `location.assign`。
   *
   * `google` 已下线，仅存量应用；新应用用 `wechat` 做网页扫码登录，或用
   * `workbuddy` 做 WorkBuddy 账号登录。
   *
   * `workbuddy` 会在本地生成 PKCE 证明并存入当前标签页的 sessionStorage，所以
   * **必须由用户手势触发同一标签页的跳转**：另开标签页或新窗口打开返回的 url，
   * 证明留在原标签页里，回调页读不到它，兑换必然失败。
   */
  async signInWithOAuth(options) {
    if (!this.oauthRelayBaseUrl) {
      return fail(badRequest("signInWithOAuth requires oauthRelayBaseUrl"));
    }
    if (options.provider !== "google" && options.provider !== "wechat" && options.provider !== "workbuddy") {
      return fail(badRequest("\u5F53\u524D SDK \u4E0D\u652F\u6301\u8BE5\u767B\u5F55\u65B9\u5F0F\uFF0C\u8BF7\u68C0\u67E5 SDK \u7248\u672C\u4E0E\u767B\u5F55\u914D\u7F6E\u3002"));
    }
    const redirectTo = options.redirectTo ?? currentPageUrl();
    if (!redirectTo) {
      return fail(badRequest("signInWithOAuth requires redirectTo outside a browser environment"));
    }
    return this.startRelayOAuth(options, redirectTo);
  }
  /** 回调输入的 query 归一：接受完整 URL 或裸 query。 */
  parseCallbackQuery(input) {
    try {
      const query = /^https?:\/\//i.test(input) ? new URL(input).search : input;
      return ok(new URLSearchParams(query));
    } catch {
      return fail(badRequest("oauth callback URL is invalid"));
    }
  }
  /**
   * 完成第三方登录：读回调 URL 上的参数换会话。
   *
   * 在回调落地页调一次即可。`code` 缺失时返回 `null` 数据而**不是**错误 ——
   * 落地页可能被直接访问（用户收藏了它），那不是失败。
   *
   * @deprecated Google 登录已下线，新应用不应再调用该方法。
   */
  async handleOAuthCallback(search) {
    const parsed = this.parseCallbackQuery(search ?? currentPageSearch());
    if (parsed.error || !parsed.data) {
      return fail(parsed.error ?? badRequest("oauth callback URL is invalid"));
    }
    const params = parsed.data;
    const oauthError = oauthProviderRejectMessage(params);
    if (oauthError) {
      return fail({
        kind: "unauthenticated",
        message: oauthError,
        status: 0
      });
    }
    const code = params.get("code");
    if (!code) {
      return ok(null);
    }
    const state = params.get("state") ?? "";
    if (!state) {
      return fail(badRequest("oauth callback requires state"));
    }
    const providerId = params.get("provider_id");
    if (providerId !== "custom-oauth") {
      return fail(badRequest("oauth callback requires provider_id=custom-oauth"));
    }
    const body = {
      provider_id: providerId,
      provider_code: code,
      state,
      provider_params: {
        state
      }
    };
    return this.postForSession(AUTH_PATHS.signInWithProvider, body);
  }
  /**
   * 网页微信扫码回调：用 Relay 带回的 code/state 换 Genie session。
   *
   * 仅用于 **微信扫码** 落地页。Google 存量应用必须继续调用
   * `handleOAuthCallback`（custom-oauth 路径）。两者不可互换：本方法会拒绝
   * `provider != "wechat"` 的回调，报错看起来像前端传错参数。
   */
  async handleWechatWebCallback(search) {
    const parsed = this.parseCallbackQuery(search ?? currentPageSearch());
    if (parsed.error || !parsed.data) {
      return fail(parsed.error ?? badRequest("oauth callback URL is invalid"));
    }
    const params = parsed.data;
    const oauthError = oauthProviderRejectMessage(params);
    if (oauthError) {
      return fail({
        kind: "unauthenticated",
        message: oauthError,
        status: 0
      });
    }
    const code = params.get("code");
    if (!code) {
      return ok(null);
    }
    const state = params.get("state") ?? "";
    if (!state) {
      return fail(badRequest("oauth callback requires state"));
    }
    const provider = params.get("provider");
    if (provider && provider !== "wechat") {
      return fail(badRequest("wechat callback requires provider=wechat"));
    }
    if (params.get("provider_id") === "custom-oauth") {
      return fail(badRequest("wechat callback must not use provider_id=custom-oauth"));
    }
    return this.postForSession(AUTH_PATHS.loginWechatWeb, {
      code,
      state
    });
  }
  /**
   * WorkBuddy 统一登录回调：用 Relay 带回的 code/state 加本地 verifier 换
   * Genie session。
   *
   * ---------------------------------------------------------------------------
   * 在**登录守卫之前**无条件调用一次
   * ---------------------------------------------------------------------------
   *
   * 回调落地的那一刻还没有会话，守卫先跑就会把用户弹回登录页、顺手把 URL 上的
   * code/state 丢掉，表现是「点了登录转一圈又回到登录页」。
   *
   * 返回 `{ data: null, error: null }` 表示**这不是一次 WorkBuddy 回调**（普通
   * 页面访问、用户收藏了落地页），不是失败：照常渲染未登录状态即可。
   *
   * 失败一律不建会话：用户在授权页点了拒绝、本地证明缺失（换了标签页、清了
   * sessionStorage）、回调参数不合法，都只返回 error。
   *
   * 兑换成功后 URL 上的 `code` / `state` / `provider` 应由调用方清掉
   * （`history.replaceState`），业务参数如 `sharecode` 要保留。清理前后重复调用
   * 本方法都不会再次兑换：并发的那次合流到同一个 promise、拿到同一个结果，
   * 串行的那次按「成功已记下」返回空。
   */
  async handleWorkBuddyCallback(search) {
    const parsed = this.parseCallbackQuery(search ?? currentPageSearch());
    if (parsed.error || !parsed.data) {
      return fail(parsed.error ?? badRequest("oauth callback URL is invalid"));
    }
    const params = parsed.data;
    const provider = params.get("provider");
    if (provider && provider !== "workbuddy") {
      return ok(null);
    }
    const oauthError = oauthProviderRejectMessage(params);
    if (oauthError) {
      this.workBuddyPkce.clearVerifier();
      return fail({
        kind: "unauthenticated",
        message: oauthError,
        status: 0
      });
    }
    const code = params.get("code");
    if (!code) {
      return ok(null);
    }
    const state = params.get("state") ?? "";
    if (!state) {
      return fail(badRequest("workbuddy callback requires state"));
    }
    if (params.get("provider_id") === "custom-oauth") {
      return fail(badRequest("workbuddy callback must not use provider_id=custom-oauth"));
    }
    if (this.workBuddyPkce.isConsumed(state)) {
      return ok(null);
    }
    const inflight = this.workBuddyExchanges.get(state);
    if (inflight) {
      return inflight;
    }
    const verifier = this.workBuddyPkce.readVerifier();
    if (!verifier) {
      return fail(badRequest("workbuddy callback has no local PKCE verifier; sign in again in this tab"));
    }
    this.workBuddyPkce.clearVerifier();
    const task = this.exchangeWorkBuddyCode(code, state, verifier);
    this.workBuddyExchanges.set(state, task);
    try {
      return await task;
    } finally {
      this.workBuddyExchanges.delete(state);
    }
  }
  /** 真正那一次兑换，单飞逻辑在 {@link handleWorkBuddyCallback}。 */
  async exchangeWorkBuddyCode(code, state, verifier) {
    const result = await this.postForSession(AUTH_PATHS.loginWorkBuddy, {
      code,
      state,
      code_verifier: verifier
    });
    if (result.data) {
      this.workBuddyPkce.markConsumed(state);
    }
    return result;
  }
  /** 忘记密码：发码，验证码通过后更新密码并自动登录。 */
  async resetPasswordForEmail(email) {
    if (!email) {
      return fail(badRequest("resetPasswordForEmail requires email"));
    }
    const sent = await this.request(AUTH_PATHS.verification, {
      method: "POST",
      body: {
        email,
        usage: "PASSWORD_RESET",
        target: "USER"
      }
    });
    if (sent.error) {
      return fail(sent.error);
    }
    const payload = sent.data ?? {};
    const verificationId = typeof payload.verification_id === "string" ? payload.verification_id : "";
    if (!verificationId) {
      return fail(badRequest("provider returned no verification_id"));
    }
    return ok({
      updateUser: /* @__PURE__ */ __name(async ({ nonce, password }) => {
        const verified = await this.request(AUTH_PATHS.verificationVerify, {
          method: "POST",
          body: {
            verification_id: verificationId,
            verification_code: nonce
          }
        });
        if (verified.error) {
          return fail(verified.error);
        }
        const verifiedPayload = verified.data ?? {};
        const verificationToken = typeof verifiedPayload.verification_token === "string" ? verifiedPayload.verification_token : "";
        if (!verificationToken) {
          return fail(badRequest("provider returned no verification_token"));
        }
        const reset = await this.request(AUTH_PATHS.resetPassword, {
          method: "POST",
          body: {
            email,
            new_password: password,
            verification_token: verificationToken
          }
        });
        if (reset.error) {
          return fail(reset.error);
        }
        const signedIn = await this.signInWithPassword({
          email,
          password
        });
        if (!signedIn.error) {
          this.notify("PASSWORD_RECOVERY", signedIn.data);
        }
        return signedIn;
      }, "updateUser")
    });
  }
  /** 登录后使用旧密码进行 sudo 校验并更新密码。 */
  async resetPasswordForOld(credentials) {
    const token = await this.getAccessToken();
    if (!token) {
      return fail({
        kind: "unauthenticated",
        message: "no active session",
        status: 0
      });
    }
    const sudo = await this.request(AUTH_PATHS.sudo, {
      method: "POST",
      token,
      body: {
        password: credentials.oldPassword
      }
    });
    if (sudo.error) {
      return fail(sudo.error);
    }
    const payload = sudo.data ?? {};
    const sudoToken = typeof payload.sudo_token === "string" ? payload.sudo_token : "";
    if (!sudoToken) {
      return fail(badRequest("provider returned no sudo_token"));
    }
    const updated = await this.request(AUTH_PATHS.userPassword, {
      method: "PATCH",
      token,
      body: {
        sudo_token: sudoToken,
        new_password: credentials.newPassword
      }
    });
    if (updated.error) {
      return fail(updated.error);
    }
    const session = await this.getSession();
    if (session.data) {
      this.notify("USER_UPDATED", session.data);
      return ok(session.data);
    }
    return fail(session.error ?? {
      kind: "unauthenticated",
      message: "no active session",
      status: 0
    });
  }
  // ------------------------------------------------------------------
  // 会话
  // ------------------------------------------------------------------
  /**
   * 读当前会话。
   *
   * 会在临近过期时**顺手续期** —— 只读本地不续期的话，调用方拿到一个还剩
   * 3 秒有效期的 token 去发请求，到服务端就已经过期了。
   */
  async getSession() {
    try {
      return ok(await this.sessions.ensure());
    } catch (err) {
      return fail(isCloudError(err) ? err : normalizeNetworkError(err));
    }
  }
  /** 强制续期一次，不管是否临近过期。 */
  async refreshSession() {
    try {
      return ok(await this.sessions.forceRefresh());
    } catch (err) {
      return fail(isCloudError(err) ? err : normalizeNetworkError(err));
    }
  }
  /**
   * 读当前用户。
   *
   * 会发请求（`/v1/user/me`）而不是读本地 session —— 后者的 user 字段来自
   * 登录那一刻，可能已过时（别处改了昵称、或匿名已升级为实名）。
   */
  async getUser() {
    const token = await this.getAccessToken();
    if (!token) {
      return fail({
        kind: "unauthenticated",
        message: "no active session",
        status: 0
      });
    }
    const res = await this.request(AUTH_PATHS.userMe, {
      method: "GET",
      token
    });
    if (res.error) {
      if (rejectedCredentials(res.error)) {
        this.sessions.clear();
      }
      return fail(res.error);
    }
    return ok(parseUser(res.data));
  }
  /**
   * 登出。
   *
   * 无论服务端返回什么都清本地：服务端侧是**无条件销毁**的（转发上游之后就
   * 销毁，不看上游成败），本地留着只会让界面显示一个已经不能用的登录态。
   * 断网时也必须能登出。
   */
  async signOut() {
    const session = this.sessions.peek();
    if (session?.accessToken) {
      await this.request(AUTH_PATHS.signOut, {
        method: "POST",
        body: {},
        token: session.accessToken
      });
    }
    this.sessions.clear();
    return ok(null);
  }
  /**
   * 订阅登录态变化。返回取消订阅函数。
   *
   * 订阅时会**立即**回放一次 `INITIAL_SESSION`：没有它，调用方无法区分
   * 「还没初始化完」与「初始化完了但未登录」，首屏会闪一下登录页。
   */
  onAuthStateChange(callback) {
    const id = this.nextListenerId++;
    this.listeners.set(id, callback);
    safeInvoke(callback, "INITIAL_SESSION", this.sessions.peek());
    return () => void this.listeners.delete(id);
  }
  // ------------------------------------------------------------------
  // 内部
  // ------------------------------------------------------------------
  /**
   * 拼出平台 Relay 授权地址；state 由 Relay 自己签发、校验并一次性消费。
   */
  async startRelayOAuth(options, redirectTo) {
    let callback;
    try {
      callback = new URL(redirectTo);
    } catch {
      return fail(badRequest("signInWithOAuth requires an absolute redirectTo URL"));
    }
    const relay = new URL(`${this.oauthRelayBaseUrl}/authorize`);
    relay.searchParams.set("provider", options.provider);
    relay.searchParams.set("callback_url", callback.toString());
    if (options.provider === "workbuddy") {
      const proof = await this.createWorkBuddyProof();
      if (proof.error || !proof.data) {
        return fail(proof.error ?? badRequest("signInWithOAuth could not create PKCE"));
      }
      relay.searchParams.set("code_challenge", proof.data);
      relay.searchParams.set("code_challenge_method", "S256");
    }
    return ok({
      url: relay.toString()
    });
  }
  /**
   * 生成并暂存 WorkBuddy 的 PKCE 证明，返回要发给 Relay 的 challenge。
   *
   * 先存 verifier 再返回 challenge：顺序反了的话，调用方可能在 verifier 落盘前
   * 就跳走，回调页读到空值。
   */
  async createWorkBuddyProof() {
    if (!hasWebCrypto()) {
      return fail(badRequest("workbuddy sign-in requires WebCrypto; it is unavailable in this runtime (an insecure http:// origin disables it \u2014 serve the app over https)"));
    }
    if (!this.workBuddyPkce.usable()) {
      return fail(badRequest("workbuddy sign-in requires sessionStorage to keep the PKCE verifier across the redirect; it is unavailable in this runtime"));
    }
    let verifier;
    let challenge;
    try {
      verifier = createCodeVerifier();
      challenge = await computeS256Challenge(verifier);
    } catch (err) {
      return fail(badRequest(`workbuddy sign-in could not create a PKCE proof: ${describeError(err)}`));
    }
    if (!this.workBuddyPkce.saveVerifier(verifier)) {
      return fail(badRequest("workbuddy sign-in could not persist the PKCE verifier"));
    }
    return ok(challenge);
  }
  /** 用我方句柄换新会话。这是 SessionManager 注入的续期执行体。 */
  async exchangeRefreshHandle(handle) {
    const res = await this.request(AUTH_PATHS.token, {
      method: "POST",
      body: {
        grant_type: "refresh_token",
        refresh_token: handle
      }
    });
    if (res.error) {
      throw res.error;
    }
    return parseSession(res.data, Date.now());
  }
  /** POST 一个换签端点并把响应解析成会话。 */
  async postForSession(path, body, opts = {}) {
    const res = await this.request(path, {
      method: "POST",
      body,
      headers: opts.headers
    });
    if (res.error) {
      return fail(res.error);
    }
    try {
      return ok(this.sessions.commitSignIn(parseSession(res.data, Date.now())));
    } catch (err) {
      return fail(isCloudError(err) ? err : normalizeNetworkError(err));
    }
  }
  /** 发一次 auth 请求并归一错误。 */
  async request(path, init) {
    const headers = {
      ...init.headers
    };
    if (init.body !== void 0) {
      headers["Content-Type"] = "application/json";
    }
    if (init.token) {
      headers.Authorization = `Bearer ${init.token}`;
    }
    let response;
    try {
      response = await this.fetch(this.baseUrl + path, {
        method: init.method,
        headers,
        body: init.body === void 0 ? void 0 : JSON.stringify(init.body)
      });
    } catch (err) {
      return fail(normalizeNetworkError(err));
    }
    const payload = await readBody(response);
    if (!response.ok) {
      return fail(normalizeHttpError(response.status, payload));
    }
    return ok(payload);
  }
  /** 广播事件。单个监听器抛错不能影响其它监听器与主流程。 */
  notify(event, session) {
    for (const cb of this.listeners.values()) {
      safeInvoke(cb, event, session);
    }
  }
};
function ok(data) {
  return {
    data,
    error: null
  };
}
__name(ok, "ok");
function fail(error) {
  return {
    data: null,
    error
  };
}
__name(fail, "fail");
function badRequest(message) {
  return {
    kind: "invalid-request",
    message,
    status: 0
  };
}
__name(badRequest, "badRequest");
function describeError(err) {
  return truncateMessage(err instanceof Error ? err.message : String(err), OAUTH_ERROR_MESSAGE_MAX);
}
__name(describeError, "describeError");
function isCloudError(v) {
  return !!v && typeof v === "object" && typeof v.kind === "string";
}
__name(isCloudError, "isCloudError");
function rejectedCredentials(error) {
  return error.kind === "unauthenticated" || error.code === "invalid_grant";
}
__name(rejectedCredentials, "rejectedCredentials");
async function readBody(response) {
  const text = await response.text();
  if (!text) {
    return null;
  }
  try {
    return JSON.parse(text);
  } catch {
    return {
      message: text
    };
  }
}
__name(readBody, "readBody");
function safeInvoke(cb, event, session) {
  try {
    cb(event, session);
  } catch {
  }
}
__name(safeInvoke, "safeInvoke");
function currentPageUrl() {
  const loc = globalThis.location;
  return loc ? loc.origin + loc.pathname : "";
}
__name(currentPageUrl, "currentPageUrl");
function currentPageSearch() {
  return globalThis.location?.search ?? "";
}
__name(currentPageSearch, "currentPageSearch");

// src/vendor/postgrest/types/common/common.ts
var DEFAULT_MAX_RETRIES = 3;
var getRetryDelay = /* @__PURE__ */ __name((attemptIndex) => Math.min(1e3 * 2 ** attemptIndex, 3e4), "getRetryDelay");
var RETRYABLE_STATUS_CODES = [
  520,
  503
];
var RETRYABLE_METHODS = [
  "GET",
  "HEAD",
  "OPTIONS"
];

// src/vendor/postgrest/PostgrestError.ts
var PostgrestError = class extends Error {
  static {
    __name(this, "PostgrestError");
  }
  details;
  hint;
  code;
  /**
  * @example
  * ```ts
  * import PostgrestError from '@supabase/postgrest-js'
  *
  * throw new PostgrestError({
  *   message: 'Row level security prevented the request',
  *   details: 'RLS denied the insert',
  *   hint: 'Check your policies',
  *   code: 'PGRST301',
  * })
  * ```
  */
  constructor(context) {
    super(context.message);
    this.name = "PostgrestError";
    this.details = context.details;
    this.hint = context.hint;
    this.code = context.code;
  }
  toJSON() {
    return {
      name: this.name,
      message: this.message,
      details: this.details,
      hint: this.hint,
      code: this.code
    };
  }
};

// src/vendor/postgrest/PostgrestBuilder.ts
function sleep(ms, signal) {
  return new Promise((resolve) => {
    if (signal?.aborted) {
      resolve();
      return;
    }
    const id = setTimeout(() => {
      signal?.removeEventListener("abort", onAbort);
      resolve();
    }, ms);
    function onAbort() {
      clearTimeout(id);
      resolve();
    }
    __name(onAbort, "onAbort");
    signal?.addEventListener("abort", onAbort);
  });
}
__name(sleep, "sleep");
function shouldRetry(method, status, attemptCount, retryEnabled) {
  if (!retryEnabled || attemptCount >= DEFAULT_MAX_RETRIES) {
    return false;
  }
  if (!RETRYABLE_METHODS.includes(method)) {
    return false;
  }
  if (!RETRYABLE_STATUS_CODES.includes(status)) {
    return false;
  }
  return true;
}
__name(shouldRetry, "shouldRetry");
var PostgrestBuilder = class {
  static {
    __name(this, "PostgrestBuilder");
  }
  method;
  url;
  headers;
  schema;
  body;
  shouldThrowOnError = false;
  signal;
  fetch;
  isMaybeSingle;
  shouldStripNulls;
  urlLengthLimit;
  // Retry configuration - enabled by default
  retryEnabled = true;
  /**
  * Creates a builder configured for a specific PostgREST request.
  *
  * @example Using supabase-js (recommended)
  * ```ts
  * import { createClient } from '@supabase/supabase-js'
  *
  * const supabase = createClient('https://xyzcompany.supabase.co', 'your-publishable-key')
  * const { data, error } = await supabase.from('users').select('*')
  * ```
  *
  * @category Database
  *
  * @example Standalone import for bundle-sensitive environments
  * ```ts
  * import { PostgrestQueryBuilder } from '@supabase/postgrest-js'
  *
  * const builder = new PostgrestQueryBuilder(
  *   new URL('https://xyzcompany.supabase.co/rest/v1/users'),
  *   { headers: new Headers({ apikey: 'your-publishable-key' }) }
  * )
  * ```
  */
  constructor(builder) {
    this.method = builder.method;
    this.url = builder.url;
    this.headers = new Headers(builder.headers);
    this.schema = builder.schema;
    this.body = builder.body;
    this.shouldThrowOnError = builder.shouldThrowOnError ?? false;
    this.signal = builder.signal;
    this.isMaybeSingle = builder.isMaybeSingle ?? false;
    this.shouldStripNulls = builder.shouldStripNulls ?? false;
    this.urlLengthLimit = builder.urlLengthLimit ?? 8e3;
    this.retryEnabled = builder.retry ?? true;
    if (builder.fetch) {
      this.fetch = builder.fetch;
    } else {
      this.fetch = fetch;
    }
  }
  /**
  * If there's an error with the query, throwOnError will reject the promise by
  * throwing the error instead of returning it as part of a successful response.
  *
  * {@link https://github.com/supabase/supabase-js/issues/92}
  *
  * @category Database
  * @subcategory Using modifiers
  */
  throwOnError() {
    this.shouldThrowOnError = true;
    return this;
  }
  /**
  * Strip null values from the response data. Properties with `null` values
  * will be omitted from the returned JSON objects.
  *
  * Requires PostgREST 11.2.0+.
  *
  * {@link https://docs.postgrest.org/en/stable/references/api/resource_representation.html#stripped-nulls}
  *
  * @category Database
  * @subcategory Using modifiers
  *
  * @example With `select()`
  * ```ts
  * const { data, error } = await supabase
  *   .from('characters')
  *   .select()
  *   .stripNulls()
  * ```
  *
  * @exampleSql With `select()`
  * ```sql
  * create table
  *   characters (id int8 primary key, name text, bio text);
  *
  * insert into
  *   characters (id, name, bio)
  * values
  *   (1, 'Luke', null),
  *   (2, 'Leia', 'Princess of Alderaan');
  * ```
  *
  * @exampleResponse With `select()`
  * ```json
  * {
  *   "data": [
  *     {
  *       "id": 1,
  *       "name": "Luke"
  *     },
  *     {
  *       "id": 2,
  *       "name": "Leia",
  *       "bio": "Princess of Alderaan"
  *     }
  *   ],
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  */
  stripNulls() {
    if (this.headers.get("Accept") === "text/csv") {
      throw new Error("stripNulls() cannot be used with csv()");
    }
    this.shouldStripNulls = true;
    return this;
  }
  /**
  * Set an HTTP header on this single PostgREST request, overriding any header
  * with the same name set on the client.
  *
  * This is an advanced escape hatch for one-off needs (passing a custom
  * `Authorization` for a single query, attaching a tracing header, etc.).
  * Most callers do not need it: configure client-wide headers via the
  * `headers` option when constructing the client, and authentication via
  * Supabase Auth.
  *
  * @param name - HTTP header name
  * @param value - HTTP header value
  *
  * @category Database
  * @subcategory Using modifiers
  */
  setHeader(name, value) {
    this.headers = new Headers(this.headers);
    this.headers.set(name, value);
    return this;
  }
  /**
  * @category Database
  * @subcategory Using modifiers
  *
  * Configure retry behavior for this request.
  *
  * By default, retries are enabled for idempotent requests (GET, HEAD, OPTIONS)
  * that fail with network errors or specific HTTP status codes (503, 520).
  * Retries use exponential backoff (1s, 2s, 4s) with a maximum of 3 attempts.
  *
  * @param enabled - Whether to enable retries for this request
  *
  * @example
  * ```ts
  * // Disable retries for a specific query
  * const { data, error } = await supabase
  *   .from('users')
  *   .select()
  *   .retry(false)
  * ```
  */
  retry(enabled) {
    this.retryEnabled = enabled;
    return this;
  }
  then(onfulfilled, onrejected) {
    if (this.schema === void 0) {
    } else if ([
      "GET",
      "HEAD"
    ].includes(this.method)) {
      this.headers.set("Accept-Profile", this.schema);
    } else {
      this.headers.set("Content-Profile", this.schema);
    }
    if (this.method !== "GET" && this.method !== "HEAD") {
      this.headers.set("Content-Type", "application/json");
    }
    if (this.shouldStripNulls) {
      const currentAccept = this.headers.get("Accept");
      if (currentAccept === "application/vnd.pgrst.object+json") {
        this.headers.set("Accept", "application/vnd.pgrst.object+json;nulls=stripped");
      } else if (!currentAccept || currentAccept === "application/json") {
        this.headers.set("Accept", "application/vnd.pgrst.array+json;nulls=stripped");
      }
    }
    const _fetch = this.fetch;
    const executeWithRetry = /* @__PURE__ */ __name(async () => {
      let attemptCount = 0;
      while (true) {
        const headers = {};
        this.headers.forEach((value, key) => {
          headers[key] = value;
        });
        if (attemptCount > 0) {
          headers["X-Retry-Count"] = String(attemptCount);
        }
        let res2;
        try {
          res2 = await _fetch(this.url.toString(), {
            method: this.method,
            headers,
            body: JSON.stringify(this.body, (_, value) => typeof value === "bigint" ? value.toString() : value),
            signal: this.signal
          });
        } catch (fetchError) {
          if (fetchError?.name === "AbortError" || fetchError?.code === "ABORT_ERR") {
            throw fetchError;
          }
          if (!RETRYABLE_METHODS.includes(this.method)) {
            throw fetchError;
          }
          if (this.retryEnabled && attemptCount < DEFAULT_MAX_RETRIES) {
            const delay = getRetryDelay(attemptCount);
            attemptCount++;
            await sleep(delay, this.signal);
            continue;
          }
          throw fetchError;
        }
        if (shouldRetry(this.method, res2.status, attemptCount, this.retryEnabled)) {
          const retryAfterHeader = res2.headers?.get("Retry-After") ?? null;
          const delay = retryAfterHeader !== null ? Math.max(0, parseInt(retryAfterHeader, 10) || 0) * 1e3 : getRetryDelay(attemptCount);
          await res2.text();
          attemptCount++;
          await sleep(delay, this.signal);
          continue;
        }
        return await this.processResponse(res2);
      }
    }, "executeWithRetry");
    let res = executeWithRetry();
    if (!this.shouldThrowOnError) {
      res = res.catch((fetchError) => {
        let errorDetails = "";
        let hint = "";
        let code = "";
        const cause = fetchError?.cause;
        if (cause) {
          const causeMessage = cause?.message ?? "";
          const causeCode = cause?.code ?? "";
          errorDetails = `${fetchError?.name ?? "FetchError"}: ${fetchError?.message}`;
          errorDetails += `

Caused by: ${cause?.name ?? "Error"}: ${causeMessage}`;
          if (causeCode) {
            errorDetails += ` (${causeCode})`;
          }
          if (cause?.stack) {
            errorDetails += `
${cause.stack}`;
          }
        } else {
          errorDetails = fetchError?.stack ?? "";
        }
        const urlLength = this.url.toString().length;
        if (fetchError?.name === "AbortError" || fetchError?.code === "ABORT_ERR") {
          code = "";
          hint = "Request was aborted (timeout or manual cancellation)";
          if (urlLength > this.urlLengthLimit) {
            hint += `. Note: Your request URL is ${urlLength} characters, which may exceed server limits. If selecting many fields, consider using views. If filtering with large arrays (e.g., .in('id', [many IDs])), consider using an RPC function to pass values server-side.`;
          }
        } else if (cause?.name === "HeadersOverflowError" || cause?.code === "UND_ERR_HEADERS_OVERFLOW") {
          code = "";
          hint = "HTTP headers exceeded server limits (typically 16KB)";
          if (urlLength > this.urlLengthLimit) {
            hint += `. Your request URL is ${urlLength} characters. If selecting many fields, consider using views. If filtering with large arrays (e.g., .in('id', [200+ IDs])), consider using an RPC function instead.`;
          }
        }
        return {
          success: false,
          error: {
            message: `${fetchError?.name ?? "FetchError"}: ${fetchError?.message}`,
            details: errorDetails,
            hint,
            code
          },
          data: null,
          count: null,
          status: 0,
          statusText: ""
        };
      });
    }
    return res.then(onfulfilled, onrejected);
  }
  /**
  * Process a fetch response and return the standardized postgrest response.
  */
  async processResponse(res) {
    let error = null;
    let data = null;
    let count = null;
    let status = res.status;
    let statusText = res.statusText;
    if (res.ok) {
      if (this.method !== "HEAD") {
        const body = await res.text();
        if (body === "") {
        } else if (this.headers.get("Accept") === "text/csv") {
          data = body;
        } else if (this.headers.get("Accept") && this.headers.get("Accept")?.includes("application/vnd.pgrst.plan+text")) {
          data = body;
        } else {
          try {
            data = JSON.parse(body);
          } catch {
            error = {
              message: body
            };
            data = null;
            if (this.shouldThrowOnError) {
              throw new PostgrestError({
                message: body,
                details: "",
                hint: "",
                code: ""
              });
            }
          }
        }
      }
      const countHeader = this.headers.get("Prefer")?.match(/count=(exact|planned|estimated)/);
      const contentRange = res.headers.get("content-range")?.split("/");
      if (countHeader && contentRange && contentRange.length > 1) {
        count = parseInt(contentRange[1]);
      }
      if (this.isMaybeSingle && Array.isArray(data)) {
        if (data.length > 1) {
          error = {
            // https://github.com/PostgREST/postgrest/blob/a867d79c42419af16c18c3fb019eba8df992626f/src/PostgREST/Error.hs#L553
            code: "PGRST116",
            details: `Results contain ${data.length} rows, application/vnd.pgrst.object+json requires 1 row`,
            hint: null,
            message: "JSON object requested, multiple (or no) rows returned"
          };
          data = null;
          count = null;
          status = 406;
          statusText = "Not Acceptable";
          if (this.shouldThrowOnError) {
            throw new PostgrestError({
              ...error,
              hint: error.hint ?? ""
            });
          }
        } else if (data.length === 1) {
          data = data[0];
        } else {
          data = null;
        }
      }
    } else {
      const body = await res.text();
      try {
        error = JSON.parse(body);
        if (Array.isArray(error) && res.status === 404) {
          data = [];
          error = null;
          status = 200;
          statusText = "OK";
        }
      } catch {
        if (res.status === 404 && body === "") {
          status = 204;
          statusText = "No Content";
        } else {
          error = {
            message: body
          };
        }
      }
      if (error && this.shouldThrowOnError) {
        throw new PostgrestError(error);
      }
    }
    return {
      success: error === null,
      error,
      data,
      count,
      status,
      statusText
    };
  }
  /**
  * Override the type of the returned `data`.
  *
  * @typeParam NewResult - The new result type to override with
  * @deprecated Use overrideTypes<yourType, { merge: false }>() method at the end of your call chain instead
  *
  * @category Database
  * @subcategory Using modifiers
  */
  returns() {
    return this;
  }
  /**
  * Override the type of the returned `data` field in the response.
  *
  * @typeParam NewResult - The new type to cast the response data to
  * @typeParam Options - Optional type configuration (defaults to { merge: true })
  * @typeParam Options.merge - When true, merges the new type with existing return type. When false, replaces the existing types entirely (defaults to true)
  * @example
  * ```typescript
  * // Merge with existing types (default behavior)
  * const query = supabase
  *   .from('users')
  *   .select()
  *   .overrideTypes<{ custom_field: string }>()
  *
  * // Replace existing types completely
  * const replaceQuery = supabase
  *   .from('users')
  *   .select()
  *   .overrideTypes<{ id: number; name: string }, { merge: false }>()
  * ```
  * @returns A PostgrestBuilder instance with the new type
  *
  * @category Database
  * @subcategory Using modifiers
  *
  * @example Complete Override type of successful response
  * ```ts
  * const { data } = await supabase
  *   .from('countries')
  *   .select()
  *   .overrideTypes<Array<MyType>, { merge: false }>()
  * ```
  *
  * @exampleResponse Complete Override type of successful response
  * ```ts
  * let x: typeof data // MyType[]
  * ```
  *
  * @example Complete Override type of object response
  * ```ts
  * const { data } = await supabase
  *   .from('countries')
  *   .select()
  *   .maybeSingle()
  *   .overrideTypes<MyType, { merge: false }>()
  * ```
  *
  * @exampleResponse Complete Override type of object response
  * ```ts
  * let x: typeof data // MyType | null
  * ```
  *
  * @example Partial Override type of successful response
  * ```ts
  * const { data } = await supabase
  *   .from('countries')
  *   .select()
  *   .overrideTypes<Array<{ status: "A" | "B" }>>()
  * ```
  *
  * @exampleResponse Partial Override type of successful response
  * ```ts
  * let x: typeof data // Array<CountryRowProperties & { status: "A" | "B" }>
  * ```
  *
  * @example Partial Override type of object response
  * ```ts
  * const { data } = await supabase
  *   .from('countries')
  *   .select()
  *   .maybeSingle()
  *   .overrideTypes<{ status: "A" | "B" }>()
  * ```
  *
  * @exampleResponse Partial Override type of object response
  * ```ts
  * let x: typeof data // CountryRowProperties & { status: "A" | "B" } | null
  * ```
  *
  * @example Merge vs replace existing types
  * ```typescript
  * // Merge with existing types (default behavior)
  * const query = supabase
  *   .from('users')
  *   .select()
  *   .overrideTypes<{ custom_field: string }>()
  *
  * // Replace existing types completely
  * const replaceQuery = supabase
  *   .from('users')
  *   .select()
  *   .overrideTypes<{ id: number; name: string }, { merge: false }>()
  * ```
  */
  overrideTypes() {
    return this;
  }
};

// src/vendor/postgrest/PostgrestTransformBuilder.ts
var PostgrestTransformBuilder = class extends PostgrestBuilder {
  static {
    __name(this, "PostgrestTransformBuilder");
  }
  throwOnError() {
    return super.throwOnError();
  }
  /**
  * Perform a SELECT on the query result.
  *
  * By default, `.insert()`, `.update()`, `.upsert()`, and `.delete()` do not
  * return modified rows. By calling this method, modified rows are returned in
  * `data`.
  *
  * @param columns - The columns to retrieve, separated by commas
  *
  * @category Database
  * @subcategory Using modifiers
  *
  * @example With `upsert()`
  * ```ts
  * const { data, error } = await supabase
  *   .from('characters')
  *   .upsert({ id: 1, name: 'Han Solo' })
  *   .select()
  * ```
  *
  * @exampleSql With `upsert()`
  * ```sql
  * create table
  *   characters (id int8 primary key, name text);
  *
  * insert into
  *   characters (id, name)
  * values
  *   (1, 'Han');
  * ```
  *
  * @exampleResponse With `upsert()`
  * ```json
  * {
  *   "data": [
  *     {
  *       "id": 1,
  *       "name": "Han Solo"
  *     }
  *   ],
  *   "status": 201,
  *   "statusText": ""
  * }
  * ```
  */
  select(columns) {
    let quoted = false;
    const cleanedColumns = (columns ?? "*").split("").map((c) => {
      if (/\s/.test(c) && !quoted) {
        return "";
      }
      if (c === '"') {
        quoted = !quoted;
      }
      return c;
    }).join("");
    this.url.searchParams.set("select", cleanedColumns);
    this.headers.append("Prefer", "return=representation");
    return this;
  }
  /**
  * Order the query result by `column`.
  *
  * You can call this method multiple times to order by multiple columns.
  *
  * You can order referenced tables, but it only affects the ordering of the
  * parent table if you use `!inner` in the query.
  *
  * @param column - The column to order by
  * @param options - Named parameters
  * @param options.ascending - If `true`, the result will be in ascending order
  * @param options.nullsFirst - If `true`, `null`s appear first. If `false`,
  * `null`s appear last.
  * @param options.referencedTable - Set this to order a referenced table by
  * its columns
  * @param options.foreignTable - Deprecated, use `options.referencedTable`
  * instead
  *
  * @category Database
  * @subcategory Using modifiers
  *
  * @example With `select()`
  * ```ts
  * const { data, error } = await supabase
  *   .from('characters')
  *   .select('id, name')
  *   .order('id', { ascending: false })
  * ```
  *
  * @exampleSql With `select()`
  * ```sql
  * create table
  *   characters (id int8 primary key, name text);
  *
  * insert into
  *   characters (id, name)
  * values
  *   (1, 'Luke'),
  *   (2, 'Leia'),
  *   (3, 'Han');
  * ```
  *
  * @exampleResponse With `select()`
  * ```json
  * {
  *   "data": [
  *     {
  *       "id": 3,
  *       "name": "Han"
  *     },
  *     {
  *       "id": 2,
  *       "name": "Leia"
  *     },
  *     {
  *       "id": 1,
  *       "name": "Luke"
  *     }
  *   ],
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  *
  * @exampleDescription On a referenced table
  * Ordering with `referencedTable` doesn't affect the ordering of the
  * parent table.
  *
  * @example On a referenced table
  * ```ts
  *   const { data, error } = await supabase
  *     .from('orchestral_sections')
  *     .select(`
  *       name,
  *       instruments (
  *         name
  *       )
  *     `)
  *     .order('name', { referencedTable: 'instruments', ascending: false })
  *
  * ```
  *
  * @exampleSql On a referenced table
  * ```sql
  * create table
  *   orchestral_sections (id int8 primary key, name text);
  * create table
  *   instruments (
  *     id int8 primary key,
  *     section_id int8 not null references orchestral_sections,
  *     name text
  *   );
  *
  * insert into
  *   orchestral_sections (id, name)
  * values
  *   (1, 'strings'),
  *   (2, 'woodwinds');
  * insert into
  *   instruments (id, section_id, name)
  * values
  *   (1, 1, 'harp'),
  *   (2, 1, 'violin');
  * ```
  *
  * @exampleResponse On a referenced table
  * ```json
  * {
  *   "data": [
  *     {
  *       "name": "strings",
  *       "instruments": [
  *         {
  *           "name": "violin"
  *         },
  *         {
  *           "name": "harp"
  *         }
  *       ]
  *     },
  *     {
  *       "name": "woodwinds",
  *       "instruments": []
  *     }
  *   ],
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  *
  * @exampleDescription Order parent table by a referenced table
  * Ordering with `referenced_table(col)` affects the ordering of the
  * parent table.
  *
  * @example Order parent table by a referenced table
  * ```ts
  *   const { data, error } = await supabase
  *     .from('instruments')
  *     .select(`
  *       name,
  *       section:orchestral_sections (
  *         name
  *       )
  *     `)
  *     .order('section(name)', { ascending: true })
  *
  * ```
  *
  * @exampleSql Order parent table by a referenced table
  * ```sql
  * create table
  *   orchestral_sections (id int8 primary key, name text);
  * create table
  *   instruments (
  *     id int8 primary key,
  *     section_id int8 not null references orchestral_sections,
  *     name text
  *   );
  *
  * insert into
  *   orchestral_sections (id, name)
  * values
  *   (1, 'strings'),
  *   (2, 'woodwinds');
  * insert into
  *   instruments (id, section_id, name)
  * values
  *   (1, 2, 'flute'),
  *   (2, 1, 'violin');
  * ```
  *
  * @exampleResponse Order parent table by a referenced table
  * ```json
  * {
  *   "data": [
  *     {
  *       "name": "violin",
  *       "orchestral_sections": {"name": "strings"}
  *     },
  *     {
  *       "name": "flute",
  *       "orchestral_sections": {"name": "woodwinds"}
  *     }
  *   ],
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  */
  order(column, { ascending = true, nullsFirst, foreignTable, referencedTable = foreignTable } = {}) {
    const key = referencedTable ? `${referencedTable}.order` : "order";
    const existingOrder = this.url.searchParams.get(key);
    this.url.searchParams.set(key, `${existingOrder ? `${existingOrder},` : ""}${column}.${ascending ? "asc" : "desc"}${nullsFirst === void 0 ? "" : nullsFirst ? ".nullsfirst" : ".nullslast"}`);
    return this;
  }
  /**
  * Limit the query result by `rows`.
  *
  * @param rows - The maximum number of rows to return
  * @param options - Named parameters
  * @param options.referencedTable - Set this to limit rows of referenced
  * tables instead of the parent table
  * @param options.foreignTable - Deprecated, use `options.referencedTable`
  * instead
  *
  * @category Database
  * @subcategory Using modifiers
  *
  * @example With `select()`
  * ```ts
  * const { data, error } = await supabase
  *   .from('characters')
  *   .select('name')
  *   .limit(1)
  * ```
  *
  * @exampleSql With `select()`
  * ```sql
  * create table
  *   characters (id int8 primary key, name text);
  *
  * insert into
  *   characters (id, name)
  * values
  *   (1, 'Luke'),
  *   (2, 'Leia'),
  *   (3, 'Han');
  * ```
  *
  * @exampleResponse With `select()`
  * ```json
  * {
  *   "data": [
  *     {
  *       "name": "Luke"
  *     }
  *   ],
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  *
  * @example On a referenced table
  * ```ts
  * const { data, error } = await supabase
  *   .from('orchestral_sections')
  *   .select(`
  *     name,
  *     instruments (
  *       name
  *     )
  *   `)
  *   .limit(1, { referencedTable: 'instruments' })
  * ```
  *
  * @exampleSql On a referenced table
  * ```sql
  * create table
  *   orchestral_sections (id int8 primary key, name text);
  * create table
  *   instruments (
  *     id int8 primary key,
  *     section_id int8 not null references orchestral_sections,
  *     name text
  *   );
  *
  * insert into
  *   orchestral_sections (id, name)
  * values
  *   (1, 'strings');
  * insert into
  *   instruments (id, section_id, name)
  * values
  *   (1, 1, 'harp'),
  *   (2, 1, 'violin');
  * ```
  *
  * @exampleResponse On a referenced table
  * ```json
  * {
  *   "data": [
  *     {
  *       "name": "strings",
  *       "instruments": [
  *         {
  *           "name": "violin"
  *         }
  *       ]
  *     }
  *   ],
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  */
  limit(rows, { foreignTable, referencedTable = foreignTable } = {}) {
    const key = typeof referencedTable === "undefined" ? "limit" : `${referencedTable}.limit`;
    this.url.searchParams.set(key, `${rows}`);
    return this;
  }
  /**
  * Limit the query result by starting at an offset `from` and ending at the offset `to`.
  * Only records within this range are returned.
  * This respects the query order and if there is no order clause the range could behave unexpectedly.
  * The `from` and `to` values are 0-based and inclusive: `range(1, 3)` will include the second, third
  * and fourth rows of the query.
  *
  * @param from - The starting index from which to limit the result
  * @param to - The last index to which to limit the result
  * @param options - Named parameters
  * @param options.referencedTable - Set this to limit rows of referenced
  * tables instead of the parent table
  * @param options.foreignTable - Deprecated, use `options.referencedTable`
  * instead
  *
  * @category Database
  * @subcategory Using modifiers
  *
  * @example With `select()`
  * ```ts
  * const { data, error } = await supabase
  *   .from('characters')
  *   .select('name')
  *   .range(0, 1)
  * ```
  *
  * @exampleSql With `select()`
  * ```sql
  * create table
  *   characters (id int8 primary key, name text);
  *
  * insert into
  *   characters (id, name)
  * values
  *   (1, 'Luke'),
  *   (2, 'Leia'),
  *   (3, 'Han');
  * ```
  *
  * @exampleResponse With `select()`
  * ```json
  * {
  *   "data": [
  *     {
  *       "name": "Luke"
  *     },
  *     {
  *       "name": "Leia"
  *     }
  *   ],
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  */
  range(from, to, { foreignTable, referencedTable = foreignTable } = {}) {
    const keyOffset = typeof referencedTable === "undefined" ? "offset" : `${referencedTable}.offset`;
    const keyLimit = typeof referencedTable === "undefined" ? "limit" : `${referencedTable}.limit`;
    this.url.searchParams.set(keyOffset, `${from}`);
    this.url.searchParams.set(keyLimit, `${to - from + 1}`);
    return this;
  }
  /**
  * Set the AbortSignal for the fetch request.
  *
  * @param signal - The AbortSignal to use for the fetch request
  *
  * @category Database
  * @subcategory Using modifiers
  *
  * @remarks
  * You can use this to set a timeout for the request.
  *
  * @exampleDescription Aborting requests in-flight
  * You can use an [`AbortController`](https://developer.mozilla.org/en-US/docs/Web/API/AbortController) to abort requests.
  * Note that `status` and `statusText` don't mean anything for aborted requests as the request wasn't fulfilled.
  *
  * @example Aborting requests in-flight
  * ```ts
  * const ac = new AbortController()
  *
  * const { data, error } = await supabase
  *   .from('very_big_table')
  *   .select()
  *   .abortSignal(ac.signal)
  *
  * // Abort the request after 100 ms
  * setTimeout(() => ac.abort(), 100)
  * ```
  *
  * @exampleResponse Aborting requests in-flight
  * ```json
  *   {
  *     "error": {
  *       "message": "AbortError: The user aborted a request.",
  *       "details": "",
  *       "hint": "The request was aborted locally via the provided AbortSignal.",
  *       "code": ""
  *     },
  *     "status": 0,
  *     "statusText": ""
  *   }
  *
  * ```
  *
  * @example Set a timeout
  * ```ts
  * const { data, error } = await supabase
  *   .from('very_big_table')
  *   .select()
  *   .abortSignal(AbortSignal.timeout(1000 /* ms *\/))
  * ```
  *
  * @exampleResponse Set a timeout
  * ```json
  *   {
  *     "error": {
  *       "message": "FetchError: The user aborted a request.",
  *       "details": "",
  *       "hint": "",
  *       "code": ""
  *     },
  *     "status": 0,
  *     "statusText": ""
  *   }
  *
  * ```
  */
  abortSignal(signal) {
    this.signal = signal;
    return this;
  }
  /**
  * Return `data` as a single object instead of an array of objects.
  *
  * Query result must be one row (e.g. using `.limit(1)`), otherwise this
  * returns an error.
  *
  * @category Database
  * @subcategory Using modifiers
  *
  * @example With `select()`
  * ```ts
  * const { data, error } = await supabase
  *   .from('characters')
  *   .select('name')
  *   .limit(1)
  *   .single()
  * ```
  *
  * @exampleSql With `select()`
  * ```sql
  * create table
  *   characters (id int8 primary key, name text);
  *
  * insert into
  *   characters (id, name)
  * values
  *   (1, 'Luke'),
  *   (2, 'Leia'),
  *   (3, 'Han');
  * ```
  *
  * @exampleResponse With `select()`
  * ```json
  * {
  *   "data": {
  *     "name": "Luke"
  *   },
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  */
  single() {
    this.headers.set("Accept", "application/vnd.pgrst.object+json");
    return this;
  }
  /**
  * Return `data` as a single object instead of an array of objects.
  *
  * Query result must be zero or one row (e.g. using `.limit(1)`), otherwise
  * this returns an error.
  *
  * @category Database
  * @subcategory Using modifiers
  *
  * @example With `select()`
  * ```ts
  * const { data, error } = await supabase
  *   .from('characters')
  *   .select()
  *   .eq('name', 'Katniss')
  *   .maybeSingle()
  * ```
  *
  * @exampleSql With `select()`
  * ```sql
  * create table
  *   characters (id int8 primary key, name text);
  *
  * insert into
  *   characters (id, name)
  * values
  *   (1, 'Luke'),
  *   (2, 'Leia'),
  *   (3, 'Han');
  * ```
  *
  * @exampleResponse With `select()`
  * ```json
  * {
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  */
  maybeSingle() {
    this.isMaybeSingle = true;
    return this;
  }
  /**
  * Return `data` as a string in CSV format.
  *
  * @category Database
  * @subcategory Using modifiers
  *
  * @exampleDescription Return data as CSV
  * By default, the data is returned in JSON format, but can also be returned as Comma Separated Values.
  *
  * @example Return data as CSV
  * ```ts
  * const { data, error } = await supabase
  *   .from('characters')
  *   .select()
  *   .csv()
  * ```
  *
  * @exampleSql Return data as CSV
  * ```sql
  * create table
  *   characters (id int8 primary key, name text);
  *
  * insert into
  *   characters (id, name)
  * values
  *   (1, 'Luke'),
  *   (2, 'Leia'),
  *   (3, 'Han');
  * ```
  *
  * @exampleResponse Return data as CSV
  * ```json
  * {
  *   "data": "id,name\n1,Luke\n2,Leia\n3,Han",
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  */
  csv() {
    this.headers.set("Accept", "text/csv");
    return this;
  }
  /**
  * Return `data` as an object in [GeoJSON](https://geojson.org) format.
  *
  * @category Database
  * @subcategory Using modifiers
  */
  geojson() {
    this.headers.set("Accept", "application/geo+json");
    return this;
  }
  /**
  * Return `data` as the EXPLAIN plan for the query.
  *
  * You need to enable the
  * [db_plan_enabled](https://supabase.com/docs/guides/database/debugging-performance#enabling-explain)
  * setting before using this method.
  *
  * @param options - Named parameters
  *
  * @param options.analyze - If `true`, the query will be executed and the
  * actual run time will be returned
  *
  * @param options.verbose - If `true`, the query identifier will be returned
  * and `data` will include the output columns of the query
  *
  * @param options.settings - If `true`, include information on configuration
  * parameters that affect query planning
  *
  * @param options.buffers - If `true`, include information on buffer usage
  *
  * @param options.wal - If `true`, include information on WAL record generation
  *
  * @param options.format - The format of the output, can be `"text"` (default)
  * or `"json"`
  *
  * @category Database
  * @subcategory Using modifiers
  *
  * @exampleDescription Get the execution plan
  * By default, the data is returned in TEXT format, but can also be returned as JSON by using the `format` parameter.
  *
  * @example Get the execution plan
  * ```ts
  * const { data, error } = await supabase
  *   .from('characters')
  *   .select()
  *   .explain()
  * ```
  *
  * @exampleSql Get the execution plan
  * ```sql
  * create table
  *   characters (id int8 primary key, name text);
  *
  * insert into
  *   characters (id, name)
  * values
  *   (1, 'Luke'),
  *   (2, 'Leia'),
  *   (3, 'Han');
  * ```
  *
  * @exampleResponse Get the execution plan
  * ```js
  * Aggregate  (cost=33.34..33.36 rows=1 width=112)
  *   ->  Limit  (cost=0.00..18.33 rows=1000 width=40)
  *         ->  Seq Scan on characters  (cost=0.00..22.00 rows=1200 width=40)
  * ```
  *
  * @exampleDescription Get the execution plan with analyze and verbose
  * By default, the data is returned in TEXT format, but can also be returned as JSON by using the `format` parameter.
  *
  * @example Get the execution plan with analyze and verbose
  * ```ts
  * const { data, error } = await supabase
  *   .from('characters')
  *   .select()
  *   .explain({analyze:true,verbose:true})
  * ```
  *
  * @exampleSql Get the execution plan with analyze and verbose
  * ```sql
  * create table
  *   characters (id int8 primary key, name text);
  *
  * insert into
  *   characters (id, name)
  * values
  *   (1, 'Luke'),
  *   (2, 'Leia'),
  *   (3, 'Han');
  * ```
  *
  * @exampleResponse Get the execution plan with analyze and verbose
  * ```js
  * Aggregate  (cost=33.34..33.36 rows=1 width=112) (actual time=0.041..0.041 rows=1 loops=1)
  *   Output: NULL::bigint, count(ROW(characters.id, characters.name)), COALESCE(json_agg(ROW(characters.id, characters.name)), '[]'::json), NULLIF(current_setting('response.headers'::text, true), ''::text), NULLIF(current_setting('response.status'::text, true), ''::text)
  *   ->  Limit  (cost=0.00..18.33 rows=1000 width=40) (actual time=0.005..0.006 rows=3 loops=1)
  *         Output: characters.id, characters.name
  *         ->  Seq Scan on public.characters  (cost=0.00..22.00 rows=1200 width=40) (actual time=0.004..0.005 rows=3 loops=1)
  *               Output: characters.id, characters.name
  * Query Identifier: -4730654291623321173
  * Planning Time: 0.407 ms
  * Execution Time: 0.119 ms
  * ```
  */
  explain({ analyze = false, verbose = false, settings = false, buffers = false, wal = false, format = "text" } = {}) {
    const options = [
      analyze ? "analyze" : null,
      verbose ? "verbose" : null,
      settings ? "settings" : null,
      buffers ? "buffers" : null,
      wal ? "wal" : null
    ].filter(Boolean).join("|");
    const forMediatype = this.headers.get("Accept") ?? "application/json";
    this.headers.set("Accept", `application/vnd.pgrst.plan+${format}; for="${forMediatype}"; options=${options};`);
    if (format === "json") {
      return this;
    } else {
      return this;
    }
  }
  /**
  * Dry-run this request: execute the query but discard the changes.
  *
  * Server-side, PostgREST runs the query inside a transaction and rolls it back
  * instead of committing. The response still contains the data that *would* have
  * been returned — `RETURNING` clauses execute and RLS, triggers, and constraints
  * are all evaluated — but no row is actually inserted, updated, or deleted.
  *
  * This affects only the single request it is chained to. The JS caller has no
  * handle on the transaction: supabase-js does not group multiple queries into
  * one transaction. For multi-statement transactional logic, use a database
  * function (`supabase.rpc(...)`).
  *
  * Sets the `Prefer: tx=rollback` header. See PostgREST's docs on transaction
  * preferences for the underlying mechanism.
  *
  * @category Database
  * @subcategory Using modifiers
  *
  * @example Validate an insert without persisting
  * ```ts
  * const { data, error } = await supabase
  *   .from('countries')
  *   .insert({ name: 'France' })
  *   .select()
  *   .rollback()
  * // `data` shows what would have been inserted; nothing is saved.
  * ```
  */
  rollback() {
    this.headers.append("Prefer", "tx=rollback");
    return this;
  }
  /**
  * Override the type of the returned `data`.
  *
  * @typeParam NewResult - The new result type to override with
  * @deprecated Use overrideTypes<yourType, { merge: false }>() method at the end of your call chain instead
  *
  * @category Database
  * @subcategory Using modifiers
  *
  * @remarks
  * - Deprecated: use overrideTypes method instead
  *
  * @example Override type of successful response
  * ```ts
  * const { data } = await supabase
  *   .from('countries')
  *   .select()
  *   .returns<Array<MyType>>()
  * ```
  *
  * @exampleResponse Override type of successful response
  * ```js
  * let x: typeof data // MyType[]
  * ```
  *
  * @example Override type of object response
  * ```ts
  * const { data } = await supabase
  *   .from('countries')
  *   .select()
  *   .maybeSingle()
  *   .returns<MyType>()
  * ```
  *
  * @exampleResponse Override type of object response
  * ```js
  * let x: typeof data // MyType | null
  * ```
  */
  returns() {
    return this;
  }
  /**
  * Set the maximum number of rows that can be affected by the query.
  * Only available in PostgREST v13+ and only works with PATCH and DELETE methods.
  *
  * @param rows - The maximum number of rows that can be affected
  *
  * @category Database
  * @subcategory Using modifiers
  */
  maxAffected(rows) {
    this.headers.append("Prefer", "handling=strict");
    this.headers.append("Prefer", `max-affected=${rows}`);
    return this;
  }
};

// src/vendor/postgrest/PostgrestFilterBuilder.ts
var PostgrestReservedCharsRegexp = new RegExp("[,()]");
var PostgrestFilterBuilder = class extends PostgrestTransformBuilder {
  static {
    __name(this, "PostgrestFilterBuilder");
  }
  throwOnError() {
    return super.throwOnError();
  }
  /**
  * Match only rows where `column` is equal to `value`.
  *
  * To check if the value of `column` is NULL, you should use `.is()` instead.
  *
  * @param column - The column to filter on
  * @param value - The value to filter with
  *
  * @category Database
  * @subcategory Using filters
  *
  * @example With `select()`
  * ```ts
  * const { data, error } = await supabase
  *   .from('characters')
  *   .select()
  *   .eq('name', 'Leia')
  * ```
  *
  * @exampleSql With `select()`
  * ```sql
  * create table
  *   characters (id int8 primary key, name text);
  *
  * insert into
  *   characters (id, name)
  * values
  *   (1, 'Luke'),
  *   (2, 'Leia'),
  *   (3, 'Han');
  * ```
  *
  * @exampleResponse With `select()`
  * ```json
  * {
  *   "data": [
  *     {
  *       "id": 2,
  *       "name": "Leia"
  *     }
  *   ],
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  */
  eq(column, value) {
    this.url.searchParams.append(column, `eq.${value}`);
    return this;
  }
  /**
  * Match only rows where `column` is not equal to `value`.
  *
  * This filter does not include rows where `column` is `NULL`. To match null
  * values, use `.is(column, null)` instead.
  *
  * @param column - The column to filter on
  * @param value - The value to filter with
  *
  * @category Database
  * @subcategory Using filters
  *
  * @example With `select()`
  * ```ts
  * const { data, error } = await supabase
  *   .from('characters')
  *   .select()
  *   .neq('name', 'Leia')
  * ```
  *
  * @exampleSql With `select()`
  * ```sql
  * create table
  *   characters (id int8 primary key, name text);
  *
  * insert into
  *   characters (id, name)
  * values
  *   (1, 'Luke'),
  *   (2, 'Leia'),
  *   (3, 'Han');
  * ```
  *
  * @exampleResponse With `select()`
  * ```json
  * {
  *   "data": [
  *     {
  *       "id": 1,
  *       "name": "Luke"
  *     },
  *     {
  *       "id": 3,
  *       "name": "Han"
  *     }
  *   ],
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  */
  neq(column, value) {
    this.url.searchParams.append(column, `neq.${value}`);
    return this;
  }
  gt(column, value) {
    this.url.searchParams.append(column, `gt.${value}`);
    return this;
  }
  gte(column, value) {
    this.url.searchParams.append(column, `gte.${value}`);
    return this;
  }
  lt(column, value) {
    this.url.searchParams.append(column, `lt.${value}`);
    return this;
  }
  lte(column, value) {
    this.url.searchParams.append(column, `lte.${value}`);
    return this;
  }
  like(column, pattern) {
    this.url.searchParams.append(column, `like.${pattern}`);
    return this;
  }
  likeAllOf(column, patterns) {
    this.url.searchParams.append(column, `like(all).{${patterns.join(",")}}`);
    return this;
  }
  likeAnyOf(column, patterns) {
    this.url.searchParams.append(column, `like(any).{${patterns.join(",")}}`);
    return this;
  }
  ilike(column, pattern) {
    this.url.searchParams.append(column, `ilike.${pattern}`);
    return this;
  }
  ilikeAllOf(column, patterns) {
    this.url.searchParams.append(column, `ilike(all).{${patterns.join(",")}}`);
    return this;
  }
  ilikeAnyOf(column, patterns) {
    this.url.searchParams.append(column, `ilike(any).{${patterns.join(",")}}`);
    return this;
  }
  regexMatch(column, pattern) {
    this.url.searchParams.append(column, `match.${pattern}`);
    return this;
  }
  regexIMatch(column, pattern) {
    this.url.searchParams.append(column, `imatch.${pattern}`);
    return this;
  }
  is(column, value) {
    this.url.searchParams.append(column, `is.${value}`);
    return this;
  }
  /**
  * Match only rows where `column` IS DISTINCT FROM `value`.
  *
  * Unlike `.neq()`, this treats `NULL` as a comparable value. Two `NULL` values
  * are considered equal (not distinct), and comparing `NULL` with any non-NULL
  * value returns true (distinct).
  *
  * @param column - The column to filter on
  * @param value - The value to filter with
  */
  isDistinct(column, value) {
    this.url.searchParams.append(column, `isdistinct.${value}`);
    return this;
  }
  /**
  * Match only rows where `column` is included in the `values` array.
  *
  * @param column - The column to filter on
  * @param values - The values array to filter with
  *
  * @category Database
  * @subcategory Using filters
  *
  * @example With `select()`
  * ```ts
  * const { data, error } = await supabase
  *   .from('characters')
  *   .select()
  *   .in('name', ['Leia', 'Han'])
  * ```
  *
  * @exampleSql With `select()`
  * ```sql
  * create table
  *   characters (id int8 primary key, name text);
  *
  * insert into
  *   characters (id, name)
  * values
  *   (1, 'Luke'),
  *   (2, 'Leia'),
  *   (3, 'Han');
  * ```
  *
  * @exampleResponse With `select()`
  * ```json
  * {
  *   "data": [
  *     {
  *       "id": 2,
  *       "name": "Leia"
  *     },
  *     {
  *       "id": 3,
  *       "name": "Han"
  *     }
  *   ],
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  */
  in(column, values) {
    const cleanedValues = Array.from(new Set(values)).map((s) => {
      if (typeof s === "string" && PostgrestReservedCharsRegexp.test(s)) return `"${s}"`;
      else return `${s}`;
    }).join(",");
    this.url.searchParams.append(column, `in.(${cleanedValues})`);
    return this;
  }
  /**
  * Match only rows where `column` is NOT included in the `values` array.
  *
  * @param column - The column to filter on
  * @param values - The values array to filter with
  */
  notIn(column, values) {
    const cleanedValues = Array.from(new Set(values)).map((s) => {
      if (typeof s === "string" && PostgrestReservedCharsRegexp.test(s)) return `"${s}"`;
      else return `${s}`;
    }).join(",");
    this.url.searchParams.append(column, `not.in.(${cleanedValues})`);
    return this;
  }
  contains(column, value) {
    if (typeof value === "string") {
      this.url.searchParams.append(column, `cs.${value}`);
    } else if (Array.isArray(value)) {
      this.url.searchParams.append(column, `cs.{${value.join(",")}}`);
    } else {
      this.url.searchParams.append(column, `cs.${JSON.stringify(value)}`);
    }
    return this;
  }
  containedBy(column, value) {
    if (typeof value === "string") {
      this.url.searchParams.append(column, `cd.${value}`);
    } else if (Array.isArray(value)) {
      this.url.searchParams.append(column, `cd.{${value.join(",")}}`);
    } else {
      this.url.searchParams.append(column, `cd.${JSON.stringify(value)}`);
    }
    return this;
  }
  rangeGt(column, range) {
    this.url.searchParams.append(column, `sr.${range}`);
    return this;
  }
  rangeGte(column, range) {
    this.url.searchParams.append(column, `nxl.${range}`);
    return this;
  }
  rangeLt(column, range) {
    this.url.searchParams.append(column, `sl.${range}`);
    return this;
  }
  rangeLte(column, range) {
    this.url.searchParams.append(column, `nxr.${range}`);
    return this;
  }
  rangeAdjacent(column, range) {
    this.url.searchParams.append(column, `adj.${range}`);
    return this;
  }
  overlaps(column, value) {
    if (typeof value === "string") {
      this.url.searchParams.append(column, `ov.${value}`);
    } else {
      this.url.searchParams.append(column, `ov.{${value.join(",")}}`);
    }
    return this;
  }
  textSearch(column, query, { config, type } = {}) {
    let typePart = "";
    if (type === "plain") {
      typePart = "pl";
    } else if (type === "phrase") {
      typePart = "ph";
    } else if (type === "websearch") {
      typePart = "w";
    }
    const configPart = config === void 0 ? "" : `(${config})`;
    this.url.searchParams.append(column, `${typePart}fts${configPart}.${query}`);
    return this;
  }
  match(query) {
    Object.entries(query).filter(([_, value]) => value !== void 0).forEach(([column, value]) => {
      this.url.searchParams.append(column, `eq.${value}`);
    });
    return this;
  }
  /**
  * Match only rows which doesn't satisfy the filter.
  *
  * Unlike most filters, `opearator` and `value` are used as-is and need to
  * follow [PostgREST
  * syntax](https://postgrest.org/en/stable/api.html#operators). You also need
  * to make sure they are properly sanitized.
  *
  * @param column - The column to filter on
  * @param operator - The operator to be negated to filter with, following
  * PostgREST syntax
  * @param value - The value to filter with, following PostgREST syntax
  *
  * @category Database
  * @subcategory Using filters
  *
  * @remarks
  * not() expects you to use the raw PostgREST syntax for the filter values.
  *
  * ```ts
  * .not('id', 'in', '(5,6,7)')  // Use `()` for `in` filter
  * .not('arraycol', 'cs', '{"a","b"}')  // Use `cs` for `contains()`, `{}` for array values
  * ```
  *
  * @example With `select()`
  * ```ts
  * const { data, error } = await supabase
  *   .from('countries')
  *   .select()
  *   .not('name', 'is', null)
  * ```
  *
  * @exampleSql With `select()`
  * ```sql
  * create table
  *   countries (id int8 primary key, name text);
  *
  * insert into
  *   countries (id, name)
  * values
  *   (1, 'null'),
  *   (2, null);
  * ```
  *
  * @exampleResponse With `select()`
  * ```json
  *   {
  *     "data": [
  *       {
  *         "id": 1,
  *         "name": "null"
  *       }
  *     ],
  *     "status": 200,
  *     "statusText": "OK"
  *   }
  *
  * ```
  */
  not(column, operator, value) {
    this.url.searchParams.append(column, `not.${operator}.${value}`);
    return this;
  }
  /**
  * Match only rows which satisfy at least one of the filters.
  *
  * Unlike most filters, `filters` is used as-is and needs to follow [PostgREST
  * syntax](https://postgrest.org/en/stable/api.html#operators). You also need
  * to make sure it's properly sanitized.
  *
  * It's currently not possible to do an `.or()` filter across multiple tables.
  *
  * @param filters - The filters to use, following PostgREST syntax
  * @param options - Named parameters
  * @param options.referencedTable - Set this to filter on referenced tables
  * instead of the parent table
  * @param options.foreignTable - Deprecated, use `referencedTable` instead
  *
  * @category Database
  * @subcategory Using filters
  *
  * @remarks
  * or() expects you to use the raw PostgREST syntax for the filter names and values.
  *
  * ```ts
  * .or('id.in.(5,6,7), arraycol.cs.{"a","b"}')  // Use `()` for `in` filter, `{}` for array values and `cs` for `contains()`.
  * .or('id.in.(5,6,7), arraycol.cd.{"a","b"}')  // Use `cd` for `containedBy()`
  * ```
  *
  * @example With `select()`
  * ```ts
  * const { data, error } = await supabase
  *   .from('characters')
  *   .select('name')
  *   .or('id.eq.2,name.eq.Han')
  * ```
  *
  * @exampleSql With `select()`
  * ```sql
  * create table
  *   characters (id int8 primary key, name text);
  *
  * insert into
  *   characters (id, name)
  * values
  *   (1, 'Luke'),
  *   (2, 'Leia'),
  *   (3, 'Han');
  * ```
  *
  * @exampleResponse With `select()`
  * ```json
  * {
  *   "data": [
  *     {
  *       "name": "Leia"
  *     },
  *     {
  *       "name": "Han"
  *     }
  *   ],
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  *
  * @example Use `or` with `and`
  * ```ts
  * const { data, error } = await supabase
  *   .from('characters')
  *   .select('name')
  *   .or('id.gt.3,and(id.eq.1,name.eq.Luke)')
  * ```
  *
  * @exampleSql Use `or` with `and`
  * ```sql
  * create table
  *   characters (id int8 primary key, name text);
  *
  * insert into
  *   characters (id, name)
  * values
  *   (1, 'Luke'),
  *   (2, 'Leia'),
  *   (3, 'Han');
  * ```
  *
  * @exampleResponse Use `or` with `and`
  * ```json
  * {
  *   "data": [
  *     {
  *       "name": "Luke"
  *     }
  *   ],
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  *
  * @example Use `or` on referenced tables
  * ```ts
  * const { data, error } = await supabase
  *   .from('orchestral_sections')
  *   .select(`
  *     name,
  *     instruments!inner (
  *       name
  *     )
  *   `)
  *   .or('section_id.eq.1,name.eq.guzheng', { referencedTable: 'instruments' })
  * ```
  *
  * @exampleSql Use `or` on referenced tables
  * ```sql
  * create table
  *   orchestral_sections (id int8 primary key, name text);
  * create table
  *   instruments (
  *     id int8 primary key,
  *     section_id int8 not null references orchestral_sections,
  *     name text
  *   );
  *
  * insert into
  *   orchestral_sections (id, name)
  * values
  *   (1, 'strings'),
  *   (2, 'woodwinds');
  * insert into
  *   instruments (id, section_id, name)
  * values
  *   (1, 2, 'flute'),
  *   (2, 1, 'violin');
  * ```
  *
  * @exampleResponse Use `or` on referenced tables
  * ```json
  * {
  *   "data": [
  *     {
  *       "name": "strings",
  *       "instruments": [
  *         {
  *           "name": "violin"
  *         }
  *       ]
  *     }
  *   ],
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  */
  or(filters, { foreignTable, referencedTable = foreignTable } = {}) {
    const key = referencedTable ? `${referencedTable}.or` : "or";
    this.url.searchParams.append(key, `(${filters})`);
    return this;
  }
  filter(column, operator, value) {
    this.url.searchParams.append(column, `${operator}.${value}`);
    return this;
  }
};

// src/vendor/postgrest/PostgrestQueryBuilder.ts
var PostgrestQueryBuilder = class {
  static {
    __name(this, "PostgrestQueryBuilder");
  }
  url;
  headers;
  schema;
  signal;
  fetch;
  urlLengthLimit;
  /**
  * Enable or disable automatic retries for transient errors.
  * When enabled, idempotent requests (GET/HEAD/OPTIONS) that fail with network
  * errors or HTTP 503/520 responses are automatically retried with exponential
  * backoff (1s, 2s, 4s, up to 3 attempts). Defaults to `true` when not specified.
  */
  retry;
  /**
  * Creates a query builder scoped to a Postgres table or view.
  *
  * @category Database
  *
  * @param url - The URL for the query
  * @param options - Named parameters
  * @param options.headers - Custom headers
  * @param options.schema - Postgres schema to use
  * @param options.fetch - Custom fetch implementation
  * @param options.urlLengthLimit - Maximum URL length before warning
  * @param options.retry - Enable automatic retries for transient errors (default: true)
  *
  * @example Using supabase-js (recommended)
  * ```ts
  * import { createClient } from '@supabase/supabase-js'
  *
  * const supabase = createClient('https://xyzcompany.supabase.co', 'your-publishable-key')
  * const { data, error } = await supabase.from('users').select('*')
  * ```
  *
  * @example Standalone import for bundle-sensitive environments
  * ```ts
  * import { PostgrestQueryBuilder } from '@supabase/postgrest-js'
  *
  * const query = new PostgrestQueryBuilder(
  *   new URL('https://xyzcompany.supabase.co/rest/v1/users'),
  *   { headers: { apikey: 'your-publishable-key' }, retry: true }
  * )
  * ```
  */
  constructor(url, { headers = {}, schema, fetch: fetch1, urlLengthLimit = 8e3, retry }) {
    this.url = url;
    this.headers = new Headers(headers);
    this.schema = schema;
    this.fetch = fetch1;
    this.urlLengthLimit = urlLengthLimit;
    this.retry = retry;
  }
  /**
  * Clone URL and headers to prevent shared state between operations.
  */
  cloneRequestState() {
    return {
      url: new URL(this.url.toString()),
      headers: new Headers(this.headers)
    };
  }
  /**
     * Perform a SELECT query on the table or view.
     *
     * @param columns - The columns to retrieve, separated by commas. Columns can be renamed when returned with `customName:columnName`
     *
     * @param options - Named parameters
     *
     * @param options.head - When set to `true`, `data` will not be returned.
     * Useful if you only need the count.
     *
     * @param options.count - Count algorithm to use to count rows in the table or view.
     *
     * `"exact"`: Exact but slow count algorithm. Performs a `COUNT(*)` under the
     * hood.
     *
     * `"planned"`: Approximated but fast count algorithm. Uses the Postgres
     * statistics under the hood.
     *
     * `"estimated"`: Uses exact count for low numbers and planned count for high
     * numbers.
     *
     * @remarks
     * When using `count` with `.range()` or `.limit()`, the returned `count` is the total number of rows
     * that match your filters, not the number of rows in the current page. Use this to build pagination UI.
   *
   * - By default, Supabase projects return a maximum of 1,000 rows. This setting can be changed in your project's [API settings](/dashboard/project/_/settings/api). It's recommended that you keep it low to limit the payload size of accidental or malicious requests. You can use `range()` queries to paginate through your data.
   * - `select()` can be combined with [Filters](/docs/reference/javascript/using-filters)
   * - `select()` can be combined with [Modifiers](/docs/reference/javascript/using-modifiers)
   * - `apikey` is a reserved keyword if you're using the [Supabase Platform](/docs/guides/platform) and [should be avoided as a column name](https://github.com/supabase/supabase/issues/5465). *
   * @category Database
   *
   * @example Getting your data
   * ```js
   * const { data, error } = await supabase
   *   .from('characters')
   *   .select()
   * ```
   *
   * @exampleSql Getting your data
   * ```sql
   * create table
   *   characters (id int8 primary key, name text);
   *
   * insert into
   *   characters (id, name)
   * values
   *   (1, 'Harry'),
   *   (2, 'Frodo'),
   *   (3, 'Katniss');
   * ```
   *
   * @exampleResponse Getting your data
   * ```json
   * {
   *   "data": [
   *     {
   *       "id": 1,
   *       "name": "Harry"
   *     },
   *     {
   *       "id": 2,
   *       "name": "Frodo"
   *     },
   *     {
   *       "id": 3,
   *       "name": "Katniss"
   *     }
   *   ],
   *   "status": 200,
   *   "statusText": "OK"
   * }
   * ```
   *
   * @exampleDescription Handling errors
   * The most useful field on a Postgres error is usually `hint` — when the database knows the fix, it puts the literal SQL there. For example, a permission-denied error (`code: '42501'`) arrives with a `hint` like `"Grant the required privileges to the current role with: GRANT SELECT ON public.characters TO anon;"`. Log the full `error` object so the hint isn't hidden behind `error.message`.
   *
   * @example Handling errors
   * ```js
   * const { data, error } = await supabase.from('characters').select()
   * if (error) {
   *   // Logs the full error: message, code, details, and hint.
   *   console.error(error)
   *   return
   * }
   * ```
   *
   * @exampleResponse Handling errors
   * ```json
   * {
   *   "error": {
   *     "code": "42501",
   *     "details": null,
   *     "hint": "Grant the required privileges to the current role with: GRANT SELECT ON public.characters TO anon;",
   *     "message": "permission denied for table characters"
   *   },
   *   "status": 401,
   *   "statusText": ""
   * }
   * ```
   *
   * @example Selecting specific columns
   * ```js
   * const { data, error } = await supabase
   *   .from('characters')
   *   .select('name')
   * ```
   *
   * @exampleSql Selecting specific columns
   * ```sql
   * create table
   *   characters (id int8 primary key, name text);
   *
   * insert into
   *   characters (id, name)
   * values
   *   (1, 'Frodo'),
   *   (2, 'Harry'),
   *   (3, 'Katniss');
   * ```
   *
   * @exampleResponse Selecting specific columns
   * ```json
   * {
   *   "data": [
   *     {
   *       "name": "Frodo"
   *     },
   *     {
   *       "name": "Harry"
   *     },
   *     {
   *       "name": "Katniss"
   *     }
   *   ],
   *   "status": 200,
   *   "statusText": "OK"
   * }
   * ```
   *
   * @exampleDescription Query referenced tables
   * If your database has foreign key relationships, you can query related tables too.
   *
   * @example Query referenced tables
   * ```js
   * const { data, error } = await supabase
   *   .from('orchestral_sections')
   *   .select(`
   *     name,
   *     instruments (
   *       name
   *     )
   *   `)
   * ```
   *
   * @exampleSql Query referenced tables
   * ```sql
   * create table
   *   orchestral_sections (id int8 primary key, name text);
   * create table
   *   instruments (
   *     id int8 primary key,
   *     section_id int8 not null references orchestral_sections,
   *     name text
   *   );
   *
   * insert into
   *   orchestral_sections (id, name)
   * values
   *   (1, 'strings'),
   *   (2, 'woodwinds');
   * insert into
   *   instruments (id, section_id, name)
   * values
   *   (1, 2, 'flute'),
   *   (2, 1, 'violin');
   * ```
   *
   * @exampleResponse Query referenced tables
   * ```json
   * {
   *   "data": [
   *     {
   *       "name": "strings",
   *       "instruments": [
   *         {
   *           "name": "violin"
   *         }
   *       ]
   *     },
   *     {
   *       "name": "woodwinds",
   *       "instruments": [
   *         {
   *           "name": "flute"
   *         }
   *       ]
   *     }
   *   ],
   *   "status": 200,
   *   "statusText": "OK"
   * }
   * ```
   *
   * @exampleDescription Query referenced tables with spaces in their names
   * If your table name contains spaces, you must use double quotes in the `select` statement to reference the table.
   *
   * @example Query referenced tables with spaces in their names
   * ```js
   * const { data, error } = await supabase
   *   .from('orchestral sections')
   *   .select(`
   *     name,
   *     "musical instruments" (
   *       name
   *     )
   *   `)
   * ```
   *
   * @exampleSql Query referenced tables with spaces in their names
   * ```sql
   * create table
   *   "orchestral sections" (id int8 primary key, name text);
   * create table
   *   "musical instruments" (
   *     id int8 primary key,
   *     section_id int8 not null references "orchestral sections",
   *     name text
   *   );
   *
   * insert into
   *   "orchestral sections" (id, name)
   * values
   *   (1, 'strings'),
   *   (2, 'woodwinds');
   * insert into
   *   "musical instruments" (id, section_id, name)
   * values
   *   (1, 2, 'flute'),
   *   (2, 1, 'violin');
   * ```
   *
   * @exampleResponse Query referenced tables with spaces in their names
   * ```json
   * {
   *   "data": [
   *     {
   *       "name": "strings",
   *       "musical instruments": [
   *         {
   *           "name": "violin"
   *         }
   *       ]
   *     },
   *     {
   *       "name": "woodwinds",
   *       "musical instruments": [
   *         {
   *           "name": "flute"
   *         }
   *       ]
   *     }
   *   ],
   *   "status": 200,
   *   "statusText": "OK"
   * }
   * ```
   *
   * @exampleDescription Query referenced tables through a join table
   * If you're in a situation where your tables are **NOT** directly
   * related, but instead are joined by a _join table_, you can still use
   * the `select()` method to query the related data. The join table needs
   * to have the foreign keys as part of its composite primary key.
   *
   * @example Query referenced tables through a join table
   * ```ts
   * const { data, error } = await supabase
   *   .from('users')
   *   .select(`
   *     name,
   *     teams (
   *       name
   *     )
   *   `)
   *
   * ```     * @exampleSql Query referenced tables through a join table
   * ```sql
   * create table
   *   users (
   *     id int8 primary key,
   *     name text
   *   );
   * create table
   *   teams (
   *     id int8 primary key,
   *     name text
   *   );
   * -- join table
   * create table
   *   users_teams (
   *     user_id int8 not null references users,
   *     team_id int8 not null references teams,
   *     -- both foreign keys must be part of a composite primary key
   *     primary key (user_id, team_id)
   *   );
   *
   * insert into
   *   users (id, name)
   * values
   *   (1, 'Kiran'),
   *   (2, 'Evan');
   * insert into
   *   teams (id, name)
   * values
   *   (1, 'Green'),
   *   (2, 'Blue');
   * insert into
   *   users_teams (user_id, team_id)
   * values
   *   (1, 1),
   *   (1, 2),
   *   (2, 2);
   * ```
   *
   * @exampleResponse Query referenced tables through a join table
   * ```json
   *   {
   *     "data": [
   *       {
   *         "name": "Kiran",
   *         "teams": [
   *           {
   *             "name": "Green"
   *           },
   *           {
   *             "name": "Blue"
   *           }
   *         ]
   *       },
   *       {
   *         "name": "Evan",
   *         "teams": [
   *           {
   *             "name": "Blue"
   *           }
   *         ]
   *       }
   *     ],
   *     "status": 200,
   *     "statusText": "OK"
   *   }
   *
   * ```
   *
   * @exampleDescription Query the same referenced table multiple times
   * If you need to query the same referenced table twice, use the name of the
   * joined column to identify which join to use. You can also give each
   * column an alias.
   *
   * @example Query the same referenced table multiple times
   * ```ts
   * const { data, error } = await supabase
   *   .from('messages')
   *   .select(`
   *     content,
   *     from:sender_id(name),
   *     to:receiver_id(name)
   *   `)
   *
   * // To infer types, use the name of the table (in this case `users`) and
   * // the name of the foreign key constraint.
   * const { data, error } = await supabase
   *   .from('messages')
   *   .select(`
   *     content,
   *     from:users!messages_sender_id_fkey(name),
   *     to:users!messages_receiver_id_fkey(name)
   *   `)
   * ```
   *
   * @exampleSql Query the same referenced table multiple times
   * ```sql
   *  create table
   *  users (id int8 primary key, name text);
   *
   *  create table
   *    messages (
   *      sender_id int8 not null references users,
   *      receiver_id int8 not null references users,
   *      content text
   *    );
   *
   *  insert into
   *    users (id, name)
   *  values
   *    (1, 'Kiran'),
   *    (2, 'Evan');
   *
   *  insert into
   *    messages (sender_id, receiver_id, content)
   *  values
   *    (1, 2, '👋');
   *  ```
   * ```
   *
   * @exampleResponse Query the same referenced table multiple times
   * ```json
   * {
   *   "data": [
   *     {
   *       "content": "👋",
   *       "from": {
   *         "name": "Kiran"
   *       },
   *       "to": {
   *         "name": "Evan"
   *       }
   *     }
   *   ],
   *   "status": 200,
   *   "statusText": "OK"
   * }
   * ```
   *
   * @exampleDescription Query nested foreign tables through a join table
   * You can use the result of a joined table to gather data in
   * another foreign table. With multiple references to the same foreign
   * table you must specify the column on which to conduct the join.
   *
   * @example Query nested foreign tables through a join table
   * ```ts
   *   const { data, error } = await supabase
   *     .from('games')
   *     .select(`
   *       game_id:id,
   *       away_team:teams!games_away_team_fkey (
   *         users (
   *           id,
   *           name
   *         )
   *       )
   *     `)
   *
   * ```
   *
   * @exampleSql Query nested foreign tables through a join table
   * ```sql
   * ```sql
   * create table
   *   users (
   *     id int8 primary key,
   *     name text
   *   );
   * create table
   *   teams (
   *     id int8 primary key,
   *     name text
   *   );
   * -- join table
   * create table
   *   users_teams (
   *     user_id int8 not null references users,
   *     team_id int8 not null references teams,
   *
   *     primary key (user_id, team_id)
   *   );
   * create table
   *   games (
   *     id int8 primary key,
   *     home_team int8 not null references teams,
   *     away_team int8 not null references teams,
   *     name text
   *   );
   *
   * insert into users (id, name)
   * values
   *   (1, 'Kiran'),
   *   (2, 'Evan');
   * insert into
   *   teams (id, name)
   * values
   *   (1, 'Green'),
   *   (2, 'Blue');
   * insert into
   *   users_teams (user_id, team_id)
   * values
   *   (1, 1),
   *   (1, 2),
   *   (2, 2);
   * insert into
   *   games (id, home_team, away_team, name)
   * values
   *   (1, 1, 2, 'Green vs Blue'),
   *   (2, 2, 1, 'Blue vs Green');
   * ```
   *
   * @exampleResponse Query nested foreign tables through a join table
   * ```json
   *   {
   *     "data": [
   *       {
   *         "game_id": 1,
   *         "away_team": {
   *           "users": [
   *             {
   *               "id": 1,
   *               "name": "Kiran"
   *             },
   *             {
   *               "id": 2,
   *               "name": "Evan"
   *             }
   *           ]
   *         }
   *       },
   *       {
   *         "game_id": 2,
   *         "away_team": {
   *           "users": [
   *             {
   *               "id": 1,
   *               "name": "Kiran"
   *             }
   *           ]
   *         }
   *       }
   *     ],
   *     "status": 200,
   *     "statusText": "OK"
   *   }
   *
   * ```
   *
   * @exampleDescription Filtering through referenced tables
   * If the filter on a referenced table's column is not satisfied, the referenced
   * table returns `[]` or `null` but the parent table is not filtered out.
   * If you want to filter out the parent table rows, use the `!inner` hint
   *
   * @example Filtering through referenced tables
   * ```ts
   * const { data, error } = await supabase
   *   .from('instruments')
   *   .select('name, orchestral_sections(*)')
   *   .eq('orchestral_sections.name', 'percussion')
   * ```
   *
   * @exampleSql Filtering through referenced tables
   * ```sql
   * create table
   *   orchestral_sections (id int8 primary key, name text);
   * create table
   *   instruments (
   *     id int8 primary key,
   *     section_id int8 not null references orchestral_sections,
   *     name text
   *   );
   *
   * insert into
   *   orchestral_sections (id, name)
   * values
   *   (1, 'strings'),
   *   (2, 'woodwinds');
   * insert into
   *   instruments (id, section_id, name)
   * values
   *   (1, 2, 'flute'),
   *   (2, 1, 'violin');
   * ```
   *
   * @exampleResponse Filtering through referenced tables
   * ```json
   * {
   *   "data": [
   *     {
   *       "name": "flute",
   *       "orchestral_sections": null
   *     },
   *     {
   *       "name": "violin",
   *       "orchestral_sections": null
   *     }
   *   ],
   *   "status": 200,
   *   "statusText": "OK"
   * }
   * ```
   *
   * @exampleDescription Querying referenced table with count
   * You can get the number of rows in a related table by using the
   * **count** property.
   *
   * @example Querying referenced table with count
   * ```ts
   * const { data, error } = await supabase
   *   .from('orchestral_sections')
   *   .select(`*, instruments(count)`)
   * ```
   *
   * @exampleSql Querying referenced table with count
   * ```sql
   * create table orchestral_sections (
   *   "id" "uuid" primary key default "extensions"."uuid_generate_v4"() not null,
   *   "name" text
   * );
   *
   * create table characters (
   *   "id" "uuid" primary key default "extensions"."uuid_generate_v4"() not null,
   *   "name" text,
   *   "section_id" "uuid" references public.orchestral_sections on delete cascade
   * );
   *
   * with section as (
   *   insert into orchestral_sections (name)
   *   values ('strings') returning id
   * )
   * insert into instruments (name, section_id) values
   * ('violin', (select id from section)),
   * ('viola', (select id from section)),
   * ('cello', (select id from section)),
   * ('double bass', (select id from section));
   * ```
   *
   * @exampleResponse Querying referenced table with count
   * ```json
   * [
   *   {
   *     "id": "693694e7-d993-4360-a6d7-6294e325d9b6",
   *     "name": "strings",
   *     "instruments": [
   *       {
   *         "count": 4
   *       }
   *     ]
   *   }
   * ]
   * ```
   *
   * @exampleDescription Querying with count option
   * You can get the number of rows by using the
   * [count](/docs/reference/javascript/select#parameters) option.
   *
   * @example Querying with count option
   * ```ts
   * const { count, error } = await supabase
   *   .from('characters')
   *   .select('*', { count: 'exact', head: true })
   * ```
   *
   * @exampleSql Querying with count option
   * ```sql
   * create table
   *   characters (id int8 primary key, name text);
   *
   * insert into
   *   characters (id, name)
   * values
   *   (1, 'Luke'),
   *   (2, 'Leia'),
   *   (3, 'Han');
   * ```
   *
   * @exampleResponse Querying with count option
   * ```json
   * {
   *   "count": 3,
   *   "status": 200,
   *   "statusText": "OK"
   * }
   * ```
   *
   * @exampleDescription Querying JSON data
   * You can select and filter data inside of
   * [JSON](/docs/guides/database/json) columns. Postgres offers some
   * [operators](/docs/guides/database/json#query-the-jsonb-data) for
   * querying JSON data.
   *
   * @example Querying JSON data
   * ```ts
   * const { data, error } = await supabase
   *   .from('users')
   *   .select(`
   *     id, name,
   *     address->city
   *   `)
   * ```
   *
   * @exampleSql Querying JSON data
   * ```sql
   * create table
   *   users (
   *     id int8 primary key,
   *     name text,
   *     address jsonb
   *   );
   *
   * insert into
   *   users (id, name, address)
   * values
   *   (1, 'Frodo', '{"city":"Hobbiton"}');
   * ```
   *
   * @exampleResponse Querying JSON data
   * ```json
   * {
   *   "data": [
   *     {
   *       "id": 1,
   *       "name": "Frodo",
   *       "city": "Hobbiton"
   *     }
   *   ],
   *   "status": 200,
   *   "statusText": "OK"
   * }
   * ```
   *
   * @exampleDescription Querying referenced table with inner join
   * If you don't want to return the referenced table contents, you can leave the parenthesis empty.
   * Like `.select('name, orchestral_sections!inner()')`.
   *
   * @example Querying referenced table with inner join
   * ```ts
   * const { data, error } = await supabase
   *   .from('instruments')
   *   .select('name, orchestral_sections!inner(name)')
   *   .eq('orchestral_sections.name', 'woodwinds')
   *   .limit(1)
   * ```
   *
   * @exampleSql Querying referenced table with inner join
   * ```sql
   * create table orchestral_sections (
   *   "id" "uuid" primary key default "extensions"."uuid_generate_v4"() not null,
   *   "name" text
   * );
   *
   * create table instruments (
   *   "id" "uuid" primary key default "extensions"."uuid_generate_v4"() not null,
   *   "name" text,
   *   "section_id" "uuid" references public.orchestral_sections on delete cascade
   * );
   *
   * with section as (
   *   insert into orchestral_sections (name)
   *   values ('woodwinds') returning id
   * )
   * insert into instruments (name, section_id) values
   * ('flute', (select id from section)),
   * ('clarinet', (select id from section)),
   * ('bassoon', (select id from section)),
   * ('piccolo', (select id from section));
   * ```
   *
   * @exampleResponse Querying referenced table with inner join
   * ```json
   * {
   *   "data": [
   *     {
   *       "name": "flute",
   *       "orchestral_sections": {"name": "woodwinds"}
   *     }
   *   ],
   *   "status": 200,
   *   "statusText": "OK"
   * }
   * ```
   *
   * @exampleDescription Switching schemas per query
   * In addition to setting the schema during initialization, you can also switch schemas on a per-query basis.
   * Make sure you've set up your [database privileges and API settings](/docs/guides/api/using-custom-schemas).
   *
   * @example Switching schemas per query
   * ```ts
   * const { data, error } = await supabase
   *   .schema('myschema')
   *   .from('mytable')
   *   .select()
   * ```
   *
   * @exampleSql Switching schemas per query
   * ```sql
   * create schema myschema;
   *
   * create table myschema.mytable (
   *   id uuid primary key default gen_random_uuid(),
   *   data text
   * );
   *
   * insert into myschema.mytable (data) values ('mydata');
   * ```
   *
   * @exampleResponse Switching schemas per query
   * ```json
   * {
   *   "data": [
   *     {
   *       "id": "4162e008-27b0-4c0f-82dc-ccaeee9a624d",
   *       "data": "mydata"
   *     }
   *   ],
   *   "status": 200,
   *   "statusText": "OK"
   * }
   * ```
     */
  select(columns, options) {
    const { head: head2 = false, count } = options ?? {};
    const method = head2 ? "HEAD" : "GET";
    let quoted = false;
    const cleanedColumns = (columns ?? "*").split("").map((c) => {
      if (/\s/.test(c) && !quoted) {
        return "";
      }
      if (c === '"') {
        quoted = !quoted;
      }
      return c;
    }).join("");
    const { url, headers } = this.cloneRequestState();
    url.searchParams.set("select", cleanedColumns);
    if (count) {
      headers.append("Prefer", `count=${count}`);
    }
    return new PostgrestFilterBuilder({
      method,
      url,
      headers,
      schema: this.schema,
      fetch: this.fetch,
      urlLengthLimit: this.urlLengthLimit,
      retry: this.retry
    });
  }
  /**
  * Perform an INSERT into the table or view.
  *
  * By default, inserted rows are not returned. To return it, chain the call
  * with `.select()`.
  *
  * @param values - The values to insert. Pass an object to insert a single row
  * or an array to insert multiple rows.
  *
  * @param options - Named parameters
  *
  * @param options.count - Count algorithm to use to count inserted rows.
  *
  * `"exact"`: Exact but slow count algorithm. Performs a `COUNT(*)` under the
  * hood.
  *
  * `"planned"`: Approximated but fast count algorithm. Uses the Postgres
  * statistics under the hood.
  *
  * `"estimated"`: Uses exact count for low numbers and planned count for high
  * numbers.
  *
  * @param options.defaultToNull - Make missing fields default to `null`.
  * Otherwise, use the default value for the column. Only applies for bulk
  * inserts.
  *
  * @category Database
  *
  * @example Create a record
  * ```ts
  * const { error } = await supabase
  *   .from('countries')
  *   .insert({ id: 1, name: 'Mordor' })
  * ```
  *
  * @exampleSql Create a record
  * ```sql
  * create table
  *   countries (id int8 primary key, name text);
  * ```
  *
  * @exampleResponse Create a record
  * ```json
  * {
  *   "status": 201,
  *   "statusText": ""
  * }
  * ```
  *
  * @exampleDescription Handling errors
  * `error.hint` from Postgres often contains the actionable fix (e.g. `"Grant the required privileges to the current role with: GRANT INSERT ON public.countries TO anon;"` for a `42501` permission-denied error). Log the full `error` object so it isn't hidden behind `error.message`.
  *
  * @example Handling errors
  * ```js
  * const { error } = await supabase.from('countries').insert({ id: 1, name: 'Mordor' })
  * if (error) console.error(error)
  * ```
  *
  * @example Create a record and return it
  * ```ts
  * const { data, error } = await supabase
  *   .from('countries')
  *   .insert({ id: 1, name: 'Mordor' })
  *   .select()
  * ```
  *
  * @exampleSql Create a record and return it
  * ```sql
  * create table
  *   countries (id int8 primary key, name text);
  * ```
  *
  * @exampleResponse Create a record and return it
  * ```json
  * {
  *   "data": [
  *     {
  *       "id": 1,
  *       "name": "Mordor"
  *     }
  *   ],
  *   "status": 201,
  *   "statusText": ""
  * }
  * ```
  *
  * @exampleDescription Bulk create
  * A bulk create operation is handled in a single transaction.
  * If any of the inserts fail, none of the rows are inserted.
  *
  * @example Bulk create
  * ```ts
  * const { error } = await supabase
  *   .from('countries')
  *   .insert([
  *     { id: 1, name: 'Mordor' },
  *     { id: 1, name: 'The Shire' },
  *   ])
  * ```
  *
  * @exampleSql Bulk create
  * ```sql
  * create table
  *   countries (id int8 primary key, name text);
  * ```
  *
  * @exampleResponse Bulk create
  * ```json
  * {
  *   "error": {
  *     "code": "23505",
  *     "details": "Key (id)=(1) already exists.",
  *     "hint": null,
  *     "message": "duplicate key value violates unique constraint \"countries_pkey\""
  *   },
  *   "status": 409,
  *   "statusText": ""
  * }
  * ```
  */
  insert(values, { count, defaultToNull = true } = {}) {
    const method = "POST";
    const { url, headers } = this.cloneRequestState();
    if (count) {
      headers.append("Prefer", `count=${count}`);
    }
    if (!defaultToNull) {
      headers.append("Prefer", `missing=default`);
    }
    if (Array.isArray(values)) {
      const columns = values.reduce((acc, x) => acc.concat(Object.keys(x)), []);
      if (columns.length > 0) {
        const uniqueColumns = [
          ...new Set(columns)
        ].map((column) => `"${column}"`);
        url.searchParams.set("columns", uniqueColumns.join(","));
      }
    }
    return new PostgrestFilterBuilder({
      method,
      url,
      headers,
      schema: this.schema,
      body: values,
      fetch: this.fetch ?? fetch,
      urlLengthLimit: this.urlLengthLimit,
      retry: this.retry
    });
  }
  /**
  * Perform an UPSERT on the table or view. Depending on the column(s) passed
  * to `onConflict`, `.upsert()` allows you to perform the equivalent of
  * `.insert()` if a row with the corresponding `onConflict` columns doesn't
  * exist, or if it does exist, perform an alternative action depending on
  * `ignoreDuplicates`.
  *
  * By default, upserted rows are not returned. To return it, chain the call
  * with `.select()`.
  *
  * @param values - The values to upsert with. Pass an object to upsert a
  * single row or an array to upsert multiple rows.
  *
  * @param options - Named parameters
  *
  * @param options.onConflict - Comma-separated UNIQUE column(s) to specify how
  * duplicate rows are determined. Two rows are duplicates if all the
  * `onConflict` columns are equal.
  *
  * @param options.ignoreDuplicates - If `true`, duplicate rows are ignored. If
  * `false`, duplicate rows are merged with existing rows.
  *
  * @param options.count - Count algorithm to use to count upserted rows.
  *
  * `"exact"`: Exact but slow count algorithm. Performs a `COUNT(*)` under the
  * hood.
  *
  * `"planned"`: Approximated but fast count algorithm. Uses the Postgres
  * statistics under the hood.
  *
  * `"estimated"`: Uses exact count for low numbers and planned count for high
  * numbers.
  *
  * @param options.defaultToNull - Make missing fields default to `null`.
  * Otherwise, use the default value for the column. This only applies when
  * inserting new rows, not when merging with existing rows under
  * `ignoreDuplicates: false`. This also only applies when doing bulk upserts.
  *
  * @example Upsert a single row using a unique key
  * ```ts
  * // Upserting a single row, overwriting based on the 'username' unique column
  * const { data, error } = await supabase
  *   .from('users')
  *   .upsert({ username: 'supabot' }, { onConflict: 'username' })
  *
  * // Example response:
  * // {
  * //   data: [
  * //     { id: 4, message: 'bar', username: 'supabot' }
  * //   ],
  * //   error: null
  * // }
  * ```
  *
  * @example Upsert with conflict resolution and exact row counting
  * ```ts
  * // Upserting and returning exact count
  * const { data, error, count } = await supabase
  *   .from('users')
  *   .upsert(
  *     {
  *       id: 3,
  *       message: 'foo',
  *       username: 'supabot'
  *     },
  *     {
  *       onConflict: 'username',
  *       count: 'exact'
  *     }
  *   )
  *
  * // Example response:
  * // {
  * //   data: [
  * //     {
  * //       id: 42,
  * //       handle: "saoirse",
  * //       display_name: "Saoirse"
  * //     }
  * //   ],
  * //   count: 1,
  * //   error: null
  * // }
  * ```
  *
  * @category Database
  *
  * @remarks
  * - Primary keys must be included in `values` to use upsert.
  *
  * @example Upsert your data
  * ```ts
  * const { data, error } = await supabase
  *   .from('instruments')
  *   .upsert({ id: 1, name: 'piano' })
  *   .select()
  * ```
  *
  * @exampleSql Upsert your data
  * ```sql
  * create table
  *   instruments (id int8 primary key, name text);
  *
  * insert into
  *   instruments (id, name)
  * values
  *   (1, 'harpsichord');
  * ```
  *
  * @exampleResponse Upsert your data
  * ```json
  * {
  *   "data": [
  *     {
  *       "id": 1,
  *       "name": "piano"
  *     }
  *   ],
  *   "status": 201,
  *   "statusText": ""
  * }
  * ```
  *
  * @exampleDescription Handling errors
  * `error.hint` from Postgres often contains the actionable fix (e.g. `"Grant the required privileges to the current role with: GRANT INSERT, UPDATE ON public.instruments TO anon;"` for a `42501` permission-denied error). Log the full `error` object so it isn't hidden behind `error.message`.
  *
  * @example Handling errors
  * ```js
  * const { data, error } = await supabase.from('instruments').upsert({ id: 1, name: 'piano' }).select()
  * if (error) console.error(error)
  * ```
  *
  * @example Bulk Upsert your data
  * ```ts
  * const { data, error } = await supabase
  *   .from('instruments')
  *   .upsert([
  *     { id: 1, name: 'piano' },
  *     { id: 2, name: 'harp' },
  *   ])
  *   .select()
  * ```
  *
  * @exampleSql Bulk Upsert your data
  * ```sql
  * create table
  *   instruments (id int8 primary key, name text);
  *
  * insert into
  *   instruments (id, name)
  * values
  *   (1, 'harpsichord');
  * ```
  *
  * @exampleResponse Bulk Upsert your data
  * ```json
  * {
  *   "data": [
  *     {
  *       "id": 1,
  *       "name": "piano"
  *     },
  *     {
  *       "id": 2,
  *       "name": "harp"
  *     }
  *   ],
  *   "status": 201,
  *   "statusText": ""
  * }
  * ```
  *
  * @exampleDescription Upserting into tables with constraints
  * In the following query, `upsert()` implicitly uses the `id`
  * (primary key) column to determine conflicts. If there is no existing
  * row with the same `id`, `upsert()` inserts a new row, which
  * will fail in this case as there is already a row with `handle` `"saoirse"`.
  * Using the `onConflict` option, you can instruct `upsert()` to use
  * another column with a unique constraint to determine conflicts.
  *
  * @example Upserting into tables with constraints
  * ```ts
  * const { data, error } = await supabase
  *   .from('users')
  *   .upsert({ id: 42, handle: 'saoirse', display_name: 'Saoirse' })
  *   .select()
  * ```
  *
  * @exampleSql Upserting into tables with constraints
  * ```sql
  * create table
  *   users (
  *     id int8 generated by default as identity primary key,
  *     handle text not null unique,
  *     display_name text
  *   );
  *
  * insert into
  *   users (id, handle, display_name)
  * values
  *   (1, 'saoirse', null);
  * ```
  *
  * @exampleResponse Upserting into tables with constraints
  * ```json
  * {
  *   "error": {
  *     "code": "23505",
  *     "details": "Key (handle)=(saoirse) already exists.",
  *     "hint": null,
  *     "message": "duplicate key value violates unique constraint \"users_handle_key\""
  *   },
  *   "status": 409,
  *   "statusText": ""
  * }
  * ```
  */
  upsert(values, { onConflict, ignoreDuplicates = false, count, defaultToNull = true } = {}) {
    const method = "POST";
    const { url, headers } = this.cloneRequestState();
    headers.append("Prefer", `resolution=${ignoreDuplicates ? "ignore" : "merge"}-duplicates`);
    if (onConflict !== void 0) url.searchParams.set("on_conflict", onConflict);
    if (count) {
      headers.append("Prefer", `count=${count}`);
    }
    if (!defaultToNull) {
      headers.append("Prefer", "missing=default");
    }
    if (Array.isArray(values)) {
      const columns = values.reduce((acc, x) => acc.concat(Object.keys(x)), []);
      if (columns.length > 0) {
        const uniqueColumns = [
          ...new Set(columns)
        ].map((column) => `"${column}"`);
        url.searchParams.set("columns", uniqueColumns.join(","));
      }
    }
    return new PostgrestFilterBuilder({
      method,
      url,
      headers,
      schema: this.schema,
      body: values,
      fetch: this.fetch ?? fetch,
      urlLengthLimit: this.urlLengthLimit,
      retry: this.retry
    });
  }
  /**
  * Perform an UPDATE on the table or view.
  *
  * By default, updated rows are not returned. To return it, chain the call
  * with `.select()` after filters.
  *
  * @param values - The values to update with
  *
  * @param options - Named parameters
  *
  * @param options.count - Count algorithm to use to count updated rows.
  *
  * `"exact"`: Exact but slow count algorithm. Performs a `COUNT(*)` under the
  * hood.
  *
  * `"planned"`: Approximated but fast count algorithm. Uses the Postgres
  * statistics under the hood.
  *
  * `"estimated"`: Uses exact count for low numbers and planned count for high
  * numbers.
  *
  * @category Database
  *
  * @remarks
  * - `update()` should always be combined with [Filters](/docs/reference/javascript/using-filters) to target the item(s) you wish to update.
  *
  * @example Updating your data
  * ```ts
  * const { error } = await supabase
  *   .from('instruments')
  *   .update({ name: 'piano' })
  *   .eq('id', 1)
  * ```
  *
  * @exampleSql Updating your data
  * ```sql
  * create table
  *   instruments (id int8 primary key, name text);
  *
  * insert into
  *   instruments (id, name)
  * values
  *   (1, 'harpsichord');
  * ```
  *
  * @exampleResponse Updating your data
  * ```json
  * {
  *   "status": 204,
  *   "statusText": ""
  * }
  * ```
  *
  * @exampleDescription Handling errors
  * `error.hint` from Postgres often contains the actionable fix (e.g. `"Grant the required privileges to the current role with: GRANT UPDATE ON public.instruments TO anon;"` for a `42501` permission-denied error). Log the full `error` object so it isn't hidden behind `error.message`.
  *
  * @example Handling errors
  * ```js
  * const { error } = await supabase.from('instruments').update({ name: 'piano' }).eq('id', 1)
  * if (error) console.error(error)
  * ```
  *
  * @example Update a record and return it
  * ```ts
  * const { data, error } = await supabase
  *   .from('instruments')
  *   .update({ name: 'piano' })
  *   .eq('id', 1)
  *   .select()
  * ```
  *
  * @exampleSql Update a record and return it
  * ```sql
  * create table
  *   instruments (id int8 primary key, name text);
  *
  * insert into
  *   instruments (id, name)
  * values
  *   (1, 'harpsichord');
  * ```
  *
  * @exampleResponse Update a record and return it
  * ```json
  * {
  *   "data": [
  *     {
  *       "id": 1,
  *       "name": "piano"
  *     }
  *   ],
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  *
  * @exampleDescription Updating JSON data
  * Postgres offers some
  * [operators](/docs/guides/database/json#query-the-jsonb-data) for
  * working with JSON data. Currently, it is only possible to update the entire JSON document.
  *
  * @example Updating JSON data
  * ```ts
  * const { data, error } = await supabase
  *   .from('users')
  *   .update({
  *     address: {
  *       street: 'Melrose Place',
  *       postcode: 90210
  *     }
  *   })
  *   .eq('address->postcode', 90210)
  *   .select()
  * ```
  *
  * @exampleSql Updating JSON data
  * ```sql
  * create table
  *   users (
  *     id int8 primary key,
  *     name text,
  *     address jsonb
  *   );
  *
  * insert into
  *   users (id, name, address)
  * values
  *   (1, 'Michael', '{ "postcode": 90210 }');
  * ```
  *
  * @exampleResponse Updating JSON data
  * ```json
  * {
  *   "data": [
  *     {
  *       "id": 1,
  *       "name": "Michael",
  *       "address": {
  *         "street": "Melrose Place",
  *         "postcode": 90210
  *       }
  *     }
  *   ],
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  */
  update(values, { count } = {}) {
    const method = "PATCH";
    const { url, headers } = this.cloneRequestState();
    if (count) {
      headers.append("Prefer", `count=${count}`);
    }
    return new PostgrestFilterBuilder({
      method,
      url,
      headers,
      schema: this.schema,
      body: values,
      fetch: this.fetch ?? fetch,
      urlLengthLimit: this.urlLengthLimit,
      retry: this.retry
    });
  }
  /**
  * Perform a DELETE on the table or view.
  *
  * By default, deleted rows are not returned. To return it, chain the call
  * with `.select()` after filters.
  *
  * @param options - Named parameters
  *
  * @param options.count - Count algorithm to use to count deleted rows.
  *
  * `"exact"`: Exact but slow count algorithm. Performs a `COUNT(*)` under the
  * hood.
  *
  * `"planned"`: Approximated but fast count algorithm. Uses the Postgres
  * statistics under the hood.
  *
  * `"estimated"`: Uses exact count for low numbers and planned count for high
  * numbers.
  *
  * @category Database
  *
  * @remarks
  * - `delete()` should always be combined with [filters](/docs/reference/javascript/using-filters) to target the item(s) you wish to delete.
  * - If you use `delete()` with filters and you have
  *   [RLS](/docs/learn/auth-deep-dive/auth-row-level-security) enabled, only
  *   rows visible through `SELECT` policies are deleted. Note that by default
  *   no rows are visible, so you need at least one `SELECT`/`ALL` policy that
  *   makes the rows visible.
  * - When using `delete().in()`, specify an array of values to target multiple rows with a single query. This is particularly useful for batch deleting entries that share common criteria, such as deleting users by their IDs. Ensure that the array you provide accurately represents all records you intend to delete to avoid unintended data removal.
  *
  * @example Delete a single record
  * ```ts
  * const response = await supabase
  *   .from('countries')
  *   .delete()
  *   .eq('id', 1)
  * ```
  *
  * @exampleSql Delete a single record
  * ```sql
  * create table
  *   countries (id int8 primary key, name text);
  *
  * insert into
  *   countries (id, name)
  * values
  *   (1, 'Mordor');
  * ```
  *
  * @exampleResponse Delete a single record
  * ```json
  * {
  *   "status": 204,
  *   "statusText": ""
  * }
  * ```
  *
  * @exampleDescription Handling errors
  * `error.hint` from Postgres often contains the actionable fix (e.g. `"Grant the required privileges to the current role with: GRANT DELETE ON public.countries TO anon;"` for a `42501` permission-denied error). Log the full `error` object so it isn't hidden behind `error.message`.
  *
  * @example Handling errors
  * ```js
  * const { error } = await supabase.from('countries').delete().eq('id', 1)
  * if (error) console.error(error)
  * ```
  *
  * @example Delete a record and return it
  * ```ts
  * const { data, error } = await supabase
  *   .from('countries')
  *   .delete()
  *   .eq('id', 1)
  *   .select()
  * ```
  *
  * @exampleSql Delete a record and return it
  * ```sql
  * create table
  *   countries (id int8 primary key, name text);
  *
  * insert into
  *   countries (id, name)
  * values
  *   (1, 'Mordor');
  * ```
  *
  * @exampleResponse Delete a record and return it
  * ```json
  * {
  *   "data": [
  *     {
  *       "id": 1,
  *       "name": "Mordor"
  *     }
  *   ],
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  *
  * @example Delete multiple records
  * ```ts
  * const response = await supabase
  *   .from('countries')
  *   .delete()
  *   .in('id', [1, 2, 3])
  * ```
  *
  * @exampleSql Delete multiple records
  * ```sql
  * create table
  *   countries (id int8 primary key, name text);
  *
  * insert into
  *   countries (id, name)
  * values
  *   (1, 'Rohan'), (2, 'The Shire'), (3, 'Mordor');
  * ```
  *
  * @exampleResponse Delete multiple records
  * ```json
  * {
  *   "status": 204,
  *   "statusText": ""
  * }
  * ```
  */
  delete({ count } = {}) {
    const method = "DELETE";
    const { url, headers } = this.cloneRequestState();
    if (count) {
      headers.append("Prefer", `count=${count}`);
    }
    return new PostgrestFilterBuilder({
      method,
      url,
      headers,
      schema: this.schema,
      fetch: this.fetch ?? fetch,
      urlLengthLimit: this.urlLengthLimit,
      retry: this.retry
    });
  }
};

// src/vendor/postgrest/PostgrestClient.ts
var PostgrestClient = class _PostgrestClient {
  static {
    __name(this, "PostgrestClient");
  }
  url;
  headers;
  schemaName;
  fetch;
  urlLengthLimit;
  // Retry configuration - enabled by default
  retry;
  // TODO: Add back shouldThrowOnError once we figure out the typings
  /**
  * Creates a PostgREST client.
  *
  * @param url - URL of the PostgREST endpoint
  * @param options - Named parameters
  * @param options.headers - Custom headers
  * @param options.schema - Postgres schema to switch to
  * @param options.fetch - Custom fetch
  * @param options.timeout - Optional timeout in milliseconds for all requests. When set, requests will automatically abort after this duration to prevent indefinite hangs.
  * @param options.urlLengthLimit - Maximum URL length in characters before warnings/errors are triggered. Defaults to 8000.
  * @param options.retry - Enable or disable automatic retries for transient errors.
  *   When enabled, idempotent requests (GET, HEAD, OPTIONS) that fail with network
  *   errors or HTTP 503/520 responses will be automatically retried up to 3 times
  *   with exponential backoff (1s, 2s, 4s). Defaults to `true`.
  * @example Using supabase-js (recommended)
  * ```ts
  * import { createClient } from '@supabase/supabase-js'
  *
  * const supabase = createClient('https://xyzcompany.supabase.co', 'your-publishable-key')
  * const { data, error } = await supabase.from('profiles').select('*')
  * ```
  *
  * @category Database
  *
  * @remarks
  * - A `timeout` option (in milliseconds) can be set to automatically abort requests that take too long.
  * - A `urlLengthLimit` option (default: 8000) can be set to control when URL length warnings are included in error messages for aborted requests.
  *
  * @example Standalone import for bundle-sensitive environments
  * ```ts
  * import { PostgrestClient } from '@supabase/postgrest-js'
  *
  * const postgrest = new PostgrestClient('https://xyzcompany.supabase.co/rest/v1', {
  *   headers: { apikey: 'your-publishable-key' },
  *   schema: 'public',
  *   timeout: 30000, // 30 second timeout
  * })
  * ```
  */
  constructor(url, { headers = {}, schema, fetch: fetch1, timeout, urlLengthLimit = 8e3, retry } = {}) {
    this.url = url;
    this.headers = new Headers(headers);
    this.schemaName = schema;
    this.urlLengthLimit = urlLengthLimit;
    const originalFetch = fetch1 ?? globalThis.fetch;
    if (timeout !== void 0 && timeout > 0) {
      this.fetch = (input, init) => {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), timeout);
        const existingSignal = init?.signal;
        if (existingSignal) {
          if (existingSignal.aborted) {
            clearTimeout(timeoutId);
            return originalFetch(input, init);
          }
          const abortHandler = /* @__PURE__ */ __name(() => {
            clearTimeout(timeoutId);
            controller.abort();
          }, "abortHandler");
          existingSignal.addEventListener("abort", abortHandler, {
            once: true
          });
          return originalFetch(input, {
            ...init,
            signal: controller.signal
          }).finally(() => {
            clearTimeout(timeoutId);
            existingSignal.removeEventListener("abort", abortHandler);
          });
        }
        return originalFetch(input, {
          ...init,
          signal: controller.signal
        }).finally(() => clearTimeout(timeoutId));
      };
    } else {
      this.fetch = originalFetch;
    }
    this.retry = retry;
  }
  from(relation) {
    if (!relation || typeof relation !== "string" || relation.trim() === "") {
      throw new Error("Invalid relation name: relation must be a non-empty string.");
    }
    const url = new URL(`${this.url}/${relation}`);
    return new PostgrestQueryBuilder(url, {
      headers: new Headers(this.headers),
      schema: this.schemaName,
      fetch: this.fetch,
      urlLengthLimit: this.urlLengthLimit,
      retry: this.retry
    });
  }
  /**
  * Select a schema to query or perform an function (rpc) call.
  *
  * The schema needs to be on the list of exposed schemas inside Supabase.
  *
  * @param schema - The schema to query
  *
  * @category Database
  */
  schema(schema) {
    return new _PostgrestClient(this.url, {
      headers: this.headers,
      schema,
      fetch: this.fetch,
      urlLengthLimit: this.urlLengthLimit,
      retry: this.retry
    });
  }
  /**
  * Perform a function call.
  *
  * @param fn - The function name to call
  * @param args - The arguments to pass to the function call
  * @param options - Named parameters
  * @param options.head - When set to `true`, `data` will not be returned.
  * Useful if you only need the count.
  * @param options.get - When set to `true`, the function will be called with
  * read-only access mode.
  * @param options.count - Count algorithm to use to count rows returned by the
  * function. Only applicable for [set-returning
  * functions](https://www.postgresql.org/docs/current/functions-srf.html).
  *
  * `"exact"`: Exact but slow count algorithm. Performs a `COUNT(*)` under the
  * hood.
  *
  * `"planned"`: Approximated but fast count algorithm. Uses the Postgres
  * statistics under the hood.
  *
  * `"estimated"`: Uses exact count for low numbers and planned count for high
  * numbers.
  *
  * @example
  * ```ts
  * // For cross-schema functions where type inference fails, use overrideTypes:
  * const { data } = await supabase
  *   .schema('schema_b')
  *   .rpc('function_a', {})
  *   .overrideTypes<{ id: string; user_id: string }[]>()
  * ```
  *
  * @category Database
  *
  * @example Call a Postgres function without arguments
  * ```ts
  * const { data, error } = await supabase.rpc('hello_world')
  * ```
  *
  * @exampleSql Call a Postgres function without arguments
  * ```sql
  * create function hello_world() returns text as $$
  *   select 'Hello world';
  * $$ language sql;
  * ```
  *
  * @exampleResponse Call a Postgres function without arguments
  * ```json
  * {
  *   "data": "Hello world",
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  *
  * @example Call a Postgres function with arguments
  * ```ts
  * const { data, error } = await supabase.rpc('echo', { say: '👋' })
  * ```
  *
  * @exampleSql Call a Postgres function with arguments
  * ```sql
  * create function echo(say text) returns text as $$
  *   select say;
  * $$ language sql;
  * ```
  *
  * @exampleResponse Call a Postgres function with arguments
  * ```json
  *   {
  *     "data": "👋",
  *     "status": 200,
  *     "statusText": "OK"
  *   }
  *
  * ```
  *
  * @exampleDescription Bulk processing
  * You can process large payloads by passing in an array as an argument.
  *
  * @example Bulk processing
  * ```ts
  * const { data, error } = await supabase.rpc('add_one_each', { arr: [1, 2, 3] })
  * ```
  *
  * @exampleSql Bulk processing
  * ```sql
  * create function add_one_each(arr int[]) returns int[] as $$
  *   select array_agg(n + 1) from unnest(arr) as n;
  * $$ language sql;
  * ```
  *
  * @exampleResponse Bulk processing
  * ```json
  * {
  *   "data": [
  *     2,
  *     3,
  *     4
  *   ],
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  *
  * @exampleDescription Call a Postgres function with filters
  * Postgres functions that return tables can also be combined with [Filters](/docs/reference/javascript/using-filters) and [Modifiers](/docs/reference/javascript/using-modifiers).
  *
  * @example Call a Postgres function with filters
  * ```ts
  * const { data, error } = await supabase
  *   .rpc('list_stored_countries')
  *   .eq('id', 1)
  *   .single()
  * ```
  *
  * @exampleSql Call a Postgres function with filters
  * ```sql
  * create table
  *   countries (id int8 primary key, name text);
  *
  * insert into
  *   countries (id, name)
  * values
  *   (1, 'Rohan'),
  *   (2, 'The Shire');
  *
  * create function list_stored_countries() returns setof countries as $$
  *   select * from countries;
  * $$ language sql;
  * ```
  *
  * @exampleResponse Call a Postgres function with filters
  * ```json
  * {
  *   "data": {
  *     "id": 1,
  *     "name": "Rohan"
  *   },
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  *
  * @example Call a read-only Postgres function
  * ```ts
  * const { data, error } = await supabase.rpc('hello_world', undefined, { get: true })
  * ```
  *
  * @exampleSql Call a read-only Postgres function
  * ```sql
  * create function hello_world() returns text as $$
  *   select 'Hello world';
  * $$ language sql;
  * ```
  *
  * @exampleResponse Call a read-only Postgres function
  * ```json
  * {
  *   "data": "Hello world",
  *   "status": 200,
  *   "statusText": "OK"
  * }
  * ```
  */
  rpc(fn, args = {}, { head: head2 = false, get: get2 = false, count } = {}) {
    let method;
    const url = new URL(`${this.url}/rpc/${fn}`);
    let body;
    const _isObject = /* @__PURE__ */ __name((v) => v !== null && typeof v === "object" && (!Array.isArray(v) || v.some(_isObject)), "_isObject");
    const _hasObjectArg = head2 && Object.values(args).some(_isObject);
    if (_hasObjectArg) {
      method = "POST";
      body = args;
    } else if (head2 || get2) {
      method = head2 ? "HEAD" : "GET";
      Object.entries(args).filter(([_, value]) => value !== void 0).map(([name, value]) => [
        name,
        Array.isArray(value) ? `{${value.join(",")}}` : `${value}`
      ]).forEach(([name, value]) => {
        url.searchParams.append(name, value);
      });
    } else {
      method = "POST";
      body = args;
    }
    const headers = new Headers(this.headers);
    if (_hasObjectArg) {
      headers.set("Prefer", count ? `count=${count},return=minimal` : "return=minimal");
    } else if (count) {
      headers.set("Prefer", `count=${count}`);
    }
    return new PostgrestFilterBuilder({
      method,
      url,
      headers,
      schema: this.schemaName,
      body,
      fetch: this.fetch ?? fetch,
      urlLengthLimit: this.urlLengthLimit,
      retry: this.retry
    });
  }
};

// src/modules/database.ts
var WorkBuddyDatabaseModule = class {
  static {
    __name(this, "WorkBuddyDatabaseModule");
  }
  /**
   * 底层 PostgREST 客户端。刻意保持 private —— 对外只暴露 `from` / `rpc`，
   * 不让 vendor 客户端（及其 `.schema()` 等入口）泄漏到应用。
   */
  client;
  constructor(config, fetch2) {
    this.client = new PostgrestClient(`${config.endpoint}${CLOUD_MODULE_PATHS.database}`, {
      fetch: fetch2
    });
    this.from = this.client.from.bind(this.client);
    this.rpc = this.client.rpc.bind(this.client);
  }
  /**
   * 在一张表或视图上发起查询。返回值即 supabase-js 的查询构造器，
   * 支持 `select/insert/upsert/update/delete` 及全部 filter/transform 链，
   * `await` 得到 `{ data, error }`。语义与 supabase-js `.from()` 一致。
   *
   * 只放行 public schema —— 不提供 `.schema()` 切换（数据面会拒系统 schema）。
   */
  from;
  /**
   * 调用一个 PostgreSQL 函数（RPC）。语义同 supabase-js `.rpc()`：
   * 返回可继续 `.select()/.order()/.limit()` 的构造器（集合返回型函数）。
   */
  rpc;
  /**
   * 归一化后的数据面基址（`/.cloud/database/rest`，无尾斜杠）。
   * 仅用于诊断/契约测试；应用不应据此手拼请求。
   */
  get url() {
    return this.client.url;
  }
};
function createDatabaseModule(config, fetch2) {
  return new WorkBuddyDatabaseModule(config, fetch2);
}
__name(createDatabaseModule, "createDatabaseModule");

// src/modules/llm/errors.ts
var CloudOpenAIError = class extends Error {
  static {
    __name(this, "CloudOpenAIError");
  }
  error;
  status;
  requestId;
  retryAfterMs;
  constructor(error, init = {}) {
    const errorObj = typeof error === "string" ? {
      message: error,
      type: "server_error",
      param: null,
      code: null
    } : error;
    super(errorObj.message);
    this.name = "CloudOpenAIError";
    this.error = errorObj;
    this.status = init.status;
    this.requestId = init.requestId;
    this.retryAfterMs = init.retryAfterMs;
    if (init.cause !== void 0) {
      if (!("cause" in this)) {
        Object.defineProperty(this, "cause", {
          value: init.cause,
          writable: false,
          enumerable: false,
          configurable: false
        });
      }
    }
  }
};
function parseRetryAfter(headerValue) {
  if (!headerValue) return void 0;
  const trimmed = headerValue.trim();
  const asNum = Number(trimmed);
  if (!isNaN(asNum) && asNum >= 0 && Number.isInteger(asNum)) {
    return asNum * 1e3;
  }
  const asDate = Date.parse(trimmed);
  if (!isNaN(asDate)) {
    const diff = asDate - Date.now();
    return diff > 0 ? diff : 0;
  }
  return void 0;
}
__name(parseRetryAfter, "parseRetryAfter");

// src/modules/llm/models.ts
function stringField(...values) {
  return values.find((value) => typeof value === "string" && value.length > 0);
}
__name(stringField, "stringField");
function numberField(...values) {
  return values.find((value) => typeof value === "number" && Number.isFinite(value));
}
__name(numberField, "numberField");
function booleanField(...values) {
  return values.find((value) => typeof value === "boolean");
}
__name(booleanField, "booleanField");
function contextWindowField(...values) {
  for (const value of values) {
    if (typeof value === "number" && Number.isFinite(value)) {
      return value;
    }
    if (value !== null && typeof value === "object" && !Array.isArray(value)) {
      return normalizeContextWindowObject(value);
    }
  }
  return void 0;
}
__name(contextWindowField, "contextWindowField");
function normalizeContextWindowObject(raw) {
  const result = {};
  for (const [key, value] of Object.entries(raw)) {
    if (key === "supportedLengths") {
      if (Array.isArray(value)) {
        result.supportedLengths = value.filter((item) => typeof item === "number" && Number.isFinite(item));
      }
      continue;
    }
    if (key === "defaultLength") {
      if (typeof value === "number" && Number.isFinite(value)) {
        result.defaultLength = value;
      }
      continue;
    }
    Object.defineProperty(result, key, {
      value,
      writable: true,
      enumerable: true,
      configurable: true
    });
  }
  return result;
}
__name(normalizeContextWindowObject, "normalizeContextWindowObject");
function modalitiesField(value) {
  if (!value || typeof value !== "object") return void 0;
  const raw = value;
  const input = Array.isArray(raw.input) ? raw.input.filter((item) => typeof item === "string") : void 0;
  const output = Array.isArray(raw.output) ? raw.output.filter((item) => typeof item === "string") : void 0;
  return input?.length || output?.length ? {
    ...input?.length ? {
      input
    } : {},
    ...output?.length ? {
      output
    } : {}
  } : void 0;
}
__name(modalitiesField, "modalitiesField");
function capabilitiesField(value) {
  if (!value || typeof value !== "object") return void 0;
  const raw = value;
  const entries = Object.entries(raw).filter(([, enabled]) => typeof enabled === "boolean");
  return entries.length ? Object.fromEntries(entries) : void 0;
}
__name(capabilitiesField, "capabilitiesField");
function pricingField(value) {
  if (!value || typeof value !== "object") return void 0;
  const raw = value;
  const pricing = {
    ...stringField(raw.currency) ? {
      currency: raw.currency
    } : {},
    ...numberField(raw.inputPerMillionTokens) !== void 0 ? {
      inputPerMillionTokens: raw.inputPerMillionTokens
    } : {},
    ...numberField(raw.outputPerMillionTokens) !== void 0 ? {
      outputPerMillionTokens: raw.outputPerMillionTokens
    } : {},
    ...stringField(raw.displayText) ? {
      displayText: raw.displayText
    } : {}
  };
  return Object.keys(pricing).length ? pricing : void 0;
}
__name(pricingField, "pricingField");
function reasoningField(value) {
  if (!value || typeof value !== "object") return void 0;
  const raw = value;
  const result = {};
  const effort = stringField(raw.effort);
  if (effort !== void 0) result.effort = effort;
  const defaultEffort = stringField(raw.defaultEffort);
  if (defaultEffort !== void 0) result.defaultEffort = defaultEffort;
  if (Array.isArray(raw.supportedEfforts)) {
    result.supportedEfforts = raw.supportedEfforts.filter((item) => typeof item === "string");
  }
  const rawSummary = stringField(raw.summary);
  if (rawSummary !== void 0 && (rawSummary === "auto" || rawSummary === "concise" || rawSummary === "detailed")) {
    result.summary = rawSummary;
  }
  const canDisable = booleanField(raw.canDisableThinking);
  if (canDisable !== void 0) result.canDisableThinking = canDisable;
  return Object.keys(result).length > 0 ? result : void 0;
}
__name(reasoningField, "reasoningField");
function normalizeModel(raw) {
  const id = stringField(raw.id, raw.ID);
  if (!id) return null;
  const serverEnabled = booleanField(raw.enabled, raw.Enabled);
  const serverDisabled = booleanField(raw.disabled, raw.Disabled);
  let enabled;
  let disabled;
  if (serverEnabled !== void 0) {
    enabled = serverEnabled;
    if (serverDisabled !== void 0) disabled = serverDisabled;
  } else if (serverDisabled !== void 0) {
    disabled = serverDisabled;
    enabled = !serverDisabled;
  } else {
    enabled = true;
  }
  return {
    id,
    name: stringField(raw.name, raw.Name) ?? id,
    ...stringField(raw.provider, raw.Provider) ? {
      provider: stringField(raw.provider, raw.Provider)
    } : {},
    ...stringField(raw.vendor, raw.Vendor) ? {
      vendor: stringField(raw.vendor, raw.Vendor)
    } : {},
    ...stringField(raw.family, raw.Family) ? {
      family: stringField(raw.family, raw.Family)
    } : {},
    ...stringField(raw.version, raw.Version) ? {
      version: stringField(raw.version, raw.Version)
    } : {},
    ...stringField(raw.description, raw.Description) ? {
      description: stringField(raw.description, raw.Description)
    } : {},
    ...stringField(raw.descriptionZh, raw.DescriptionZh) ? {
      descriptionZh: stringField(raw.descriptionZh, raw.DescriptionZh)
    } : {},
    ...stringField(raw.descriptionEn, raw.DescriptionEn) ? {
      descriptionEn: stringField(raw.descriptionEn, raw.DescriptionEn)
    } : {},
    ...stringField(raw.iconUrl, raw.IconURL) ? {
      iconUrl: stringField(raw.iconUrl, raw.IconURL)
    } : {},
    ...contextWindowField(raw.contextWindow, raw.ContextWindow) !== void 0 ? {
      contextWindow: contextWindowField(raw.contextWindow, raw.ContextWindow)
    } : {},
    ...numberField(raw.maxInputTokens, raw.MaxInputTokens) !== void 0 ? {
      maxInputTokens: numberField(raw.maxInputTokens, raw.MaxInputTokens)
    } : {},
    ...numberField(raw.maxOutputTokens, raw.MaxOutputTokens) !== void 0 ? {
      maxOutputTokens: numberField(raw.maxOutputTokens, raw.MaxOutputTokens)
    } : {},
    ...modalitiesField(raw.modalities ?? raw.Modalities) ? {
      modalities: modalitiesField(raw.modalities ?? raw.Modalities)
    } : {},
    ...capabilitiesField(raw.capabilities ?? raw.Capabilities) ? {
      capabilities: capabilitiesField(raw.capabilities ?? raw.Capabilities)
    } : {},
    enabled,
    ...disabled !== void 0 ? {
      disabled
    } : {},
    ...booleanField(raw.isDefault, raw.IsDefault) !== void 0 ? {
      isDefault: booleanField(raw.isDefault, raw.IsDefault)
    } : {},
    ...numberField(raw.sortOrder, raw.SortOrder) !== void 0 ? {
      sortOrder: numberField(raw.sortOrder, raw.SortOrder)
    } : {},
    ...pricingField(raw.pricing ?? raw.Pricing) ? {
      pricing: pricingField(raw.pricing ?? raw.Pricing)
    } : {},
    // User-specified sparse fields: preserve explicit false/0, omit only when absent.
    ...stringField(raw.credits, raw.Credits) ? {
      credits: stringField(raw.credits, raw.Credits)
    } : {},
    ...numberField(raw.maxAllowedSize, raw.MaxAllowedSize) !== void 0 ? {
      maxAllowedSize: numberField(raw.maxAllowedSize, raw.MaxAllowedSize)
    } : {},
    ...booleanField(raw.disabledMultimodal, raw.DisabledMultimodal) !== void 0 ? {
      disabledMultimodal: booleanField(raw.disabledMultimodal, raw.DisabledMultimodal)
    } : {},
    ...booleanField(raw.supportsImages, raw.SupportsImages) !== void 0 ? {
      supportsImages: booleanField(raw.supportsImages, raw.SupportsImages)
    } : {},
    ...booleanField(raw.supportsToolCall, raw.SupportsToolCall) !== void 0 ? {
      supportsToolCall: booleanField(raw.supportsToolCall, raw.SupportsToolCall)
    } : {},
    ...booleanField(raw.supportsReasoning, raw.SupportsReasoning) !== void 0 ? {
      supportsReasoning: booleanField(raw.supportsReasoning, raw.SupportsReasoning)
    } : {},
    ...booleanField(raw.onlyReasoning, raw.OnlyReasoning) !== void 0 ? {
      onlyReasoning: booleanField(raw.onlyReasoning, raw.OnlyReasoning)
    } : {},
    ...reasoningField(raw.reasoning ?? raw.Reasoning) ? {
      reasoning: reasoningField(raw.reasoning ?? raw.Reasoning)
    } : {},
    ...numberField(raw.temperature, raw.Temperature) !== void 0 ? {
      temperature: numberField(raw.temperature, raw.Temperature)
    } : {},
    ...numberField(raw.top_k, raw.Top_K) !== void 0 ? {
      top_k: numberField(raw.top_k, raw.Top_K)
    } : {},
    ...numberField(raw.top_p, raw.Top_P) !== void 0 ? {
      top_p: numberField(raw.top_p, raw.Top_P)
    } : {},
    ...numberField(raw.repetition_penalty, raw.Repetition_Penalty) !== void 0 ? {
      repetition_penalty: numberField(raw.repetition_penalty, raw.Repetition_Penalty)
    } : {}
  };
}
__name(normalizeModel, "normalizeModel");
function getModelDisplayName(model) {
  return model.name || model.id;
}
__name(getModelDisplayName, "getModelDisplayName");
function getModelCapability(model, capability) {
  return model.capabilities?.[capability];
}
__name(getModelCapability, "getModelCapability");
var ModelsAPI = class {
  static {
    __name(this, "ModelsAPI");
  }
  baseUrl;
  fetch;
  constructor(baseUrl, fetch2) {
    this.baseUrl = baseUrl;
    this.fetch = fetch2;
  }
  /**
   * List the browser-safe public model directory for this application.
   *
   * `id` is the value to pass as `model` to `chat.completions.create()`.
   * Optional metadata is included only when the server explicitly provides
   * it; absence means unknown, not unsupported. The actual call result
   * is determined by the response, not by the directory entry.
   */
  async list(signal) {
    let response;
    try {
      response = await this.fetch(`${this.baseUrl}/models`, {
        method: "GET",
        headers: {
          Accept: "application/json"
        },
        signal
      });
    } catch (err) {
      if (err instanceof Error && err.name === "AbortError") {
        throw err;
      }
      throw new CloudOpenAIError({
        message: `Network error: ${err?.message ?? "unknown"}`,
        type: "server_error",
        param: null,
        code: "gateway_network_error"
      }, {
        cause: err
      });
    }
    if (!response.ok) {
      throw await httpError(response);
    }
    const text = await response.text();
    let parsed;
    try {
      parsed = JSON.parse(text);
    } catch {
      throw new CloudOpenAIError({
        message: "Failed to parse models response: invalid JSON",
        type: "server_error",
        param: null,
        code: "gateway_invalid_response"
      });
    }
    const rawModels = Array.isArray(parsed) ? parsed : Array.isArray(parsed?.data) ? parsed.data : [];
    const models = [];
    for (const raw of rawModels) {
      const normalized = normalizeModel(raw);
      if (normalized) models.push(normalized);
    }
    return models;
  }
};
async function httpError(response) {
  const text = await response.text().catch(() => "");
  let errorObj;
  try {
    const parsed = JSON.parse(text);
    if (parsed && typeof parsed === "object" && parsed.error) {
      const e = parsed.error;
      errorObj = {
        message: typeof e.message === "string" ? e.message : `HTTP ${response.status}`,
        type: typeof e.type === "string" ? e.type : "server_error",
        param: e.param === void 0 ? null : e.param,
        code: e.code === void 0 ? null : e.code
      };
    } else {
      errorObj = {
        message: typeof parsed === "string" ? parsed : `HTTP ${response.status}`,
        type: "server_error",
        param: null,
        code: null
      };
    }
  } catch {
    errorObj = {
      message: text || `HTTP ${response.status}`,
      type: "server_error",
      param: null,
      code: null
    };
  }
  const requestId = response.headers.get("x-request-id") ?? void 0;
  const retryAfterMs = parseRetryAfter(response.headers.get("retry-after"));
  return new CloudOpenAIError(errorObj, {
    status: response.status,
    requestId,
    retryAfterMs
  });
}
__name(httpError, "httpError");

// src/modules/llm/utf8-decoder.ts
var Utf8Decoder = class {
  static {
    __name(this, "Utf8Decoder");
  }
  codePoint = 0;
  bytesNeeded = 0;
  bytesSeen = 0;
  lowerBoundary = 128;
  upperBoundary = 191;
  bomSeen = false;
  streaming = false;
  resetSequence() {
    this.codePoint = 0;
    this.bytesNeeded = 0;
    this.bytesSeen = 0;
    this.lowerBoundary = 128;
    this.upperBoundary = 191;
  }
  decode(input = new Uint8Array(), options = {}) {
    if (!this.streaming) {
      this.resetSequence();
      this.bomSeen = false;
    }
    this.streaming = options.stream === true;
    let output = "";
    const emit = /* @__PURE__ */ __name((codePoint) => {
      if (!this.bomSeen) {
        this.bomSeen = true;
        if (codePoint === 65279) return;
      }
      output += String.fromCodePoint(codePoint);
    }, "emit");
    for (let i = 0; i < input.length; i++) {
      const byte = input[i];
      if (this.bytesNeeded === 0) {
        if (byte <= 127) {
          emit(byte);
        } else if (byte >= 194 && byte <= 223) {
          this.bytesNeeded = 1;
          this.codePoint = byte & 31;
        } else if (byte >= 224 && byte <= 239) {
          this.bytesNeeded = 2;
          this.codePoint = byte & 15;
          if (byte === 224) this.lowerBoundary = 160;
          if (byte === 237) this.upperBoundary = 159;
        } else if (byte >= 240 && byte <= 244) {
          this.bytesNeeded = 3;
          this.codePoint = byte & 7;
          if (byte === 240) this.lowerBoundary = 144;
          if (byte === 244) this.upperBoundary = 143;
        } else {
          emit(65533);
        }
        continue;
      }
      if (byte < this.lowerBoundary || byte > this.upperBoundary) {
        this.resetSequence();
        emit(65533);
        i--;
        continue;
      }
      this.lowerBoundary = 128;
      this.upperBoundary = 191;
      this.codePoint = this.codePoint << 6 | byte & 63;
      this.bytesSeen++;
      if (this.bytesSeen === this.bytesNeeded) {
        emit(this.codePoint);
        this.resetSequence();
      }
    }
    if (!this.streaming && this.bytesNeeded > 0) {
      emit(65533);
      this.resetSequence();
    }
    return output;
  }
};

// src/modules/llm/sse.ts
var SSEDecoder = class SSEDecoder2 {
  static {
    __name(this, "SSEDecoder");
  }
  event = null;
  dataParts = [];
  /**
   * Feed a single line. Returns an SSEEvent when the current event is
   * terminated (i.e. when an empty line is received), or null otherwise.
   */
  decode(line) {
    let l = line;
    if (l.endsWith("\r")) {
      l = l.slice(0, -1);
    }
    if (l === "") {
      if (this.event === null && this.dataParts.length === 0) {
        return null;
      }
      const ev = {
        event: this.event,
        data: this.dataParts.join("\n")
      };
      this.event = null;
      this.dataParts = [];
      return ev;
    }
    if (l.startsWith(":")) {
      return null;
    }
    const colonIdx = l.indexOf(":");
    let field;
    let value;
    if (colonIdx === -1) {
      field = l;
      value = "";
    } else {
      field = l.slice(0, colonIdx);
      let rest = l.slice(colonIdx + 1);
      if (rest.startsWith(" ")) {
        rest = rest.slice(1);
      }
      value = rest;
    }
    if (field === "event") {
      this.event = value;
    } else if (field === "data") {
      this.dataParts.push(value);
    }
    return null;
  }
  /** Flush any remaining buffered data as a final event. */
  flush() {
    if (this.event === null && this.dataParts.length === 0) {
      return null;
    }
    const ev = {
      event: this.event,
      data: this.dataParts.join("\n")
    };
    this.event = null;
    this.dataParts = [];
    return ev;
  }
};
var LineDecoder = class LineDecoder2 {
  static {
    __name(this, "LineDecoder");
  }
  buffer = new Uint8Array();
  decoder;
  constructor() {
    this.decoder = typeof TextDecoder === "undefined" ? new Utf8Decoder() : new TextDecoder("utf-8");
  }
  /**
   * Decode a chunk and yield complete lines.
   *
   * Lines are terminated by \n, \r, or \r\n. The line terminators are
   * NOT included in the returned strings.
   */
  decode(chunk) {
    const newData = new Uint8Array(this.buffer.length + chunk.length);
    newData.set(this.buffer);
    newData.set(chunk, this.buffer.length);
    this.buffer = newData;
    const lines = [];
    let start = 0;
    for (let i = 0; i < this.buffer.length; i++) {
      if (this.buffer[i] === 10 || this.buffer[i] === 13) {
        const lineBytes = this.buffer.subarray(start, i);
        const line = this.decoder.decode(lineBytes, {
          stream: true
        });
        lines.push(line);
        if (this.buffer[i] === 13 && i + 1 < this.buffer.length && this.buffer[i + 1] === 10) {
          i++;
        }
        start = i + 1;
      }
    }
    if (start > 0) {
      this.buffer = this.buffer.slice(start);
    }
    return lines;
  }
  /**
   * Flush remaining buffered data. Returns a final line if any data remains
   * (without a trailing newline). The TextDecoder is also flushed.
   */
  flush() {
    if (this.buffer.length === 0) {
      const remaining = this.decoder.decode();
      return remaining ? [
        remaining
      ] : [];
    }
    const line = this.decoder.decode(this.buffer, {
      stream: false
    });
    this.buffer = new Uint8Array();
    return line ? [
      line
    ] : [];
  }
};
var SSE_DONE = "[DONE]";
async function* iterSSEEvents(body, signal) {
  const sseDecoder = new SSEDecoder();
  const lineDecoder = new LineDecoder();
  const reader = body.getReader();
  let aborted = false;
  const onAbort = /* @__PURE__ */ __name(() => {
    aborted = true;
    reader.cancel().catch(() => {
    });
  }, "onAbort");
  if (signal) {
    if (signal.aborted) {
      return;
    }
    signal.addEventListener("abort", onAbort, {
      once: true
    });
  }
  try {
    while (true) {
      if (aborted) {
        return;
      }
      let result;
      try {
        result = await reader.read();
      } catch (err) {
        if (aborted || err instanceof Error && err.name === "AbortError") {
          return;
        }
        throw err;
      }
      const { done, value } = result;
      if (done) break;
      for (const line of lineDecoder.decode(value)) {
        const ev = sseDecoder.decode(line);
        if (ev) yield ev;
      }
    }
    for (const line of lineDecoder.flush()) {
      const ev = sseDecoder.decode(line);
      if (ev) yield ev;
    }
    const finalEv = sseDecoder.flush();
    if (finalEv) yield finalEv;
  } finally {
    if (signal) {
      signal.removeEventListener("abort", onAbort);
    }
    try {
      reader.releaseLock();
    } catch {
    }
  }
}
__name(iterSSEEvents, "iterSSEEvents");

// src/modules/llm/chat.ts
function extractSSEError(data, requestId) {
  const init = requestId ? {
    requestId
  } : {};
  try {
    const parsed = JSON.parse(data);
    if (parsed && typeof parsed === "object") {
      const errorObj = parsed.error ?? parsed;
      if (errorObj && typeof errorObj === "object") {
        return new CloudOpenAIError({
          message: typeof errorObj.message === "string" ? errorObj.message : "Stream error",
          type: typeof errorObj.type === "string" ? errorObj.type : "server_error",
          param: errorObj.param === void 0 ? null : errorObj.param,
          code: errorObj.code === void 0 ? null : errorObj.code
        }, init);
      }
    }
  } catch {
  }
  return new CloudOpenAIError({
    message: data || "Stream error",
    type: "server_error",
    param: null,
    code: null
  }, init);
}
__name(extractSSEError, "extractSSEError");
var ChatCompletionsAPI = class {
  static {
    __name(this, "ChatCompletionsAPI");
  }
  baseUrl;
  fetch;
  constructor(baseUrl, fetch2) {
    this.baseUrl = baseUrl;
    this.fetch = fetch2;
  }
  create(input) {
    if (input.stream !== true) {
      throw new CloudOpenAIError({
        message: "stream must be true; non-streaming chat completions are not supported",
        type: "invalid_request_error",
        param: "stream",
        code: "request_stream_required"
      });
    }
    return this.createStreaming(input);
  }
  /**
   * Streaming chat completion — returns an async generator of chunks.
   *
   * Reads the SSE stream incrementally, yielding ChatCompletionChunk objects.
   * `stream_options` is passed through unchanged when present.
   *
   * The `X-Request-Id` response header is captured and attached (as
   * `requestId`) to every `CloudOpenAIError` thrown from within the stream:
   * `event: error`, chunk-embedded error, JSON parse failure, and missing
   * `[DONE]` interruption. Non-2xx HTTP errors continue to go through
   * `httpError`, which independently extracts `X-Request-Id`.
   *
   * Throws CloudOpenAIError on:
   * - `event: error` in the stream
   * - Stream ends without `[DONE]` (gateway_stream_interrupted)
   * - JSON parse errors in data frames
   * - Caller abort (AbortSignal) — exits silently, no throw
   */
  async *createStreaming(input) {
    const { signal, conversationId, ...body } = input;
    body.stream = true;
    let response;
    try {
      response = await this.fetch(`${this.baseUrl}/chat/completions`, {
        method: "POST",
        headers: {
          Accept: "text/event-stream",
          "Content-Type": "application/json",
          ...conversationId !== void 0 ? {
            "X-Conversation-ID": conversationId
          } : {}
        },
        body: JSON.stringify(body),
        signal
      });
    } catch (err) {
      if (err instanceof Error && err.name === "AbortError") {
        return;
      }
      throw new CloudOpenAIError({
        message: `Network error: ${err?.message ?? "unknown"}`,
        type: "server_error",
        param: null,
        code: "gateway_network_error"
      }, {
        cause: err
      });
    }
    if (!response.ok) {
      throw await httpError(response);
    }
    if (!response.body) {
      throw new CloudOpenAIError({
        message: "Response body is empty \u2014 streaming not supported",
        type: "server_error",
        param: null,
        code: "gateway_invalid_response"
      }, {
        requestId: response.headers.get("x-request-id") ?? void 0
      });
    }
    const requestId = response.headers.get("x-request-id") ?? void 0;
    let receivedDone = false;
    let threw = false;
    try {
      for await (const sseEvent of iterSSEEvents(response.body, signal)) {
        if (sseEvent.event === "error") {
          threw = true;
          throw extractSSEError(sseEvent.data, requestId);
        }
        if (sseEvent.event === null || sseEvent.event === "") {
          if (sseEvent.data === SSE_DONE) {
            receivedDone = true;
            return;
          }
          if (!sseEvent.data) {
            continue;
          }
          let chunk;
          try {
            chunk = JSON.parse(sseEvent.data);
          } catch {
            threw = true;
            throw new CloudOpenAIError({
              message: `Failed to parse SSE data: ${sseEvent.data}`,
              type: "server_error",
              param: null,
              code: "gateway_invalid_response"
            }, {
              requestId
            });
          }
          if (chunk && typeof chunk === "object" && "error" in chunk) {
            threw = true;
            const errObj = chunk.error;
            throw new CloudOpenAIError({
              message: typeof errObj?.message === "string" ? errObj.message : "Stream error",
              type: typeof errObj?.type === "string" ? errObj.type : "server_error",
              param: errObj?.param === void 0 ? null : errObj.param,
              code: errObj?.code === void 0 ? null : errObj.code
            }, {
              requestId
            });
          }
          yield chunk;
        }
      }
    } catch (err) {
      if (err instanceof Error && err.name === "AbortError") {
        return;
      }
      threw = true;
      throw err;
    }
    if (!receivedDone && !threw && !signal?.aborted) {
      throw new CloudOpenAIError({
        message: "\u6D41\u5F0F\u54CD\u5E94\u4E2D\u65AD\u3002",
        type: "server_error",
        param: null,
        code: "gateway_stream_interrupted"
      }, {
        requestId
      });
    }
  }
};

// src/modules/llm.ts
var LlmModule = class {
  static {
    __name(this, "LlmModule");
  }
  fetch;
  /** 该模块的数据面基址。 */
  baseUrl;
  /** Models namespace。 */
  models;
  /** Chat namespace。 */
  chat;
  constructor(config, fetch2) {
    this.fetch = fetch2;
    this.baseUrl = `${config.endpoint}${CLOUD_MODULE_PATHS.llm}`;
    this.models = new ModelsAPI(this.baseUrl, this.fetch);
    this.chat = {
      completions: new ChatCompletionsAPI(this.baseUrl, this.fetch)
    };
  }
};

// src/vendor/storage/lib/common/errors.ts
var StorageError = class extends Error {
  static {
    __name(this, "StorageError");
  }
  __isStorageError = true;
  namespace;
  status;
  statusCode;
  constructor(message, namespace = "storage", status, statusCode) {
    super(message);
    this.namespace = namespace;
    this.name = namespace === "vectors" ? "StorageVectorsError" : "StorageError";
    this.status = status;
    this.statusCode = statusCode;
  }
  toJSON() {
    return {
      name: this.name,
      message: this.message,
      status: this.status,
      statusCode: this.statusCode
    };
  }
};
function isStorageError(error) {
  return typeof error === "object" && error !== null && "__isStorageError" in error;
}
__name(isStorageError, "isStorageError");
var StorageApiError = class extends StorageError {
  static {
    __name(this, "StorageApiError");
  }
  status;
  statusCode;
  /**
  * Service-specific error code from the Storage API response body, such as
  * `NoSuchKey`, `AccessDenied` or `ResourceAlreadyExists`. Use this to branch
  * on the specific error rather than parsing the message.
  * @see https://supabase.com/docs/guides/storage/debugging/error-codes
  */
  code;
  constructor(message, status, statusCode, namespace = "storage", code) {
    super(message, namespace, status, statusCode);
    this.name = namespace === "vectors" ? "StorageVectorsApiError" : "StorageApiError";
    this.status = status;
    this.statusCode = statusCode;
    this.code = code;
  }
  toJSON() {
    return {
      ...super.toJSON(),
      code: this.code
    };
  }
};
var StorageUnknownError = class extends StorageError {
  static {
    __name(this, "StorageUnknownError");
  }
  originalError;
  constructor(message, originalError, namespace = "storage") {
    super(message, namespace);
    this.name = namespace === "vectors" ? "StorageVectorsUnknownError" : "StorageUnknownError";
    this.originalError = originalError;
  }
};

// src/vendor/storage/lib/common/headers.ts
function setHeader(headers, name, value) {
  const result = {
    ...headers
  };
  const nameLower = name.toLowerCase();
  for (const key of Object.keys(result)) {
    if (key.toLowerCase() === nameLower) {
      delete result[key];
    }
  }
  result[nameLower] = value;
  return result;
}
__name(setHeader, "setHeader");
function normalizeHeaders(headers) {
  const result = {};
  for (const [key, value] of Object.entries(headers)) {
    result[key.toLowerCase()] = value;
  }
  return result;
}
__name(normalizeHeaders, "normalizeHeaders");

// src/vendor/storage/lib/common/helpers.ts
var resolveFetch = /* @__PURE__ */ __name((customFetch) => {
  if (customFetch) {
    return (...args) => customFetch(...args);
  }
  return (...args) => fetch(...args);
}, "resolveFetch");
var isPlainObject = /* @__PURE__ */ __name((value) => {
  if (typeof value !== "object" || value === null) {
    return false;
  }
  const prototype = Object.getPrototypeOf(value);
  return (prototype === null || prototype === Object.prototype || Object.getPrototypeOf(prototype) === null) && !(Symbol.toStringTag in value) && !(Symbol.iterator in value);
}, "isPlainObject");
var recursiveToCamel = /* @__PURE__ */ __name((item) => {
  if (Array.isArray(item)) {
    return item.map((el) => recursiveToCamel(el));
  } else if (typeof item === "function" || item !== Object(item)) {
    return item;
  }
  const result = {};
  Object.entries(item).forEach(([key, value]) => {
    const newKey = key.replace(/([-_][a-z])/gi, (c) => c.toUpperCase().replace(/[-_]/g, ""));
    result[newKey] = recursiveToCamel(value);
  });
  return result;
}, "recursiveToCamel");
var encodeStoragePath = /* @__PURE__ */ __name((path) => path.split("/").map(encodeURIComponent).join("/"), "encodeStoragePath");

// src/vendor/storage/lib/common/fetch.ts
var _getErrorMessage = /* @__PURE__ */ __name((err) => {
  if (typeof err === "object" && err !== null) {
    const e = err;
    if (typeof e.msg === "string") return e.msg;
    if (typeof e.message === "string") return e.message;
    if (typeof e.error_description === "string") return e.error_description;
    if (typeof e.error === "string") return e.error;
    if (typeof e.error === "object" && e.error !== null) {
      const nested = e.error;
      if (typeof nested.message === "string") return nested.message;
    }
  }
  return JSON.stringify(err);
}, "_getErrorMessage");
var handleError = /* @__PURE__ */ __name(async (error, reject, options, namespace) => {
  const isResponseLike = error !== null && typeof error === "object" && "json" in error && typeof error.json === "function";
  if (isResponseLike) {
    const responseError = error;
    let status = parseInt(String(responseError.status), 10);
    if (!Number.isFinite(status)) {
      status = 500;
    }
    responseError.json().then((err) => {
      const statusCode = err?.statusCode || err?.code || status + "";
      reject(new StorageApiError(_getErrorMessage(err), status, statusCode, namespace, err?.code));
    }).catch(() => {
      const statusCode = status + "";
      const message = responseError.statusText || `HTTP ${status} error`;
      reject(new StorageApiError(message, status, statusCode, namespace));
    });
  } else {
    reject(new StorageUnknownError(_getErrorMessage(error), error, namespace));
  }
}, "handleError");
var _getRequestParams = /* @__PURE__ */ __name((method, options, parameters, body) => {
  const params = {
    method,
    headers: options?.headers || {}
  };
  if (method === "GET" || method === "HEAD" || !body) {
    return {
      ...params,
      ...parameters
    };
  }
  if (isPlainObject(body)) {
    const headers = options?.headers || {};
    let contentType;
    for (const [key, value] of Object.entries(headers)) {
      if (key.toLowerCase() === "content-type") {
        contentType = value;
      }
    }
    params.headers = setHeader(headers, "Content-Type", contentType ?? "application/json");
    params.body = JSON.stringify(body);
  } else {
    params.body = body;
  }
  if (options?.duplex) {
    params.duplex = options.duplex;
  }
  return {
    ...params,
    ...parameters
  };
}, "_getRequestParams");
async function _handleRequest(fetcher, method, url, options, parameters, body, namespace) {
  return new Promise((resolve, reject) => {
    fetcher(url, _getRequestParams(method, options, parameters, body)).then((result) => {
      if (!result.ok) throw result;
      if (options?.noResolveJson) return result;
      if (namespace === "vectors") {
        const contentType = result.headers.get("content-type");
        const contentLength = result.headers.get("content-length");
        if (contentLength === "0" || result.status === 204) {
          return {};
        }
        if (!contentType || !contentType.includes("application/json")) {
          return {};
        }
      }
      return result.json();
    }).then((data) => resolve(data)).catch((error) => handleError(error, reject, options, namespace));
  });
}
__name(_handleRequest, "_handleRequest");
function createFetchApi(namespace = "storage") {
  return {
    /**
    * Performs a GET request
    * @param fetcher - Fetch function to use
    * @param url - Request URL
    * @param options - Custom fetch options
    * @param parameters - Additional fetch parameters
    * @returns Promise with parsed response
    */
    get: /* @__PURE__ */ __name(async (fetcher, url, options, parameters) => {
      return _handleRequest(fetcher, "GET", url, options, parameters, void 0, namespace);
    }, "get"),
    /**
    * Performs a POST request
    * @param fetcher - Fetch function to use
    * @param url - Request URL
    * @param body - Request body to be JSON stringified
    * @param options - Custom fetch options
    * @param parameters - Additional fetch parameters
    * @returns Promise with parsed response
    */
    post: /* @__PURE__ */ __name(async (fetcher, url, body, options, parameters) => {
      return _handleRequest(fetcher, "POST", url, options, parameters, body, namespace);
    }, "post"),
    /**
    * Performs a PUT request
    * @param fetcher - Fetch function to use
    * @param url - Request URL
    * @param body - Request body to be JSON stringified
    * @param options - Custom fetch options
    * @param parameters - Additional fetch parameters
    * @returns Promise with parsed response
    */
    put: /* @__PURE__ */ __name(async (fetcher, url, body, options, parameters) => {
      return _handleRequest(fetcher, "PUT", url, options, parameters, body, namespace);
    }, "put"),
    /**
    * Performs a HEAD request
    * @param fetcher - Fetch function to use
    * @param url - Request URL
    * @param options - Custom fetch options
    * @param parameters - Additional fetch parameters
    * @returns Promise with Response object (not JSON parsed)
    */
    head: /* @__PURE__ */ __name(async (fetcher, url, options, parameters) => {
      return _handleRequest(fetcher, "HEAD", url, {
        ...options,
        noResolveJson: true
      }, parameters, void 0, namespace);
    }, "head"),
    /**
    * Performs a DELETE request
    * @param fetcher - Fetch function to use
    * @param url - Request URL
    * @param body - Request body to be JSON stringified
    * @param options - Custom fetch options
    * @param parameters - Additional fetch parameters
    * @returns Promise with parsed response
    */
    remove: /* @__PURE__ */ __name(async (fetcher, url, body, options, parameters) => {
      return _handleRequest(fetcher, "DELETE", url, options, parameters, body, namespace);
    }, "remove")
  };
}
__name(createFetchApi, "createFetchApi");
var defaultApi = createFetchApi("storage");
var { get, post, put, head, remove } = defaultApi;
var vectorsApi = createFetchApi("vectors");

// src/vendor/storage/lib/common/BaseApiClient.ts
var BaseApiClient = class {
  static {
    __name(this, "BaseApiClient");
  }
  url;
  headers;
  fetch;
  shouldThrowOnError = false;
  namespace;
  /**
  * Creates a new BaseApiClient instance
  * @param url - Base URL for API requests
  * @param headers - Default headers for API requests
  * @param fetch - Optional custom fetch implementation
  * @param namespace - Error namespace ('storage' or 'vectors')
  */
  constructor(url, headers = {}, fetch2, namespace = "storage") {
    this.url = url;
    this.headers = normalizeHeaders(headers);
    this.fetch = resolveFetch(fetch2);
    this.namespace = namespace;
  }
  /**
  * Enable throwing errors instead of returning them.
  * When enabled, errors are thrown instead of returned in { data, error } format.
  *
  * @returns this - For method chaining
  */
  throwOnError() {
    this.shouldThrowOnError = true;
    return this;
  }
  /**
  * Set an HTTP header for the request.
  * Creates a shallow copy of headers to avoid mutating shared state.
  *
  * @param name - Header name
  * @param value - Header value
  * @returns this - For method chaining
  */
  setHeader(name, value) {
    this.headers = setHeader(this.headers, name, value);
    return this;
  }
  /**
  * Handles API operation with standardized error handling
  * Eliminates repetitive try-catch blocks across all API methods
  *
  * This wrapper:
  * 1. Executes the operation
  * 2. Returns { data, error: null } on success
  * 3. Returns { data: null, error } on failure (if shouldThrowOnError is false)
  * 4. Throws error on failure (if shouldThrowOnError is true)
  *
  * @typeParam T - The expected data type from the operation
  * @param operation - Async function that performs the API call
  * @returns Promise with { data, error } tuple
  *
  * @example Handling an operation
  * ```typescript
  * async listBuckets() {
  *   return this.handleOperation(async () => {
  *     return await get(this.fetch, `${this.url}/bucket`, {
  *       headers: this.headers,
  *     })
  *   })
  * }
  * ```
  */
  async handleOperation(operation) {
    try {
      const data = await operation();
      return {
        data,
        error: null
      };
    } catch (error) {
      if (this.shouldThrowOnError) {
        throw error;
      }
      if (isStorageError(error)) {
        return {
          data: null,
          error
        };
      }
      throw error;
    }
  }
};

// src/vendor/storage/packages/StreamDownloadBuilder.ts
var StreamDownloadBuilder = class {
  static {
    __name(this, "StreamDownloadBuilder");
  }
  downloadFn;
  shouldThrowOnError;
  [Symbol.toStringTag] = "StreamDownloadBuilder";
  promise = null;
  constructor(downloadFn, shouldThrowOnError) {
    this.downloadFn = downloadFn;
    this.shouldThrowOnError = shouldThrowOnError;
  }
  then(onfulfilled, onrejected) {
    return this.getPromise().then(onfulfilled, onrejected);
  }
  catch(onrejected) {
    return this.getPromise().catch(onrejected);
  }
  finally(onfinally) {
    return this.getPromise().finally(onfinally);
  }
  getPromise() {
    if (!this.promise) {
      this.promise = this.execute();
    }
    return this.promise;
  }
  async execute() {
    try {
      const result = await this.downloadFn();
      return {
        data: result.body,
        error: null
      };
    } catch (error) {
      if (this.shouldThrowOnError) {
        throw error;
      }
      if (isStorageError(error)) {
        return {
          data: null,
          error
        };
      }
      throw error;
    }
  }
};

// src/vendor/storage/packages/BlobDownloadBuilder.ts
var BlobDownloadBuilder = class {
  static {
    __name(this, "BlobDownloadBuilder");
  }
  downloadFn;
  shouldThrowOnError;
  [Symbol.toStringTag] = "BlobDownloadBuilder";
  promise = null;
  constructor(downloadFn, shouldThrowOnError) {
    this.downloadFn = downloadFn;
    this.shouldThrowOnError = shouldThrowOnError;
  }
  asStream() {
    return new StreamDownloadBuilder(this.downloadFn, this.shouldThrowOnError);
  }
  then(onfulfilled, onrejected) {
    return this.getPromise().then(onfulfilled, onrejected);
  }
  catch(onrejected) {
    return this.getPromise().catch(onrejected);
  }
  finally(onfinally) {
    return this.getPromise().finally(onfinally);
  }
  getPromise() {
    if (!this.promise) {
      this.promise = this.execute();
    }
    return this.promise;
  }
  async execute() {
    try {
      const result = await this.downloadFn();
      return {
        data: await result.blob(),
        error: null
      };
    } catch (error) {
      if (this.shouldThrowOnError) {
        throw error;
      }
      if (isStorageError(error)) {
        return {
          data: null,
          error
        };
      }
      throw error;
    }
  }
};

// src/vendor/storage/packages/StorageFileApi.ts
var DEFAULT_SEARCH_OPTIONS = {
  limit: 100,
  offset: 0,
  sortBy: {
    column: "name",
    order: "asc"
  }
};
var DEFAULT_FILE_OPTIONS = {
  cacheControl: "3600",
  contentType: "text/plain;charset=UTF-8",
  upsert: false
};
var StorageFileApi = class extends BaseApiClient {
  static {
    __name(this, "StorageFileApi");
  }
  bucketId;
  constructor(url, headers = {}, bucketId, fetch2) {
    super(url, headers, fetch2, "storage");
    this.bucketId = bucketId;
  }
  /**
  * Uploads a file to an existing bucket or replaces an existing file at the specified path with a new one.
  *
  * @param method HTTP method.
  * @param path The relative file path. Should be of the format `folder/subfolder/filename.png`. The bucket must already exist before attempting to upload.
  * @param fileBody The body of the file to be stored in the bucket.
  */
  async uploadOrUpdate(method, path, fileBody, fileOptions) {
    return this.handleOperation(async () => {
      let body;
      const options = {
        ...DEFAULT_FILE_OPTIONS,
        ...fileOptions
      };
      let headers = {
        ...this.headers,
        ...method === "POST" && {
          "x-upsert": String(options.upsert)
        }
      };
      const metadata = options.metadata;
      if (typeof Blob !== "undefined" && fileBody instanceof Blob) {
        body = new FormData();
        body.append("cacheControl", options.cacheControl);
        if (metadata) {
          body.append("metadata", this.encodeMetadata(metadata));
        }
        body.append("", fileBody);
      } else if (typeof FormData !== "undefined" && fileBody instanceof FormData) {
        body = fileBody;
        if (!body.has("cacheControl")) {
          body.append("cacheControl", options.cacheControl);
        }
        if (metadata && !body.has("metadata")) {
          body.append("metadata", this.encodeMetadata(metadata));
        }
      } else {
        body = fileBody;
        headers["cache-control"] = `max-age=${options.cacheControl}`;
        headers["content-type"] = options.contentType;
        if (metadata) {
          headers["x-metadata"] = this.toBase64(this.encodeMetadata(metadata));
        }
        const isStream = typeof ReadableStream !== "undefined" && body instanceof ReadableStream || body && typeof body === "object" && "pipe" in body && typeof body.pipe === "function";
        if (isStream && !options.duplex) {
          options.duplex = "half";
        }
      }
      if (fileOptions?.headers) {
        for (const [key, value] of Object.entries(fileOptions.headers)) {
          headers = setHeader(headers, key, value);
        }
      }
      const cleanPath = this._removeEmptyFolders(path);
      const _path = this._getFinalPath(cleanPath);
      const data = await (method == "PUT" ? put : post)(this.fetch, `${this.url}/object/${_path}`, body, {
        headers,
        ...options?.duplex ? {
          duplex: options.duplex
        } : {}
      });
      return {
        path: cleanPath,
        id: data.Id,
        fullPath: data.Key
      };
    });
  }
  /**
  * Uploads a file to an existing bucket.
  *
  * @category Storage
  * @subcategory File Buckets
  * @param path The file path, including the file name. Should be of the format `folder/subfolder/filename.png`. The bucket must already exist before attempting to upload.
  * @param fileBody The body of the file to be stored in the bucket.
  * @param fileOptions Optional file upload options including cacheControl, contentType, upsert, and metadata.
  * @returns Promise with response containing file path, id, and fullPath or error
  *
  * @example Upload file
  * ```js
  * const avatarFile = event.target.files[0]
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .upload('public/avatar1.png', avatarFile, {
  *     cacheControl: '3600',
  *     upsert: false
  *   })
  * ```
  *
  * Response:
  * ```json
  * {
  *   "data": {
  *     "path": "public/avatar1.png",
  *     "fullPath": "avatars/public/avatar1.png"
  *   },
  *   "error": null
  * }
  * ```
  *
  * @example Upload file using `ArrayBuffer` from base64 file data
  * ```js
  * import { decode } from 'base64-arraybuffer'
  *
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .upload('public/avatar1.png', decode('base64FileData'), {
  *     contentType: 'image/png'
  *   })
  * ```
  *
  * @example Handling errors
  * ```js
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .upload('public/avatar1.png', avatarFile)
  *
  * if (error) {
  *   // Log the full error so fields like `statusCode` and `error` (the
  *   // Storage error name, e.g. "Duplicate") aren't hidden behind `error.message`.
  *   console.error(error)
  *   return
  * }
  * ```
  *
  * @remarks
  * - RLS policy permissions required:
  *   - `buckets` table permissions: none
  *   - `objects` table permissions: only `insert` when you are uploading new files and `select`, `insert` and `update` when you are upserting files
  * - Refer to the [Storage guide](/docs/guides/storage/security/access-control) on how access control works
  * - For React Native, using either `Blob`, `File` or `FormData` does not work as intended. Upload file using `ArrayBuffer` from base64 file data instead, see example below.
  */
  async upload(path, fileBody, fileOptions) {
    return this.uploadOrUpdate("POST", path, fileBody, fileOptions);
  }
  /**
  * Upload a file with a token generated from `createSignedUploadUrl`.
  *
  * @category Storage
  * @subcategory File Buckets
  * @param path The file path, including the file name. Should be of the format `folder/subfolder/filename.png`. The bucket must already exist before attempting to upload.
  * @param token The token generated from `createSignedUploadUrl`
  * @param fileBody The body of the file to be stored in the bucket.
  * @param fileOptions HTTP headers (cacheControl, contentType, etc.).
  * **Note:** The `upsert` option has no effect here. To enable upsert behavior,
  * pass `{ upsert: true }` when calling `createSignedUploadUrl()` instead.
  * @returns Promise with response containing file path and fullPath or error
  *
  * @example Upload to a signed URL
  * ```js
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .uploadToSignedUrl('folder/cat.jpg', 'token-from-createSignedUploadUrl', file)
  * ```
  *
  * Response:
  * ```json
  * {
  *   "data": {
  *     "path": "folder/cat.jpg",
  *     "fullPath": "avatars/folder/cat.jpg"
  *   },
  *   "error": null
  * }
  * ```
  *
  * @remarks
  * - RLS policy permissions required:
  *   - `buckets` table permissions: none
  *   - `objects` table permissions: none
  * - Refer to the [Storage guide](/docs/guides/storage/security/access-control) on how access control works
  */
  async uploadToSignedUrl(path, token, fileBody, fileOptions) {
    const cleanPath = this._removeEmptyFolders(path);
    const _path = this._getFinalPath(cleanPath);
    const url = new URL(this.url + `/object/upload/sign/${_path}`);
    url.searchParams.set("token", token);
    return this.handleOperation(async () => {
      let body;
      const options = {
        ...DEFAULT_FILE_OPTIONS,
        ...fileOptions
      };
      let headers = {
        ...this.headers,
        ...{
          "x-upsert": String(options.upsert)
        }
      };
      const metadata = options.metadata;
      if (typeof Blob !== "undefined" && fileBody instanceof Blob) {
        body = new FormData();
        body.append("cacheControl", options.cacheControl);
        if (metadata) {
          body.append("metadata", this.encodeMetadata(metadata));
        }
        body.append("", fileBody);
      } else if (typeof FormData !== "undefined" && fileBody instanceof FormData) {
        body = fileBody;
        if (!body.has("cacheControl")) {
          body.append("cacheControl", options.cacheControl);
        }
        if (metadata && !body.has("metadata")) {
          body.append("metadata", this.encodeMetadata(metadata));
        }
      } else {
        body = fileBody;
        headers["cache-control"] = `max-age=${options.cacheControl}`;
        headers["content-type"] = options.contentType;
        if (metadata) {
          headers["x-metadata"] = this.toBase64(this.encodeMetadata(metadata));
        }
        const isStream = typeof ReadableStream !== "undefined" && body instanceof ReadableStream || body && typeof body === "object" && "pipe" in body && typeof body.pipe === "function";
        if (isStream && !options.duplex) {
          options.duplex = "half";
        }
      }
      if (fileOptions?.headers) {
        for (const [key, value] of Object.entries(fileOptions.headers)) {
          headers = setHeader(headers, key, value);
        }
      }
      const data = await put(this.fetch, url.toString(), body, {
        headers,
        ...options?.duplex ? {
          duplex: options.duplex
        } : {}
      });
      return {
        path: cleanPath,
        fullPath: data.Key
      };
    });
  }
  /**
  * Creates a signed upload URL.
  * Signed upload URLs can be used to upload files to the bucket without further authentication.
  * They are valid for 2 hours.
  *
  * @category Storage
  * @subcategory File Buckets
  * @param path The file path, including the current file name. For example `folder/image.png`.
  * @param options.upsert If set to true, allows the file to be overwritten if it already exists.
  * @returns Promise with response containing signed upload URL, token, and path or error
  *
  * @example Create Signed Upload URL
  * ```js
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .createSignedUploadUrl('folder/cat.jpg')
  * ```
  *
  * Response:
  * ```json
  * {
  *   "data": {
  *     "signedUrl": "https://example.supabase.co/storage/v1/object/upload/sign/avatars/folder/cat.jpg?token=<TOKEN>",
  *     "path": "folder/cat.jpg",
  *     "token": "<TOKEN>"
  *   },
  *   "error": null
  * }
  * ```
  *
  * @remarks
  * - RLS policy permissions required:
  *   - `buckets` table permissions: none
  *   - `objects` table permissions: `insert`
  * - Refer to the [Storage guide](/docs/guides/storage/security/access-control) on how access control works
  */
  async createSignedUploadUrl(path, options) {
    return this.handleOperation(async () => {
      let _path = this._getFinalPath(path);
      const headers = {
        ...this.headers
      };
      if (options?.upsert) {
        headers["x-upsert"] = "true";
      }
      const data = await post(this.fetch, `${this.url}/object/upload/sign/${_path}`, {}, {
        headers
      });
      const url = new URL(this.url + data.url);
      const token = url.searchParams.get("token");
      if (!token) {
        throw new StorageError("No token returned by API");
      }
      return {
        signedUrl: url.toString(),
        path,
        token
      };
    });
  }
  /**
  * Replaces an existing file at the specified path with a new one.
  *
  * @category Storage
  * @subcategory File Buckets
  * @param path The relative file path. Should be of the format `folder/subfolder/filename.png`. The bucket must already exist before attempting to update.
  * @param fileBody The body of the file to be stored in the bucket.
  * @param fileOptions Optional file upload options including cacheControl, contentType, and metadata.
  * **Note:** The `upsert` option has no effect here. `update()` always replaces the
  * file at the given path, so the `x-upsert` header is not sent. To control upsert
  * behavior, use `upload()` instead.
  * @returns Promise with response containing file path, id, and fullPath or error
  *
  * @example Update file
  * ```js
  * const avatarFile = event.target.files[0]
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .update('public/avatar1.png', avatarFile, {
  *     cacheControl: '3600'
  *   })
  * ```
  *
  * Response:
  * ```json
  * {
  *   "data": {
  *     "path": "public/avatar1.png",
  *     "fullPath": "avatars/public/avatar1.png"
  *   },
  *   "error": null
  * }
  * ```
  *
  * @example Update file using `ArrayBuffer` from base64 file data
  * ```js
  * import {decode} from 'base64-arraybuffer'
  *
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .update('public/avatar1.png', decode('base64FileData'), {
  *     contentType: 'image/png'
  *   })
  * ```
  *
  * @remarks
  * - RLS policy permissions required:
  *   - `buckets` table permissions: none
  *   - `objects` table permissions: `update` and `select`
  * - `update()` always replaces the file at the given path regardless of the `upsert` option.
  * - Refer to the [Storage guide](/docs/guides/storage/security/access-control) on how access control works
  * - For React Native, using either `Blob`, `File` or `FormData` does not work as intended. Update file using `ArrayBuffer` from base64 file data instead, see example below.
  */
  async update(path, fileBody, fileOptions) {
    return this.uploadOrUpdate("PUT", path, fileBody, fileOptions);
  }
  /**
  * Moves an existing file to a new path in the same bucket.
  *
  * @category Storage
  * @subcategory File Buckets
  * @param fromPath The original file path, including the current file name. For example `folder/image.png`.
  * @param toPath The new file path, including the new file name. For example `folder/image-new.png`.
  * @param options The destination options.
  * @returns Promise with response containing success message or error
  *
  * @example Move file
  * ```js
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .move('public/avatar1.png', 'private/avatar2.png')
  * ```
  *
  * Response:
  * ```json
  * {
  *   "data": {
  *     "message": "Successfully moved"
  *   },
  *   "error": null
  * }
  * ```
  *
  * @remarks
  * - RLS policy permissions required:
  *   - `buckets` table permissions: none
  *   - `objects` table permissions: `update` and `select`
  * - Refer to the [Storage guide](/docs/guides/storage/security/access-control) on how access control works
  */
  async move(fromPath, toPath, options) {
    return this.handleOperation(async () => {
      return await post(this.fetch, `${this.url}/object/move`, {
        bucketId: this.bucketId,
        sourceKey: fromPath,
        destinationKey: toPath,
        destinationBucket: options?.destinationBucket
      }, {
        headers: this.headers
      });
    });
  }
  /**
  * Copies an existing file to a new path in the same bucket.
  *
  * @category Storage
  * @subcategory File Buckets
  * @param fromPath The original file path, including the current file name. For example `folder/image.png`.
  * @param toPath The new file path, including the new file name. For example `folder/image-copy.png`.
  * @param options The destination options.
  * @returns Promise with response containing copied file path or error
  *
  * @example Copy file
  * ```js
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .copy('public/avatar1.png', 'private/avatar2.png')
  * ```
  *
  * Response:
  * ```json
  * {
  *   "data": {
  *     "path": "avatars/private/avatar2.png"
  *   },
  *   "error": null
  * }
  * ```
  *
  * @remarks
  * - RLS policy permissions required:
  *   - `buckets` table permissions: none
  *   - `objects` table permissions: `insert` and `select`
  * - Refer to the [Storage guide](/docs/guides/storage/security/access-control) on how access control works
  */
  async copy(fromPath, toPath, options) {
    return this.handleOperation(async () => {
      const data = await post(this.fetch, `${this.url}/object/copy`, {
        bucketId: this.bucketId,
        sourceKey: fromPath,
        destinationKey: toPath,
        destinationBucket: options?.destinationBucket
      }, {
        headers: this.headers
      });
      return {
        path: data.Key
      };
    });
  }
  /**
  * Creates a signed URL. Use a signed URL to share a file for a fixed amount of time.
  *
  * @category Storage
  * @subcategory File Buckets
  * @param path The file path, including the current file name. For example `folder/image.png`.
  * @param expiresIn The number of seconds until the signed URL expires. For example, `60` for a URL which is valid for one minute.
  * @param options.download triggers the file as a download if set to true. Set this parameter as the name of the file if you want to trigger the download with a different filename.
  * @param options.transform Transform the asset before serving it to the client.
  * @param options.cacheNonce Append a cache nonce parameter to the URL to invalidate the cache.
  * @returns Promise with response containing signed URL or error
  *
  * @example Create Signed URL
  * ```js
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .createSignedUrl('folder/avatar1.png', 60)
  * ```
  *
  * Response:
  * ```json
  * {
  *   "data": {
  *     "signedUrl": "https://example.supabase.co/storage/v1/object/sign/avatars/folder/avatar1.png?token=<TOKEN>"
  *   },
  *   "error": null
  * }
  * ```
  *
  * @example Create a signed URL for an asset with transformations
  * ```js
  * const { data } = await supabase
  *   .storage
  *   .from('avatars')
  *   .createSignedUrl('folder/avatar1.png', 60, {
  *     transform: {
  *       width: 100,
  *       height: 100,
  *     }
  *   })
  * ```
  *
  * @example Create a signed URL which triggers the download of the asset
  * ```js
  * const { data } = await supabase
  *   .storage
  *   .from('avatars')
  *   .createSignedUrl('folder/avatar1.png', 60, {
  *     download: true,
  *   })
  * ```
  *
  * @remarks
  * - RLS policy permissions required:
  *   - `buckets` table permissions: none
  *   - `objects` table permissions: `select`
  * - Refer to the [Storage guide](/docs/guides/storage/security/access-control) on how access control works
  */
  async createSignedUrl(path, expiresIn, options) {
    return this.handleOperation(async () => {
      let _path = this._getFinalPath(path);
      const hasTransform = typeof options?.transform === "object" && options.transform !== null && Object.keys(options.transform).length > 0;
      let data = await post(this.fetch, `${this.url}/object/sign/${_path}`, {
        expiresIn,
        ...hasTransform ? {
          transform: options.transform
        } : {}
      }, {
        headers: this.headers
      });
      const query = new URLSearchParams();
      if (options?.download) query.set("download", options.download === true ? "" : options.download);
      if (options?.cacheNonce != null) query.set("cacheNonce", String(options.cacheNonce));
      const queryString = query.toString();
      const signedUrl = encodeURI(`${this.url}${data.signedURL}${queryString ? `&${queryString}` : ""}`);
      return {
        signedUrl
      };
    });
  }
  /**
  * Creates multiple signed URLs. Use a signed URL to share a file for a fixed amount of time.
  *
  * @category Storage
  * @subcategory File Buckets
  * @param paths The file paths to be downloaded, including the current file names. For example `['folder/image.png', 'folder2/image2.png']`.
  * @param expiresIn The number of seconds until the signed URLs expire. For example, `60` for URLs which are valid for one minute.
  * @param options.download triggers the file as a download if set to true. Set this parameter as the name of the file if you want to trigger the download with a different filename.
  * @param options.cacheNonce Append a cache nonce parameter to the URL to invalidate the cache.
  * @returns Promise with response containing array of objects with signedUrl, path, and error or error
  *
  * @example Create Signed URLs
  * ```js
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .createSignedUrls(['folder/avatar1.png', 'folder/avatar2.png'], 60)
  * ```
  *
  * Response:
  * ```json
  * {
  *   "data": [
  *     {
  *       "error": null,
  *       "path": "folder/avatar1.png",
  *       "signedURL": "/object/sign/avatars/folder/avatar1.png?token=<TOKEN>",
  *       "signedUrl": "https://example.supabase.co/storage/v1/object/sign/avatars/folder/avatar1.png?token=<TOKEN>"
  *     },
  *     {
  *       "error": null,
  *       "path": "folder/avatar2.png",
  *       "signedURL": "/object/sign/avatars/folder/avatar2.png?token=<TOKEN>",
  *       "signedUrl": "https://example.supabase.co/storage/v1/object/sign/avatars/folder/avatar2.png?token=<TOKEN>"
  *     }
  *   ],
  *   "error": null
  * }
  * ```
  *
  * @remarks
  * - RLS policy permissions required:
  *   - `buckets` table permissions: none
  *   - `objects` table permissions: `select`
  * - Refer to the [Storage guide](/docs/guides/storage/security/access-control) on how access control works
  */
  async createSignedUrls(paths, expiresIn, options) {
    return this.handleOperation(async () => {
      const data = await post(this.fetch, `${this.url}/object/sign/${this.bucketId}`, {
        expiresIn,
        paths
      }, {
        headers: this.headers
      });
      const query = new URLSearchParams();
      if (options?.download) query.set("download", options.download === true ? "" : options.download);
      if (options?.cacheNonce != null) query.set("cacheNonce", String(options.cacheNonce));
      const queryString = query.toString();
      return data.map((datum) => ({
        ...datum,
        signedUrl: datum.signedURL ? encodeURI(`${this.url}${datum.signedURL}${queryString ? `&${queryString}` : ""}`) : null
      }));
    });
  }
  /**
  * Downloads a file from a private bucket. For public buckets, make a request to the URL returned from `getPublicUrl` instead.
  *
  * @category Storage
  * @subcategory File Buckets
  * @param path The full path and file name of the file to be downloaded. For example `folder/image.png`.
  * @param options Optional settings: `transform` to transform the asset before serving it to the client, and `cacheNonce` to append a cache nonce parameter to the URL to invalidate the cache.
  * @param parameters Additional fetch parameters like signal for cancellation. Supports standard fetch options including cache control.
  * @returns BlobDownloadBuilder instance for downloading the file
  *
  * @example Download file
  * ```js
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .download('folder/avatar1.png')
  * ```
  *
  * Response:
  * ```json
  * {
  *   "data": <BLOB>,
  *   "error": null
  * }
  * ```
  *
  * @example Download file with transformations
  * ```js
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .download('folder/avatar1.png', {
  *     transform: {
  *       width: 100,
  *       height: 100,
  *       quality: 80
  *     }
  *   })
  * ```
  *
  * @example Download with cache control (useful in Edge Functions)
  * ```js
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .download('folder/avatar1.png', {}, { cache: 'no-store' })
  * ```
  *
  * @example Download with abort signal
  * ```js
  * const controller = new AbortController()
  * setTimeout(() => controller.abort(), 5000)
  *
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .download('folder/avatar1.png', {}, { signal: controller.signal })
  * ```
  *
  * @remarks
  * - RLS policy permissions required:
  *   - `buckets` table permissions: none
  *   - `objects` table permissions: `select`
  * - Refer to the [Storage guide](/docs/guides/storage/security/access-control) on how access control works
  */
  download(path, options, parameters) {
    const wantsTransformation = typeof options?.transform === "object" && options.transform !== null && Object.keys(options.transform).length > 0;
    const renderPath = wantsTransformation ? "render/image/authenticated" : "object";
    const query = new URLSearchParams();
    if (options?.transform) this.applyTransformOptsToQuery(query, options.transform);
    if (options?.cacheNonce != null) query.set("cacheNonce", String(options.cacheNonce));
    const queryString = query.toString();
    const _path = this._getFinalPath(path);
    const downloadFn = /* @__PURE__ */ __name(() => get(this.fetch, `${this.url}/${renderPath}/${_path}${queryString ? `?${queryString}` : ""}`, {
      headers: this.headers,
      noResolveJson: true
    }, parameters), "downloadFn");
    return new BlobDownloadBuilder(downloadFn, this.shouldThrowOnError);
  }
  /**
  * Retrieves the details of an existing file.
  *
  * Returns detailed file metadata including size, content type, and timestamps.
  * Note: The API returns `last_modified` field, not `updated_at`.
  *
  * @category Storage
  * @subcategory File Buckets
  * @param path The file path, including the file name. For example `folder/image.png`.
  * @returns Promise with response containing file metadata or error
  *
  * @example Get file info
  * ```js
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .info('folder/avatar1.png')
  *
  * if (data) {
  *   console.log('Last modified:', data.lastModified)
  *   console.log('Size:', data.size)
  * }
  * ```
  */
  async info(path) {
    const _path = this._getFinalPath(path);
    return this.handleOperation(async () => {
      const data = await get(this.fetch, `${this.url}/object/info/${_path}`, {
        headers: this.headers
      });
      return recursiveToCamel(data);
    });
  }
  /**
  * Checks the existence of a file.
  *
  * @category Storage
  * @subcategory File Buckets
  * @param path The file path, including the file name. For example `folder/image.png`.
  * @returns Promise with response containing boolean indicating file existence or error
  *
  * @example Check file existence
  * ```js
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .exists('folder/avatar1.png')
  * ```
  */
  async exists(path) {
    const _path = this._getFinalPath(path);
    try {
      await head(this.fetch, `${this.url}/object/${_path}`, {
        headers: this.headers
      });
      return {
        data: true,
        error: null
      };
    } catch (error) {
      if (this.shouldThrowOnError) {
        throw error;
      }
      if (isStorageError(error)) {
        const status = error instanceof StorageApiError ? error.status : error instanceof StorageUnknownError ? error.originalError?.status : void 0;
        if (status !== void 0 && [
          400,
          404
        ].includes(status)) {
          return {
            data: false,
            error
          };
        }
      }
      throw error;
    }
  }
  /**
  * A simple convenience function to get the URL for an asset in a public bucket. If you do not want to use this function, you can construct the public URL by concatenating the bucket URL with the path to the asset.
  * This function does not verify if the bucket is public. If a public URL is created for a bucket which is not public, you will not be able to download the asset.
  *
  * @category Storage
  * @subcategory File Buckets
  * @param path The path and name of the file to generate the public URL for. For example `folder/image.png`.
  * @param options.download Triggers the file as a download if set to true. Set this parameter as the name of the file if you want to trigger the download with a different filename.
  * @param options.transform Transform the asset before serving it to the client.
  * @param options.cacheNonce Append a cache nonce parameter to the URL to invalidate the cache.
  * @returns Object with public URL
  *
  * @example Returns the URL for an asset in a public bucket
  * ```js
  * const { data } = supabase
  *   .storage
  *   .from('public-bucket')
  *   .getPublicUrl('folder/avatar1.png')
  * ```
  *
  * Response:
  * ```json
  * {
  *   "data": {
  *     "publicUrl": "https://example.supabase.co/storage/v1/object/public/public-bucket/folder/avatar1.png"
  *   }
  * }
  * ```
  *
  * @example Returns the URL for an asset in a public bucket with transformations
  * ```js
  * const { data } = supabase
  *   .storage
  *   .from('public-bucket')
  *   .getPublicUrl('folder/avatar1.png', {
  *     transform: {
  *       width: 100,
  *       height: 100,
  *     }
  *   })
  * ```
  *
  * @example Returns the URL which triggers the download of an asset in a public bucket
  * ```js
  * const { data } = supabase
  *   .storage
  *   .from('public-bucket')
  *   .getPublicUrl('folder/avatar1.png', {
  *     download: true,
  *   })
  * ```
  *
  * @remarks
  * - The bucket needs to be set to public, either via [updateBucket()](/docs/reference/javascript/storage-updatebucket) or by going to Storage on [supabase.com/dashboard](https://supabase.com/dashboard), clicking the overflow menu on a bucket and choosing "Make public"
  * - RLS policy permissions required:
  *   - `buckets` table permissions: none
  *   - `objects` table permissions: none
  * - Refer to the [Storage guide](/docs/guides/storage/security/access-control) on how access control works
  */
  getPublicUrl(path, options) {
    const _path = this._getFinalPath(path);
    const query = new URLSearchParams();
    if (options?.download) query.set("download", options.download === true ? "" : options.download);
    if (options?.transform) this.applyTransformOptsToQuery(query, options.transform);
    if (options?.cacheNonce != null) query.set("cacheNonce", String(options.cacheNonce));
    const queryString = query.toString();
    const wantsTransformation = typeof options?.transform === "object" && options.transform !== null && Object.keys(options.transform).length > 0;
    const renderPath = wantsTransformation ? "render/image" : "object";
    return {
      data: {
        publicUrl: encodeURI(`${this.url}/${renderPath}/public/${_path}`) + (queryString ? `?${queryString}` : "")
      }
    };
  }
  /**
  * Deletes files within the same bucket
  *
  * Returns an array of FileObject entries for the deleted files. Note that deprecated
  * fields like `bucket_id` may or may not be present in the response - do not rely on them.
  *
  * @category Storage
  * @subcategory File Buckets
  * @param paths An array of files to delete, including the path and file name. For example [`'folder/image.png'`].
  * @returns Promise with response containing array of deleted file objects or error
  *
  * @example Delete file
  * ```js
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .remove(['folder/avatar1.png'])
  * ```
  *
  * Response:
  * ```json
  * {
  *   "data": [],
  *   "error": null
  * }
  * ```
  *
  * @remarks
  * - RLS policy permissions required:
  *   - `buckets` table permissions: none
  *   - `objects` table permissions: `delete` and `select`
  * - Refer to the [Storage guide](/docs/guides/storage/security/access-control) on how access control works
  */
  async remove(paths) {
    return this.handleOperation(async () => {
      return await remove(this.fetch, `${this.url}/object/${this.bucketId}`, {
        prefixes: paths
      }, {
        headers: this.headers
      });
    });
  }
  /**
  * Purges the CDN cache for a single object in this bucket.
  *
  * Maps to `DELETE /cdn/{bucket}/{path}` on the Storage API. The server
  * issues a CDN invalidation for the object and returns `{ message: 'success' }`.
  *
  * **Requires the `service_role` key.** The underlying endpoint enforces
  * `service_role` JWT — calls made with the anon key or a user JWT will be
  * rejected by the server.
  *
  * **Hosted CDN feature.** On self-hosted Supabase, the Storage service must
  * have `CDN_PURGE_ENDPOINT_URL` configured and the `purgeCache` tenant
  * feature enabled, otherwise the server returns an error.
  *
  * Operates on a single object path. There is no wildcard or recursion: pass
  * the exact path of the object you want invalidated.
  *
  * @category Storage
  * @subcategory File Buckets
  * @param path The path (relative to the bucket) of the object to purge, e.g. `folder/avatar.png`.
  * @param options Optional purge cache options.
  * @param options.transformations If true, purges only transformations (resized/formatted variants), leaving the original cached file intact.
  * @param parameters Optional fetch parameters such as an `AbortController` signal.
  * @returns Promise with `{ data: { message }, error: null }` on success or `{ data: null, error }` on failure.
  *
  * @example Purge a single cached object
  * ```js
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .purgeCache('folder/avatar1.png')
  * ```
  *
  * @example Purge only transformations for a single object
  * ```js
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .purgeCache('folder/avatar1.png', { transformations: true })
  * ```
  */
  async purgeCache(path, options, parameters) {
    return this.handleOperation(async () => {
      const _path = encodeStoragePath(this._getFinalPath(path));
      const query = new URLSearchParams();
      if (options?.transformations) {
        query.set("transformations", "true");
      }
      const queryString = query.toString();
      return await remove(this.fetch, `${this.url}/cdn/${_path}${queryString ? `?${queryString}` : ""}`, {}, {
        headers: this.headers
      }, parameters);
    });
  }
  /**
  * Get file metadata
  * @param id the file id to retrieve metadata
  */
  // async getMetadata(
  //   id: string
  // ): Promise<
  //   | {
  //       data: Metadata
  //       error: null
  //     }
  //   | {
  //       data: null
  //       error: StorageError
  //     }
  // > {
  //   try {
  //     const data = await get(this.fetch, `${this.url}/metadata/${id}`, { headers: this.headers })
  //     return { data, error: null }
  //   } catch (error) {
  //     if (isStorageError(error)) {
  //       return { data: null, error }
  //     }
  //     throw error
  //   }
  // }
  /**
  * Update file metadata
  * @param id the file id to update metadata
  * @param meta the new file metadata
  */
  // async updateMetadata(
  //   id: string,
  //   meta: Metadata
  // ): Promise<
  //   | {
  //       data: Metadata
  //       error: null
  //     }
  //   | {
  //       data: null
  //       error: StorageError
  //     }
  // > {
  //   try {
  //     const data = await post(
  //       this.fetch,
  //       `${this.url}/metadata/${id}`,
  //       { ...meta },
  //       { headers: this.headers }
  //     )
  //     return { data, error: null }
  //   } catch (error) {
  //     if (isStorageError(error)) {
  //       return { data: null, error }
  //     }
  //     throw error
  //   }
  // }
  /**
  * Lists all the files and folders within a path of the bucket.
  *
  * **Important:** For folder entries, fields like `id`, `updated_at`, `created_at`,
  * `last_accessed_at`, and `metadata` will be `null`. Only files have these fields populated.
  * Additionally, deprecated fields like `bucket_id`, `owner`, and `buckets` are NOT returned
  * by this method.
  *
  * @category Storage
  * @subcategory File Buckets
  * @param path The folder path.
  * @param options Search options including limit (defaults to 100), offset, sortBy, and search
  * @param parameters Optional fetch parameters including signal for cancellation
  * @returns Promise with response containing array of files/folders or error
  *
  * @example List files in a bucket
  * ```js
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .list('folder', {
  *     limit: 100,
  *     offset: 0,
  *     sortBy: { column: 'name', order: 'asc' },
  *   })
  *
  * // Handle files vs folders
  * data?.forEach(item => {
  *   if (item.id !== null) {
  *     // It's a file
  *     console.log('File:', item.name, 'Size:', item.metadata?.size)
  *   } else {
  *     // It's a folder
  *     console.log('Folder:', item.name)
  *   }
  * })
  * ```
  *
  * Response:
  * ```json
  * {
  *   "data": [
  *     {
  *       "name": "avatar1.png",
  *       "id": "e668cf7f-821b-4a2f-9dce-7dfa5dd1cfd2",
  *       "updated_at": "2024-05-22T23:06:05.580Z",
  *       "created_at": "2024-05-22T23:04:34.443Z",
  *       "last_accessed_at": "2024-05-22T23:04:34.443Z",
  *       "metadata": {
  *         "eTag": "\"c5e8c553235d9af30ef4f6e280790b92\"",
  *         "size": 32175,
  *         "mimetype": "image/png",
  *         "cacheControl": "max-age=3600",
  *         "lastModified": "2024-05-22T23:06:05.574Z",
  *         "contentLength": 32175,
  *         "httpStatusCode": 200
  *       }
  *     }
  *   ],
  *   "error": null
  * }
  * ```
  *
  * @example Search files in a bucket
  * ```js
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .list('folder', {
  *     limit: 100,
  *     offset: 0,
  *     sortBy: { column: 'name', order: 'asc' },
  *     search: 'jon'
  *   })
  * ```
  *
  * @remarks
  * - RLS policy permissions required:
  *   - `buckets` table permissions: none
  *   - `objects` table permissions: `select`
  * - Refer to the [Storage guide](/docs/guides/storage/security/access-control) on how access control works
  */
  async list(path, options, parameters) {
    return this.handleOperation(async () => {
      const sortBy = options?.sortBy ? {
        ...DEFAULT_SEARCH_OPTIONS.sortBy,
        ...options.sortBy
      } : DEFAULT_SEARCH_OPTIONS.sortBy;
      const body = {
        ...DEFAULT_SEARCH_OPTIONS,
        ...options,
        sortBy,
        prefix: path || ""
      };
      return await post(this.fetch, `${this.url}/object/list/${this.bucketId}`, body, {
        headers: this.headers
      }, parameters);
    });
  }
  /**
  * Lists all the files and folders within a bucket using the V2 API with pagination support.
  *
  * **Important:** Folder entries in the `folders` array only contain `name` and optionally `key` —
  * they have no `id`, timestamps, or `metadata` fields. Full file metadata is only available
  * on entries in the `objects` array.
  *
  * @experimental this method signature might change in the future
  *
  * @category Storage
  * @subcategory File Buckets
  * @param options Search options including prefix, cursor for pagination, limit, with_delimiter
  * @param parameters Optional fetch parameters including signal for cancellation
  * @returns Promise with response containing folders/objects arrays with pagination info or error
  *
  * @example List files with pagination
  * ```js
  * const { data, error } = await supabase
  *   .storage
  *   .from('avatars')
  *   .listV2({
  *     prefix: 'folder/',
  *     limit: 100,
  *   })
  *
  * // Handle pagination
  * if (data?.hasNext) {
  *   const nextPage = await supabase
  *     .storage
  *     .from('avatars')
  *     .listV2({
  *       prefix: 'folder/',
  *       cursor: data.nextCursor,
  *     })
  * }
  *
  * // Handle files vs folders
  * data?.objects.forEach(file => {
  *   if (file.id !== null) {
  *     console.log('File:', file.name, 'Size:', file.metadata?.size)
  *   }
  * })
  * data?.folders.forEach(folder => {
  *   console.log('Folder:', folder.name)
  * })
  * ```
  */
  async listV2(options, parameters) {
    return this.handleOperation(async () => {
      const body = {
        ...options
      };
      return await post(this.fetch, `${this.url}/object/list-v2/${this.bucketId}`, body, {
        headers: this.headers
      }, parameters);
    });
  }
  encodeMetadata(metadata) {
    return JSON.stringify(metadata);
  }
  toBase64(data) {
    if (typeof Buffer !== "undefined") {
      return Buffer.from(data).toString("base64");
    }
    return btoa(data);
  }
  _getFinalPath(path) {
    return `${this.bucketId}/${path.replace(/^\/+/, "")}`;
  }
  _removeEmptyFolders(path) {
    return path.replace(/^\/|\/$/g, "").replace(/\/+/g, "/");
  }
  /** Modifies the `query`, appending values the from `transform` */
  applyTransformOptsToQuery(query, transform) {
    if (transform.width) query.set("width", transform.width.toString());
    if (transform.height) query.set("height", transform.height.toString());
    if (transform.resize) query.set("resize", transform.resize);
    if (transform.format) query.set("format", transform.format);
    if (transform.quality) query.set("quality", transform.quality.toString());
    return query;
  }
};

// src/vendor/storage/lib/version.ts
var version = "2.112.3";

// src/vendor/storage/lib/constants.ts
var DEFAULT_HEADERS = {
  "X-Client-Info": `storage-js/${version}`
};

// src/modules/storage.ts
var RUNTIME_STORAGE_BUCKET = "runtime";
var DEFAULT_SIGNED_URL_TTL_SECONDS = 10 * 60;
var MAX_SIGNED_URL_TTL_SECONDS = 60 * 60;
var CloudStoragePathError = class extends Error {
  static {
    __name(this, "CloudStoragePathError");
  }
  constructor(message) {
    super(message);
    this.name = "CloudStoragePathError";
  }
};
var WorkBuddyStorageDownload = class {
  static {
    __name(this, "WorkBuddyStorageDownload");
  }
  blob;
  stream;
  [Symbol.toStringTag] = "WorkBuddyStorageDownload";
  constructor(blob, stream) {
    this.blob = blob;
    this.stream = stream;
  }
  asStream() {
    return this.stream();
  }
  then(onfulfilled, onrejected) {
    return this.blob().then(onfulfilled, onrejected);
  }
  catch(onrejected) {
    return this.blob().catch(onrejected);
  }
  finally(onfinally) {
    return this.blob().finally(onfinally);
  }
};
var WorkBuddyStorageBucket = class {
  static {
    __name(this, "WorkBuddyStorageBucket");
  }
  fileApi;
  constructor(fileApi) {
    this.fileApi = fileApi;
  }
  upload(path, body, options) {
    return mapStorageResult(this.fileApi.upload(validateObjectPath(path), body, options));
  }
  update(path, body, options) {
    return mapStorageResult(this.fileApi.update(validateObjectPath(path), body, options));
  }
  list(prefix = "", options) {
    return mapStorageResult(this.fileApi.list(validateObjectPrefix(prefix), options));
  }
  listPage(options) {
    return mapStorageResult(this.fileApi.listV2({
      ...options,
      prefix: validateObjectPrefix(options?.prefix ?? "")
    }));
  }
  info(path) {
    return mapStorageResult(this.fileApi.info(validateObjectPath(path)));
  }
  async exists(path) {
    const result = await this.fileApi.exists(validateObjectPath(path));
    if (result.error) {
      return {
        data: null,
        error: normalizeStorageError(result.error)
      };
    }
    return {
      data: result.data,
      error: null
    };
  }
  download(path) {
    const builder = this.fileApi.download(validateObjectPath(path));
    return new WorkBuddyStorageDownload(() => mapStorageResult(builder), () => mapStorageResult(builder.asStream()));
  }
  remove(paths) {
    if (paths.length === 0) {
      throw new CloudStoragePathError("remove requires at least one object path.");
    }
    return mapStorageResult(this.fileApi.remove(paths.map(validateObjectPath)));
  }
  copy(fromPath, toPath) {
    return mapStorageResult(this.fileApi.copy(validateObjectPath(fromPath), validateObjectPath(toPath)));
  }
  move(fromPath, toPath) {
    return mapStorageResult(this.fileApi.move(validateObjectPath(fromPath), validateObjectPath(toPath)));
  }
  createSignedUrl(path, expiresIn = DEFAULT_SIGNED_URL_TTL_SECONDS) {
    return mapStorageResult(this.fileApi.createSignedUrl(validateObjectPath(path), validateSignedURLTTL(expiresIn)));
  }
  createSignedUrls(paths, expiresIn = DEFAULT_SIGNED_URL_TTL_SECONDS) {
    if (paths.length === 0) {
      throw new CloudStoragePathError("createSignedUrls requires at least one object path.");
    }
    return mapStorageResult(this.fileApi.createSignedUrls(paths.map(validateObjectPath), validateSignedURLTTL(expiresIn)));
  }
  createSignedUploadUrl(path, options) {
    return mapStorageResult(this.fileApi.createSignedUploadUrl(validateObjectPath(path), {
      upsert: options?.upsert ?? false
    }));
  }
  uploadToSignedUrl(path, token, body, options) {
    if (!token) {
      throw new CloudStoragePathError("signed upload token is required.");
    }
    return mapStorageResult(this.fileApi.uploadToSignedUrl(validateObjectPath(path), token, body, options));
  }
};
var WorkBuddyStorageModule = class extends WorkBuddyStorageBucket {
  static {
    __name(this, "WorkBuddyStorageModule");
  }
  runtime;
  constructor(client) {
    const storageClient = client;
    const runtimeApi = storageClient.from(RUNTIME_STORAGE_BUCKET);
    super(runtimeApi);
    this.runtime = new WorkBuddyStorageBucket(runtimeApi);
  }
  /**
   * 兼容 bucket-native 调用形态，但只允许固定的 `runtime`。
   * 终端应用不能枚举、创建或切换逻辑 Bucket。
   */
  from(bucketID = RUNTIME_STORAGE_BUCKET) {
    if (bucketID !== RUNTIME_STORAGE_BUCKET) {
      throw new CloudStoragePathError(`Only the "${RUNTIME_STORAGE_BUCKET}" storage bucket is available.`);
    }
    return this.runtime;
  }
  userPath(userID, relativePath) {
    return scopedPath("users", userID, relativePath);
  }
  sharedPath(ownerID, relativePath) {
    return scopedPath("shared", ownerID, relativePath);
  }
};
function createStorageModule(config, fetch2) {
  const client = {
    from: /* @__PURE__ */ __name((bucketID) => new StorageFileApi(`${config.endpoint}${CLOUD_MODULE_PATHS.storage}`, DEFAULT_HEADERS, bucketID, fetch2), "from")
  };
  return new WorkBuddyStorageModule(client);
}
__name(createStorageModule, "createStorageModule");
function scopedPath(scope, ownerID, relativePath) {
  const owner = validatePathSegment(ownerID, "owner/user id");
  const relative = validatePath(relativePath, false);
  return validateObjectPath(`${scope}/${owner}/${relative}`);
}
__name(scopedPath, "scopedPath");
function validateObjectPath(path) {
  const normalized = validatePath(path, false);
  if (!normalized.includes("/")) {
    throw new CloudStoragePathError("Object paths must use users/<uid>/... or shared/<ownerUid>/....");
  }
  const [scope, owner, ...rest] = normalized.split("/");
  if (scope !== "users" && scope !== "shared" || !owner || rest.length === 0) {
    throw new CloudStoragePathError("Object paths must use users/<uid>/... or shared/<ownerUid>/....");
  }
  return normalized;
}
__name(validateObjectPath, "validateObjectPath");
function validateObjectPrefix(prefix) {
  if (prefix === "") {
    return "";
  }
  const normalized = validatePath(prefix, true);
  const [scope, owner] = normalized.split("/");
  if (scope === "shared" && !owner) {
    return "shared";
  }
  if (scope !== "users" && scope !== "shared" || !owner) {
    throw new CloudStoragePathError("List prefixes must start with users/<uid> or shared/<ownerUid>.");
  }
  return normalized;
}
__name(validateObjectPrefix, "validateObjectPrefix");
function validatePath(path, allowTrailingSlash) {
  if (typeof path !== "string" || path.trim() === "") {
    throw new CloudStoragePathError("Storage path must be a non-empty relative path.");
  }
  let decoded = path.trim();
  for (let index = 0; index < 3; index += 1) {
    try {
      const next = decodeURIComponent(decoded);
      if (next === decoded) break;
      decoded = next;
    } catch {
      throw new CloudStoragePathError("Storage path contains invalid URL encoding.");
    }
  }
  if (decoded.startsWith("/") || decoded.includes("\\") || decoded.includes("\0") || decoded.includes("//") || !allowTrailingSlash && decoded.endsWith("/")) {
    throw new CloudStoragePathError("Storage path is not a safe relative object path.");
  }
  const normalized = allowTrailingSlash ? decoded.replace(/\/+$/, "") : decoded;
  const segments = normalized.split("/");
  if (segments.some((segment) => segment === "" || segment === "." || segment === "..")) {
    throw new CloudStoragePathError("Storage path traversal is not allowed.");
  }
  return normalized;
}
__name(validatePath, "validatePath");
function validatePathSegment(value, label) {
  if (!value) {
    throw new CloudStoragePathError(`${label} is not a valid storage path segment.`);
  }
  let decoded = value;
  for (let index = 0; index < 3; index += 1) {
    try {
      const next = decodeURIComponent(decoded);
      if (next === decoded) break;
      decoded = next;
    } catch {
      throw new CloudStoragePathError(`${label} contains invalid URL encoding.`);
    }
  }
  if (decoded.includes("/") || decoded.includes("\\") || decoded.includes("\0") || decoded === "." || decoded === "..") {
    throw new CloudStoragePathError(`${label} is not a valid storage path segment.`);
  }
  return decoded;
}
__name(validatePathSegment, "validatePathSegment");
function validateSignedURLTTL(expiresIn) {
  if (!Number.isInteger(expiresIn) || expiresIn <= 0 || expiresIn > MAX_SIGNED_URL_TTL_SECONDS) {
    throw new CloudStoragePathError(`Signed URL expiry must be an integer between 1 and ${MAX_SIGNED_URL_TTL_SECONDS} seconds.`);
  }
  return expiresIn;
}
__name(validateSignedURLTTL, "validateSignedURLTTL");
async function mapStorageResult(source) {
  const result = await source;
  if (result.error) {
    return {
      data: null,
      error: normalizeStorageError(result.error)
    };
  }
  if (result.data === null) {
    return {
      data: null,
      error: {
        name: "CloudStorageResponseError",
        message: "Storage API returned neither data nor an error."
      }
    };
  }
  return {
    data: result.data,
    error: null
  };
}
__name(mapStorageResult, "mapStorageResult");
function normalizeStorageError(error) {
  if (error instanceof Error) {
    const source = error;
    return {
      name: source.name,
      message: source.message,
      status: source.status,
      statusCode: source.statusCode,
      code: source.code,
      cause: error
    };
  }
  return {
    name: "CloudStorageError",
    message: String(error),
    cause: error
  };
}
__name(normalizeStorageError, "normalizeStorageError");

// src/config.ts
var PUBLISHABLE_KEY_PATTERN = /^wbpk_/;
function normalizeHttpUrl(value, field) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new WorkBuddyCloudConfigError(`${field} is required and must be a non-empty string.`);
  }
  const trimmed = value.trim();
  let parsed;
  try {
    parsed = new URL(trimmed);
  } catch {
    throw new WorkBuddyCloudConfigError(`${field} must be an absolute URL, received: ${trimmed}`);
  }
  if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
    throw new WorkBuddyCloudConfigError(`${field} must use http(s), received protocol: ${parsed.protocol}`);
  }
  return trimmed.replace(/\/+$/, "");
}
__name(normalizeHttpUrl, "normalizeHttpUrl");
function resolveEndpoint(value) {
  if (value !== void 0 && value !== null && value !== "") {
    return normalizeHttpUrl(value, "endpoint");
  }
  const origin = globalThis.location?.origin;
  if (typeof origin !== "string" || origin === "") {
    throw new WorkBuddyCloudConfigError("endpoint is required outside browsers (no location.origin to fall back to).");
  }
  return origin.replace(/\/+$/, "");
}
__name(resolveEndpoint, "resolveEndpoint");
function normalizePublishableKey(publishableKey) {
  if (typeof publishableKey !== "string" || publishableKey.trim() === "") {
    throw new WorkBuddyCloudConfigError("publishableKey is required and must be a non-empty string.");
  }
  const trimmed = publishableKey.trim();
  if (!PUBLISHABLE_KEY_PATTERN.test(trimmed)) {
    throw new WorkBuddyCloudConfigError('publishableKey must start with "wbpk_".');
  }
  return trimmed;
}
__name(normalizePublishableKey, "normalizePublishableKey");
function resolveFetch2(candidate) {
  if (candidate) {
    return candidate;
  }
  if (typeof globalThis.fetch !== "function") {
    throw new WorkBuddyCloudConfigError("Global fetch is unavailable in this runtime; pass options.fetch explicitly.");
  }
  return globalThis.fetch.bind(globalThis);
}
__name(resolveFetch2, "resolveFetch");
function resolveRuntimeConfig(options) {
  if (!options || typeof options !== "object") {
    throw new WorkBuddyCloudConfigError("createWorkBuddyCloud requires publishableKey.");
  }
  return Object.freeze({
    endpoint: resolveEndpoint(options.endpoint),
    oauthRelayBaseUrl: options.oauthRelayBaseUrl ? normalizeHttpUrl(options.oauthRelayBaseUrl, "oauthRelayBaseUrl") : "",
    publishableKey: normalizePublishableKey(options.publishableKey),
    fetch: resolveFetch2(options.fetch)
  });
}
__name(resolveRuntimeConfig, "resolveRuntimeConfig");

// src/client.ts
var WorkBuddyCloudClient = class {
  static {
    __name(this, "WorkBuddyCloudClient");
  }
  config;
  /** PostgREST 语义的数据库模块（`/.cloud/database/rest`）。 */
  database;
  auth;
  /** 对象存储客户端（`/.cloud/storage`）。 */
  storage;
  llm;
  constructor(config, options = {}) {
    this.config = config;
    this.auth = new AuthModule(config, createCloudFetch(config, anonymousTokenProvider), {
      storage: options.storage,
      workBuddyMiniProgram: options.workBuddyMiniProgram
    });
    const fetch2 = createCloudFetch(config, () => this.auth.getAccessToken());
    this.database = createDatabaseModule(config, fetch2);
    this.storage = createStorageModule(config, fetch2);
    this.llm = new LlmModule(config, fetch2);
  }
  /** 归一化后的数据面基址（无尾斜杠）。 */
  get endpoint() {
    return this.config.endpoint;
  }
  /** 归一化后的环境中心 OAuth Relay 基址（无尾斜杠）。 */
  get oauthRelayBaseUrl() {
    return this.config.oauthRelayBaseUrl;
  }
};
function createWorkBuddyCloud(options) {
  return new WorkBuddyCloudClient(resolveRuntimeConfig(options), {
    storage: options.storage
  });
}
__name(createWorkBuddyCloud, "createWorkBuddyCloud");

export {
  __name,
  WorkBuddyCloudConfigError,
  resolveRuntimeConfig,
  PUBLISHABLE_KEY_HEADER,
  createCloudFetch,
  anonymousTokenProvider,
  CLOUD_PATH_PREFIX,
  CLOUD_MODULE_PATHS,
  createMemoryStorage,
  AuthModule,
  WorkBuddyDatabaseModule,
  CloudOpenAIError,
  getModelDisplayName,
  getModelCapability,
  LlmModule,
  RUNTIME_STORAGE_BUCKET,
  DEFAULT_SIGNED_URL_TTL_SECONDS,
  MAX_SIGNED_URL_TTL_SECONDS,
  CloudStoragePathError,
  WorkBuddyStorageDownload,
  WorkBuddyStorageBucket,
  WorkBuddyStorageModule,
  WorkBuddyCloudClient,
  createWorkBuddyCloud
};
