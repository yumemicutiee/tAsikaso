// What Claude costs, in US dollars per million tokens, by model. Used for the
// daily spend cap and the cost in each log line. Thinking is billed as
// output. Check https://platform.claude.com/docs/en/about-claude/pricing when
// you change models; the Claude Console's usage page is the real bill.

export interface ModelPrice {
  /** Uncached input tokens. */
  input: number;
  /** Output tokens, thinking included. */
  output: number;
  /** Prompt-cache reads. */
  cacheRead: number;
  /** Prompt-cache writes (5-minute cache). */
  cacheWrite: number;
}

const price = (input: number, output: number, cacheRead = input / 10): ModelPrice => ({
  input,
  output,
  cacheRead,
  cacheWrite: input * 1.25,
});

export const PRICES: Readonly<Record<string, ModelPrice>> = {
  "claude-opus-5-5": price(4, 20, 0.2),
  "claude-opus-5": price(5, 25),
  "claude-opus-4-8": price(5, 25),
  "claude-opus-4-7": price(5, 25),
  "claude-opus-4-6": price(5, 25),
  "claude-sonnet-5-5": price(2, 10, 0.2),
  "claude-sonnet-5": price(2, 10),
  "claude-sonnet-4-6": price(3, 15),
  "claude-haiku-4-5": price(1, 5),
  "claude-fable-5-1": price(10, 50, 0.25),
  "claude-fable-5": price(10, 50),
};

/** A model missing from the table is priced at the dearest rate in it, so the cap errs on the safe side. */
const DEAREST: ModelPrice = Object.values(PRICES).reduce((a, b) =>
  b.output > a.output ? b : a,
);

/**
 * The price for [model]: an exact match, else the longest table entry it
 * extends ("claude-opus-5-5-20261101" → "claude-opus-5-5"), else the dearest.
 */
export function priceFor(model: string): { price: ModelPrice; known: boolean } {
  const exact = PRICES[model];
  if (exact) return { price: exact, known: true };
  let best = "";
  for (const key of Object.keys(PRICES)) {
    if (model.startsWith(key + "-") && key.length > best.length) best = key;
  }
  return best ? { price: PRICES[best]!, known: true } : { price: DEAREST, known: false };
}

export interface TokenCounts {
  input: number;
  output: number;
  cacheRead?: number;
  cacheWrite?: number;
}

/** Dollars for [tokens] on [model]. */
export function costUsd(model: string, tokens: TokenCounts): number {
  const { price } = priceFor(model);
  return (
    (tokens.input * price.input +
      tokens.output * price.output +
      (tokens.cacheRead ?? 0) * price.cacheRead +
      (tokens.cacheWrite ?? 0) * price.cacheWrite) /
    1_000_000
  );
}
