/**
 * Market quotes — server-side resolver for the app's `.ticker` pin. Resolves a
 * "stock:AAPL" / "crypto:BTC" source id to a `TickerDTO` (price, day change,
 * session high/low, an intraday sparkline and the market session) via
 * **Finnhub** (one key covers both markets). The key lives only here (Worker
 * secret `FINNHUB_KEY`), never on the device.
 *
 * Source split by market:
 *  - stocks → Finnhub `/quote` (current, change %, OHLC, prev-close) + a name
 *    from `/stock/profile2`. Session (pre/open/after/closed) is derived from the
 *    US trading calendar in `marketState()` — Finnhub's quote carries no flag.
 *  - crypto → Finnhub crypto candles (`BINANCE:<SYM>USDT`); price is the last
 *    close, the basis is the close ~24h ago, and the candle closes feed the
 *    sparkline. Crypto trades 24/7, so the session is always "open".
 *
 * NOTE: only `/quote` is on every Finnhub free plan with certainty. Crypto
 * candles and `/stock/candle` (the stock sparkline) have moved in and out of the
 * free tier; this resolver treats a candle failure as "no sparkline" (returns
 * `spark: []`, which the app renders by simply omitting the line) rather than
 * failing the whole quote. Confirm both candle calls against a real key on the
 * plan you deploy with.
 */
import type { Env } from "./index";

export interface TickerDTO {
  symbol?: string;
  market?: "stock" | "crypto";
  name?: string;
  currency?: string;
  price?: number;
  change?: number;
  changePercent?: number;
  dayHigh?: number;
  dayLow?: number;
  spark?: number[];
  state?: string; // MarketState raw: open | preMarket | afterHours | closed
}

const FINNHUB = "https://finnhub.io/api/v1";
/** Cap the sparkline so the pushed content-state stays small (matches the
 * app's `TickerPayload.maxSparkPoints`). */
const MAX_SPARK = 48;

/** Resolve one source id ("stock:AAPL" / "crypto:BTC") to a quote. */
export async function fetchQuote(env: Env, market: "stock" | "crypto", symbol: string): Promise<TickerDTO | null> {
  if (!env.FINNHUB_KEY) return null;
  return market === "crypto" ? fetchCrypto(env, symbol) : fetchStock(env, symbol);
}

// MARK: Stocks

async function fetchStock(env: Env, symbol: string): Promise<TickerDTO | null> {
  const q = await getJSON(`${FINNHUB}/quote?symbol=${encodeURIComponent(symbol)}&token=${env.FINNHUB_KEY}`);
  // Finnhub `/quote`: c current, d change, dp change %, h high, l low, pc prev close.
  if (!q || typeof q.c !== "number" || q.c === 0) return null;

  const profile = await getJSON(
    `${FINNHUB}/stock/profile2?symbol=${encodeURIComponent(symbol)}&token=${env.FINNHUB_KEY}`,
  ).catch(() => null);

  return {
    symbol,
    market: "stock",
    name: profile?.name ?? "",
    currency: profile?.currency ?? "USD",
    price: q.c,
    change: typeof q.d === "number" ? q.d : q.c - (q.pc ?? q.c),
    changePercent: typeof q.dp === "number" ? q.dp : 0,
    dayHigh: q.h || undefined,
    dayLow: q.l || undefined,
    spark: await stockSpark(env, symbol).catch(() => []),
    state: marketState(),
  };
}

/** Intraday sparkline from `/stock/candle` (5-min resolution, today). Returns
 * [] when the plan doesn't include candles (free-tier 403) — the app just omits
 * the line. */
async function stockSpark(env: Env, symbol: string): Promise<number[]> {
  const now = Math.floor(Date.now() / 1000);
  const from = now - 24 * 3600;
  const c = await getJSON(
    `${FINNHUB}/stock/candle?symbol=${encodeURIComponent(symbol)}&resolution=5&from=${from}&to=${now}&token=${env.FINNHUB_KEY}`,
  );
  if (!c || c.s !== "ok" || !Array.isArray(c.c)) return [];
  return sample(c.c as number[], MAX_SPARK);
}

// MARK: Crypto

async function fetchCrypto(env: Env, symbol: string): Promise<TickerDTO | null> {
  // Finnhub quotes crypto on exchange-prefixed pairs; Binance USDT is the most
  // broadly covered. (BTC → BINANCE:BTCUSDT.)
  const pair = `BINANCE:${symbol}USDT`;
  const now = Math.floor(Date.now() / 1000);
  const from = now - 24 * 3600;
  const c = await getJSON(
    `${FINNHUB}/crypto/candle?symbol=${encodeURIComponent(pair)}&resolution=30&from=${from}&to=${now}&token=${env.FINNHUB_KEY}`,
  );
  if (!c || c.s !== "ok" || !Array.isArray(c.c) || c.c.length === 0) return null;

  const closes = c.c as number[];
  const highs = (c.h as number[]) ?? [];
  const lows = (c.l as number[]) ?? [];
  const price = closes[closes.length - 1];
  const basis = closes[0]; // ~24h ago
  const change = price - basis;
  const changePercent = basis !== 0 ? (change / basis) * 100 : 0;

  return {
    symbol,
    market: "crypto",
    name: symbol,
    currency: "USD",
    price,
    change,
    changePercent,
    dayHigh: highs.length ? Math.max(...highs) : undefined,
    dayLow: lows.length ? Math.min(...lows) : undefined,
    spark: sample(closes, MAX_SPARK),
    state: "open", // crypto never closes
  };
}

// MARK: helpers

/** US equity session → the app's `MarketState` raw value, computed from the
 * Eastern-time clock (regular 09:30–16:00, pre 04:00–09:30, after 16:00–20:00,
 * weekend/overnight closed). Holidays are NOT special-cased — a holiday reads
 * as a normal closed/extended day, which is harmless for a glance. */
export function marketState(now: Date = new Date()): string {
  const f = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/New_York",
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
  const parts = Object.fromEntries(f.formatToParts(now).map((p) => [p.type, p.value]));
  const weekday = parts.weekday;
  if (weekday === "Sat" || weekday === "Sun") return "closed";
  // "24" can appear at midnight in some runtimes; clamp to 0.
  const hour = parseInt(parts.hour, 10) % 24;
  const minute = parseInt(parts.minute, 10);
  const mins = hour * 60 + minute;
  if (mins >= 9 * 60 + 30 && mins < 16 * 60) return "open";
  if (mins >= 4 * 60 && mins < 9 * 60 + 30) return "preMarket";
  if (mins >= 16 * 60 && mins < 20 * 60) return "afterHours";
  return "closed";
}

/** Evenly downsample a series to at most `n` points, keeping the last. */
function sample(series: number[], n: number): number[] {
  const clean = series.filter((v) => typeof v === "number" && isFinite(v));
  if (clean.length <= n) return clean;
  const step = clean.length / n;
  const out: number[] = [];
  for (let i = 0; i < n; i++) out.push(clean[Math.floor(i * step)]);
  out[out.length - 1] = clean[clean.length - 1];
  return out;
}

async function getJSON(url: string): Promise<any | null> {
  const res = await fetch(url);
  if (!res.ok) return null;
  return res.json();
}
