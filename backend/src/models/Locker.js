const mongoose = require('mongoose');

const lockerSchema = new mongoose.Schema({
  locker_id: {
    type: String,
    required: true,
    unique: true,
    // e.g., LOCKER_001, LOCKER_002, etc.
  },
  status: {
    type: String,
    enum: ['AVAILABLE', 'OCCUPIED', 'MAINTENANCE'],
    default: 'AVAILABLE',
  },
  current_token: {
    type: String,
    default: null,
    // The active token for this locker (null if no active token)
  },
  token_expires_at: {
    type: Date,
    default: null,
    // When the current token expires
  },
  occupied_by_parcel: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Parcel',
    default: null,
    // Reference to the parcel currently in this locker
  },
  last_opened_at: {
    type: Date,
    default: null,
  },
  created_at: {
    type: Date,
    default: Date.now,
  },
  updated_at: {
    type: Date,
    default: Date.now,
  },
});

// Update the updated_at timestamp before saving
lockerSchema.pre('save', function(next) {
  this.updated_at = Date.now();
  next();
});

// Method to check if token is valid
lockerSchema.methods.isTokenValid = function() {
  if (!this.current_token || !this.token_expires_at) {
    return false;
  }
  return new Date() < this.token_expires_at;
};

// Method to clear expired token
lockerSchema.methods.clearExpiredToken = function() {
  if (this.current_token && this.token_expires_at && new Date() >= this.token_expires_at) {
    this.current_token = null;
    this.token_expires_at = null;
    return true;
  }
  return false;
};

module.exports = mongoose.model('Locker', lockerSchema);
