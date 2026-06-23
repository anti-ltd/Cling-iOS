/**
 * ESPN scoreboard reader — server-side twin of the app's `MatchFeed.swift` and
 * `FightFeed.swift`. One `fetchStates(leaguePath)` covers every sport: it loads
 * the right scoreboard and returns a map of sourceID → the live state the
 * poller diffs and pushes. A new sport is a new extractor here, nothing else.
 */
export type MatchStatus = "scheduled" | "live" | "halftime" | "suspended" | "finished";
export type FightStatus = "upcoming" | "live" | "finished";
export type GameStatusT = "scheduled" | "live" | "halftime" | "finished";

export interface MatchState {
  kind: "match";
  sourceID: string;
  homeScore: number;
  awayScore: number;
  minute: number | null;
  status: MatchStatus;
  /** Latest play-by-play line, enriched by the poller from the per-event
   * summary (the scoreboard doesn't carry it); null until then. */
  lastEvent: string | null;
}

export interface FightState {
  kind: "fight";
  sourceID: string;
  redName: string;
  blueName: string;
  round: number | null;
  clock: string | null;
  boutName: string;
  status: FightStatus;
  winner: "red" | "blue" | null;
  method: string | null;
}

export interface GameState {
  kind: "game";
  sourceID: string;
  homeScore: number;
  awayScore: number;
  period: number | null;
  clock: string | null;
  situation: string | null;
  status: GameStatusT;
}

export type SportState = MatchState | FightState | GameState;

export async function fetchStates(leaguePath: string): Promise<Map<string, SportState>> {
  const res = await fetch(
    `https://site.api.espn.com/apis/site/v2/sports/${leaguePath}/scoreboard`,
    { cf: { cacheTtl: 0 }, headers: { accept: "application/json" } },
  );
  if (!res.ok) throw new Error(`ESPN ${leaguePath} ${res.status}`);
  const board = (await res.json()) as { events?: any[] };

  const out = new Map<string, SportState>();
  for (const event of board.events ?? []) {
    // mma → fight card; soccer → match; the US leagues → team game.
    const state = leaguePath.startsWith("mma/")
      ? fightState(event)
      : leaguePath.startsWith("soccer/")
        ? matchState(event)
        : gameState(event, leaguePath);
    if (state) out.set(state.sourceID, state);
  }
  return out;
}

// MARK: Goal enrichment (soccer)

/** Who scored, for the GOAL! banner. The scoreboard carries only the score, so
 * the scorer + minute come from the per-event summary, fetched once per goal. */
export interface GoalInfo {
  scorer: string;
  minute: string; // ESPN's display clock, e.g. "23'" or "90'+2'"
}

/**
 * The latest goal in a match — scorer name + minute — from ESPN's per-event
 * summary `keyEvents`. Called only on a detected score change, so it's one
 * extra request per goal, not per tick. Returns null if the summary lacks a
 * nameable scorer (own goals / parsing miss) — the banner falls back to score.
 */
export async function fetchLatestGoal(leaguePath: string, eventID: string): Promise<GoalInfo | null> {
  const res = await fetch(
    `https://site.api.espn.com/apis/site/v2/sports/${leaguePath}/summary?event=${eventID}`,
    { cf: { cacheTtl: 0 }, headers: { accept: "application/json" } },
  );
  if (!res.ok) throw new Error(`ESPN summary ${eventID} ${res.status}`);
  const data = (await res.json()) as { keyEvents?: any[] };

  // keyEvents run chronologically; walk from the end for the most recent goal.
  const events = data.keyEvents ?? [];
  for (let i = events.length - 1; i >= 0; i--) {
    const ev = events[i];
    const isGoal = ev?.scoringPlay === true || /goal/i.test(ev?.type?.text ?? "");
    if (!isGoal) continue;
    const scorer = ev?.athletesInvolved?.[0]?.displayName;
    if (!scorer) return null;
    const minute = ev?.clock?.displayValue ?? "";
    return { scorer, minute };
  }
  return null;
}

/**
 * The latest play-by-play line for a live match — ESPN's per-event `commentary`
 * feed (the throw-in-level text the reference single-match card shows under the
 * score). One request per match, and the poller calls it only for matches that
 * changed this tick, so it's not a per-tick cost on a frozen scoreline. Long
 * lines (goals carry a full sentence) are cut at a word boundary with an
 * ellipsis so they never end mid-word; the renderer tail-truncates to 2 lines
 * on top. Returns null when the summary has no commentary yet.
 */
const COMMENTARY_MAX = 160;

/** A play-by-play line plus whether it's a meaningful moment (goal / card /
 * penalty / VAR) — the device's "Key moments" auto-expand alerts only on these. */
export interface CommentaryLine {
  text: string;
  important: boolean;
}

/** ESPN play-type slugs worth interrupting for. The summary tags most key
 * events; prose-only lines fall through to the text sniff below. */
const IMPORTANT_SLUGS = new Set([
  "goal", "own-goal", "penalty-goal",
  "yellow-card", "red-card", "yellow-red-card",
  "penalty", "penalty-missed", "penalty-saved",
  "var", "video-review",
]);

function isImportant(slug: string | undefined, text: string): boolean {
  if (slug && IMPORTANT_SLUGS.has(slug.toLowerCase())) return true;
  const t = text.toLowerCase();
  return (
    t.startsWith("goal!") ||
    t.includes("penalty") ||
    t.includes("red card") ||
    t.includes("yellow card") ||
    t.includes("var ") ||
    t.includes("video review")
  );
}

export async function fetchLatestCommentary(leaguePath: string, eventID: string): Promise<CommentaryLine | null> {
  const res = await fetch(
    `https://site.api.espn.com/apis/site/v2/sports/${leaguePath}/summary?event=${eventID}`,
    { cf: { cacheTtl: 0 }, headers: { accept: "application/json" } },
  );
  if (!res.ok) throw new Error(`ESPN summary ${eventID} ${res.status}`);
  const data = (await res.json()) as { commentary?: any[] };

  // Commentary runs chronologically; walk from the end for the most recent
  // entry that actually carries text (some are structural and carry none).
  const items = data.commentary ?? [];
  for (let i = items.length - 1; i >= 0; i--) {
    const raw = (items[i]?.text ?? "").trim();
    if (!raw) continue;
    const slug = items[i]?.play?.type?.type as string | undefined;
    return { text: clampToWord(raw, COMMENTARY_MAX), important: isImportant(slug, raw) };
  }
  return null;
}

/** Trim to a max length on a word boundary, adding an ellipsis when cut. Avoids
 * the mid-word stop a hard slice produces ("…shot fro"). */
function clampToWord(text: string, max: number): string {
  if (text.length <= max) return text;
  const cut = text.slice(0, max);
  const lastSpace = cut.lastIndexOf(" ");
  return (lastSpace > 40 ? cut.slice(0, lastSpace) : cut).trimEnd() + "…";
}

// MARK: Team games (NBA / NFL / NHL / MLB)

function gameState(event: any, leaguePath: string): GameState | null {
  const comp = event.competitions?.[0];
  const home = comp?.competitors?.find((c: any) => c.homeAway === "home");
  const away = comp?.competitors?.find((c: any) => c.homeAway === "away");
  if (!home || !away) return null;

  const status = gameStatus(comp.status);
  const live = status === "live";
  const isBaseball = leaguePath.startsWith("baseball/");
  return {
    kind: "game",
    sourceID: event.id,
    homeScore: parseInt(home.score ?? "0", 10) || 0,
    awayScore: parseInt(away.score ?? "0", 10) || 0,
    period: live ? (comp.status?.period ?? null) : null,
    // Baseball has no running clock; "Top 5th" rides as the situation instead.
    clock: live && !isBaseball ? (comp.status?.displayClock ?? null) : null,
    situation: live && isBaseball ? (comp.status?.type?.shortDetail ?? null) : null,
    status,
  };
}

function gameStatus(s: any): GameStatusT {
  if ((s?.type?.shortDetail ?? "").toLowerCase().includes("half")) return "halftime";
  switch (s?.type?.state) {
    case "pre": return "scheduled";
    case "in": return "live";
    case "post": return "finished";
    default: return s?.type?.completed ? "finished" : "scheduled";
  }
}

// MARK: Football

function matchState(event: any): MatchState | null {
  const comp = event.competitions?.[0];
  const home = comp?.competitors?.find((c: any) => c.homeAway === "home");
  const away = comp?.competitors?.find((c: any) => c.homeAway === "away");
  if (!home || !away) return null;

  const status = matchStatus(comp.status);
  return {
    kind: "match",
    sourceID: event.id,
    homeScore: parseInt(home.score ?? "0", 10) || 0,
    awayScore: parseInt(away.score ?? "0", 10) || 0,
    minute: status === "live" ? matchMinute(comp.status) : null,
    status,
    // The scoreboard carries no commentary; the poller enriches live matches
    // that changed this tick via fetchLatestCommentary.
    lastEvent: null,
  };
}

function matchStatus(s: any): MatchStatus {
  // A suspended/abandoned match still reports state "in", so check the type
  // name first — else it maps to "live" and freezes on a stale minute.
  switch (s?.type?.name) {
    case "STATUS_SUSPENDED":
    case "STATUS_ABANDONED":
    case "STATUS_DELAYED":
      return "suspended";
  }
  if ((s?.type?.shortDetail ?? "").toUpperCase().startsWith("HT")) return "halftime";
  switch (s?.type?.state) {
    case "pre": return "scheduled";
    case "in": return "live";
    case "post": return "finished";
    default: return s?.type?.completed ? "finished" : "scheduled";
  }
}

function matchMinute(s: any): number | null {
  if (s?.clock && s.clock > 0) return Math.floor(s.clock / 60);
  const d = (s?.displayClock ?? "").match(/^\d+/)?.[0];
  return d ? parseInt(d, 10) : null;
}

// MARK: UFC

function fightState(event: any): FightState | null {
  const bouts: any[] = event.competitions ?? [];
  if (!bouts.length) return null;

  const cardStatus: FightStatus = bouts.every((b) => boutState(b) === "post")
    ? "finished"
    : bouts.some((b) => boutState(b) === "in" || boutState(b) === "post")
      ? "live" // underway — mid-card, between or during bouts
      : "upcoming";

  const bout = focusedBout(event, bouts, cardStatus);
  const cs = bout?.competitors ?? [];
  const redName = cs[0]?.athlete?.displayName;
  const blueName = cs[1]?.athlete?.displayName;
  if (!bout || !redName || !blueName) return null;

  const live = boutState(bout) === "in";
  const decided = boutState(bout) === "post";
  const winner = decided ? (cs[0]?.winner ? "red" : cs[1]?.winner ? "blue" : null) : null;

  return {
    kind: "fight",
    sourceID: event.id,
    redName,
    blueName,
    round: live ? (bout.status?.period ?? null) : null,
    clock: live ? (bout.status?.displayClock ?? null) : null,
    boutName: boutLabel(event, bout),
    status: cardStatus,
    winner,
    method: decided ? fightMethod(bout) : null,
  };
}

function boutState(b: any): string | undefined {
  return b.status?.type?.state;
}

function lastName(name?: string): string {
  return (name ?? "").split(" ").pop() ?? "";
}

/**
 * The bout to show, so the pin follows the action:
 * - card underway: the bout in progress, else the next one up;
 * - before / after the card: the main event (the headline + its result).
 */
function focusedBout(event: any, bouts: any[], cardStatus: FightStatus): any | null {
  if (cardStatus === "live") {
    return (
      bouts.find((b) => boutState(b) === "in") ??
      bouts.find((b) => boutState(b) === "pre") ??
      mainEvent(event, bouts) ??
      bouts[bouts.length - 1] ??
      null
    );
  }
  return mainEvent(event, bouts) ?? bouts[bouts.length - 1] ?? null;
}

function mainEvent(event: any, bouts: any[]): any | undefined {
  const title = (event.name ?? "").toLowerCase();
  return bouts.find((b) => {
    const cs = b.competitors ?? [];
    const a = lastName(cs[0]?.athlete?.displayName).toLowerCase();
    const z = lastName(cs[1]?.athlete?.displayName).toLowerCase();
    return a && z && title.includes(a) && title.includes(z);
  });
}

function boutLabel(event: any, bout: any): string {
  return mainEvent(event, [bout]) ? "Main Event" : (bout.type?.abbreviation ?? "");
}

function fightMethod(bout: any): string | null {
  const texts: string[] = (bout.details ?? []).map((d: any) =>
    (d?.type?.text ?? "").toLowerCase(),
  );
  if (texts.some((t) => t.includes("submission"))) return "Submission";
  if (texts.some((t) => t.includes("ko") || t.includes("knockout"))) return "KO/TKO";
  if (texts.some((t) => t.includes("decision"))) return "Decision";
  return null;
}
