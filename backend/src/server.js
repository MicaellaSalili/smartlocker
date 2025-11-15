require('dotenv').config();
const express = require('express');
const cors = require('cors');
const mongoose = require('mongoose');
const Parcel = require('./models/Parcel');
const Locker = require('./models/Locker');
const mqttService = require('./services/mqttService');
const parcelController = require('../controllers/parcelController');

const app = express();

// Initialize MQTT connection (silent until ESP32 connects)
mqttService.connect();

console.log('\n🔐 SMART LOCKER BACKEND SERVER\n');

// Middleware
app.use(cors());
app.use(express.json());

// Store SSE clients for QR Generator display
const qrGeneratorClients = [];

// SSE endpoint for QR Generator updates
app.get('/api/lcd/stream', (req, res) => {
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders();

  // Add this client to the list
  qrGeneratorClients.push(res);
  
  console.log(`\n� QR Generator connected (Total: ${qrGeneratorClients.length})`);

  // Send initial connection confirmation
  res.write(`data: ${JSON.stringify({ type: 'connected', message: 'QR Generator connected' })}\n\n`);

  // Remove client when connection closes
  req.on('close', () => {
    const index = qrGeneratorClients.indexOf(res);
    if (index !== -1) {
      qrGeneratorClients.splice(index, 1);
    }
    // Only log disconnect if it was the last screen
    if (qrGeneratorClients.length === 0) {
      console.log(`� All QR Generators disconnected\n`);
    }
  });
});

// Helper function to broadcast QR updates to all QR Generator screens
function broadcastToQRGenerator(data) {
  const message = `data: ${JSON.stringify(data)}\n\n`;
  qrGeneratorClients.forEach(client => {
    client.write(message);
  });
}

// Routes
app.get('/health', (_req, res) => res.json({ ok: true }));
app.use('/api/auth', require('./routes/auth'));
// POST /api/parcels/finalize - Finalize transaction by waybill_id
app.post('/api/parcels/finalize', parcelController.finalizeTransaction);

// GET /api/lockers - Get all lockers with their status
app.get('/api/lockers', async (req, res) => {
  try {
    const lockers = await Locker.find()
      .populate('occupied_by_parcel', 'waybill_id recipient_first_name recipient_last_name status')
      .sort({ locker_id: 1 });
    
    // Clean up expired tokens
    const updates = [];
    for (const locker of lockers) {
      if (locker.clearExpiredToken()) {
        updates.push(locker.save());
      }
    }
    if (updates.length > 0) {
      await Promise.all(updates);
    }
    
    res.json({
      lockers,
      total: lockers.length,
      available: lockers.filter(l => l.status === 'AVAILABLE').length,
      occupied: lockers.filter(l => l.status === 'OCCUPIED').length,
      maintenance: lockers.filter(l => l.status === 'MAINTENANCE').length,
    });
  } catch (error) {
    console.error('Error fetching lockers:', error);
    res.status(500).json({ error: 'Failed to fetch lockers', details: error.message });
  }
});

// GET /api/lockers/:lockerId - Get specific locker details
app.get('/api/lockers/:lockerId', async (req, res) => {
  try {
    const { lockerId } = req.params;
    
    const locker = await Locker.findOne({ locker_id: lockerId })
      .populate('occupied_by_parcel');
    
    if (!locker) {
      return res.status(404).json({ error: 'Locker not found' });
    }
    
    // Clean up expired token if any
    locker.clearExpiredToken();
    await locker.save();
    
    res.json({
      locker,
      token_valid: locker.isTokenValid()
    });
  } catch (error) {
    console.error('Error fetching locker:', error);
    res.status(500).json({ error: 'Failed to fetch locker', details: error.message });
  }
});

// PUT /api/lockers/:lockerId/status - Update locker status (for maintenance, etc.)
app.put('/api/lockers/:lockerId/status', async (req, res) => {
  try {
    const { lockerId } = req.params;
    const { status } = req.body;
    
    if (!['AVAILABLE', 'OCCUPIED', 'MAINTENANCE'].includes(status)) {
      return res.status(400).json({ error: 'Invalid status. Must be AVAILABLE, OCCUPIED, or MAINTENANCE' });
    }
    
    const locker = await Locker.findOne({ locker_id: lockerId });
    
    if (!locker) {
      return res.status(404).json({ error: 'Locker not found' });
    }
    
    locker.status = status;
    
    // If setting to AVAILABLE, clear token and parcel reference
    if (status === 'AVAILABLE') {
      locker.current_token = null;
      locker.token_expires_at = null;
      locker.occupied_by_parcel = null;
    }
    
    await locker.save();
    
    res.json({
      message: 'Locker status updated',
      locker
    });
  } catch (error) {
    console.error('Error updating locker status:', error);
    res.status(500).json({ error: 'Failed to update locker status', details: error.message });
  }
});


// POST /api/parcel/log - Save transaction payload (audit + verification data)
app.post('/api/parcel/log', async (req, res) => {
  try {
    const {
      recipient_first_name,
      recipient_last_name,
      recipient_phone,
      locker_id,
      waybill_id,
      waybill_details,
      image_embedding_vector
    } = req.body;

    // Validate required fields
    if (!recipient_first_name || !recipient_last_name || !recipient_phone || 
        !locker_id || !waybill_id || !waybill_details || !image_embedding_vector) {
      return res.status(400).json({ 
        error: 'Missing required fields',
        required: ['recipient_first_name', 'recipient_last_name', 'recipient_phone', 
                   'locker_id', 'waybill_id', 'waybill_details', 'image_embedding_vector']
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
      locker_id,
      waybill_id,
      waybill_details,
      image_embedding_vector,
      status: 'DELIVERED',
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

  // Update status to DELIVERED
  parcel.status = 'DELIVERED';
  await parcel.save();

    // Door is already unlocked from QR scan, no need to unlock again
    // Just update the status in the database

    res.json({
      message: 'Transaction verified successfully',
      transaction_id: parcel._id,
      locker_id: parcel.locker_id,
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

  // PUT /api/parcel/claim/:id - Update parcel status to CLAIMED and reset locker
  app.put('/api/parcel/claim/:id', async (req, res) => {
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

      // Update status to CLAIMED
      parcel.status = 'CLAIMED';
      await parcel.save();

      // Find and reset the associated locker
      if (parcel.locker_id) {
        const locker = await Locker.findOne({ locker_id: parcel.locker_id });
        if (locker) {
          await locker.setAvailable();
        }
      }

      res.json({
        message: 'Parcel claimed and locker reset to AVAILABLE',
        transaction_id: parcel._id,
        locker_id: parcel.locker_id,
        status: parcel.status,
        claimed_at: parcel.updatedAt
      });

    } catch (error) {
      console.error('Error claiming parcel:', error);
      res.status(500).json({ error: 'Failed to claim parcel', details: error.message });
    }
  });

// PUT /api/locker/:lockerId/lock - Lock the locker door (called after courier closes door)
app.put('/api/locker/:lockerId/lock', async (req, res) => {
  try {
    const { lockerId } = req.params;

    if (!lockerId) {
      return res.status(400).json({ error: 'Locker ID is required' });
    }

    // 🔒 LOCK THE LOCKER via MQTT
    const lockSuccess = mqttService.lockLocker(lockerId);

    if (lockSuccess) {
      res.json({
        message: 'Lock command sent successfully',
        locker_id: lockerId,
        status: 'LOCKED',
        timestamp: new Date()
      });
    } else {
      res.status(500).json({
        error: 'Failed to send lock command',
        locker_id: lockerId
      });
    }

  } catch (error) {
    console.error('Error sending lock command:', error);
    res.status(500).json({ error: 'Failed to send lock command', details: error.message });
  }
});

// GET /api/locker/available - Get next available locker and generate token
app.get('/api/locker/available', async (req, res) => {
  try {
    // Find an available locker from database
    let availableLocker = await Locker.findOne({ 
      status: 'AVAILABLE' 
    }).sort({ locker_id: 1 }); // Get first available by locker_id
    
    if (!availableLocker) {
      // Count total lockers
      const totalLockers = await Locker.countDocuments();
      
      return res.status(503).json({ 
        error: 'No available lockers',
        message: 'All lockers are currently occupied. Please try again later.',
        total_lockers: totalLockers,
        occupied_lockers: totalLockers
      });
    }
    
    // Generate token for the available locker
    const crypto = require('crypto');
    const token = crypto.randomBytes(8).toString('hex');
    
    // Set expiration time (5 minutes from now)
    const expiresAt = new Date(Date.now() + (5 * 60 * 1000));
    
    // Update locker with token
    availableLocker.current_token = token;
    availableLocker.token_expires_at = expiresAt;
    await availableLocker.save();
    
    // Format QR code content
    const qrContent = `${availableLocker.locker_id}:TOKEN_${token}:EXP_${expiresAt.getTime()}`;
    
    // Log QR content for easy testing
    console.log('\n📱 QR CODE GENERATED');
    console.log(`   Locker:      ${availableLocker.locker_id}`);
    console.log(`   Token:       ${token.substring(0, 16)}`);
    console.log(`   Expires:     ${expiresAt.toLocaleTimeString()}`);
    console.log(`   Valid for:   5 minutes`);
    console.log(`   QR Content:  ${qrContent}`);
    console.log(`   � Broadcasting to ${qrGeneratorClients.length} QR Generator(s)\n`);
    
    // Broadcast QR code to all connected QR Generator screens
    broadcastToQRGenerator({
      type: 'qr_update',
      qr_content: qrContent,
      locker_id: availableLocker.locker_id,
      token: token,
      expires_at: expiresAt.toISOString()
    });
    
    // Count available lockers
    const availableCount = await Locker.countDocuments({ status: 'AVAILABLE' });
    const totalCount = await Locker.countDocuments();
    
    res.json({
      message: 'Available locker assigned successfully',
      locker_id: availableLocker.locker_id,
      token,
      expires_at: expiresAt.toISOString(),
      expires_in_seconds: 300,
      qr_content: qrContent,
      available_count: availableCount,
      total_lockers: totalCount
    });

  } catch (error) {
    console.error('Error getting available locker:', error);
    res.status(500).json({ error: 'Failed to get available locker', details: error.message });
  }
});

// POST /api/locker/generate-token - Generate access token for locker
app.post('/api/locker/generate-token', async (req, res) => {
  try {
    const { lockerId } = req.body;

    if (!lockerId) {
      return res.status(400).json({ error: 'Locker ID is required' });
    }

    // Validate locker ID format (must be fixed locker IDs)
    const validLockerIds = ['LOCKER_001', 'LOCKER_002', 'LOCKER_003', 'LOCKER_004', 'LOCKER_005'];
    if (!validLockerIds.includes(lockerId)) {
      return res.status(400).json({ 
        error: 'Invalid locker ID',
        valid_lockers: validLockerIds 
      });
    }

    // Generate random token (16 characters hex)
    const crypto = require('crypto');
    const token = crypto.randomBytes(8).toString('hex');
    
    // Set expiration time (5 minutes from now)
    const expiresAt = Date.now() + (5 * 60 * 1000);
    
    // Store token temporarily in memory (in production, use Redis or database)
    if (!global.lockerTokens) {
      global.lockerTokens = new Map();
    }
    
    global.lockerTokens.set(token, {
      lockerId,
      expiresAt,
      used: false
    });
    
    // Clean up expired tokens
    for (const [key, value] of global.lockerTokens.entries()) {
      if (value.expiresAt < Date.now()) {
        global.lockerTokens.delete(key);
      }
    }
    
    // Format QR code content: LOCKER_ID:TOKEN:EXPIRATION
    const qrContent = `${lockerId}:TOKEN_${token}:EXP_${expiresAt}`;
    
    res.json({
      message: 'Access token generated successfully',
      locker_id: lockerId,
      token,
      expires_at: new Date(expiresAt).toISOString(),
      expires_in_seconds: 300,
      qr_content: qrContent
    });

  } catch (error) {
    console.error('Error generating token:', error);
    res.status(500).json({ error: 'Failed to generate token', details: error.message });
  }
});

// PUT /api/locker/:lockerId/unlock - Unlock the locker door (called after QR scan with token validation)
app.put('/api/locker/:lockerId/unlock', async (req, res) => {
  try {
    const { lockerId } = req.params;
    const { token } = req.body;

    if (!lockerId) {
      return res.status(400).json({ error: 'Locker ID is required' });
    }

    if (!token) {
      return res.status(400).json({ error: 'Access token is required' });
    }

    // Find locker in database
    const locker = await Locker.findOne({ locker_id: lockerId });
    
    if (!locker) {
      return res.status(404).json({ error: 'Locker not found' });
    }
    
    // Validate token
    if (locker.current_token !== token) {
      return res.status(401).json({ error: 'Invalid token for this locker' });
    }
    
    // Check if token is expired
    if (!locker.token_expires_at || new Date() >= locker.token_expires_at) {
      // Clear expired token
      locker.current_token = null;
      locker.token_expires_at = null;
      await locker.save();
      
      return res.status(401).json({ error: 'Token has expired' });
    }
    
    // 🔓 UNLOCK THE LOCKER via MQTT (optional - may fail if ESP32 offline)
    const unlockSuccess = mqttService.unlockLocker(lockerId, {
      trigger: 'QR_SCAN_WITH_TOKEN',
      token,
      timestamp: new Date().toISOString()
    });

    // For testing without ESP32, we allow unlock even if MQTT fails
    console.log(`\n✅ LOCKER UNLOCKED`);
    console.log(`   Locker ID: ${lockerId}`);
    console.log(`   Token: ${token.substring(0, 16)}...`);
    console.log(`   Time: ${new Date().toLocaleTimeString()}`);
    if (!unlockSuccess) {
      console.log(`   ⚠️  MQTT command failed (ESP32 offline - but continuing anyway)`);
    }
    console.log('');
    
    // Update locker status
    locker.status = 'OCCUPIED';
    locker.last_opened_at = new Date();
    locker.current_token = null; // Clear token after use
    locker.token_expires_at = null;
    await locker.save();
    
    res.json({
      message: 'Unlock command sent successfully',
      locker_id: lockerId,
      status: 'UNLOCKED',
      timestamp: new Date(),
      mqtt_status: unlockSuccess ? 'sent' : 'offline (ESP32 not connected)'
    });

  } catch (error) {
    console.error('Error sending unlock command:', error);
    res.status(500).json({ error: 'Failed to send unlock command', details: error.message });
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

    // Find and reset the associated locker
    if (parcel.locker_id) {
      const locker = await Locker.findOne({ locker_id: parcel.locker_id });
      if (locker) {
        await locker.setAvailable();
      }
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

// MongoDB connection using Atlas URI from .env
const MONGODB_URI = process.env.MONGODB_URI;
const PORT = process.env.PORT || 3000;

if (!MONGODB_URI) {
  console.error('❌ MONGODB_URI not set in .env file!');
  process.exit(1);
}

mongoose.connect(MONGODB_URI, {
  useNewUrlParser: true,
  useUnifiedTopology: true,
})
  .then(() => {
    console.log('✅ Connected to MongoDB Atlas');
    console.log(`   Database: ${MONGODB_URI.split('/').pop()}`);
    app.listen(PORT, '0.0.0.0', () => {
      console.log('\n🚀 SERVER READY');
      console.log(`   Port:        ${PORT}`);
      console.log(`   Local:       http://localhost:${PORT}`);
      // Optionally, dynamically show network IP
      console.log(`   Network:     http://0.0.0.0:${PORT}`);
      console.log('\n   📱 Flutter App:    Ready to accept requests');
      console.log('   � QR Generator:   Waiting for connection...');
      console.log('   🔌 ESP32:          Offline (this is normal for now)\n');
    });
  })
  .catch((err) => {
    console.error('\n❌ MongoDB Atlas connection failed:', err.message);
    console.error('   Check your Atlas URI and credentials in .env!\n');
    process.exit(1);
  });