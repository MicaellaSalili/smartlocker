const express = require('express');
const bcrypt = require('bcrypt');
const crypto = require('crypto');
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

    // Generate a random application-specific userId like 'RD0000' (4 random digits)
    // Ensure uniqueness by checking existing records. Bounded attempts to avoid infinite loop.
    function randomFourDigits() {
      return String(Math.floor(Math.random() * 10000)).padStart(4, '0');
    }

    let userId;
    const MAX_ATTEMPTS = 10;
    for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
      const candidate = 'RD' + randomFourDigits();
      // Check if candidate already exists
      // Using lean() for lighter-weight query
      // eslint-disable-next-line no-await-in-loop
      const exists = await User.findOne({ userId: candidate }).lean();
      if (!exists) {
        userId = candidate;
        break;
      }
    }
    // If uniqueness couldn't be guaranteed in attempts, fall back to timestamp-based id
    if (!userId) {
      userId = 'RD' + String(Date.now()).slice(-8); // last 8 digits of timestamp
    }

    const user = await User.create({ firstName, lastName, username, email, phone, passwordHash, userId });

    // Convert createdAt to PH time string for client display (Asia/Manila)
    const createdAtPH = new Date(user.createdAt).toLocaleString('en-US', { timeZone: 'Asia/Manila' });

    return res.status(201).json({
      id: user._id,
      userId: user.userId,
      firstName: user.firstName,
      lastName: user.lastName,
      username: user.username,
      email: user.email,
      phone: user.phone,
      createdAt: createdAtPH,
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

    // Return userId and createdAt converted to PH time for display
    const createdAtPH = new Date(user.createdAt).toLocaleString('en-US', { timeZone: 'Asia/Manila' });
    return res.status(200).json({
      id: user._id,
      userId: user.userId,
      firstName: user.firstName,
      lastName: user.lastName,
      username: user.username,
      email: user.email,
      phone: user.phone,
      createdAt: createdAtPH,
    });
  } catch (err) {
    console.error('Login error:', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /api/auth/update-profile
router.post('/update-profile', async (req, res) => {
  try {
    let { id, username, email, phone } = req.body || {};

    // Input validation
    if (!id || !username || !email || !phone) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Normalize inputs
    if (typeof username === 'string') username = username.trim();
    if (typeof email === 'string') email = email.trim().toLowerCase();
    if (typeof phone === 'string') phone = phone.trim();

    // Check phone format using libphonenumber-js
    const parsed = parsePhoneNumberFromString(phone);
    if (!parsed || !parsed.isValid()) {
      return res.status(400).json({ error: 'Invalid phone number format' });
    }
    // Normalize to E.164 for storage
    phone = parsed.number; // E.164

    // Validate MongoDB ObjectId format
    if (!/^[0-9a-fA-F]{24}$/.test(id)) {
      return res.status(400).json({ error: 'Invalid user ID format' });
    }

    // Find user by id first
    const user = await User.findById(id).exec();
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Check for duplicate username/email/phone but exclude current user
    const existing = await User.findOne({
      _id: { $ne: id },
      $or: [
        { username },
        { email },
        { phone },
      ],
    }).exec();

    if (existing) {
      let field = 'username';
      if (existing.email === email) field = 'email';
      else if (existing.phone === phone) field = 'phone';
      return res.status(409).json({ error: `${field} already in use` });
    }

    try {
      // Update user fields
      user.username = username;
      user.email = email;
      user.phone = phone;
      await user.save();

      // Convert dates to PH time for response
      const createdAtPH = new Date(user.createdAt).toLocaleString('en-US', { timeZone: 'Asia/Manila' });

      // Return updated user data
      return res.status(200).json({
        id: user._id,
        userId: user.userId,
        firstName: user.firstName,
        lastName: user.lastName,
        username: user.username,
        email: user.email,
        phone: user.phone,
        createdAt: createdAtPH,
      });
    } catch (saveErr) {
      // Log the specific save error
      console.error('Error saving user:', {
        userId: id,
        error: saveErr.message,
        stack: saveErr.stack,
        validationErrors: saveErr.errors
      });
      
      // Check for validation errors
      if (saveErr.name === 'ValidationError') {
        return res.status(400).json({ 
          error: 'Validation failed', 
          details: Object.values(saveErr.errors).map(err => err.message)
        });
      }
      
      // Check for duplicate key errors
      if (saveErr.code === 11000) {
        return res.status(409).json({ error: 'This email, username, or phone is already in use' });
      }
      
      throw saveErr; // Re-throw for general error handling
    }
  } catch (err) {
    // Log the full error details
    console.error('Update profile error:', {
      userId: id,
      error: err.message,
      stack: err.stack,
      code: err.code
    });
  }
});

// POST /api/auth/forgot-password
router.post('/forgot-password', async (req, res) => {
  try {
    const { email } = req.body;
    if (!email) {
      return res.status(400).json({ error: 'Email is required' });
    }

    const user = await User.findOne({ email: email.trim().toLowerCase() });
    if (!user) {
      // For security, don't reveal whether the email exists
      return res.status(200).json({ message: 'If your email is registered, you will receive a reset code.' });
    }

    // Generate a random 6-digit code
    const resetCode = crypto.randomInt(100000, 999999).toString();
    const resetCodeExpires = new Date(Date.now() + 30 * 60000); // 30 minutes

    // Save the reset code and expiration
    user.resetCode = resetCode;
    user.resetCodeExpires = resetCodeExpires;
    await user.save();

    // TODO: In production, send this via email service
    console.log(`Reset code for ${email}: ${resetCode}`); // For testing

    return res.status(200).json({ message: 'If your email is registered, you will receive a reset code.' });
  } catch (err) {
    console.error('Forgot password error:', err);
    return res.status(500).json({ error: 'Failed to process request' });
  }
});

// POST /api/auth/reset-password
router.post('/reset-password', async (req, res) => {
  try {
    const { email, code, newPassword } = req.body;
    
    if (!email || !code || !newPassword) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    const user = await User.findOne({
      email: email.trim().toLowerCase(),
      resetCode: code,
      resetCodeExpires: { $gt: new Date() }
    });

    if (!user) {
      return res.status(400).json({ error: 'Invalid or expired reset code' });
    }

    // Hash the new password
    const passwordHash = await bcrypt.hash(newPassword, 10);

    // Update password and clear reset code
    user.passwordHash = passwordHash;
    user.resetCode = undefined;
    user.resetCodeExpires = undefined;
    await user.save();

    return res.status(200).json({ message: 'Password reset successful' });
  } catch (err) {
    console.error('Reset password error:', err);
    return res.status(500).json({ error: 'Failed to reset password' });
  }
});

module.exports = router;
