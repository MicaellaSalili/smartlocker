require('dotenv').config();
const express = require('express');
const cors = require('cors');
const mongoose = require('mongoose');
const Parcel = require('./models/Parcel');

const app = express();

// Middleware
app.use(cors());
app.use(express.json());

// Routes
app.get('/health', (_req, res) => res.json({ ok: true }));
app.use('/api/auth', require('./routes/auth'));

// POST /api/parcel/log - Save transaction payload (audit + verification data)
app.post('/api/parcel/log', async (req, res) => {
  try {
    const {
      recipient_first_name,
      recipient_last_name,
      recipient_phone,
      waybill_id,
      waybill_details,
      image_embedding_vector
    } = req.body;

    // Validate required fields
    if (!recipient_first_name || !recipient_last_name || !recipient_phone || 
        !waybill_id || !waybill_details || !image_embedding_vector) {
      return res.status(400).json({ 
        error: 'Missing required fields',
        required: ['recipient_first_name', 'recipient_last_name', 'recipient_phone', 
                   'waybill_id', 'waybill_details', 'image_embedding_vector']
      });
    }

    // Validate embedding vector
    if (!Array.isArray(image_embedding_vector) || image_embedding_vector.length !== 128) {
      return res.status(400).json({ 
        error: 'image_embedding_vector must be an array of 128 numbers' 
      });
    }

    // Create new parcel document
    const parcel = new Parcel({
      recipient_first_name,
      recipient_last_name,
      recipient_phone,
      waybill_id,
      waybill_details,
      image_embedding_vector,
      status: 'PENDING_VERIFICATION',
      initial_timestamp: new Date()
    });

    await parcel.save();

    res.status(201).json({
      message: 'Transaction logged successfully',
      transaction_id: parcel._id,
      waybill_id: parcel.waybill_id,
      status: parcel.status,
      timestamp: parcel.initial_timestamp
    });

  } catch (error) {
    if (error.code === 11000) {
      // Duplicate waybill_id
      return res.status(409).json({ 
        error: 'Waybill ID already exists',
        waybill_id: req.body.waybill_id 
      });
    }
    console.error('Error logging transaction:', error);
    res.status(500).json({ error: 'Failed to log transaction', details: error.message });
  }
});

// GET /api/parcel/:id - Retrieve verification reference data
app.get('/api/parcel/:id', async (req, res) => {
  try {
    const { id } = req.params;

    // Validate MongoDB ObjectId format
    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({ error: 'Invalid transaction ID format' });
    }

    const parcel = await Parcel.findById(id);

    if (!parcel) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    // Return reference data for live verification
    res.json({
      transaction_id: parcel._id,
      waybill_id: parcel.waybill_id,
      waybill_details: parcel.waybill_details,
      image_embedding_vector: parcel.image_embedding_vector,
      status: parcel.status,
      recipient_first_name: parcel.recipient_first_name,
      recipient_last_name: parcel.recipient_last_name,
      recipient_phone: parcel.recipient_phone,
      initial_timestamp: parcel.initial_timestamp
    });

  } catch (error) {
    console.error('Error retrieving transaction:', error);
    res.status(500).json({ error: 'Failed to retrieve transaction', details: error.message });
  }
});

// PUT /api/parcel/success/:id - Update status to VERIFIED_SUCCESS
app.put('/api/parcel/success/:id', async (req, res) => {
  try {
    const { id } = req.params;

    // Validate MongoDB ObjectId format
    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({ error: 'Invalid transaction ID format' });
    }

    const parcel = await Parcel.findById(id);

    if (!parcel) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    // Update status to VERIFIED_SUCCESS
    parcel.status = 'VERIFIED_SUCCESS';
    await parcel.save();

    res.json({
      message: 'Transaction verified successfully',
      transaction_id: parcel._id,
      waybill_id: parcel.waybill_id,
      status: parcel.status,
      initial_timestamp: parcel.initial_timestamp,
      verified_at: parcel.updatedAt,
      recipient: {
        first_name: parcel.recipient_first_name,
        last_name: parcel.recipient_last_name,
        phone: parcel.recipient_phone
      }
    });

  } catch (error) {
    console.error('Error updating transaction:', error);
    res.status(500).json({ error: 'Failed to update transaction', details: error.message });
  }
});

// DELETE /api/parcel/:id - Transaction rollback
app.delete('/api/parcel/:id', async (req, res) => {
  try {
    const { id } = req.params;

    // Validate MongoDB ObjectId format
    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({ error: 'Invalid transaction ID format' });
    }

    const parcel = await Parcel.findByIdAndDelete(id);

    if (!parcel) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    res.json({
      message: 'Transaction deleted successfully',
      transaction_id: parcel._id,
      waybill_id: parcel.waybill_id,
      deleted_at: new Date()
    });

  } catch (error) {
    console.error('Error deleting transaction:', error);
    res.status(500).json({ error: 'Failed to delete transaction', details: error.message });
  }
});

// MongoDB connection
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/smartlocker';
const PORT = process.env.PORT || 3000;

mongoose
  .connect(MONGODB_URI)
  .then(() => {
    console.log('Connected to MongoDB');
    app.listen(PORT, () => console.log(`Server listening on port ${PORT}`));
  })
  .catch((err) => {
    console.error('Failed to connect to MongoDB:', err.message);
    process.exit(1);
  });
