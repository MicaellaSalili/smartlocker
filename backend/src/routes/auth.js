const express = require('express');
const bcrypt = require('bcrypt');
const { parsePhoneNumberFromString } = require('libphonenumber-js');
const User = require('../models/User');

const router = express.Router();

// POST /api/auth/signup
router.post('/signup', async (req, res) => {
  try {
  let { firstName, lastName, username, email, phone, password } = req.body || {};

    // Normalize inputs
    if (typeof email === 'string') email = email.trim().toLowerCase();
    if (typeof username === 'string') username = username.trim();
    if (typeof firstName === 'string') firstName = firstName.trim();
    if (typeof lastName === 'string') lastName = lastName.trim();
  if (typeof phone === 'string') phone = phone.trim();

    // Basic validation
    if (!firstName || !lastName || !username || !email || !phone || !password) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Validate phone using libphonenumber-js. Expecting E.164 like +<countryCode><number>.
    const parsed = parsePhoneNumberFromString(phone);
    if (!parsed || !parsed.isValid()) {
      return res.status(400).json({ error: 'Invalid phone number format' });
    }
    // Normalize to E.164 for storage
    phone = parsed.number; // E.164

    // Check for existing email/username
    const existing = await User.findOne({ $or: [{ email }, { username }, { phone }] });
    if (existing) {
      let field = 'username';
      if (existing.email === email) field = 'email';
      else if (existing.phone === phone) field = 'phone';
      return res.status(409).json({ error: `${field} already in use` });
    }

    // Hash password
    const passwordHash = await bcrypt.hash(password, 10);

  const user = await User.create({ firstName, lastName, username, email, phone, passwordHash });

    return res.status(201).json({
      id: user._id,
      firstName: user.firstName,
      lastName: user.lastName,
      username: user.username,
      email: user.email,
      phone: user.phone,
      createdAt: user.createdAt,
    });
  } catch (err) {
    console.error('Signup error:', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /api/auth/login
router.post('/login', async (req, res) => {
  try {
    let { identifier, password } = req.body || {};
    if (typeof identifier === 'string') identifier = identifier.trim();
    if (typeof password === 'string') password = password.trim();

    if (!identifier || !password) {
      return res.status(400).json({ error: 'Missing credentials' });
    }

    const identLower = identifier.toLowerCase();
    const user = await User.findOne({
      $or: [{ email: identLower }, { username: identifier }],
    });

    if (!user) {
      return res.status(401).json({ error: 'Invalid username/email or password' });
    }

    const ok = await bcrypt.compare(password, user.passwordHash);
    if (!ok) {
      return res.status(401).json({ error: 'Invalid username/email or password' });
    }

    return res.status(200).json({
      id: user._id,
      firstName: user.firstName,
      lastName: user.lastName,
      username: user.username,
      email: user.email,
      phone: user.phone,
      createdAt: user.createdAt,
    });
  } catch (err) {
    console.error('Login error:', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
