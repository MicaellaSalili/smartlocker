# ESP32 Smart Locker Integration Guide

## Overview
This guide explains how to integrate ESP32 with the Smart Locker system to unlock doors after QR code scanning and lock them after successful verification.

## Updated Architecture Flow

```
QR Scan → Backend → MQTT → ESP32 → 🔓 UNLOCK (stays open)
   ↓
Input Details + Package Scan + Live Verification
   ↓
Verification Success → Backend → MQTT → ESP32 → 🔒 LOCK
```

### Key Changes:
- **Door unlocks** immediately after QR code scan
- **Door stays unlocked** (no auto-lock timer)
- **Door locks** only when live verification succeeds

## Prerequisites

### Software
1. **Arduino IDE** with ESP32 board support
2. **MQTT Broker** (choose one):
   - **Mosquitto** (local) - [Download](https://mosquitto.org/download/)
   - **HiveMQ Cloud** (cloud) - [Free tier](https://www.hivemq.com/mqtt-cloud-broker/)
   - **test.mosquitto.org** (testing only - public broker)

### Hardware (per locker)
1. ESP32 DevKit board
2. 5V Relay module
3. 12V Solenoid door lock
4. 12V Power supply
5. Jumper wires
6. (Optional) Magnetic door sensor
7. (Optional) Buzzer for audio feedback

## Installation Steps

### 1. Install MQTT Broker (Local Option)

#### Windows:
```bash
# Download and install Mosquitto from:
# https://mosquitto.org/download/

# Start the service
net start mosquitto
```

#### macOS:
```bash
brew install mosquitto
brew services start mosquitto
```

#### Linux:
```bash
sudo apt-get install mosquitto mosquitto-clients
sudo systemctl start mosquitto
sudo systemctl enable mosquitto
```

### 2. Configure MQTT in Node.js Backend

Update `.env` file:
```env
# MQTT Configuration
MQTT_BROKER_URL=mqtt://localhost:1883
MQTT_USERNAME=
MQTT_PASSWORD=
```

For cloud MQTT (HiveMQ example):
```env
MQTT_BROKER_URL=mqtt://your-instance.hivemq.cloud:1883
MQTT_USERNAME=your_username
MQTT_PASSWORD=your_password
```

### 3. Setup ESP32

#### Install Arduino Libraries
1. Open Arduino IDE
2. Go to **Tools → Manage Libraries**
3. Install:
   - **PubSubClient** by Nick O'Leary
   - **WiFi** (should be pre-installed with ESP32)

#### Configure ESP32 Code
1. Open `ESP32_SmartLocker_Code.ino`
2. Update these values:
```cpp
// WiFi credentials - REQUIRED!
const char* ssid = "YOUR_WIFI_SSID";        // ⚠️ Change this!
const char* password = "YOUR_WIFI_PASSWORD"; // ⚠️ Change this!

// MQTT Broker
const char* mqtt_server = "test.mosquitto.org";  // or your broker IP/domain
const int mqtt_port = 1883;

// Locker ID - MUST MATCH THE QR CODE
const char* LOCKER_ID = "LOCKER_001";  // ⚠️ Change for each locker
```

**Important Notes:**
- WiFi must be 2.4GHz (ESP32 doesn't support 5GHz)
- Locker ID must exactly match the QR code content
- Each ESP32 must have a unique Locker ID

#### Wire the Hardware
```
ESP32         Relay Module      Solenoid Lock
--------------------------------------------
GPIO 26   →   IN               
5V        →   VCC              
GND       →   GND              
              COM          →   12V+
              NO           →   Lock+
12V PSU   →                →   Lock-
GND       →                →   12V-
```

#### Upload Code
1. Connect ESP32 via USB
2. Select **Tools → Board → ESP32 Dev Module**
3. Select correct **Port**
4. Click **Upload**
5. Open **Serial Monitor** (115200 baud) to see status

### 4. Test the System

#### Backend Test
Start the Node.js server:
```bash
cd backend
npm run dev
```

You should see:
```
✅ MQTT Client connected to broker
```

#### ESP32 Test
Check Serial Monitor, you should see:
```
===========================================
   ESP32 Smart Locker Controller v2.0
===========================================
Locker ID: LOCKER_001
-------------------------------------------
Flow:
1. QR Scan → UNLOCK (stays open)
2. Verification Success → LOCK
===========================================

✅ WiFi Connected!
IP Address: 192.168.1.100
✅ MQTT Connected!
📡 Subscribed to: smartlocker/locker/LOCKER_001/unlock
📡 Subscribed to: smartlocker/locker/LOCKER_001/lock
```

#### Manual MQTT Test
Test unlock command directly:
```bash
# Test unlock (door stays open)
mosquitto_pub -h test.mosquitto.org -t "smartlocker/locker/LOCKER_001/unlock" -m '{"command":"UNLOCK"}'

# Test lock (after verification)
mosquitto_pub -h test.mosquitto.org -t "smartlocker/locker/LOCKER_001/lock" -m '{"command":"LOCK"}'
```

ESP32 Serial Monitor should show:
```
🔓 UNLOCK COMMAND RECEIVED
⚡ Activating relay...
✅ Door UNLOCKED
⏳ Waiting for LOCK command...
   (No auto-lock - door stays open)
```

### 5. Full Flow Test

#### Complete User Journey:

**Step 1: QR Code Scan**
1. Open Flutter app
2. Tap scan button
3. Scan QR code containing `LOCKER_001`
4. ✅ **Door unlocks immediately** via MQTT
5. Dialog shows: "Locker Unlocked Successfully"

**Step 2: Enter Details**
6. Tap "Proceed to Input Recipient Details"
7. Enter first name, last name, phone number
8. Tap "Next"
9. 🚪 **Door remains open**

**Step 3: Scan Package**
10. Scan package barcode (waybill)
11. App reads waybill details with OCR
12. Generates image embedding
13. Saves to MongoDB
14. 🚪 **Door still open**

**Step 4: Live Verification**
15. App shows live camera feed
16. Scan the same package again
17. App compares embeddings
18. If match successful:
    - ✅ **Door locks immediately** via MQTT
    - Shows "Package Placed Successfully"
    - Dialog: "Verification complete. Door has been locked automatically."

#### Expected Backend Logs:
```bash
# After QR scan
✅ Unlock command sent to locker LOCKER_001 after QR scan
✅ Unlock command sent to LOCKER_001
   Topic: smartlocker/locker/LOCKER_001/unlock
   Payload: {
  command: 'UNLOCK',
  lockerId: 'LOCKER_001',
  timestamp: '2025-11-07T08:49:48.693Z',
  trigger: 'QR_SCAN'
}

# After verification (no unlock command anymore!)
Transaction verified successfully

# After verification success
✅ Lock command sent to LOCKER_001
   Topic: smartlocker/locker/LOCKER_001/lock
```

#### Expected ESP32 Serial Output:
```
# After QR scan
📨 Message received!
Topic: smartlocker/locker/LOCKER_001/unlock
🔓 UNLOCK COMMAND RECEIVED
⚡ Activating relay...
✅ Door UNLOCKED
⏳ Waiting for LOCK command...

# (Door stays open during verification...)

# After verification success
📨 Message received!
Topic: smartlocker/locker/LOCKER_001/lock
🔒 LOCK COMMAND RECEIVED
⚡ Deactivating relay...
✅ Door LOCKED
🔐 Locker secured
```

## MQTT Topics Structure

```
smartlocker/locker/{LOCKER_ID}/unlock  → ESP32 subscribes (receives unlock commands)
smartlocker/locker/{LOCKER_ID}/lock    → ESP32 subscribes (receives lock commands)
smartlocker/locker/{LOCKER_ID}/status  → ESP32 publishes (sends status updates)
```

## Troubleshooting

### ESP32 Won't Connect to WiFi
- Check SSID and password
- Ensure 2.4GHz network (ESP32 doesn't support 5GHz)
- Check WiFi signal strength

### ESP32 Won't Connect to MQTT
- Verify broker IP/domain
- Check if broker is running: `netstat -an | grep 1883`
- Test with mosquitto_sub: `mosquitto_sub -h localhost -t "#" -v`
- Check firewall settings

### Door Doesn't Unlock
- Check wiring connections (see ESP32_WIRING_DIAGRAM.md)
- Verify relay is clicking (should hear it)
- Test relay manually in Arduino: `digitalWrite(26, HIGH);`
- Check 12V power supply to solenoid
- Verify MQTT message is being received (check Serial Monitor)

### Door Doesn't Lock After Verification
- Check if lock command is being sent (backend logs)
- Verify ESP32 is subscribed to lock topic
- Check GPIO 26 goes LOW when lock command received
- Verify relay deactivates (no click sound)

### Door Auto-Locks Immediately
- Old ESP32 code still has timer - reflash with updated code
- Check ESP32_SmartLocker_Code.ino has NO auto-lock timer
- Serial Monitor should say "No auto-lock - door stays open"

### Multiple Lockers
For multiple lockers:
1. Flash each ESP32 with unique `LOCKER_ID`
2. Each ESP32 subscribes to its own topic
3. QR codes must match the `LOCKER_ID`

Example:
- ESP32 #1: `LOCKER_001`
- ESP32 #2: `LOCKER_002`
- ESP32 #3: `LOCKER_003`

## Production Recommendations

1. **Use Secured MQTT**
   - Enable TLS/SSL
   - Use username/password authentication
   - Use private MQTT broker

2. **Add Monitoring**
   - Log all unlock events to database
   - Monitor ESP32 online/offline status
   - Track door sensor states

3. **Improve Security**
   - Add timeout for verification
   - Implement unlock token/OTP
   - Add camera verification

4. **Hardware Improvements**
   - Add UPS/battery backup
   - Use industrial-grade solenoid locks
   - Add tamper detection sensors

## Environment Variables Reference

Add to `backend/.env`:
```env
# MQTT Configuration
MQTT_BROKER_URL=mqtt://localhost:1883
MQTT_USERNAME=
MQTT_PASSWORD=

# For SSL/TLS (production)
# MQTT_BROKER_URL=mqtts://your-broker.com:8883
# MQTT_CA_CERT=/path/to/ca.crt
```

## Updated Flow Diagram

```
┌─────────────────────────────────────────────────────┐
│ PHASE 1: QR SCAN → UNLOCK                          │
├─────────────────────────────────────────────────────┤
│                                                     │
│  User scans QR code (LOCKER_001)                   │
│         ↓                                           │
│  Flutter: home_screen.dart                          │
│         ↓                                           │
│  PUT /api/locker/LOCKER_001/unlock                  │
│         ↓                                           │
│  Backend: mqttService.unlockLocker()                │
│         ↓                                           │
│  MQTT Topic: smartlocker/locker/LOCKER_001/unlock   │
│         ↓                                           │
│  ESP32 receives unlock command                      │
│         ↓                                           │
│  GPIO 26 = HIGH (relay activates)                   │
│         ↓                                           │
│  🔓 DOOR UNLOCKS (stays open!)                      │
│                                                     │
└─────────────────────────────────────────────────────┘

              ⏱️ Door stays unlocked...

┌─────────────────────────────────────────────────────┐
│ PHASE 2: USER INTERACTION                          │
├─────────────────────────────────────────────────────┤
│                                                     │
│  User enters recipient details                      │
│  User scans package barcode                         │
│  System saves to MongoDB                            │
│  User performs live verification                    │
│         ↓                                           │
│  Embeddings match? ─→ NO ─→ Error (door stays open)│
│         ↓ YES                                       │
│                                                     │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ PHASE 3: VERIFICATION SUCCESS → LOCK               │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Flutter: live_screen.dart                          │
│         ↓                                           │
│  PUT /api/locker/LOCKER_001/lock                    │
│         ↓                                           │
│  Backend: mqttService.lockLocker()                  │
│         ↓                                           │
│  MQTT Topic: smartlocker/locker/LOCKER_001/lock     │
│         ↓                                           │
│  ESP32 receives lock command                        │
│         ↓                                           │
│  GPIO 26 = LOW (relay deactivates)                  │
│         ↓                                           │
│  🔒 DOOR LOCKS                                      │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## API Endpoints Reference

### Unlock Endpoint (Called after QR scan)
```http
PUT /api/locker/:lockerId/unlock

Example:
PUT http://localhost:3000/api/locker/LOCKER_001/unlock

Response:
{
  "message": "Unlock command sent successfully",
  "locker_id": "LOCKER_001",
  "status": "UNLOCKED",
  "timestamp": "2025-11-07T08:49:48.693Z"
}
```

### Lock Endpoint (Called after verification success)
```http
PUT /api/locker/:lockerId/lock

Example:
PUT http://localhost:3000/api/locker/LOCKER_001/lock

Response:
{
  "message": "Lock command sent successfully",
  "locker_id": "LOCKER_001",
  "status": "LOCKED",
  "timestamp": "2025-11-07T08:51:23.456Z"
}
```

### Verification Endpoint (Updates DB, no unlock)
```http
PUT /api/parcel/success/:id

Note: This endpoint NO LONGER sends unlock command!
It only updates the database status to VERIFIED_SUCCESS.
```

## Support

For issues or questions:
- Check Serial Monitor output on ESP32
- Enable debug logging in mqttService.js
- Test MQTT communication manually with mosquitto_pub
- Verify all credentials and configurations
- Review ESP32_SETUP_CHECKLIST.md for detailed setup
- Check ESP32_WIRING_DIAGRAM.md for hardware connections

## Quick Troubleshooting Commands

```bash
# Check if MQTT broker is running
netstat -an | grep 1883

# Subscribe to all MQTT messages (debugging)
mosquitto_sub -h test.mosquitto.org -t "#" -v

# Test unlock manually
curl -X PUT http://localhost:3000/api/locker/LOCKER_001/unlock

# Test lock manually
curl -X PUT http://localhost:3000/api/locker/LOCKER_001/lock

# Run backend MQTT test
cd backend
node testMQTT.js
```
