import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';

import { generateBets } from '../scripts/_bet-templates.mjs';
import {
  MARKET_BET_TEMPLATES, MARKET_FEED, MARKET_SETTLEMENT_FEED, MARKET_MIN_VOLUME,
  eligibleMarkets, marketSlugFromUrl,
} from '../scripts/_bet-templates-markets.mjs';
import { parseMetricKey, resolveHardSpec, MARKET_SETTLEMENT_MAX_LAG_MS } from '../scripts/_forecast-resolution-eval.mjs';
import { RESOLUTION_FEED_KEYS } from '../scripts/_forecast-resolution.mjs';
import {
  shapeResolutionFeed, ingestHistory, updateMarketSettlements,
  parseGammaSettlement, parseKalshiSettlement,
} from '../scripts/seed-forecast-resolutions.mjs';

const NOW = Date.parse('2026-07-23T00:00:00Z');
const DAY_MS = 24 * 60 * 60 * 1000;

function market(overrides = {}) {
  return {
    title: 'Will the Fed cut rates in September 2026?',
    yesPrice: 62,
    volume: 500_000,
    url: 'https://polymarket.com/event/fed-cut-september-2026',
    endDate: new Date(NOW + 20 * DAY_MS).toISOString(),
    ...overrides,
  };
}

function feedFixture(markets = [market()], overrides = {}) {
  return { geopolitical: markets, tech: [], finance: [], fetchedAt: NOW, ...overrides };
}

describe('marketSlugFromUrl', () => {
  it('derives venue + slug from polymarket and kalshi urls', () => {
    assert.deepEqual(marketSlugFromUrl('https://polymarket.com/event/fed-cut-2026'), { source: 'polymarket', slug: 'fed-cut-2026' });
    assert.deepEqual(marketSlugFromUrl('https://kalshi.com/markets/KXFED-26SEP'), { source: 'kalshi', slug: 'KXFED-26SEP' });
    assert.equal(marketSlugFromUrl('https://example.com/x'), null);
  });
});

describe('eligibleMarkets + slot templates', () => {
  it('generates a bet per eligible market with a settlement-feed spec and market decorations', () => {
    const bets = generateBets(MARKET_BET_TEMPLATES, { [MARKET_FEED]: feedFixture() }, NOW);
    assert.equal(bets.length, 1);
    const bet = bets[0];
    assert.equal(bet.id, 'market:fed-cut-september-2026');
    assert.equal(bet.domain, 'market');
    assert.equal(bet.resolution.sourceFeed, MARKET_SETTLEMENT_FEED);
    assert.equal(bet.resolution.window, 'at-deadline');
    assert.equal(bet.resolution.threshold, 50);
    assert.equal(bet.resolution.deadline, Date.parse(market().endDate));
    assert.equal(bet.marketSlug, 'fed-cut-september-2026');
    assert.equal(bet.marketSource, 'polymarket');
    assert.equal(bet.calibration.marketPrice, 62);
    const parsed = parseMetricKey(bet.resolution.metricKey);
    assert.equal(parsed.fn, 'yesPrice');
    assert.equal(parsed.feedKey, MARKET_SETTLEMENT_FEED);
    assert.ok(RESOLUTION_FEED_KEYS.has(bet.resolution.sourceFeed));
  });

  it('skips thin, dateless, near-dated, and far-dated markets', () => {
    const feed = feedFixture([
      market({ title: 'thin', volume: MARKET_MIN_VOLUME - 1, url: 'https://polymarket.com/event/thin' }),
      market({ title: 'dateless', endDate: undefined, url: 'https://polymarket.com/event/dateless' }),
      market({ title: 'too near', endDate: new Date(NOW + 1 * DAY_MS).toISOString(), url: 'https://polymarket.com/event/near' }),
      market({ title: 'too far', endDate: new Date(NOW + 90 * DAY_MS).toISOString(), url: 'https://polymarket.com/event/far' }),
    ]);
    assert.equal(generateBets(MARKET_BET_TEMPLATES, { [MARKET_FEED]: feed }, NOW).length, 0);
  });

  it('dedups the same market across category arrays and sorts by volume', () => {
    const shared = market();
    const bigger = market({ title: 'Bigger market?', volume: 900_000, url: 'https://polymarket.com/event/bigger' });
    const feed = feedFixture([shared], { tech: [shared, bigger] });
    const bets = generateBets(MARKET_BET_TEMPLATES, { [MARKET_FEED]: feed }, NOW);
    assert.equal(bets.length, 2);
    assert.equal(bets[0].marketSlug, 'bigger'); // slot 0 = highest volume
  });

  it('parses adversarial titles through the metricKey grammar', () => {
    const tricky = market({ title: 'Will X (or Y==Z) happen?', url: 'https://polymarket.com/event/tricky' });
    const bets = generateBets(MARKET_BET_TEMPLATES, { [MARKET_FEED]: feedFixture([tricky]) }, NOW);
    const parsed = parseMetricKey(bets[0].resolution.metricKey);
    assert.equal(parsed.value, 'Will X (or Y==Z) happen?');
  });
});

describe('market bets resolve via the settlement feed (pend → settle → resolve)', () => {
  function marketEntry() {
    const bets = generateBets(MARKET_BET_TEMPLATES, { [MARKET_FEED]: feedFixture() }, NOW);
    const ledger = ingestHistory({}, [{ generatedAt: NOW, predictions: bets }], NOW);
    return Object.values(ledger)[0];
  }

  it('carries marketSlug/marketSource through resolver ingest', () => {
    const entry = marketEntry();
    assert.equal(entry.marketSlug, 'fed-cut-september-2026');
    assert.equal(entry.marketSource, 'polymarket');
  });

  it('pends at endDate while no settlement record exists (empty feed present)', () => {
    const entry = marketEntry();
    const res = resolveHardSpec(entry, [], [], entry.deadline + DAY_MS);
    assert.equal(res.status, 'pending');
    assert.equal(res.evidence.reason, 'value_source_record_missing');
  });

  it('resolves YES/NO from a settled record regardless of its asOf timing', () => {
    const entry = marketEntry();
    const settledYes = shapeResolutionFeed(MARKET_SETTLEMENT_FEED, {
      records: [{ market: market().title, slug: 'fed-cut-september-2026', yesPrice: 100, asOf: entry.deadline - DAY_MS }],
    });
    const yes = resolveHardSpec(entry, settledYes, [], entry.deadline + DAY_MS);
    assert.equal(yes.outcome, 'YES'); // settled 100 >= 50, early-settle asOf accepted

    const settledNo = shapeResolutionFeed(MARKET_SETTLEMENT_FEED, {
      records: [{ market: market().title, slug: 'fed-cut-september-2026', yesPrice: 0, asOf: entry.deadline + DAY_MS }],
    });
    const no = resolveHardSpec(entry, settledNo, [], entry.deadline + 2 * DAY_MS);
    assert.equal(no.outcome, 'NO');
  });

  it('VOIDs only after the settlement grace with no record', () => {
    const entry = marketEntry();
    const res = resolveHardSpec(entry, [], [], entry.deadline + MARKET_SETTLEMENT_MAX_LAG_MS + 1);
    assert.equal(res.outcome, 'VOID');
    assert.equal(res.evidence.reason, 'value_source_never_settled');
  });
});

describe('settlement parsing + loader', () => {
  it('parseGammaSettlement extracts the settled YES price by title', () => {
    const events = [{
      markets: [
        { question: 'Other market?', closed: true, outcomes: '["Yes","No"]', outcomePrices: '["0.2","0.8"]' },
        { question: 'Will the Fed cut rates in September 2026?', closed: true, outcomes: '["Yes","No"]', outcomePrices: '["1","0"]' },
      ],
    }];
    assert.equal(parseGammaSettlement(events, 'Will the Fed cut rates in September 2026?'), 100);
  });

  it('parseGammaSettlement returns null while the market is still open', () => {
    const events = [{ markets: [{ question: 'Q?', closed: false, outcomes: '["Yes","No"]', outcomePrices: '["0.6","0.4"]' }] }];
    assert.equal(parseGammaSettlement(events, 'Q?'), null);
  });

  it('parseKalshiSettlement maps settled results and rejects open markets', () => {
    assert.equal(parseKalshiSettlement({ market: { status: 'settled', result: 'yes' } }), 100);
    assert.equal(parseKalshiSettlement({ market: { status: 'finalized', result: 'no' } }), 0);
    assert.equal(parseKalshiSettlement({ market: { status: 'active', result: '' } }), null);
  });

  it('updateMarketSettlements fetches due unsettled slugs and appends records', async () => {
    const bets = generateBets(MARKET_BET_TEMPLATES, { [MARKET_FEED]: feedFixture() }, NOW);
    const ledger = ingestHistory({}, [{ generatedAt: NOW, predictions: bets }], NOW);
    const writes = [];
    const stats = await updateMarketSettlements(ledger, Date.parse(market().endDate) + DAY_MS, {
      fetchSettlement: async () => 100,
      readJson: async () => ({ records: [] }),
      writeJson: async (key, value) => { writes.push({ key, value }); },
    });
    assert.equal(stats.settled, 1);
    assert.equal(writes.length, 1);
    assert.equal(writes[0].value.records[0].slug, 'fed-cut-september-2026');
    assert.equal(writes[0].value.records[0].yesPrice, 100);
  });

  it('updateMarketSettlements skips already-settled slugs and non-due bets', async () => {
    const bets = generateBets(MARKET_BET_TEMPLATES, { [MARKET_FEED]: feedFixture() }, NOW);
    const ledger = ingestHistory({}, [{ generatedAt: NOW, predictions: bets }], NOW);
    let fetches = 0;
    // Already settled → no fetch.
    const statsSettled = await updateMarketSettlements(ledger, Date.parse(market().endDate) + DAY_MS, {
      fetchSettlement: async () => { fetches += 1; return 100; },
      readJson: async () => ({ records: [{ slug: 'fed-cut-september-2026', yesPrice: 100 }] }),
      writeJson: async () => {},
    });
    assert.equal(statsSettled.fetched, 0);
    // Not yet due → no fetch.
    const statsNotDue = await updateMarketSettlements(ledger, NOW + DAY_MS, {
      fetchSettlement: async () => { fetches += 1; return 100; },
      readJson: async () => ({ records: [] }),
      writeJson: async () => {},
    });
    assert.deepEqual(statsNotDue, { fetched: 0, settled: 0 });
    assert.equal(fetches, 0);
  });
});
