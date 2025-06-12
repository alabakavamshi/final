const moment = require('moment');

// In-memory cache: { ticker: { lastFetched: timestamp, prices: [{ price, lastUpdatedAt }] } }
const stockCache = new Map();

const CACHE_DURATION_MINUTES = 5; // Refresh cache every 5 minutes

// Get cached data for a ticker
const getCachedStockData = (ticker) => {
  const cached = stockCache.get(ticker);
  if (!cached) return null;

  const now = moment();
  const lastFetched = moment(cached.lastFetched);
  const minutesSinceLastFetch = now.diff(lastFetched, 'minutes');

  if (minutesSinceLastFetch >= CACHE_DURATION_MINUTES) {
    return null; // Cache expired
  }

  return cached.prices;
};

// Set cached data for a ticker
const setCachedStockData = (ticker, prices) => {
  stockCache.set(ticker, {
    lastFetched: moment().toISOString(),
    prices,
  });
};

// Filter prices within the last m minutes
const filterPricesByTime = (prices, minutes) => {
  const cutoff = moment().subtract(minutes, 'minutes');
  return prices
    .filter((entry) => moment(entry.lastUpdatedAt).isAfter(cutoff))
    .sort((a, b) => moment(a.lastUpdatedAt) - moment(b.lastUpdatedAt));
};

module.exports = {
  getCachedStockData,
  setCachedStockData,
  filterPricesByTime,
};