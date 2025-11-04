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

// POST /api/auth/change-password
// Body: { id: string, oldPassword: string, newPassword: string }
router.post('/change-password', async (req, res) => {
  try {
    const { id, oldPassword, newPassword } = req.body || {};

    if (!id || !oldPassword || !newPassword) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    if (typeof newPassword !== 'string' || newPassword.length < 8) {
      return res.status(400).json({ error: 'Password must be at least 8 characters' });
    }

    const user = await User.findById(id);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const ok = await bcrypt.compare(oldPassword, user.passwordHash);
    if (!ok) {
      return res.status(401).json({ error: 'Current password is incorrect' });
    }

    const passwordHash = await bcrypt.hash(newPassword, 10);
    user.passwordHash = passwordHash;
    await user.save();

    return res.json({ ok: true });
  } catch (err) {
    console.error('Change password error:', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /api/auth/update-profile
// Body: { id: string, username: string, email: string, phone: string }
router.post('/update-profile', async (req, res) => {
  try {
    let { id, username, email, phone } = req.body || {};

    if (!id || !username || !email || !phone) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    if (typeof email === 'string') email = email.trim().toLowerCase();
    if (typeof username === 'string') username = username.trim();
    if (typeof phone === 'string') phone = phone.trim();

    // Validate phone and normalize to E.164
    const parsed = parsePhoneNumberFromString(phone);
    if (!parsed || !parsed.isValid()) {
      return res.status(400).json({ error: 'Invalid phone number format' });
    }
    phone = parsed.number;

    // Enforce uniqueness excluding current user
    const conflict = await User.findOne({
      _id: { $ne: id },
      $or: [{ email }, { username }, { phone }],
    });
    if (conflict) {
      let field = 'username';
      if (conflict.email === email) field = 'email';
      else if (conflict.phone === phone) field = 'phone';
      return res.status(409).json({ error: `${field} already in use` });
    }

    const updated = await User.findByIdAndUpdate(
      id,
      { $set: { username, email, phone } },
      { new: true }
    );

    if (!updated) {
      return res.status(404).json({ error: 'User not found' });
    }

    return res.json({
      id: updated._id,
      firstName: updated.firstName,
      lastName: updated.lastName,
      username: updated.username,
      email: updated.email,
      phone: updated.phone,
      createdAt: updated.createdAt,
    });
  } catch (err) {
    console.error('Update profile error:', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
