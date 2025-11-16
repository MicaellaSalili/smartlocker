const Parcel = require('../src/models/Parcel');

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
