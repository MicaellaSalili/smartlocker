const mongoose = require('mongoose');

const parcelSchema = new mongoose.Schema({
  recipient_first_name: {
    type: String,
    required: true,
    trim: true
  },
  recipient_last_name: {
    type: String,
    required: true,
    trim: true
  },
  recipient_phone: {
    type: String,
    required: true,
    trim: true
  },
  locker_id: {
    type: String,
    required: true,
    trim: true
  },
  waybill_id: {
    type: String,
    required: true,
    unique: true,
    trim: true
  },
  waybill_details: {
    type: String,
    required: true
  },
  image_embedding_vector: {
    type: [Number],
    required: true,
    validate: {
      validator: function(v) {
        return Array.isArray(v) && v.length === 128;
      },
      message: 'Embedding vector must contain exactly 128 numbers'
    }
  },
  status: {
    type: String,
    enum: ['PENDING_VERIFICATION', 'VERIFIED_SUCCESS', 'FAILED'],
    default: 'PENDING_VERIFICATION'
  },
  initial_timestamp: {
    type: Date,
    default: Date.now
  }
}, {
  timestamps: true // Adds createdAt and updatedAt fields automatically
});

// Create indexes (removed duplicate waybill_id index since it's already unique in schema)
parcelSchema.index({ status: 1 });

const Parcel = mongoose.model('Parcel', parcelSchema);

module.exports = Parcel;
