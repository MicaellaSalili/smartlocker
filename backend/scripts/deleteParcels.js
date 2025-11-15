require('dotenv').config({ path: '../.env' });
const mongoose = require('mongoose');
const Parcel = require('../src/models/Parcel');

const MONGODB_URI = process.env.MONGODB_URI;

if (!MONGODB_URI) {
  console.error('❌ MONGODB_URI not set in .env file!');
  process.exit(1);
}

async function deleteAllParcels() {
  try {
    console.log('Connecting to MongoDB...');
    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB');

    const result = await Parcel.deleteMany({});
    console.log(`🗑️ Deleted ${result.deletedCount} parcels from the database.`);

    process.exit(0);
  } catch (error) {
    console.error('❌ Error deleting parcels:', error);
    process.exit(1);
  }
}

deleteAllParcels();
