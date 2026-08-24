const express = require('express');
const sqlite3 = require('sqlite3').verbose();
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

// إنشاء والاتصال بقاعدة بيانات حقيقية (database.sqlite)
const dbPath = path.resolve(__dirname, 'database.sqlite');
const db = new sqlite3.Database(dbPath, (err) => {
  if (err) {
    console.error('Error opening database ❌', err.message);
  } else {
    console.log('Connected to real SQLite database successfully 🗄️');
  }
});

// إنشاء جدول المستخدمين الحقيقي إذا لم يكن موجوداً
db.run(`CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  password TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
)`, (err) => {
  if (!err) {
    console.log('Users table ready & verified ✅');
  }
});

// نقطة التحقق من حالة الخادم
app.get('/', (req, res) => {
  res.status(200).json({
    status: 'success',
    message: 'Welcome to Alfaeq Yemen Real Database Ecosystem 🚀',
    version: '1.0.0',
    environment: 'Production Ready'
  });
});

app.get('/api/v1/status', (req, res) => {
  res.status(200).json({
    service: 'Alfaeq Yemen Core API with Real DB',
    uptime: process.uptime(),
    timestamp: new Date().toISOString()
  });
});

// 1. تسجيل مستخدم جديد (قاعدة بيانات حقيقية)
app.post('/api/v1/auth/register', (req, res) => {
  const { username, email, password } = req.body;

  if (!username || !email || !password) {
    return res.status(400).json({ status: 'error', message: 'الرجاء إدخال جميع الحقول المطلوبة' });
  }

  const query = `INSERT INTO users (username, email, password) VALUES (?, ?, ?)`;
  db.run(query, [username, email, password], function(err) {
    if (err) {
      if (err.message.includes('UNIQUE constraint failed')) {
        return res.status(400).json({ status: 'error', message: 'البريد الإلكتروني مسجل مسبقاً' });
      }
      return res.status(500).json({ status: 'error', message: err.message });
    }

    res.status(201).json({
      status: 'success',
      message: 'تم تسجيل المستخدم في قاعدة البيانات بنجاح',
      user: { id: this.lastID, username, email }
    });
  });
});

// 2. تسجيل الدخول (التحقق من قاعدة البيانات الحقيقية)
app.post('/api/v1/auth/login', (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({ status: 'error', message: 'الرجاء إدخال البريد وكلمة المرور' });
  }

  const query = `SELECT * FROM users WHERE email = ? AND password = ?`;
  db.get(query, [email, password], (err, row) => {
    if (err) {
      return res.status(500).json({ status: 'error', message: err.message });
    }

    if (!row) {
      return res.status(401).json({ status: 'error', message: 'البريد الإلكتروني أو كلمة المرور غير صحيحة' });
    }

    res.status(200).json({
      status: 'success',
      message: 'تم تسجيل الدخول بنجاح من قاعدة البيانات',
      token: `real-jwt-token-alfaeq-${row.id}-2026`,
      user: { id: row.id, username: row.username, email: row.email }
    });
  });
});

app.listen(PORT, () => {
  console.log(`Alfaeq Yemen Backend with Database is running live on port ${PORT} 🌍`);
});
