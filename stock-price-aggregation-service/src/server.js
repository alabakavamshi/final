require('dotenv').config();
const express = require('express');
const cors = require('cors'); // Import cors
const routes = require('./routes');

const app = express();
const PORT = process.env.PORT || 5000;

// Enable CORS for requests from http://localhost:3000
app.use(cors({
  origin: 'http://localhost:3000', // Allow requests from this origin
  methods: ['GET', 'POST', 'PUT', 'DELETE'], // Allowed methods
  allowedHeaders: ['Content-Type', 'Authorization'], // Allowed headers
}));

// Middleware
app.use(express.json());

// Routes
app.use('/', routes);

// Start the server
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});