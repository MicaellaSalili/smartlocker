const Parcel = require('../src/models/Parcel');
const mqttService = require('../src/services/mqttService');
const mongoose = require('mongoose');

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
