# ESP32 Setup Checklist

## ✅ Step-by-Step Setup Guide

### 1️⃣ Install Arduino IDE & ESP32 Support

- [ ] Download Arduino IDE from: https://www.arduino.cc/en/software
- [ ] Open Arduino IDE
- [ ] Go to: `File` → `Preferences`
- [ ] Add this URL to "Additional Board Manager URLs":
  ```
  https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
  ```
- [ ] Go to: `Tools` → `Board` → `Boards Manager`
- [ ] Search for "ESP32"
- [ ] Install "**esp32 by Espressif Systems**"

### 2️⃣ Install Required Libraries

- [ ] Go to: `Tools` → `Manage Libraries`
- [ ] Search for "**PubSubClient**"
- [ ] Install "PubSubClient by Nick O'Leary"

### 3️⃣ Configure the Code

Open `ESP32_SmartLocker_Code.ino` and update these lines:

**Line 20-21: WiFi Credentials**
```cpp
const char* ssid = "YOUR_WIFI_SSID";        // ⚠️ Change to your WiFi name
const char* password = "YOUR_WIFI_PASSWORD"; // ⚠️ Change to your WiFi password
```

**Line 24: MQTT Broker** (optional - default is test.mosquitto.org)
```cpp
const char* mqtt_server = "test.mosquitto.org";  // Public test broker
// Or use your computer's IP if running local broker:
// const char* mqtt_server = "192.168.1.100";  // Find with: ipconfig
```

**Line 30: Locker ID** ⚠️ IMPORTANT!
```cpp
const char* LOCKER_ID = "LOCKER_001";  // Must match your QR code!
```

### 4️⃣ Connect & Upload to ESP32

- [ ] Connect ESP32 to computer via USB cable
- [ ] In Arduino IDE:
  - [ ] `Tools` → `Board` → `ESP32 Arduino` → Select "**ESP32 Dev Module**"
  - [ ] `Tools` → `Port` → Select your ESP32 port (e.g., COM3, COM4)
  - [ ] `Tools` → `Upload Speed` → Select "**115200**"
- [ ] Click the **Upload** button (➡️ arrow icon)
- [ ] Wait for "Done uploading" message

### 5️⃣ Verify ESP32 is Working

- [ ] Open Serial Monitor: `Tools` → `Serial Monitor`
- [ ] Set baud rate to **115200**
- [ ] Press **Reset** button on ESP32

**You should see:**
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

Connecting to WiFi...
✅ WiFi Connected!
IP Address: 192.168.1.xxx
✅ MQTT Connected!
📡 Subscribed to: smartlocker/locker/LOCKER_001/unlock
📡 Subscribed to: smartlocker/locker/LOCKER_001/lock
```

### 6️⃣ Hardware Wiring

**Components needed:**
- [ ] ESP32 DevKit board
- [ ] 5V Relay module (1-channel)
- [ ] 12V Solenoid lock
- [ ] 12V Power supply (2A minimum)
- [ ] Jumper wires
- [ ] Breadboard (optional)

**Wiring Diagram:**

```
┌─────────────────────────────────────────────┐
│            ESP32 to Relay                   │
├─────────────────────────────────────────────┤
│  ESP32 GPIO 26  →  Relay IN (Signal)       │
│  ESP32 5V       →  Relay VCC (Power)       │
│  ESP32 GND      →  Relay GND (Ground)      │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│          Relay to Solenoid Lock             │
├─────────────────────────────────────────────┤
│  Relay COM      →  12V+ (Power Supply)     │
│  Relay NO       →  Solenoid + (Red wire)   │
│  12V GND        →  Solenoid - (Black wire) │
└─────────────────────────────────────────────┘

Optional LED Status Indicator:
┌─────────────────────────────────────────────┐
│  ESP32 GPIO 25  →  LED + (with resistor)   │
│  ESP32 GND      →  LED -                    │
└─────────────────────────────────────────────┘
```

**Important Safety Notes:**
- ⚠️ Never connect 12V directly to ESP32!
- ⚠️ Use relay as a switch for high voltage
- ⚠️ Double-check polarity before powering on
- ⚠️ Use appropriate wire gauge for 12V power

### 7️⃣ Test MQTT Communication

**Option A: Test from Backend**
```bash
cd backend
node testMQTT.js
```

**Option B: Test with mosquitto_pub** (if installed)
```bash
# Unlock test
mosquitto_pub -h test.mosquitto.org -t "smartlocker/locker/LOCKER_001/unlock" -m '{"command":"UNLOCK"}'

# Lock test
mosquitto_pub -h test.mosquitto.org -t "smartlocker/locker/LOCKER_001/lock" -m '{"command":"LOCK"}'
```

**Option C: Test with curl** (via backend API)
```bash
# Unlock
curl -X PUT http://localhost:3000/api/locker/LOCKER_001/unlock

# Lock
curl -X PUT http://localhost:3000/api/locker/LOCKER_001/lock
```

**Expected ESP32 Response:**
```
📨 Message received!
Topic: smartlocker/locker/LOCKER_001/unlock
Message: {"command":"UNLOCK"}
🔓 UNLOCK COMMAND RECEIVED
===========================================
⚡ Activating relay...
✅ Door UNLOCKED
⏳ Waiting for LOCK command...
===========================================
```

### 8️⃣ Full App Flow Test

#### Step-by-Step Test Procedure:

**Phase 1: QR Scan → Unlock**
- [ ] Start backend: `cd backend && npm run dev`
- [ ] Verify backend shows: `✅ MQTT Client connected to broker`
- [ ] Start Flutter app
- [ ] Tap the scan button (center FAB button)
- [ ] Scan QR code with locker ID (e.g., "LOCKER_001")
- [ ] **Expected Result:**
  - Dialog shows: "Locker Unlocked Successfully"
  - Backend logs: `✅ Unlock command sent to locker LOCKER_001 after QR scan`
  - ESP32 Serial Monitor shows:
    ```
    🔓 UNLOCK COMMAND RECEIVED
    ✅ Door UNLOCKED
    ⏳ Waiting for LOCK command...
    ```
  - ✅ **Door physically unlocks** (relay clicks, solenoid retracts)
  - Door stays unlocked (no timeout)

**Phase 2: Data Entry (Door Stays Open)**
- [ ] Tap "Proceed to Input Recipient Details"
- [ ] Enter first name (e.g., "Alijah")
- [ ] Enter last name (e.g., "Eugenio")
- [ ] Enter phone number (e.g., "09285719747")
- [ ] Tap "Next"
- [ ] **Expected Result:**
  - Door remains unlocked
  - No MQTT commands sent
  - Navigates to package scan screen

**Phase 3: Package Scan (Door Still Open)**
- [ ] Scan package barcode/waybill
- [ ] Wait for OCR processing
- [ ] **Expected Result:**
  - Waybill details extracted
  - Embedding generated
  - Data saved to MongoDB
  - Door still unlocked
  - Navigates to live verification screen

**Phase 4: Live Verification → Lock**
- [ ] Point camera at the same package
- [ ] Wait for embedding comparison
- [ ] **Expected Result:**
  - If match successful:
    - Backend logs: `✅ Lock command sent to LOCKER_001`
    - ESP32 Serial Monitor shows:
      ```
      🔒 LOCK COMMAND RECEIVED
      ✅ Door LOCKED
      ```
    - ✅ **Door physically locks** (relay clicks, solenoid extends)
    - Dialog shows: "Package Placed Successfully"
    - Message: "Verification complete. Door has been locked automatically."

#### Backend Log Verification:
```bash
# You should see this sequence:
✅ Unlock command sent to locker LOCKER_001 after QR scan
   Topic: smartlocker/locker/LOCKER_001/unlock
   Payload: { command: 'UNLOCK', trigger: 'QR_SCAN' }

Transaction logged successfully: WB1762505435733

Transaction verified successfully

✅ Lock command sent to LOCKER_001
   Topic: smartlocker/locker/LOCKER_001/lock
```

#### ESP32 Serial Monitor Verification:
```bash
# After QR scan:
📨 Message received!
🔓 UNLOCK COMMAND RECEIVED
⚡ Activating relay...
✅ Door UNLOCKED
⏳ Waiting for LOCK command...

# (Door stays open while user completes verification...)

# After verification success:
📨 Message received!
🔒 LOCK COMMAND RECEIVED
⚡ Deactivating relay...
✅ Door LOCKED
🔐 Locker secured
```

### 9️⃣ Troubleshooting

**❌ WiFi not connecting:**
- [ ] ESP32 only supports 2.4GHz WiFi (not 5GHz)
- [ ] Check SSID and password are correct (case-sensitive!)
- [ ] Ensure WiFi network is available and in range
- [ ] Try moving ESP32 closer to router
- [ ] Check if WiFi has MAC address filtering enabled

**❌ MQTT connection failed:**
- [ ] Check internet connection (for test.mosquitto.org)
- [ ] Try different public broker: `broker.hivemq.com`
- [ ] Check firewall settings on your computer
- [ ] Verify MQTT port 1883 is not blocked
- [ ] Try pinging the broker: `ping test.mosquitto.org`

**❌ Door doesn't unlock after QR scan:**
- [ ] Check backend logs for "Unlock command sent" message
- [ ] Check ESP32 Serial Monitor for "UNLOCK COMMAND RECEIVED"
- [ ] Verify relay wiring (GPIO 26 → Relay IN)
- [ ] Listen for relay "click" sound
- [ ] Verify 12V power supply is working
- [ ] Test relay manually with simple blink code
- [ ] Check locker ID matches exactly (LOCKER_001 vs locker_001)

**❌ Door doesn't lock after verification:**
- [ ] Check backend logs for "Lock command sent" message
- [ ] Check ESP32 Serial Monitor for "LOCK COMMAND RECEIVED"
- [ ] Verify GPIO 26 goes LOW (use multimeter or LED)
- [ ] Check relay deactivates (no click = problem)
- [ ] Ensure verification actually succeeded
- [ ] Check live_screen.dart is calling lockLocker()

**❌ Door auto-locks immediately (old behavior):**
- [ ] You have OLD ESP32 code with timer
- [ ] Re-flash ESP32 with updated code (no auto-lock timer)
- [ ] Verify Serial Monitor shows "No auto-lock - door stays open"
- [ ] Check code has NO reference to `UNLOCK_DURATION` or timer

**❌ Commands not received:**
- [ ] Check Serial Monitor for MQTT connection status
- [ ] Verify locker ID matches QR code exactly
- [ ] Check backend is sending to correct topic
- [ ] Use `mosquitto_sub` to monitor all messages:
  ```bash
  mosquitto_sub -h test.mosquitto.org -t "#" -v
  ```
- [ ] Ensure ESP32 hasn't disconnected (check WiFi LED)

**❌ ESP32 keeps resetting/rebooting:**
- [ ] Insufficient power - use quality USB cable
- [ ] Don't power relay from ESP32 5V pin (use separate power)
- [ ] Check for loose wiring connections
- [ ] Verify no short circuits
- [ ] Try different USB port or power adapter

**❌ Wrong locker unlocks:**
- [ ] Check LOCKER_ID in ESP32 code
- [ ] Verify QR code content matches exactly
- [ ] Check backend logs to see which locker ID was sent
- [ ] Multiple ESP32s might have same ID (change one)

### 🎯 Production Checklist

Before deploying in production:

**Security:**
- [ ] Use private MQTT broker (not public test broker)
- [ ] Enable MQTT authentication (username/password)
- [ ] Use MQTT over TLS/SSL (port 8883)
- [ ] Change default MQTT credentials
- [ ] Implement rate limiting on unlock commands

**Hardware:**
- [ ] Unique locker ID for each ESP32 (LOCKER_001, LOCKER_002, etc.)
- [ ] QR codes printed with matching locker IDs
- [ ] Add door sensor for security alerts (GPIO 27)
- [ ] Add backup power (UPS/battery for outages)
- [ ] Use industrial-grade solenoid locks
- [ ] Weather-proof enclosure for outdoor lockers
- [ ] Cable management and strain relief

**Monitoring:**
- [ ] Log all unlock/lock events to database
- [ ] Set up monitoring dashboard (online/offline status)
- [ ] Configure alerts for failed unlock attempts
- [ ] Track door sensor states (opened/closed)
- [ ] Monitor ESP32 uptime and WiFi signal strength
- [ ] Set up email/SMS alerts for security events

**Testing:**
- [ ] Test emergency manual override mechanism
- [ ] Test power failure recovery
- [ ] Test WiFi reconnection after dropout
- [ ] Test MQTT reconnection after broker restart
- [ ] Verify lock works after 1000+ cycles
- [ ] Test in various environmental conditions

**Documentation:**
- [ ] Document locker ID → physical location mapping
- [ ] Create maintenance schedule
- [ ] Prepare troubleshooting guide for operators
- [ ] Document emergency procedures
- [ ] Keep spare components inventory list

---

## 📋 Quick Reference

**GPIO Pins:**
- GPIO 26: Lock control (Relay) - Main control pin
- GPIO 25: Status LED (optional) - Visual indicator
- GPIO 27: Door sensor (optional) - Security monitoring

**MQTT Topics:**
- Unlock: `smartlocker/locker/{ID}/unlock` - ESP32 subscribes
- Lock: `smartlocker/locker/{ID}/lock` - ESP32 subscribes
- Status: `smartlocker/locker/{ID}/status` - ESP32 publishes

**Lock Behavior:**
- GPIO 26 HIGH = Door UNLOCKED (relay ON, 12V to solenoid, bolt retracts)
- GPIO 26 LOW = Door LOCKED (relay OFF, no power, spring extends bolt)

**Updated Flow:**
1. **QR Scan** → Unlock command sent → Door unlocks immediately
2. **Door stays open** while user enters details and scans package
3. **Verification Success** → Lock command sent → Door locks
4. **No auto-lock timer** - door only locks when commanded

**API Endpoints:**
- `PUT /api/locker/{ID}/unlock` - Unlocks door (after QR scan)
- `PUT /api/locker/{ID}/lock` - Locks door (after verification)
- `PUT /api/parcel/success/{id}` - Updates DB (no unlock!)

**Testing Commands:**
```bash
# Test unlock
curl -X PUT http://localhost:3000/api/locker/LOCKER_001/unlock

# Test lock
curl -X PUT http://localhost:3000/api/locker/LOCKER_001/lock

# Monitor MQTT traffic
mosquitto_sub -h test.mosquitto.org -t "smartlocker/#" -v

# Test from backend
cd backend && node testMQTT.js
```

**Expected Timeline:**
- QR Scan → Unlock: ~1 second
- Door open duration: Until verification succeeds (no limit)
- Verification → Lock: ~1 second

---

## 📚 Related Documentation

- **ESP32_SmartLocker_Code.ino** - Arduino code to upload
- **ESP32_WIRING_DIAGRAM.md** - Detailed hardware wiring
- **ESP32_INTEGRATION_GUIDE.md** - System architecture overview
- **ESP32_UPDATE_SUMMARY.md** - Recent changes summary
- **LOCK_MECHANISM_EXPLAINED.md** - How the lock works

---

**Need help? Check the ESP32 Serial Monitor for debug output!**

**Common Serial Monitor Messages:**
- ✅ `WiFi Connected!` - Successfully connected to WiFi
- ✅ `MQTT Connected!` - Successfully connected to broker
- 🔓 `Door UNLOCKED` - Unlock command executed
- 🔒 `Door LOCKED` - Lock command executed
- ⏳ `Waiting for LOCK command` - Door is open, awaiting lock
- ❌ `MQTT Connection failed` - Can't reach broker
- ❌ `WiFi Connection Failed` - Can't connect to WiFi
