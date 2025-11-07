const mongoose = require('mongoose');

const userSchema = new mongoose.Schema(
  {
    firstName: { type: String, required: true, trim: true },
    lastName: { type: String, required: true, trim: true },
    // Application-specific user identifier like 'RD####'
    userId: { type: String, required: true, unique: true, index: true },
    username: { type: String, required: true, trim: true, unique: true, index: true },
    email: { type: String, required: true, trim: true, lowercase: true, unique: true, index: true },
    phone: { type: String, required: true, trim: true, unique: true, index: true },
    passwordHash: { type: String, required: true },
    resetCode: { type: String, sparse: true },
    resetCodeExpires: { type: Date },
    createdAt: { type: Date, default: Date.now }
  },
  { versionKey: false }
);

module.exports = mongoose.model('User', userSchema);
