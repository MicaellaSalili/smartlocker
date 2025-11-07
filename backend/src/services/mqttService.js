const mqtt = require('mqtt');

class MQTTService {
  constructor() {
    this.client = null;
    this.isConnected = false;
    
    // MQTT Broker configuration
    // Option 1: Use public test broker (for testing only)
    this.brokerUrl = process.env.MQTT_BROKER_URL || 'mqtt://test.mosquitto.org';
    
    // Option 2: Use local broker (recommended for production)
    // Install mosquitto: https://mosquitto.org/download/
    // this.brokerUrl = 'mqtt://localhost:1883';
    
    // Option 3: Use cloud MQTT service (HiveMQ, CloudMQTT, etc.)
    // this.brokerUrl = 'mqtt://your-broker.com:1883';
    
    this.options = {
      clientId: `smartlocker_backend_${Math.random().toString(16).slice(3)}`,
      username: process.env.MQTT_USERNAME || '',
      password: process.env.MQTT_PASSWORD || '',
      clean: true,
      reconnectPeriod: 1000,
    };
  }

  connect() {
    try {
      console.log(`Connecting to MQTT broker: ${this.brokerUrl}`);
      this.client = mqtt.connect(this.brokerUrl, this.options);

      this.client.on('connect', () => {
        this.isConnected = true;
        console.log('✅ MQTT Client connected to broker');
      });

      this.client.on('error', (error) => {
        console.error('❌ MQTT Connection error:', error);
        this.isConnected = false;
      });

      this.client.on('offline', () => {
        console.log('⚠️  MQTT Client offline');
        this.isConnected = false;
      });

      this.client.on('reconnect', () => {
        console.log('🔄 MQTT Client reconnecting...');
      });

    } catch (error) {
      console.error('Failed to connect to MQTT broker:', error);
    }
  }

  /**
   * Send unlock command to specific locker
   * @param {string} lockerId - The locker ID to unlock
   * @param {object} additionalData - Optional data (waybill_id, recipient, etc.)
   * @returns {boolean} - Success status
   */
  unlockLocker(lockerId, additionalData = {}) {
    if (!this.isConnected || !this.client) {
      console.error('❌ Cannot send unlock command - MQTT not connected');
      return false;
    }

    try {
      // Topic structure: smartlocker/locker/{lockerId}/unlock
      const topic = `smartlocker/locker/${lockerId}/unlock`;
      
      const payload = {
        command: 'UNLOCK',
        lockerId: lockerId,
        timestamp: new Date().toISOString(),
        ...additionalData
      };

      const message = JSON.stringify(payload);

      this.client.publish(topic, message, { qos: 1, retain: false }, (error) => {
        if (error) {
          console.error(`❌ Failed to publish unlock command for ${lockerId}:`, error);
        } else {
          console.log(`✅ Unlock command sent to ${lockerId}`);
          console.log(`   Topic: ${topic}`);
          console.log(`   Payload:`, payload);
        }
      });

      return true;
    } catch (error) {
      console.error('Error sending unlock command:', error);
      return false;
    }
  }

  /**
   * Send lock command to specific locker
   * @param {string} lockerId - The locker ID to lock
   */
  lockLocker(lockerId) {
    if (!this.isConnected || !this.client) {
      console.error('❌ Cannot send lock command - MQTT not connected');
      return false;
    }

    try {
      const topic = `smartlocker/locker/${lockerId}/lock`;
      
      const payload = {
        command: 'LOCK',
        lockerId: lockerId,
        timestamp: new Date().toISOString()
      };

      const message = JSON.stringify(payload);

      this.client.publish(topic, message, { qos: 1, retain: false }, (error) => {
        if (error) {
          console.error(`❌ Failed to publish lock command for ${lockerId}:`, error);
        } else {
          console.log(`✅ Lock command sent to ${lockerId}`);
        }
      });

      return true;
    } catch (error) {
      console.error('Error sending lock command:', error);
      return false;
    }
  }

  /**
   * Get locker status (ESP32 should publish to this topic)
   * @param {string} lockerId 
   * @param {function} callback - Called when status update received
   */
  subscribeToLockerStatus(lockerId, callback) {
    if (!this.isConnected || !this.client) {
      console.error('❌ Cannot subscribe - MQTT not connected');
      return;
    }

    const topic = `smartlocker/locker/${lockerId}/status`;
    
    this.client.subscribe(topic, (error) => {
      if (error) {
        console.error(`❌ Failed to subscribe to ${topic}:`, error);
      } else {
        console.log(`✅ Subscribed to locker status: ${topic}`);
      }
    });

    this.client.on('message', (receivedTopic, message) => {
      if (receivedTopic === topic) {
        try {
          const data = JSON.parse(message.toString());
          callback(data);
        } catch (error) {
          console.error('Error parsing status message:', error);
        }
      }
    });
  }

  disconnect() {
    if (this.client) {
      this.client.end();
      this.isConnected = false;
      console.log('MQTT Client disconnected');
    }
  }
}

// Export singleton instance
const mqttService = new MQTTService();
module.exports = mqttService;
