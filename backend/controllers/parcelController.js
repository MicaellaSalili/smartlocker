const Parcel = require('../src/models/Parcel');
const mqttService = require('../src/services/mqttService');
const smsService = require('../src/services/smsService');
const mongoose = require('mongoose');

// Deliver parcel after courier drop-off (marks as DELIVERED)
exports.deliverParcel = async (req, res) => {
  try {
    const { waybill_id, locker_id } = req.body;
    if (!waybill_id || !locker_id) {
      return res.status(400).json({ error: 'waybill_id and locker_id are required' });
    }
    const parcel = await Parcel.findOne({ waybill_id });
    if (!parcel) {
      return res.status(404).json({ error: 'Parcel not found' });
    }
    parcel.status = 'DELIVERED';
    parcel.locker_id = locker_id;
    await parcel.save();
    console.log(`✅ Parcel delivered: ${waybill_id} → Status: DELIVERED, Locker: ${locker_id}`);
    res.json({
      message: 'Parcel status updated to DELIVERED',
      waybill_id: parcel.waybill_id,
      status: parcel.status,
      locker_id: parcel.locker_id,
      delivered_at: parcel.updatedAt
    });
  } catch (error) {
    console.error('Error delivering parcel:', error);
    res.status(500).json({ error: 'Failed to deliver parcel', details: error.message });
  }
};

exports.finalizeTransaction = async (req, res) => {
  try {
    const { waybill_id } = req.body;
    if (!waybill_id) {
      return res.status(400).json({ error: 'waybill_id is required' });
    }
    const parcel = await Parcel.findOne({ waybill_id });
    if (!parcel) {
      return res.status(404).json({ error: 'Parcel not found' });
    }
    parcel.status = 'CLAIMED';
    await parcel.save();
    res.json({
      message: 'Parcel status updated to CLAIMED',
      waybill_id: parcel.waybill_id,
      status: parcel.status,
      claimed_at: parcel.updatedAt
    });
  } catch (error) {
    console.error('Error finalizing transaction:', error);
    res.status(500).json({ error: 'Failed to finalize transaction', details: error.message });
  }
};

// GET /api/transaction/:id/reference
exports.getReferenceData = async (req, res) => {
  try {
    const { id } = req.params;
    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({ error: 'Invalid transaction ID format' });
    }
    const parcel = await Parcel.findById(id);
    if (!parcel) {
      return res.status(404).json({ error: 'Parcel not found' });
    }
    res.json({
      waybillId: parcel.waybill_id,
      waybillDetails: parcel.waybill_details,
      embedding: parcel.image_embedding_vector
    });
  } catch (error) {
    console.error('Error fetching reference data:', error);
    res.status(500).json({ error: 'Failed to fetch reference data', details: error.message });
  }
};

// POST /api/transaction/:id/finalize
exports.finalizeTransactionById = async (req, res) => {
  try {
    const { id } = req.params;
    const parcel = await Parcel.findById(id);
    if (!parcel) {
      return res.status(404).json({ error: 'Parcel not found' });
    }
    parcel.status = 'CLAIMED';
    await parcel.save();

    // Set associated locker to AVAILABLE
    if (parcel.locker_id) {
      const Locker = require('../src/models/Locker');
      const locker = await Locker.findOne({ locker_id: parcel.locker_id });
      if (locker) {
        locker.status = 'AVAILABLE';
        locker.occupied_by_parcel = null;
        locker.current_token = null;
        locker.token_expires_at = null;
        await locker.save();
      }
    }

    res.json({
      message: 'Parcel status updated to CLAIMED and locker set to AVAILABLE',
      waybill_id: parcel.waybill_id,
      status: parcel.status,
      claimed_at: parcel.updatedAt
    });
  } catch (error) {
    console.error('Error finalizing transaction by id:', error);
    res.status(500).json({ error: 'Failed to finalize transaction', details: error.message });
  }
};

// DELETE /api/transaction/:id
exports.deleteTransaction = async (req, res) => {
  try {
    const { id } = req.params;
    const parcel = await Parcel.findByIdAndDelete(id);
    if (!parcel) {
      return res.status(404).json({ error: 'Parcel not found' });
    }
    res.json({ message: 'Parcel deleted successfully', waybill_id: parcel.waybill_id });
  } catch (error) {
    console.error('Error deleting transaction:', error);
    res.status(500).json({ error: 'Failed to delete transaction', details: error.message });
  }
};

// POST /api/locker/:id/lock
exports.lockLocker = async (req, res) => {
  try {
    const { id } = req.params;
    // Call MQTT service to lock the locker
    const result = await mqttService.lockLocker(id);
    res.json({ message: 'Locker lock command sent', locker_id: id, mqtt_result: result });
  } catch (error) {
    console.error('Error locking locker:', error);
    res.status(500).json({ error: 'Failed to lock locker', details: error.message });
  }
};

// POST /api/transaction/:id/request-otp - Generate and send OTP via SMS
exports.requestOTP = async (req, res) => {
  try {
    const { id } = req.params;

    // Validate MongoDB ObjectId format
    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({ error: 'Invalid transaction ID format' });
    }

    const parcel = await Parcel.findById(id);
    if (!parcel) {
      return res.status(404).json({ error: 'Parcel not found' });
    }

    // Check if parcel is already claimed
    if (parcel.status === 'CLAIMED') {
      return res.status(400).json({ error: 'Parcel already claimed' });
    }

    // Generate 6-digit OTP
    const otp = Math.floor(100000 + Math.random() * 900000).toString();

    // Save OTP and expiry (5 minutes from now)
    parcel.otp = otp;
    parcel.otpExpires = new Date(Date.now() + 5 * 60 * 1000);
    await parcel.save();

    // TESTING MODE: Bypass SMS sending, log OTP to console instead
    console.log(`\n📱 OTP GENERATED (TESTING MODE - SMS BYPASSED)`);
    console.log(`   Transaction ID: ${parcel._id}`);
    console.log(`   Waybill: ${parcel.waybill_id}`);
    console.log(`   Recipient: ${parcel.recipient_first_name} ${parcel.recipient_last_name}`);
    console.log(`   Phone: ${parcel.recipient_phone}`);
    console.log(`   🔑 OTP: ${otp}`);
    console.log(`   Expires: ${parcel.otpExpires.toLocaleString()}`);
    console.log(`   Valid for: 5 minutes\n`);

    res.json({
      message: 'OTP generated successfully (check console for OTP)',
      transaction_id: parcel._id,
      phone: parcel.recipient_phone.replace(/(\d{3})\d{4}(\d{4})/, '$1****$2'), // Mask phone number
      testing_mode: true,
      otp_in_console: true
    });
  } catch (error) {
    console.error('Error requesting OTP:', error);
    res.status(500).json({ error: 'Failed to request OTP', details: error.message });
  }
};

// POST /api/transaction/:id/verify-otp - Verify OTP and allow claim
exports.verifyOTP = async (req, res) => {
  try {
    const { id } = req.params;
    const { otp } = req.body;

    // Validate MongoDB ObjectId format
    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({ error: 'Invalid transaction ID format' });
    }

    if (!otp) {
      return res.status(400).json({ error: 'OTP is required' });
    }

    const parcel = await Parcel.findById(id);
    if (!parcel) {
      return res.status(404).json({ error: 'Parcel not found' });
    }

    // Check if parcel is already claimed
    if (parcel.status === 'CLAIMED') {
      return res.status(400).json({ error: 'Parcel already claimed' });
    }

    // Check if OTP exists
    if (!parcel.otp) {
      return res.status(400).json({ error: 'No OTP requested for this parcel' });
    }

    // Check if OTP is expired
    if (Date.now() > parcel.otpExpires) {
      return res.status(400).json({ error: 'OTP has expired. Please request a new one.' });
    }

    // Verify OTP
    if (parcel.otp !== otp.trim()) {
      return res.status(400).json({ error: 'Invalid OTP' });
    }

    // OTP is valid - clear OTP and allow claim process to continue
    parcel.otp = null;
    parcel.otpExpires = null;
    await parcel.save();

    res.json({
      message: 'OTP verified successfully',
      transaction_id: parcel._id,
      waybill_id: parcel.waybill_id,
      locker_id: parcel.locker_id,
      verified: true
    });
  } catch (error) {
    console.error('Error verifying OTP:', error);
    res.status(500).json({ error: 'Failed to verify OTP', details: error.message });
  }
};