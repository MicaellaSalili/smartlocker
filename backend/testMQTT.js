/**
 * Test script to verify MQTT connection and unlock command
 * Run this to test if MQTT is working correctly
 * 
 * Usage: node testMQTT.js
 */

require('dotenv').config();
const mqttService = require('./src/services/mqttService');

console.log('\n===========================================');
console.log('  MQTT Test Script for Smart Locker');
console.log('===========================================\n');

// Connect to MQTT broker
mqttService.connect();

// Wait for connection
setTimeout(() => {
  if (mqttService.isConnected) {
    console.log('\n✅ MQTT Connection successful!\n');
    
    // Test unlock command
    console.log('📤 Sending test unlock command...');
    const testLockerId = 'LOCKER_001';
    
    const result = mqttService.unlockLocker(testLockerId, {
      test: true,
      waybill_id: 'TEST_WAYBILL_123',
      recipient_name: 'Test User'
    });
    
    if (result) {
      console.log(`✅ Unlock command sent successfully to ${testLockerId}`);
      console.log('\n📝 Check your ESP32 Serial Monitor to verify it received the command\n');
    } else {
      console.log('❌ Failed to send unlock command');
    }
    
    // Subscribe to status updates
    console.log(`\n📡 Subscribing to status updates for ${testLockerId}...`);
    mqttService.subscribeToLockerStatus(testLockerId, (data) => {
      console.log('\n📨 Status update received:');
      console.log(JSON.stringify(data, null, 2));
    });
    
    // Keep script running to receive status updates
    console.log('\n⏳ Listening for status updates... (Press Ctrl+C to exit)\n');
    
  } else {
    console.log('\n❌ MQTT Connection failed!');
    console.log('Please check:');
    console.log('  1. MQTT broker is running (mosquitto, HiveMQ, etc.)');
    console.log('  2. MQTT_BROKER_URL in .env is correct');
    console.log('  3. Network/firewall settings\n');
    process.exit(1);
  }
}, 2000);

// Handle exit
process.on('SIGINT', () => {
  console.log('\n\n👋 Disconnecting from MQTT...');
  mqttService.disconnect();
  process.exit(0);
});
