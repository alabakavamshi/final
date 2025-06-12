const axios = require('axios');
const moment = require('moment');
const { getCachedStockData, setCachedStockData, filterPricesByTime } = require('./cache');

const TEST_SERVER_URL = process.env.TEST_SERVER_URL || 'http://20.244.56.144/evaluation-service';

// Store the token and its expiration time
let authToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJNYXBDbGFpbXMiOnsiZXhwIjoxNzQ5NzA4MTE1LCJpYXQiOjE3NDk3MDc4MTUsImlzcyI6IkFmZm9yZG1lZCIsImp0aSI6IjE2ZWJmZjljLTQzNTEtNDcyNi05NzQ1LTM3MDg2NDRhNjNlOSIsInN1YiI6IjIyMDNhNTIyMzhAc3J1LmVkdS5pbiJ9LCJlbWFpbCI6IjIyMDNhNTIyMzhAc3J1LmVkdS5pbiIsIm5hbWUiOiJ2YW1zaGkga3Jpc2huYSBhbGFiYWthIiwicm9sbE5vIjoiMjIwM2E1MjIzOCIsImFjY2Vzc0NvZGUiOiJNVkd3RUYiLCJjbGllbnRJRCI6IjE2ZWJmZjljLTQzNTEtNDcyNi05NzQ1LTM3MDg2NDRhNjNlOSIsImNsaWVudFNlY3JldCI6IkdWQ0h6QkFUWkJ6WmdiQVgifQ.8wykRPiL9xxsy45cGjmkpOmFWUYP7so1rGLGmVwLyUo";
let tokenExpiration = 1749708115; // Expires at June 12, 2025, 11:41:55 AM UTC

// Credentials for token request (extracted from the token payload)
const AUTH_CREDENTIALS = {
  email: "2203a52238@sru.edu.in",
  name: "vamshi krishna alabaka",
  rollNo: "2203a52238",
  accessCode: "MVGwEF",
  clientID: "16ebff9c-4351-4726-9745-3708644a63e9",
  clientSecret: "GVCHzBATZBzZgbAG"
};

// Function to fetch a new authorization token
const fetchAuthToken = async () => {
  try {
    const response = await axios.post(`${TEST_SERVER_URL}/auth`, AUTH_CREDENTIALS);
    authToken = response.data.access_token;
    tokenExpiration = response.data.expires_in;
    console.log('New token fetched:', authToken);
    console.log('Token expires at:', new Date(tokenExpiration * 1000).toISOString());
  } catch (error) {
    console.error('Failed to fetch auth token:', error.message);
    authToken = null; // Reset token on failure
    tokenExpiration = null;
  }
};

// Check if token is expired or not set
const isTokenExpired = () => {
  if (!authToken || !tokenExpiration) return true;
  const currentTime = Math.floor(Date.now() / 1000); // Current time in seconds
  return currentTime >= tokenExpiration;
};

// Fetch token if needed
const ensureAuthToken = async () => {
  if (isTokenExpired()) {
    await fetchAuthToken();
  }
};

// Mock data for testing (fallback if test server fails)
const mockStockData = {
  NVDA: [
    { price: 231.95296, lastUpdatedAt: "2025-05-08T04:26:27.46584912Z" },
    { price: 124.95156, lastUpdatedAt: "2025-05-08T04:30:23.4659403412Z" },
    { price: 459.09558, lastUpdatedAt: "2025-05-08T04:39:14.464887447Z" },
    { price: 998.27924, lastUpdatedAt: "2025-05-08T04:50:03.4649036062Z" },
  ],
  PYPL: [
    { price: 680.59766, lastUpdatedAt: "2025-05-09T02:04:27.464908465Z" },
    { price: 652.6387, lastUpdatedAt: "2025-05-09T02:16:15.466525768Z" },
    { price: 42.583908, lastUpdatedAt: "2025-05-09T02:23:08.465127888Z" },
  ],
  AAPL: [
    { price: 150.0, lastUpdatedAt: "2025-05-08T04:26:27.46584912Z" },
    { price: 152.5, lastUpdatedAt: "2025-05-08T04:30:23.4659403412Z" },
  ],
  GOOGL: [
    { price: 2800.0, lastUpdatedAt: "2025-05-08T04:26:27.46584912Z" },
    { price: 2810.0, lastUpdatedAt: "2025-05-08T04:30:23.4659403412Z" },
  ],
  MSFT: [
    { price: 300.0, lastUpdatedAt: "2025-05-08T04:26:27.46584912Z" },
    { price: 305.0, lastUpdatedAt: "2025-05-08T04:30:23.4659403412Z" },
  ],
  TSLA: [
    { price: 700.0, lastUpdatedAt: "2025-05-08T04:26:27.46584912Z" },
    { price: 710.0, lastUpdatedAt: "2025-05-08T04:30:23.4659403412Z" },
  ],
};

// Mock stock list
const mockStockList = {
  stocks: {
    "Nvidia Corporation": "NVDA",
    "PayPal Holdings, Inc.": "PYPL",
    "Apple Inc.": "AAPL",
    "Alphabet Inc. Class A": "GOOGL",
    "Microsoft Corporation": "MSFT",
    "Tesla, Inc.": "TSLA",
  },
};

// Fetch stock price history from the test server (or use mock data)
const fetchStockPriceHistory = async (ticker, minutes) => {
  try {
    const cachedData = getCachedStockData(ticker);
    if (cachedData) {
      return filterPricesByTime(cachedData, minutes);
    }

    let prices;
    await ensureAuthToken();

    // If token fetch failed or token is invalid, fall back to mock data
    if (!authToken) {
      console.warn(`No valid token available for ${ticker}. Using mock data.`);
      prices = mockStockData[ticker] || [];
    } else {
      try {
        const response = await axios.get(`${TEST_SERVER_URL}/stocks/${ticker}?minutes=${minutes}`, {
          headers: {
            Authorization: `Bearer ${authToken}`,
          },
        });
        prices = Array.isArray(response.data) ? response.data : [response.data.stock];
      } catch (error) {
        console.warn(`Failed to fetch data for ${ticker} from test server: ${error.message}. Using mock data.`);
        prices = mockStockData[ticker] || [];
      }
    }

    setCachedStockData(ticker, prices);
    return filterPricesByTime(prices, minutes);
  } catch (error) {
    throw new Error(`Failed to fetch data for ${ticker}: ${error.message}`);
  }
};

// Calculate the average stock price
const calculateAveragePrice = (prices) => {
  if (!prices || prices.length === 0) return 0;
  const total = prices.reduce((sum, entry) => sum + entry.price, 0);
  return total / prices.length;
};

// Align price data for two stocks by timestamp (within 1-minute windows)
const alignPriceData = (prices1, prices2) => {
  const aligned1 = [];
  const aligned2 = [];

  const entries1 = prices1.map((entry) => ({
    price: entry.price,
    time: moment(entry.lastUpdatedAt),
  }));
  const entries2 = prices2.map((entry) => ({
    price: entry.price,
    time: moment(entry.lastUpdatedAt),
  }));

  const startTime = moment.max(entries1[0]?.time || moment(), entries2[0]?.time || moment());
  const endTime = moment.min(
    entries1[entries1.length - 1]?.time || moment(),
    entries2[entries2.length - 1]?.time || moment()
  );

  let currentTime = startTime.clone();
  while (currentTime.isSameOrBefore(endTime)) {
    const windowStart = currentTime.clone();
    const windowEnd = currentTime.clone().add(1, 'minute');

    const price1 = entries1.find((entry) =>
      entry.time.isBetween(windowStart, windowEnd, null, '[)')
    )?.price;
    const price2 = entries2.find((entry) =>
      entry.time.isBetween(windowStart, windowEnd, null, '[)')
    )?.price;

    if (price1 !== undefined && price2 !== undefined) {
      aligned1.push(price1);
      aligned2.push(price2);
    }

    currentTime.add(1, 'minute');
  }

  return { aligned1, aligned2 };
};

// Calculate Pearson correlation coefficient
const calculateCorrelation = (prices1, prices2) => {
  const { aligned1, aligned2 } = alignPriceData(prices1, prices2);
  if (aligned1.length < 2 || aligned2.length < 2) return 0;

  const n = aligned1.length;
  const mean1 = aligned1.reduce((sum, price) => sum + price, 0) / n;
  const mean2 = aligned2.reduce((sum, price) => sum + price, 0) / n;

  let cov = 0;
  let var1 = 0;
  let var2 = 0;

  for (let i = 0; i < n; i++) {
    const diff1 = aligned1[i] - mean1;
    const diff2 = aligned2[i] - mean2;
    cov += diff1 * diff2;
    var1 += diff1 * diff1;
    var2 += diff2 * diff2;
  }

  cov /= n - 1;
  const stdDev1 = Math.sqrt(var1 / (n - 1));
  const stdDev2 = Math.sqrt(var2 / (n - 1));

  if (stdDev1 === 0 || stdDev2 === 0) return 0;
  const correlation = cov / (stdDev1 * stdDev2);
  return Math.min(Math.max(correlation, -1), 1);
};

// Get average stock price API handler
const getAverageStockPrice = async (ticker, minutes) => {
  const prices = await fetchStockPriceHistory(ticker, minutes);
  const average = calculateAveragePrice(prices);

  return {
    averageStockPrice: average,
    priceHistory: prices.map((entry) => ({
      price: entry.price,
      lastUpdatedAt: entry.lastUpdatedAt,
    })),
  };
};

// Get correlation between two stocks API handler
const getStockCorrelation = async (ticker1, ticker2, minutes) => {
  const [prices1, prices2] = await Promise.all([
    fetchStockPriceHistory(ticker1, minutes),
    fetchStockPriceHistory(ticker2, minutes),
  ]);

  const correlation = calculateCorrelation(prices1, prices2);

  return {
    correlation,
    stocks: {
      [ticker1]: {
        averagePrice: calculateAveragePrice(prices1),
        priceHistory: prices1.map((entry) => ({
          price: entry.price,
          lastUpdatedAt: entry.lastUpdatedAt,
        })),
      },
      [ticker2]: {
        averagePrice: calculateAveragePrice(prices2),
        priceHistory: prices2.map((entry) => ({
          price: entry.price,
          lastUpdatedAt: entry.lastUpdatedAt,
        })),
      },
    },
  };
};

// Fetch all stocks (for /stockcorrelation/all endpoint)
const fetchAllStocks = async () => {
  try {
    await ensureAuthToken();

    if (!authToken) {
      console.warn('No valid token available for fetching stock list. Using mock data.');
      return Object.values(mockStockList.stocks);
    }

    const response = await axios.get(`${TEST_SERVER_URL}/stocks`, {
      headers: {
        Authorization: `Bearer ${authToken}`,
      },
    });
    return Object.values(response.data.stocks);
  } catch (error) {
    console.warn(`Failed to fetch stock list from test server: ${error.message}. Using mock data.`);
    return Object.values(mockStockList.stocks);
  }
};

module.exports = {
  getAverageStockPrice,
  getStockCorrelation,
  fetchStockPriceHistory,
  calculateAveragePrice,
  calculateCorrelation,
  fetchAllStocks,
};