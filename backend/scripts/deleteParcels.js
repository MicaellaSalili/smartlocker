require('dotenv').config({ path: '../.env' });
const mongoose = require('mongoose');
const Parcel = require('../src/models/Parcel');

const MONGODB_URI = process.env.MONGODB_URI;

if (!MONGODB_URI) {
  console.error('❌ MONGODB_URI not set in .env file!');
  process.exit(1);
}

async function deleteParcels() {
  try {
    await mongoose.connect(MONGODB_URI, {
      useNewUrlParser: true,
      useUnifiedTopology: true,
    });
    console.log('✅ Connected to MongoDB');

    const result = await Parcel.deleteMany({});
    console.log(`🗑️ Deleted ${result.deletedCount} parcels from the collection.`);

    await mongoose.disconnect();
    console.log('🔌 Disconnected from MongoDB');
  } catch (error) {
    console.error('❌ Error deleting parcels:', error.message);
    process.exit(1);
  }
}

deleteParcels();