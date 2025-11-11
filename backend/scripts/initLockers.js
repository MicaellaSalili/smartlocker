require('dotenv').config({ path: '../.env' });
const mongoose = require('mongoose');
const Locker = require('../src/models/Locker');

const MONGODB_URI = process.env.MONGODB_URI;

if (!MONGODB_URI) {
  console.error('❌ MONGODB_URI not set in .env file!');
  process.exit(1);
}

// Initialize 5 lockers (you mentioned you only have 1 physical unit, but we'll create 5 in DB for scalability)
const lockerIds = ['LOCKER_001', 'LOCKER_002', 'LOCKER_003', 'LOCKER_004', 'LOCKER_005'];

async function initializeLockers() {
  try {
    console.log('Connecting to MongoDB...');
    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB');
    // Debug: Print database name and collections
    const dbNameMatch = MONGODB_URI.match(/mongodb(?:\+srv)?:\/\/[^\/]+\/(\w+)/);
    const dbName = dbNameMatch ? dbNameMatch[1] : '(default or test)';
    console.log(`   Database (from URI): ${dbName}`);
    await mongoose.connection.db.listCollections().toArray(function(err, collections) {
      if (err) {
        console.log('   Error listing collections:', err.message);
      } else {
        console.log('   Collections:');
        collections.forEach(col => console.log(`     - ${col.name}`));
      }
    });

    for (const lockerId of lockerIds) {
      // Check if locker already exists
      const existingLocker = await Locker.findOne({ locker_id: lockerId });
      
      if (existingLocker) {
        console.log(`⏭️  Locker ${lockerId} already exists, skipping...`);
        continue;
      }

      // Create new locker
      const locker = new Locker({
        locker_id: lockerId,
        status: 'AVAILABLE',
        current_token: null,
        token_expires_at: null,
        occupied_by_parcel: null,
        last_opened_at: null,
      });

      await locker.save();
      console.log(`✅ Created locker: ${lockerId}`);
    }

    console.log('\n🎉 All lockers initialized successfully!');
    console.log('\n📊 Summary:');
    
    const allLockers = await Locker.find().sort({ locker_id: 1 });
    console.log(`Total lockers: ${allLockers.length}`);
    
    allLockers.forEach(locker => {
      console.log(`  - ${locker.locker_id}: ${locker.status}`);
    });

    process.exit(0);
  } catch (error) {
    console.error('❌ Error initializing lockers:', error);
    process.exit(1);
  }
}

initializeLockers();