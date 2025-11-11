require('dotenv').config({ path: '../.env' });
const mongoose = require('mongoose');
const Locker = require('../src/models/Locker');

const MONGODB_URI = process.env.MONGODB_URI;

if (!MONGODB_URI) {
  console.error('❌ MONGODB_URI not set in .env file!');
  process.exit(1);
}

async function deleteLockers() {
  try {
    await mongoose.connect(MONGODB_URI, {
      useNewUrlParser: true,
      useUnifiedTopology: true,
    });
    console.log('✅ Connected to MongoDB');

    const result = await Locker.deleteMany({});
    console.log(`🗑️ Deleted ${result.deletedCount} lockers from the collection.`);

    await mongoose.disconnect();
    console.log('🔌 Disconnected from MongoDB');
  } catch (error) {
    console.error('❌ Error deleting lockers:', error.message);
    process.exit(1);
  }
}

deleteLockers();