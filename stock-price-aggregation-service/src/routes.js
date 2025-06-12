const express = require('express');
const { getAverageStockPrice, getStockCorrelation, fetchStockPriceHistory, calculateAveragePrice, calculateCorrelation, fetchAllStocks } = require('./stockService');

const router = express.Router();

// GET /stocks/:ticker?minutes=m&aggregation=average
router.get('/stocks/:ticker', async (req, res) => {
  const { ticker } = req.params;
  const { minutes, aggregation } = req.query;

  if (!minutes || isNaN(minutes) || minutes <= 0) {
    return res.status(400).json({ error: 'Invalid minutes parameter' });
  }

  if (aggregation !== 'average') {
    return res.status(400).json({ error: 'Invalid aggregation parameter. Use "average".' });
  }

  try {
    const result = await getAverageStockPrice(ticker, parseInt(minutes));
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /stockcorrelation?minutes=m&ticker=NVDA&ticker=PYPL
router.get('/stockcorrelation', async (req, res) => {
  const { minutes, ticker } = req.query;

  if (!minutes || isNaN(minutes) || minutes <= 0) {
    return res.status(400).json({ error: 'Invalid minutes parameter' });
  }

  if (!ticker || !Array.isArray(ticker) || ticker.length !== 2) {
    return res.status(400).json({ error: 'Exactly two tickers must be provided' });
  }

  const [ticker1, ticker2] = ticker;
  if (ticker1 === ticker2) {
    return res.status(400).json({ error: 'Tickers must be different' });
  }

  try {
    const result = await getStockCorrelation(ticker1, ticker2, parseInt(minutes));
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /stockcorrelation/all?minutes=m
router.get('/stockcorrelation/all', async (req, res) => {
  const { minutes } = req.query;

  if (!minutes || isNaN(minutes) || minutes <= 0) {
    return res.status(400).json({ error: 'Invalid minutes parameter' });
  }

  try {
    const stocks = await fetchAllStocks();
    const pricePromises = stocks.map(async (ticker) => {
      const prices = await fetchStockPriceHistory(ticker, parseInt(minutes));
      return { ticker, prices };
    });
    const stockData = await Promise.all(pricePromises);

    const averages = {};
    const stdDevs = {};
    stockData.forEach(({ ticker, prices }) => {
      const pricesArray = prices.map((p) => p.price);
      const avg = calculateAveragePrice(prices);
      averages[ticker] = avg;

      const variance = pricesArray.length > 1
        ? pricesArray.reduce((sum, price) => sum + Math.pow(price - avg, 2), 0) / (pricesArray.length - 1)
        : 0;
      stdDevs[ticker] = Math.sqrt(variance);
    });

    const correlations = [];
    for (let i = 0; i < stocks.length; i++) {
      const row = [];
      for (let j = 0; j < stocks.length; j++) {
        if (i === j) {
          row.push(1);
        } else {
          const corr = calculateCorrelation(
            stockData[i].prices,
            stockData[j].prices
          );
          row.push(corr);
        }
      }
      correlations.push(row);
    }

    res.json({
      stocks,
      correlations,
      averages,
      stdDevs,
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;