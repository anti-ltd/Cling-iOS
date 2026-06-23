/**
 * `MatchPoller` — the singleton Durable Object that keeps pinned live-sport and
 * ticker pins current. Cling runs ONE Live Activity per device (a roster
 * carrying every pin), so a device registers ONCE: its roster update token, the
 * full content-state template, and the list of sport/ticker elements inside it.
 * An alarm loop polls each pinned sport's ESPN scoreboard (and each ticker's
 * quote) every ~8–25s, diffs each against the last seen state, and when any of a
 * device's elements changed it rebuilds that device's whole content-state —
 * mutating only the matching element inside `pins[]` (by pinID), leaving
 * note/parking/decor pins verbatim — and pushes it once to the roster token.
 * Finished elements get one final push, then stop being tracked, so the loop
 * winds down when nothing is live.
 *
 * Sport-agnostic: each element carries its `league` (which scoreboard to poll)
 * and `typeID` (which payload fields to swap), so football and UFC — and any
 * future sport — share this one loop.
 */
import { fetchStates, fetchLatestGoal, fetchLatestCommentary, type SportState, type GoalInfo } from "./espn";
import { pushLiveActivity, type Alert } from "./apns";
import { fetchQuote, type TickerDTO } from "./tickers";
import type { Env } from "./index";

/** Poll cadence while something is genuinely in play (a live match/game/fight,
 * an open market) — fast, to shave our slice of the GOAL! lag. ESPN's own feed
 * delay (~30–90s) is the floor; this is all we control. */
const TICK_LIVE_MS = 8_000;
/** Cadence when nothing's live (pre-kickoff, halftime, market closed) — backed
 * off so we don't hammer ESPN while scores are frozen. */
const TICK_IDLE_MS = 25_000;
/** Tickers ride a sentinel "league" — they resolve via the quote API, not a
 * scoreboard. */
const TICKER_LEAGUE = "ticker";
/** Finnhub quota guard: refresh a quote at most this often. */
const TICKER_TTL = 30_000;

/** A market quote resolved to a live state, shaped like the sport states so the
 * per-device loop treats it the same. */
type TickerLiveState = TickerDTO & { kind: "ticker"; sourceID: string };
type AnyState = SportState | TickerLiveState;

interface TickerCache {
  dto: TickerDTO;
  at: number;
}

/** One server-tracked element inside a device's roster content-state. */
interface SportElement {
  pinID: string;
  typeID: string; // "match" | "fight" | "game" | "ticker"
  sourceID: string;
  league: string; // ESPN scoreboard path, or the ticker sentinel
}

/** A device's whole roster registration. One per install. */
interface DeviceReg {
  deviceID: string;
  rosterToken: string | null;
  topic: string;
  pushToStart?: string | null;
  /** The app-built roster content-state ({ pins:[…], staleDate }); only the
   * sport/ticker elements inside get swapped, everything else rides along. */
  contentState: any;
  sports: SportElement[];
  /** Commentary auto-expand preference: "off" | "important" | "all". A fresh
   * line matching this level is pushed as an alert (expands the island) rather
   * than a silent update. Absent (older app) → treated as "off". */
  commentaryAlerts?: string;
  /** Whether a commentary auto-expand also plays the default sound + haptic. */
  commentaryAlertSound?: boolean;
  /** The APNs host whose push last succeeded for this device's token — sandbox
   * (dev build) or production (TestFlight/App Store). Learned on first success
   * so later ticks skip the wrong-host probe. Survives re-registration. */
  apnsHost?: string;
}

interface RegisterBody {
  deviceID: string;
  pushToStart?: string | null;
  bundleID: string;
  rosterToken?: string | null;
  contentState: string;
  attributes: string;
  sports: SportElement[];
  commentaryAlerts?: string;
  commentaryAlertSound?: boolean;
}

export class MatchPoller {
  constructor(
    private ctx: DurableObjectState,
    private env: Env,
  ) {}

  async fetch(req: Request): Promise<Response> {
    const body = (await req.json()) as RegisterBody;

    // Carry the learned working host across re-registration so a known-good
    // device doesn't re-probe the wrong host after every pin/token change.
    const existing = await this.ctx.storage.get<DeviceReg>(`device:${body.deviceID}`);

    const reg: DeviceReg = {
      deviceID: body.deviceID,
      rosterToken: body.rosterToken ?? null,
      topic: body.bundleID,
      pushToStart: body.pushToStart ?? null,
      contentState: safeParse(body.contentState),
      sports: body.sports ?? [],
      commentaryAlerts: body.commentaryAlerts ?? "off",
      commentaryAlertSound: body.commentaryAlertSound ?? false,
      // A fresh token may have a different env; only keep the learned host when
      // the roster token is unchanged.
      apnsHost: existing && existing.rosterToken === (body.rosterToken ?? null) ? existing.apnsHost : undefined,
    };

    // Nothing live to track, or no token to push to → forget the device. The
    // app re-registers when a sport is pinned or the token is minted.
    if (reg.sports.length === 0 || !reg.rosterToken || !reg.contentState) {
      await this.ctx.storage.delete(`device:${body.deviceID}`);
    } else {
      await this.ctx.storage.put(`device:${body.deviceID}`, reg);
    }

    const current = await this.ctx.storage.getAlarm();
    if (current === null) await this.ctx.storage.setAlarm(Date.now() + 1000);

    return Response.json({ ok: true, sports: reg.sports.length });
  }

  async alarm(): Promise<void> {
    const devices = [...(await this.ctx.storage.list<DeviceReg>({ prefix: "device:" })).values()];
    if (devices.length === 0) return; // nothing pinned — stop scheduling

    const now = Date.now();

    // One fetch per distinct ESPN league across all devices.
    const leagues = [...new Set(devices.flatMap((d) => d.sports.map((s) => s.league)))];
    const states = new Map<string, Map<string, AnyState>>();
    for (const league of leagues) {
      if (league === TICKER_LEAGUE) continue; // resolved separately below
      try {
        states.set(league, await fetchStates(league));
      } catch {
        // Transient feed error for this sport — skip it this tick.
      }
    }

    // Tickers: resolve each distinct symbol once (cache throttles Finnhub).
    const tickerSources = new Set(
      devices.flatMap((d) => d.sports).filter((s) => s.league === TICKER_LEAGUE).map((s) => s.sourceID),
    );
    if (tickerSources.size) {
      const tmap = new Map<string, AnyState>();
      for (const sourceID of tickerSources) {
        const parsed = splitTickerSource(sourceID);
        if (!parsed) continue;
        const dto = await this.getTicker(parsed.market, parsed.symbol, sourceID, now).catch(() => null);
        if (dto) tmap.set(sourceID, { kind: "ticker", sourceID, ...dto });
      }
      states.set(TICKER_LEAGUE, tmap);
    }

    // Per-source fingerprint, shared across devices (ESPN state is global), so
    // two devices watching the same fixture both push on the same change.
    const last = ((await this.ctx.storage.get("lastState")) ?? {}) as Record<string, string>;
    const pushes: Promise<unknown>[] = [];

    // Goal enrichment: for any soccer match whose total score rose since the
    // last tick, fetch the scorer + minute ONCE (shared across every device
    // watching it) so the GOAL! banner can name who scored. One request per
    // goal, not per tick; a miss just falls back to the bare scoreline.
    const goals = new Map<string, GoalInfo>();
    for (const [league, map] of states) {
      if (!league.startsWith("soccer/")) continue;
      for (const [sourceID, st] of map) {
        if (st.kind !== "match") continue;
        const prevRaw = last[sourceID];
        if (!prevRaw) continue;
        const prev = JSON.parse(prevRaw) as AnyState;
        if (prev.kind !== "match") continue;
        if (st.homeScore + st.awayScore > prev.homeScore + prev.awayScore) {
          const g = await fetchLatestGoal(league, sourceID).catch(() => null);
          if (g) goals.set(sourceID, g);
        }
      }
    }

    // Play-by-play enrichment: for any tracked live soccer match that changed
    // this tick (score or the minute rolled), fetch its latest commentary line
    // ONCE — shared across every device watching it — and fold it into the
    // state. Gated to changed + tracked matches so a frozen scoreline costs no
    // summary fetch; and because triggerKey omits lastEvent, the line rides the
    // existing ~1/min minute-tick push rather than triggering its own (a
    // throw-in feed would otherwise burn the Live Activity update budget).
    // sourceID → was this tick's commentary line meaningful (goal/card/penalty/
    // VAR). Tracked locally (not in the persisted state) and read by the device
    // loop to decide whether a "Key moments" device should auto-expand.
    const freshImportant = new Map<string, boolean>();
    const trackedSources = new Set(devices.flatMap((d) => d.sports).map((s) => s.sourceID));
    for (const [league, map] of states) {
      if (!league.startsWith("soccer/")) continue;
      for (const [sourceID, st] of map) {
        if (st.kind !== "match" || st.status !== "live") continue;
        if (!trackedSources.has(sourceID)) continue;
        const prevRaw = last[sourceID];
        const prev = prevRaw ? (JSON.parse(prevRaw) as AnyState) : null;
        const changed = !prev || prev.kind !== "match" || triggerKey(st) !== triggerKey(prev);
        if (!changed) continue;
        const line = await fetchLatestCommentary(league, sourceID).catch(() => null);
        if (line) {
          st.lastEvent = line.text;
          // Only mark commentary as fresh when the line actually changed —
          // minute ticks re-fetch the same goal/half-time line and would
          // otherwise re-alert every ~60 s.
          const prevLine = prev?.kind === "match" ? prev.lastEvent : undefined;
          if (line.text !== prevLine) {
            freshImportant.set(sourceID, line.important);
          }
        }
      }
    }

    for (const device of devices) {
      const cs = structuredClone(device.contentState);
      const stillLive: SportElement[] = [];
      let changed = false;
      const alerts: Alert[] = [];

      for (const sport of device.sports) {
        const state = states.get(sport.league)?.get(sport.sourceID);
        if (!state) {
          stillLive.push(sport); // feed miss — keep tracking, push nothing
          continue;
        }
        const prev = last[sport.sourceID] ? (JSON.parse(last[sport.sourceID]) as AnyState) : null;

        // Always fold the freshest state into the template so a push driven by
        // any one element carries every element's latest value — but only let a
        // *meaningful* change (score, status, minute) TRIGGER the push. A running
        // clock ticking every few seconds would otherwise spend the Live Activity
        // update budget and get the activity throttled (iOS then draws its own
        // spinner over the score instead of updating it).
        const applied = applyStateToPin(cs, sport.pinID, sport.typeID, state, now);
        if (applied && triggerKey(state) !== (prev ? triggerKey(prev) : "")) {
          changed = true;
          // A goal/full-time alert wins; otherwise a fresh commentary line may
          // auto-expand the island for this device, per its preference.
          const a =
            alertFor(state, prev, cs, sport.pinID, goals) ??
            commentaryAlertFor(state, cs, sport.pinID, device, freshImportant);
          if (a) alerts.push(a);
        }
        if (!isFinished(state)) stillLive.push(sport);
      }

      if (changed && device.rosterToken) {
        // Epoch SECONDS (a number), not an ISO string: ActivityKit decodes
        // content-state Dates as numbers, and a string throws typeMismatch →
        // the push is rejected and the activity shows a spinner. Matches the
        // app's encoder (ActivityPushContract: .secondsSince1970).
        cs.staleDate = csDate(now + 4 * 3600 * 1000);
        pushes.push(this.pushDevice(device, cs, alerts[0], now));
      }

      // Drop finished elements from tracking; forget the device once nothing of
      // its is live.
      if (stillLive.length !== device.sports.length) {
        if (stillLive.length === 0) {
          await this.ctx.storage.delete(`device:${device.deviceID}`);
        } else {
          device.sports = stillLive;
          await this.ctx.storage.put(`device:${device.deviceID}`, device);
        }
      }
    }

    // Record the new per-event fingerprint for the next diff.
    for (const [, map] of states) {
      for (const [sourceID, state] of map) last[sourceID] = JSON.stringify(state);
    }

    await Promise.allSettled(pushes);
    await this.ctx.storage.put("lastState", last);

    const remaining = await this.ctx.storage.list({ prefix: "device:" });
    if (remaining.size > 0) {
      // Fast cadence only while something's actually in play; back off otherwise.
      const anyLive = [...states.values()].some((m) => [...m.values()].some(isInPlay));
      await this.ctx.storage.setAlarm(now + (anyLive ? TICK_LIVE_MS : TICK_IDLE_MS));
    }
  }

  private async pushDevice(
    device: DeviceReg,
    contentState: any,
    alert: Alert | undefined,
    now: number,
  ): Promise<void> {
    // A token is valid on exactly one host (sandbox for a dev build, production
    // for TestFlight/App Store). Try the device's learned host (or the configured
    // default) first; on BadDeviceToken, the token belongs to the OTHER host, so
    // retry there once. Only a 410, or BadDeviceToken on BOTH hosts, is a truly
    // dead token worth dropping — never drop just because the first host rejected.
    const prefer = device.apnsHost ?? this.env.APNS_HOST ?? "api.push.apple.com";
    const alt = prefer.includes("sandbox") ? "api.push.apple.com" : "api.sandbox.push.apple.com";

    let usedHost = prefer;
    let result = await pushLiveActivity(this.env, device.rosterToken!, device.topic, contentState, now, alert, 4 * 3600, prefer);
    if (!result.ok && result.reason === "BadDeviceToken") {
      usedHost = alt;
      result = await pushLiveActivity(this.env, device.rosterToken!, device.topic, contentState, now, alert, 4 * 3600, alt);
    }

    if (result.ok) {
      // Remember the host that worked so the next tick skips the failed probe.
      if (device.apnsHost !== usedHost) {
        device.apnsHost = usedHost;
        await this.ctx.storage.put(`device:${device.deviceID}`, device);
      }
      return;
    }

    if (result.status === 410 || result.reason === "BadDeviceToken") {
      await this.ctx.storage.delete(`device:${device.deviceID}`);
    }
    console.log(`apns ${result.status} ${result.reason ?? ""} for device ${device.deviceID} (host ${usedHost})`);
  }

  /** Resolve a market quote, cached so foreground/poll calls and several
   * devices watching the same symbol share one Finnhub call per `TICKER_TTL`. */
  private async getTicker(
    market: "stock" | "crypto",
    symbol: string,
    sourceID: string,
    now: number,
  ): Promise<TickerDTO | null> {
    const key = `ticker:${sourceID}`;
    const cached = (await this.ctx.storage.get(key)) as TickerCache | undefined;
    if (cached && now - cached.at < TICKER_TTL) return cached.dto;

    const dto = await fetchQuote(this.env, market, symbol).catch(() => null);
    if (!dto) return cached?.dto ?? null; // upstream blip — hold the last good quote
    await this.ctx.storage.put(key, { dto, at: now });
    return dto;
  }
}

const TICKER_FIELDS = [
  "name", "currency", "price", "change", "changePercent",
  "dayHigh", "dayLow", "spark", "state",
] as const;

/** Whether a state warrants the fast poll cadence — genuinely in play, so a
 * score can change any second. Pre-kickoff, halftime, or a closed market all
 * return false and let the loop back off. */
function isInPlay(st: AnyState): boolean {
  if (st.kind === "ticker") return st.state === "open";
  return st.status === "live"; // match / game / fight underway (not halftime)
}

/**
 * The fields whose change is worth a push. Deliberately omits the high-
 * frequency display fields — a running game/fight clock — that tick every few
 * seconds and would burn the Live Activity update budget for nothing new. Those
 * still ride along in the pushed content; they just don't *trigger* a push. A
 * match keeps its minute (≈ one push/min, which the frequent-updates budget
 * easily covers) so the island clock stays live.
 */
function triggerKey(st: AnyState): string {
  switch (st.kind) {
    case "match":  return `m:${st.homeScore}-${st.awayScore}:${st.status}:${st.minute ?? ""}`;
    case "game":   return `g:${st.homeScore}-${st.awayScore}:${st.status}:${st.period ?? ""}`;
    case "fight":  return `f:${st.status}:${st.round ?? ""}:${st.winner ?? ""}:${st.method ?? ""}`;
    case "ticker": return `t:${st.price ?? ""}`;
  }
}

/** Whether a state means "stop tracking this element". */
function isFinished(st: AnyState): boolean {
  // A ticker never "finishes" — the market reopens. It stops being tracked only
  // when the app drops the pin and re-registers without it.
  if (st.kind === "ticker") return false;
  return st.status === "finished";
}

/** "stock:AAPL" / "crypto:BTC" → market + symbol. */
function splitTickerSource(sourceID: string): { market: "stock" | "crypto"; symbol: string } | null {
  const i = sourceID.indexOf(":");
  if (i < 0) return null;
  const market = sourceID.slice(0, i);
  const symbol = sourceID.slice(i + 1);
  if ((market !== "stock" && market !== "crypto") || !symbol) return null;
  return { market, symbol };
}

/** Swap a sport/ticker element's live fields into its pin inside the roster template. */
function applyStateToPin(cs: any, pinID: string, typeID: string, st: AnyState, now: number): boolean {
  const pin = (cs?.pins ?? []).find((p: any) => p?.id === pinID);
  const inner = pin?.payload?.[typeID]?._0;
  if (!inner) return false;

  if (typeID === "match" && st.kind === "match") {
    inner.homeScore = st.homeScore;
    inner.awayScore = st.awayScore;
    inner.minute = st.minute;
    inner.status = st.status;
    // Stamp when this minute was sampled (epoch seconds, matching the content-
    // state Date encoding) so the renderer anchors a self-ticking clock that
    // advances between the ~1/min pushes instead of freezing on the integer.
    inner.minuteAsOf = csDate(now);
    // Only overwrite when this tick enriched a line; a null (unchanged tick or a
    // failed summary fetch) keeps whatever commentary was last pushed.
    if (st.lastEvent !== undefined && st.lastEvent !== null) inner.lastEvent = st.lastEvent;
    return true;
  }
  if (typeID === "fight" && st.kind === "fight") {
    inner.redName = st.redName;
    inner.blueName = st.blueName;
    inner.round = st.round;
    inner.clock = st.clock;
    inner.boutName = st.boutName;
    inner.status = st.status;
    inner.winner = st.winner;
    inner.method = st.method;
    return true;
  }
  if (typeID === "game" && st.kind === "game") {
    inner.homeScore = st.homeScore;
    inner.awayScore = st.awayScore;
    inner.period = st.period;
    inner.clock = st.clock;
    inner.situation = st.situation;
    inner.status = st.status;
    return true;
  }
  if (typeID === "ticker" && st.kind === "ticker") {
    const t = st as unknown as Record<string, unknown>;
    for (const k of TICKER_FIELDS) {
      if (t[k] !== undefined && t[k] !== null) inner[k] = t[k];
    }
    return true;
  }
  return false;
}

/**
 * A banner worth interrupting for: a goal, full time, or a fight result. Names
 * come from the pin's element in the content-state (the state objects carry only
 * scores). Returns undefined for routine ticks (minute/clock) so they stay
 * silent, and on first sight (prev === null) so a register never spuriously
 * alerts.
 */
function alertFor(
  state: AnyState,
  prev: AnyState | null,
  cs: any,
  pinID: string,
  goals?: Map<string, GoalInfo>,
): Alert | undefined {
  const pin = (cs?.pins ?? []).find((p: any) => p?.id === pinID);

  if (state.kind === "match") {
    const m = pin?.payload?.match?._0 ?? {};
    const home = m.homeName || m.homeCode || "Home";
    const away = m.awayName || m.awayCode || "Away";
    const line = `${home} ${state.homeScore}–${state.awayScore} ${away}`;
    if (prev?.kind === "match") {
      if (state.homeScore > prev.homeScore || state.awayScore > prev.awayScore) {
        // Name the scorer when the summary resolved one: "Mbappé 23' — FRA 1–0 ARG".
        const g = goals?.get(state.sourceID);
        const who = g ? `${g.scorer}${g.minute ? ` ${g.minute}` : ""} — ` : "";
        return { title: "⚽️ GOAL!", body: `${who}${line}` };
      }
      if (state.status === "finished" && prev.status !== "finished") {
        return { title: "Full time", body: line };
      }
    }
    return undefined;
  }

  if (state.kind === "game") {
    // Team-game scores change constantly (a basket every few seconds) — alert
    // only on the final, never per-score, or the lock screen would be spammed.
    if (state.status === "finished" && (!prev || prev.kind !== "game" || prev.status !== "finished")) {
      const g = pin?.payload?.game?._0 ?? {};
      return {
        title: "Final",
        body: `${g.homeAbbr ?? "Home"} ${state.homeScore}–${state.awayScore} ${g.awayAbbr ?? "Away"}`,
      };
    }
    return undefined;
  }

  if (state.kind === "fight") {
    if (state.status === "finished" && (!prev || prev.kind !== "fight" || prev.status !== "finished")) {
      const f = pin?.payload?.fight?._0 ?? {};
      const winnerName = state.winner === "red" ? f.redName : state.winner === "blue" ? f.blueName : null;
      if (!winnerName) return { title: "🥊 Final", body: `${f.redName} vs ${f.blueName}` };
      const loser = state.winner === "red" ? f.blueName : f.redName;
      const how = state.method ? ` · ${state.method}` : "";
      return { title: "🥊 Result", body: `${winnerName} def. ${loser}${how}` };
    }
    return undefined;
  }

  if (state.kind === "ticker") {
    // Prices move every tick — alert only when the day's move CROSSES ±5% (was
    // under, now at/over), so it fires once per threshold, not per refresh.
    const THRESHOLD = 5;
    const pct = state.changePercent ?? 0;
    const prevPct = prev?.kind === "ticker" ? (prev.changePercent ?? 0) : 0;
    if (!prev || prev.kind !== "ticker") return undefined; // first sight never alerts
    if (Math.abs(pct) >= THRESHOLD && Math.abs(prevPct) < THRESHOLD) {
      const t = pin?.payload?.ticker?._0 ?? {};
      const sym = t.symbol ?? state.symbol ?? "";
      const arrow = pct >= 0 ? "📈" : "📉";
      const sign = pct >= 0 ? "+" : "−";
      return { title: `${arrow} ${sym} ${sign}${Math.abs(pct).toFixed(1)}%`, body: t.name || sym };
    }
    return undefined;
  }

  return undefined;
}

/**
 * A commentary auto-expand alert for a match that got a fresh play-by-play line
 * this tick, gated by the device's preference ("off" | "important" | "all").
 * Only called when no goal/full-time alert already fired, so a goal never
 * double-alerts. Silent (no sound) unless the device opted into sound + haptic.
 */
function commentaryAlertFor(
  state: AnyState,
  cs: any,
  pinID: string,
  device: DeviceReg,
  freshImportant: Map<string, boolean>,
): Alert | undefined {
  if (state.kind !== "match") return undefined;
  const level = device.commentaryAlerts ?? "off";
  if (level === "off") return undefined;
  if (!freshImportant.has(state.sourceID)) return undefined; // no fresh line this tick
  if (level === "important" && !freshImportant.get(state.sourceID)) return undefined;

  const pin = (cs?.pins ?? []).find((p: any) => p?.id === pinID);
  const m = pin?.payload?.match?._0 ?? {};
  const body = (m.lastEvent ?? "").trim();
  if (!body) return undefined;

  const home = m.homeName || m.homeCode || "Home";
  const away = m.awayName || m.awayCode || "Away";
  const min = m.minute != null ? `${m.minute}' ` : "";
  return {
    title: `${min}${home} ${state.homeScore}–${state.awayScore} ${away}`,
    body,
    silent: !device.commentaryAlertSound,
  };
}

/** Seconds between 1970-01-01 and 2001-01-01 (Apple's reference date). */
const APPLE_EPOCH_2001 = 978_307_200;

/**
 * A wall-clock millisecond instant → the number ActivityKit expects for a Date
 * INSIDE a pushed content-state: seconds since 2001 (`timeIntervalSinceReference
 * Date`), which is Swift's default `Date` Codable encoding — NOT Unix-1970. The
 * app's `referenceEncoder` matches this. (The APNs-header `timestamp`/`stale-date`
 * in apns.ts are a different domain — those stay Unix-1970 per the APNs spec.)
 * Sending 1970 seconds here makes the live match clock anchor ~31 years off.
 */
function csDate(ms: number): number {
  return Math.floor(ms / 1000) - APPLE_EPOCH_2001;
}

function safeParse(s: string): any {
  try {
    return JSON.parse(s);
  } catch {
    return null;
  }
}
