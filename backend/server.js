const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

// Middleware for parsing JSON data
app.use(express.json());

// Global Health Check & Status Endpoint
app.get('/', (req, res) => {
  res.status(200).json({
    status: 'success',
    message: 'Welcome to Alfaeq Yemen Backend Ecosystem 🚀',
    version: '1.0.0',
    environment: 'Production Ready'
  });
});

// API Routes Placeholder for Multi-service Engine
app.get('/api/v1/status', (req, res) => {
  res.status(200).json({
    service: 'Alfaeq Yemen Core API',
    uptime: process.uptime(),
    timestamp: new Date().toISOString()
  });
});

// Start Server
app.listen(PORT, () => {
  console.log(`Alfaeq Yemen Backend is running live on port ${PORT} 🌍`);
});
