/*
 * ESP32 Smart Locker Controller v2.0
 * 
 * This code connects to WiFi and MQTT broker, then listens for unlock/lock commands
 * for a specific locker ID and controls the door lock accordingly.
 * 
 * UPDATED FLOW (November 2025):
 * ================================
 * 1. User scans QR code → ESP32 receives UNLOCK command → Door unlocks
 * 2. Door STAYS UNLOCKED (no auto-lock timer!)
 * 3. User completes verification → ESP32 receives LOCK command → Door locks
 * 
 * KEY CHANGES FROM PREVIOUS VERSION:
 * - Removed auto-lock timer (was 5 seconds)
 * - Door unlocks after QR scan (not after verification)
 * - Door locks after verification success (not automatically)
 * 
 * Hardware Requirements:
 * - ESP32 DevKit (30-pin or 38-pin)
 * - 5V Relay module (1-channel)
 * - 12V Solenoid door lock
 * - 12V Power supply (2A minimum recommended)
 * - Jumper wires
 * 
 * Pin Configuration:
 * - GPIO 26: Lock Control (connected to relay IN pin)
 * - GPIO 25: Lock Status LED (optional - visual indicator)
 * - GPIO 27: Door Sensor (optional - magnetic sensor for security)
 * 
 * Wiring:
 * - ESP32 GPIO 26 → Relay IN
 * - ESP32 5V → Relay VCC
 * - ESP32 GND → Relay GND
 * - Relay COM → 12V+ (from power supply)
 * - Relay NO → Solenoid Lock+ (red wire)
 * - 12V GND → Solenoid Lock- (black wire)
 * 
 * MQTT Topics:
 * - Subscribe: smartlocker/locker/{LOCKER_ID}/unlock
 * - Subscribe: smartlocker/locker/{LOCKER_ID}/lock
 * - Publish:   smartlocker/locker/{LOCKER_ID}/status
 * 
 * Author: Smart Locker Team
 * Last Updated: November 7, 2025
 */

#include <WiFi.h>
#include <PubSubClient.h>

// ============= CONFIGURATION - CHANGE THESE BEFORE UPLOADING! =============

// WiFi credentials (REQUIRED - must change!)
const char* ssid = "YOUR_WIFI_SSID";        // ⚠️ CHANGE THIS! Your WiFi network name
const char* password = "YOUR_WIFI_PASSWORD"; // ⚠️ CHANGE THIS! Your WiFi password
                                             // NOTE: ESP32 only supports 2.4GHz WiFi (not 5GHz)

// MQTT Broker settings
const char* mqtt_server = "test.mosquitto.org";  // Public test broker (free, no auth)
                                                  // For production: Use private broker
                                                  // Example: "192.168.1.100" or "broker.example.com"
const int mqtt_port = 1883;                      // Default MQTT port (1883 for non-SSL)
const char* mqtt_user = "";                      // Leave empty if no authentication
const char* mqtt_password = "";                  // Leave empty if no authentication

// Locker ID - MUST BE UNIQUE FOR EACH ESP32
const char* LOCKER_ID = "LOCKER_001";  // ⚠️ CHANGE THIS for each locker!
                                        // This MUST match the QR code content exactly
                                        // Examples: LOCKER_001, LOCKER_002, LOCKER_003
                                        // LOCKER_001 ≠ locker_001 (case-sensitive!)

// GPIO Pins
const int LOCK_PIN = 26;        // Relay control pin (DO NOT CHANGE unless you rewire)
const int STATUS_LED = 25;      // Status LED pin (optional, can disable if not used)
const int DOOR_SENSOR_PIN = 27; // Magnetic door sensor pin (optional, for security alerts)

// ============= GLOBAL VARIABLES (DO NOT CHANGE) =============
WiFiClient espClient;
PubSubClient mqttClient(espClient);

bool isUnlocked = false;  // Current lock state (false = locked, true = unlocked)

// MQTT Topics (automatically generated from LOCKER_ID)
String unlockTopic;  // Topic to receive unlock commands
String lockTopic;    // Topic to receive lock commands  
String statusTopic;  // Topic to publish status updates

// ============= SETUP =============
void setup() {
  Serial.begin(115200);
  delay(1000);
  
  Serial.println("\n\n===========================================");
  Serial.println("   ESP32 Smart Locker Controller v2.0");
  Serial.println("===========================================");
  Serial.print("Locker ID: ");
  Serial.println(LOCKER_ID);
  Serial.println("-------------------------------------------");
  Serial.println("Flow:");
  Serial.println("1. QR Scan → UNLOCK (stays open)");
  Serial.println("2. Verification Success → LOCK");
  Serial.println("===========================================\n");
  
  // Initialize pins
  pinMode(LOCK_PIN, OUTPUT);
  pinMode(STATUS_LED, OUTPUT);
  pinMode(DOOR_SENSOR_PIN, INPUT_PULLUP);
  
  // Initial state: LOCKED
  digitalWrite(LOCK_PIN, LOW);
  digitalWrite(STATUS_LED, LOW);
  
  // Build MQTT topics
  unlockTopic = "smartlocker/locker/" + String(LOCKER_ID) + "/unlock";
  lockTopic = "smartlocker/locker/" + String(LOCKER_ID) + "/lock";
  statusTopic = "smartlocker/locker/" + String(LOCKER_ID) + "/status";
  
  // Connect to WiFi
  setupWiFi();
  
  // Setup MQTT
  mqttClient.setServer(mqtt_server, mqtt_port);
  mqttClient.setCallback(mqttCallback);
  
  // Connect to MQTT
  reconnectMQTT();
  
  // Send initial status
  publishStatus("LOCKED", "System initialized");
}

// ============= MAIN LOOP =============
void loop() {
  // Maintain MQTT connection (auto-reconnect if disconnected)
  if (!mqttClient.connected()) {
    reconnectMQTT();
  }
  mqttClient.loop();
  
  // ⚠️ NO AUTO-LOCK TIMER - Door stays unlocked until lock command is received
  // This is intentional! Door only locks when backend sends lock command
  // after successful verification.
  
  // Optional: Check door sensor for security alerts
  checkDoorSensor();
  
  delay(10);  // Small delay to prevent CPU overload
}

// ============= WiFi FUNCTIONS =============
void setupWiFi() {
  Serial.println("\nConnecting to WiFi...");
  Serial.print("SSID: ");
  Serial.println(ssid);
  
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n✅ WiFi Connected!");
    Serial.print("IP Address: ");
    Serial.println(WiFi.localIP());
    
    // Blink LED to indicate WiFi connected
    for(int i = 0; i < 3; i++) {
      digitalWrite(STATUS_LED, HIGH);
      delay(100);
      digitalWrite(STATUS_LED, LOW);
      delay(100);
    }
  } else {
    Serial.println("\n❌ WiFi Connection Failed!");
  }
}

// ============= MQTT FUNCTIONS =============
void reconnectMQTT() {
  while (!mqttClient.connected()) {
    Serial.println("\nConnecting to MQTT broker...");
    Serial.print("Broker: ");
    Serial.println(mqtt_server);
    
    String clientId = "ESP32_Locker_" + String(LOCKER_ID);
    
    if (mqttClient.connect(clientId.c_str(), mqtt_user, mqtt_password)) {
      Serial.println("✅ MQTT Connected!");
      
      // Subscribe to unlock and lock topics
      mqttClient.subscribe(unlockTopic.c_str());
      mqttClient.subscribe(lockTopic.c_str());
      
      Serial.print("📡 Subscribed to: ");
      Serial.println(unlockTopic);
      Serial.print("📡 Subscribed to: ");
      Serial.println(lockTopic);
      
      // Publish online status
      publishStatus("LOCKED", "ESP32 online");
      
    } else {
      Serial.print("❌ MQTT Connection failed, rc=");
      Serial.println(mqttClient.state());
      Serial.println("Retrying in 5 seconds...");
      delay(5000);
    }
  }
}

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  Serial.println("\n📨 Message received!");
  Serial.print("Topic: ");
  Serial.println(topic);
  
  // Convert payload to string
  String message = "";
  for (unsigned int i = 0; i < length; i++) {
    message += (char)payload[i];
  }
  Serial.print("Payload: ");
  Serial.println(message);
  
  // Check which topic the message came from
  String topicStr = String(topic);
  
  if (topicStr == unlockTopic) {
    // Unlock command received (after QR scan)
    unlockDoor();
  } 
  else if (topicStr == lockTopic) {
    // Lock command received (after verification success)
    lockDoor();
  }
  else {
    Serial.println("⚠️  Unknown topic!");
  }
}

// ============= LOCK CONTROL FUNCTIONS =============
void unlockDoor() {
  Serial.println("\n===========================================");
  Serial.println("🔓 UNLOCK COMMAND RECEIVED");
  Serial.println("===========================================");
  Serial.println("⚡ Activating relay...");
  
  digitalWrite(LOCK_PIN, HIGH);  // Activate relay (unlock)
  digitalWrite(STATUS_LED, HIGH); // Turn on LED
  
  isUnlocked = true;
  
  Serial.println("✅ Door UNLOCKED");
  Serial.println("⏳ Waiting for LOCK command...");
  Serial.println("   (No auto-lock - door stays open)");
  Serial.println("===========================================\n");
  
  publishStatus("UNLOCKED", "Door unlocked - waiting for verification");
  
  // Beep pattern (if buzzer connected)
  // beepUnlock();
}

void lockDoor() {
  Serial.println("\n===========================================");
  Serial.println("🔒 LOCK COMMAND RECEIVED");
  Serial.println("===========================================");
  Serial.println("⚡ Deactivating relay...");
  
  digitalWrite(LOCK_PIN, LOW);   // Deactivate relay (lock)
  digitalWrite(STATUS_LED, LOW);  // Turn off LED
  
  isUnlocked = false;
  
  Serial.println("✅ Door LOCKED");
  Serial.println("🔐 Locker secured");
  Serial.println("===========================================\n");
  
  publishStatus("LOCKED", "Door locked after verification");
  
  // Beep pattern (if buzzer connected)
  // beepLock();
}

void publishStatus(String status, String message) {
  // Create JSON payload with status information
  String payload = "{";
  payload += "\"locker_id\":\"" + String(LOCKER_ID) + "\",";
  payload += "\"status\":\"" + status + "\",";
  payload += "\"message\":\"" + message + "\",";
  payload += "\"timestamp\":\"" + String(millis()) + "\",";
  payload += "\"wifi_rssi\":" + String(WiFi.RSSI()) + ",";
  payload += "\"uptime_ms\":" + String(millis());
  payload += "}";
  
  // Publish to status topic
  bool published = mqttClient.publish(statusTopic.c_str(), payload.c_str());
  
  if (published) {
    Serial.println("\n📤 Status published:");
    Serial.println(payload);
  } else {
    Serial.println("\n⚠️  Failed to publish status (MQTT disconnected?)");
  }
}

void checkDoorSensor() {
  // Optional: Read magnetic door sensor for security monitoring
  // Door sensor: LOW = door open, HIGH = door closed
  // Only enable this if you have a door sensor installed on GPIO 27
  
  static bool lastDoorState = HIGH;
  bool currentDoorState = digitalRead(DOOR_SENSOR_PIN);
  
  // Detect state change
  if (currentDoorState != lastDoorState) {
    if (currentDoorState == LOW && !isUnlocked) {
      // SECURITY ALERT: Door opened while locked!
      publishStatus("ALERT", "Security breach - door opened while locked!");
      Serial.println("\n⚠️⚠️⚠️  SECURITY ALERT  ⚠️⚠️⚠️");
      Serial.println("Door opened while locked!");
      Serial.println("Possible forced entry detected!");
      
      // Optional: Add buzzer alarm here
      // alarmBuzzer();
    }
    else if (currentDoorState == HIGH && isUnlocked) {
      // Door closed while unlocked (normal during package placement)
      Serial.println("ℹ️  Door closed (waiting for lock command)");
    }
    
    lastDoorState = currentDoorState;
  }
}

// ============= UTILITY FUNCTIONS =============

void printSystemInfo() {
  // Print system information for debugging
  Serial.println("\n========== SYSTEM INFO ==========");
  Serial.print("Locker ID: ");
  Serial.println(LOCKER_ID);
  Serial.print("WiFi SSID: ");
  Serial.println(ssid);
  Serial.print("IP Address: ");
  Serial.println(WiFi.localIP());
  Serial.print("WiFi RSSI: ");
  Serial.print(WiFi.RSSI());
  Serial.println(" dBm");
  Serial.print("MQTT Server: ");
  Serial.println(mqtt_server);
  Serial.print("Uptime: ");
  Serial.print(millis() / 1000);
  Serial.println(" seconds");
  Serial.print("Lock State: ");
  Serial.println(isUnlocked ? "UNLOCKED" : "LOCKED");
  Serial.println("=================================\n");
}

// ============= OPTIONAL: BUZZER FUNCTIONS =============
/*
void beepUnlock() {
  tone(BUZZER_PIN, 1000, 100);
  delay(150);
  tone(BUZZER_PIN, 1200, 100);
}

void beepLock() {
  tone(BUZZER_PIN, 800, 200);
}
*/
