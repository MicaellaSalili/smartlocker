// Finalizes a transaction by updating parcel status to 'CLAIMED'
exports.finalizeTransaction = async (req, res) => {
	try {
		const { waybill_id } = req.body;
		if (!waybill_id) {
			return res.status(400).json({ error: 'waybill_id is required.' });
		}

		const parcel = await Parcel.findOne({ waybill_id });
		if (!parcel) {
			return res.status(404).json({ error: 'Parcel not found.' });
		}

		parcel.status = 'CLAIMED';
		await parcel.save();

		return res.status(200).json({ message: 'Parcel status updated to CLAIMED.' });
	} catch (err) {
		return res.status(500).json({ error: 'Internal server error', details: err.message });
	}
};
const Parcel = require('../src/models/Parcel');

// Handles initial parcel scan and creation
exports.createParcelScan = async (req, res) => {
	try {
		const { waybill_id, locker_id, image_embedding_vector, recipient_first_name, recipient_last_name, recipient_phone, waybill_details } = req.body;

		// Validate required fields
		if (!waybill_id || !locker_id || !Array.isArray(image_embedding_vector) || image_embedding_vector.length !== 128) {
			return res.status(400).json({
				error: 'Missing required fields or invalid embedding vector. waybill_id, locker_id, and image_embedding_vector[128] are required.'
			});
		}

		// Create new Parcel record
		const parcel = await Parcel.create({
			waybill_id,
			locker_id,
			image_embedding_vector,
			recipient_first_name,
			recipient_last_name,
			recipient_phone,
			waybill_details,
			status: 'SCANNED',
			initial_timestamp: Date.now(),
		});

		return res.status(201).json(parcel);
	} catch (err) {
		// Duplicate waybill_id error
		if (err.code === 11000 && err.keyPattern && err.keyPattern.waybill_id) {
			return res.status(409).json({ error: 'Parcel with this waybill_id already exists.' });
		}
		// Other errors
		return res.status(500).json({ error: 'Internal server error', details: err.message });
	}
};
