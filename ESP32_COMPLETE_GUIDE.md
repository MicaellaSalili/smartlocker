# ESP32 Smart Locker - Complete Implementation Guide

> **Version 2.0** - Comprehensive guide combining setup, wiring, integration, and troubleshooting

---

## 📋 Table of Contents

1. [Quick Start](#quick-start)
2. [System Overview](#system-overview)
3. [Prerequisites & Shopping List](#prerequisites--shopping-list)
4. [Backend Configuration](#backend-configuration)
5. [ESP32 Setup](#esp32-setup)
6. [Hardware Wiring](#hardware-wiring)
7. [Testing & Verification](#testing--verification)
8. [Production Deployment](#production-deployment)
9. [Troubleshooting](#troubleshooting)
10. [Integration Checklist](#integration-checklist)

---

## Quick Start

### 🚀 What You Need to Do (TL;DR)

**Do you need to change code when connecting ESP32?**
- **NO** - Current backend code is ready for ESP32!
- Just connect ESP32 and it will automatically start working
- MQTT warnings will disappear once ESP32 connects

**What you DO need to configure:**
1. MQTT broker (local Mosquitto or cloud service)
2. ESP32 code to subscribe to `smartlocker/locker/{LOCKER_ID}/unlock`
3. Update `backend/src/services/mqttService.js` broker URL if needed
4. Wire the hardware correctly
5. Upload code to ESP32

That's it! 🎉

---

## System Overview

### Architecture Flow

```
QR Scan → Backend → MQTT → ESP32 → Relay → Solenoid Lock
   ↓                                              ↓
Input Details + Package Scan               Door UNLOCKS (stays open)
   ↓
Live Verification Success
   ↓
Backend → MQTT → ESP32 → Relay → Solenoid Lock
                                        ↓
                                  Door LOCKS
```

### Key Features (v2.0):
- **Door unlocks** immediately after QR code scan
- **Door stays unlocked** (no auto-lock timer)
- **Door locks** only when live verification succeeds
- Works with or without ESP32 (testing mode)

### Complete Flow Timeline:

```
T=0s    User scans QR code
        ↓
T=1s    Door UNLOCKS (relay clicks, bolt retracts)
        ↓
        [ Door stays OPEN - no timer! ]
        ↓
T=30s   User enters details, scans package
        ↓
T=60s   User completes live verification
        ↓
T=61s   Door LOCKS (relay clicks, bolt extends)
```

---

## Prerequisites & Shopping List

### Software Requirements

1. **Arduino IDE** with ESP32 board support
2. **MQTT Broker** (choose one):
   - **Mosquitto** (local) - [Download](https://mosquitto.org/download/)
   - **HiveMQ Cloud** (cloud) - [Free tier](https://www.hivemq.com/mqtt-cloud-broker/)
   - **test.mosquitto.org** (testing only - public broker)

### Hardware Components

#### Required Components:

| Item | Specs | Price Range | Recommended Brands | Notes |
|------|-------|-------------|-------------------|-------|
| ESP32 DevKit | 30-pin or 38-pin | $5-10 | DOIT, Espressif, HiLetgo | Get CH340 USB chip version |
| 5V Relay Module | 1-channel, 10A | $2-5 | SainSmart, Elegoo, HiLetgo | Get "active high" trigger |
| 12V Solenoid Lock | 12V DC, 1-2A | $10-20 | Generic, Uxcell | Get "electric door lock" type |
| 12V Power Supply | 12V 2-3A | $5-10 | Mean Well, ALITOVE | Get UL/CE certified |
| Jumper Wires | M-F, 20cm, 40pcs | $3-5 | Elegoo, EDGELEC | Get assorted colors |
| USB Cable | Micro-USB or USB-C | $3-5 | Anker, AmazonBasics | Match your ESP32 type |

**Subtotal: ~$28-55**

#### Optional Components:

| Item | Specs | Price Range | Purpose |
|------|-------|-------------|---------|
| LED Pack | 5mm, assorted colors | $2-5 | Status indicator |
| Resistor Pack | 220Ω, 1/4W | $2-5 | For LED (get assortment) |
| Door Sensor | Magnetic, NC or NO | $2-5 | Security monitoring |
| Breadboard | 830 points | $3-8 | Prototyping |
| Enclosure Box | IP65 rated | $5-15 | Weather protection |
| Multimeter | Digital, basic | $10-20 | Testing & debugging |

#### Cost Summary:

| Configuration | Components | Estimated Cost |
|---------------|-----------|----------------|
| **Minimal** | Required only | $30-55 USD |
| **Standard** | Required + LED + resistors | $35-65 USD |
| **Full** | All components | $60-130 USD |
| **Per Additional Locker** | ESP32 + Relay + Solenoid only | $17-35 USD |

### Where to Buy:

**Online (Worldwide):**
- 🌐 **AliExpress** - Cheapest, 2-4 weeks shipping
- 🌐 **Amazon** - Fast shipping (1-2 days), higher prices
- 🌐 **DigiKey/Mouser** - High quality, reliable, expensive

**Philippines:**
- e-Gizmo, Lazada, Shopee

---

## Backend Configuration

### ✅ Current Setup (Testing Without ESP32)
- Backend allows unlock even when MQTT is offline
- "ESP32 offline - but continuing anyway" message
- App flow works end-to-end without hardware

### MQTT Broker Setup

**Current (using public test broker):**
```javascript
// backend/src/services/mqttService.js
this.brokerUrl = 'mqtt://test.mosquitto.org';
```

**For production, you have 3 options:**

#### Option A: Local Mosquitto (Recommended)

**Install Mosquitto:**

**Windows:**
```bash
# Download from https://mosquitto.org/download/
# After install:
net start mosquitto
```

**macOS:**
```bash
brew install mosquitto
brew services start mosquitto
```

**Linux:**
```bash
sudo apt-get install mosquitto mosquitto-clients
sudo systemctl start mosquitto
sudo systemctl enable mosquitto
```

**Update backend:**
```javascript
this.brokerUrl = 'mqtt://localhost:1883';
```

#### Option B: Cloud MQTT (HiveMQ, CloudMQTT, etc.)

```javascript
this.brokerUrl = 'mqtt://your-broker-url.com:1883';
this.options = {
  username: 'your-username',
  password: 'your-password'
};
```

#### Option C: Keep public broker (for testing only)
No changes needed - current setup works but not reliable for production.

### Environment Variables

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

### Test Backend MQTT

```bash
cd backend
node testMQTT.js
```

Expected output:
```
✅ MQTT Connection successful!
📤 Sending test unlock command...
✅ Unlock command sent successfully to LOCKER_001
```

---

## ESP32 Setup

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

**WiFi Credentials (REQUIRED):**
```cpp
const char* ssid = "YOUR_WIFI_SSID";        // ⚠️ Change to your WiFi name
const char* password = "YOUR_WIFI_PASSWORD"; // ⚠️ Change to your WiFi password
```

**⚠️ Important:** WiFi must be 2.4GHz (ESP32 doesn't support 5GHz)

**MQTT Broker:**
```cpp
const char* mqtt_server = "test.mosquitto.org";  // Public test broker
// Or use your computer's IP if running local broker:
// const char* mqtt_server = "192.168.1.100";  // Find with: ipconfig
```

**Locker ID (MUST MATCH QR CODE):**
```cpp
const char* LOCKER_ID = "LOCKER_001";  // ⚠️ Must match your QR code!
```

### 4️⃣ Upload to ESP32

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

---

## Hardware Wiring

### 📐 Wiring Connections (Step-by-Step)

#### Step 1: ESP32 → Relay Module

| ESP32 Pin | Wire Color (Suggested) | Relay Module Pin | Purpose |
|-----------|------------------------|------------------|---------|
| GPIO 26   | Yellow/Orange          | IN (Signal)      | Control signal |
| 5V        | Red                    | VCC (Power)      | Relay power |
| GND       | Black                  | GND (Ground)     | Common ground |

```
ESP32                    Relay Module
─────────────────────────────────────
GPIO 26 (Pin)     →      IN (Signal Input)
5V                →      VCC (Power)
GND               →      GND (Ground)
```

**⚠️ Important:** Use GPIO 26 specifically - this matches the code!

#### Step 2: Relay Module → Solenoid Lock

| Relay Terminal | Connection | Wire Color | Purpose |
|----------------|------------|------------|---------|
| COM (Common)   | 12V+ (Power Supply) | Red | High voltage input |
| NO (Normally Open) | Solenoid + | Red | To lock positive |
| NC (Normally Closed) | *Not used* | - | Leave disconnected |

```
Relay Module             12V Solenoid Lock
─────────────────────────────────────────────
COM (Common)      →      12V+ (from power supply)
NO (Normally Open) →     Solenoid + (Red wire)

Power Supply 12V GND →   Solenoid - (Black wire)
```

**⚠️ Important:** Connect to NO (Normally Open), NOT NC!

#### Step 3: Power Connections

| Component | Power Source | Voltage | Notes |
|-----------|-------------|---------|-------|
| ESP32     | USB cable   | 5V      | From computer or USB adapter |
| Relay     | ESP32 5V pin | 5V     | Low power consumption |
| Solenoid  | 12V Power Supply | 12V | High current (1-2A) |

**⚠️ Never connect 12V directly to ESP32! This will destroy it!**

### 🎨 Visual Diagram

```
                    ┌─────────────────┐
                    │   12V Power     │
                    │   Supply (2A)   │
                    └────┬────────┬───┘
                         │        │
                      12V+        GND
                         │         │
                         │         │
┌────────────────┐       │         │      ┌──────────────────┐
│                │       │         │      │                  │
│    ESP32       │       │         └──────┤─  Solenoid Lock  │
│                │       │                │   (12V)          │
│                │       │                │                  │
│  GPIO 26 ──────┼───────┼────────┐       │  Red (+) ───┐    │
│                │       │        │       │             │    │
│  5V ───────────┼───────┼────┐   │       │  Black (-) ─┼─┐  │
│                │       │    │   │       │             │ │  │
│  GND ──────────┼───────┼─┐  │   │       └─────────────┼─┼──┘
│                │       │ │  │   │                     │ │
│  GPIO 25 ──────┼───────┼─┼──┼───┼─── LED (+) ─ [220Ω]─┘ │
│                │       │ │  │   │                        │
└────────────────┘       │ │  │   │                        │
                         │ │  │   │                        │
                    ┌────┴─┴──┴───┴────┐                   │
                    │                  │                   │
                    │  Relay Module    │                   │
                    │  (5V)            │                   │
                    │                  │                   │
                    │  IN ─────────────┤ (from GPIO 26)    │
                    │  VCC ────────────┤ (from ESP32 5V)   │
                    │  GND ────────────┤ (from ESP32 GND)  │
                    │                  │                   │
                    │  COM ────────────┤ (to 12V+)         │
                    │  NO ─────────────┤ (to Solenoid +)   │
                    │  NC  (not used)  │                   │
                    │                  │                   │
                    └──────────────────┘                   │
                                                           │
                         Power Ground ─────────────────────┘
```

### ⚡ How It Works

#### UNLOCKED State (GPIO 26 = HIGH):
```
1. User scans QR code
   ↓
2. Backend sends MQTT unlock command
   ↓
3. ESP32 receives message on unlock topic
   ↓
4. ESP32 sets GPIO 26 to HIGH (3.3V output)
   ↓
5. Relay module detects signal → Switch closes
   ↓
6. 12V flows: Power Supply → COM → NO → Solenoid+
   ↓
7. Solenoid energizes → Bolt retracts
   ↓
8. 🔓 Door is UNLOCKED and STAYS UNLOCKED
```

#### LOCKED State (GPIO 26 = LOW):
```
1. Verification succeeds
   ↓
2. Backend sends MQTT lock command
   ↓
3. ESP32 receives message on lock topic
   ↓
4. ESP32 sets GPIO 26 to LOW (0V output)
   ↓
5. Relay de-energizes → Switch opens
   ↓
6. No 12V to solenoid → Spring pushes bolt out
   ↓
7. 🔒 Door is LOCKED
```

### Optional Components

#### Status LED
```
ESP32                    LED Circuit
───────────────────────────────────────────────
GPIO 25           →      LED Anode (+, longer leg)
                         ↓
                         220Ω Resistor
                         ↓
GND               →      LED Cathode (-, shorter leg)
```

**LED Behavior:**
- LED ON = Door unlocked
- LED OFF = Door locked

#### Door Sensor
```
ESP32                    Magnetic Door Sensor
────────────────────────────────────────────────
GPIO 27           →      Sensor Signal
GND               →      Sensor GND
3.3V              →      Sensor VCC (if active sensor)
```

---

## Testing & Verification

### Phase 1: Pre-Assembly Testing

#### 1. Test ESP32 Only (Software verification)
```cpp
// Upload this blink test to verify GPIO 26 works:
void setup() {
  Serial.begin(115200);
  pinMode(26, OUTPUT);
  Serial.println("GPIO 26 Blink Test");
}

void loop() {
  Serial.println("GPIO 26 HIGH");
  digitalWrite(26, HIGH);
  delay(2000);
  
  Serial.println("GPIO 26 LOW");
  digitalWrite(26, LOW);
  delay(2000);
}
```

**Expected Result:**
- Serial Monitor shows HIGH/LOW messages
- You can measure 3.3V/0V with multimeter on GPIO 26

#### 2. Test Relay (Hardware verification)
- Wire ESP32 to relay module (GPIO 26 → IN, 5V → VCC, GND → GND)
- Upload test code above
- **Expected Results:**
  - Relay clicks every 2 seconds (audible click!)
  - Red/Blue LED on relay module blinks

#### 3. Test Solenoid Independently
- **Disconnect everything from solenoid**
- Use separate 12V power supply
- **Briefly** touch 12V+ to solenoid+ (red wire)
- Touch 12V GND to solenoid- (black wire)

**Expected Results:**
- Solenoid makes a "thunk" sound
- Bolt retracts visibly
- When you disconnect, spring pushes bolt back out

**⚠️ Warning:** Don't leave 12V connected continuously - solenoid will overheat!

### Phase 2: MQTT Communication Testing

#### Test Backend Connection
```bash
cd backend
npm run dev
```

Should see:
```
✅ MQTT Client connected to broker
```

#### Test ESP32 Connection
Check Serial Monitor:
```
✅ WiFi Connected!
IP Address: 192.168.1.100
✅ MQTT Connected!
📡 Subscribed to: smartlocker/locker/LOCKER_001/unlock
📡 Subscribed to: smartlocker/locker/LOCKER_001/lock
```

#### Manual MQTT Test
```bash
# Test unlock
mosquitto_pub -h test.mosquitto.org -t "smartlocker/locker/LOCKER_001/unlock" -m '{"command":"UNLOCK"}'

# Test lock
mosquitto_pub -h test.mosquitto.org -t "smartlocker/locker/LOCKER_001/lock" -m '{"command":"LOCK"}'
```

ESP32 Serial Monitor should show:
```
🔓 UNLOCK COMMAND RECEIVED
⚡ Activating relay...
✅ Door UNLOCKED
⏳ Waiting for LOCK command...
```

### Phase 3: Full Application Test

#### Complete User Journey:

**Step 1: QR Code Scan**
1. Open Flutter app
2. Tap scan button
3. Scan QR code containing `LOCKER_001`
4. ✅ **Door unlocks immediately** via MQTT
5. Dialog shows: "Locker Unlocked Successfully"

**Step 2: Enter Details (Door Stays Open)**
6. Tap "Proceed to Input Recipient Details"
7. Enter first name, last name, phone number
8. Tap "Next"
9. 🚪 **Door remains open**

**Step 3: Scan Package (Door Still Open)**
10. Scan package barcode (waybill)
11. App reads waybill details with OCR
12. Generates image embedding
13. Saves to MongoDB
14. 🚪 **Door still open**

**Step 4: Live Verification → Lock**
15. App shows live camera feed
16. Scan the same package again
17. App compares embeddings
18. If match successful:
    - ✅ **Door locks immediately** via MQTT
    - Shows "Package Placed Successfully"

#### Expected Backend Logs:
```bash
# After QR scan
✅ Unlock command sent to locker LOCKER_001 after QR scan
✅ Unlock command sent to LOCKER_001
   Topic: smartlocker/locker/LOCKER_001/unlock

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

---

## Production Deployment

### 🔧 Before Deploying:

#### Option 1: Keep Current Behavior (Recommended for Development)
**No changes needed!** The current setup will:
- ✅ Work with ESP32 when connected (sends MQTT commands)
- ✅ Work without ESP32 (continues anyway for testing)
- ✅ Shows warning in console when ESP32 is offline

#### Option 2: Require ESP32 (Production Mode)

If you want to **enforce** that the ESP32 must be connected, change this in `backend/src/server.js`:

**Current Code (allows testing without ESP32):**
```javascript
// For testing without ESP32, we allow unlock even if MQTT fails
console.log(`\n✅ LOCKER UNLOCKED`);
if (!unlockSuccess) {
  console.log(`   ⚠️  MQTT command failed (ESP32 offline - but continuing anyway)`);
}

// Update locker status
locker.status = 'OCCUPIED';
await locker.save();

res.json({
  message: 'Unlock command sent successfully',
  locker_id: lockerId,
  status: 'UNLOCKED'
});
```

**Change To (requires ESP32):**
```javascript
if (unlockSuccess) {
  console.log(`\n✅ LOCKER UNLOCKED`);
  locker.status = 'OCCUPIED';
  await locker.save();
  
  res.json({
    message: 'Unlock command sent successfully',
    locker_id: lockerId,
    status: 'UNLOCKED'
  });
} else {
  res.status(503).json({
    error: 'ESP32 not connected',
    message: 'Cannot unlock locker - hardware not available'
  });
}
```

### 🎯 Production Checklist

#### Security:
- [ ] Use private MQTT broker (not public test broker)
- [ ] Enable MQTT authentication (username/password)
- [ ] Use MQTT over TLS/SSL (port 8883)
- [ ] Change default MQTT credentials
- [ ] Implement rate limiting on unlock commands

#### Hardware:
- [ ] Unique locker ID for each ESP32 (LOCKER_001, LOCKER_002, etc.)
- [ ] QR codes printed with matching locker IDs
- [ ] Add door sensor for security alerts (GPIO 27)
- [ ] Add backup power (UPS/battery for outages)
- [ ] Use industrial-grade solenoid locks
- [ ] Weather-proof enclosure for outdoor lockers
- [ ] Cable management and strain relief

#### Monitoring:
- [ ] Log all unlock/lock events to database
- [ ] Set up monitoring dashboard (online/offline status)
- [ ] Configure alerts for failed unlock attempts
- [ ] Track door sensor states (opened/closed)
- [ ] Monitor ESP32 uptime and WiFi signal strength
- [ ] Set up email/SMS alerts for security events

#### Testing:
- [ ] Test emergency manual override mechanism
- [ ] Test power failure recovery
- [ ] Test WiFi reconnection after dropout
- [ ] Test MQTT reconnection after broker restart
- [ ] Verify lock works after 1000+ cycles
- [ ] Test in various environmental conditions

---

## Troubleshooting

### ESP32 Connection Issues

#### ❌ WiFi not connecting
**Symptoms:** Serial Monitor shows "WiFi Connection Failed"

**Possible Causes:**
- [ ] ESP32 only supports 2.4GHz WiFi (not 5GHz)
- [ ] SSID or password incorrect (case-sensitive!)
- [ ] WiFi network unavailable or out of range
- [ ] MAC address filtering enabled on router

**Solutions:**
1. Verify WiFi is 2.4GHz network
2. Double-check SSID and password in code
3. Move ESP32 closer to router
4. Check router settings for MAC filtering
5. Try different WiFi network

#### ❌ MQTT connection failed
**Symptoms:** Serial Monitor shows "MQTT Connection failed"

**Possible Causes:**
- [ ] No internet connection (for public broker)
- [ ] Wrong broker IP/domain
- [ ] Firewall blocking port 1883
- [ ] MQTT broker not running

**Solutions:**
1. Check internet connection
2. Verify broker URL/IP is correct
3. Try public broker: `test.mosquitto.org`
4. Check firewall settings
5. Test with: `ping test.mosquitto.org`
6. Install mosquitto-clients and test:
   ```bash
   mosquitto_sub -h test.mosquitto.org -t "#" -v
   ```

### Hardware Issues

#### ❌ Door doesn't unlock after QR scan
**Symptoms:** No relay click, solenoid doesn't move

**Possible Causes:**
- [ ] Wiring connections incorrect or loose
- [ ] 12V power supply not working
- [ ] MQTT message not received by ESP32
- [ ] Relay module faulty
- [ ] Solenoid broken

**Solutions:**
1. Check backend logs for "Unlock command sent"
2. Check ESP32 Serial Monitor for "UNLOCK COMMAND RECEIVED"
3. Verify wiring: GPIO 26 → Relay IN, 5V → VCC, GND → GND
4. Listen for relay click sound
5. Test 12V supply with multimeter
6. Test relay with manual 5V to IN pin
7. Test solenoid directly with 12V
8. Verify locker ID matches QR code exactly

#### ❌ Relay clicks but solenoid doesn't move
**Symptoms:** Relay audible click, but bolt doesn't retract

**Possible Causes:**
- [ ] 12V power supply not connected
- [ ] Wrong relay terminal (using NC instead of NO)
- [ ] Solenoid wires reversed
- [ ] Solenoid burned out
- [ ] Voltage too low

**Solutions:**
1. Test 12V supply with multimeter (should show 12V)
2. Verify COM → 12V+ and NO → Solenoid+
3. Test solenoid directly with 12V (bypass relay)
4. Try swapping solenoid wires
5. Replace solenoid if broken

#### ❌ Door doesn't lock after verification
**Symptoms:** Door stays unlocked after successful verification

**Possible Causes:**
- [ ] Lock command not being sent from backend
- [ ] ESP32 not subscribed to lock topic
- [ ] GPIO 26 stuck at HIGH
- [ ] Relay stuck ON

**Solutions:**
1. Check backend logs for "Lock command sent"
2. Check ESP32 Serial Monitor for "LOCK COMMAND RECEIVED"
3. Verify ESP32 code subscribes to lock topic
4. Test manual lock command:
   ```bash
   mosquitto_pub -h test.mosquitto.org -t "smartlocker/locker/LOCKER_001/lock" -m '{"command":"LOCK"}'
   ```
5. Upload test code to force GPIO 26 LOW

### System Issues

#### ❌ ESP32 keeps resetting/rebooting
**Symptoms:** Constant restarts, boot loop

**Possible Causes:**
- [ ] Insufficient power from USB
- [ ] Trying to power solenoid from ESP32 5V
- [ ] Short circuit
- [ ] Brown-out detector triggering

**Solutions:**
1. Use quality USB cable and 2A power adapter
2. **Never power solenoid from ESP32** - use separate 12V supply
3. Check all wiring for shorts
4. Disconnect relay and test ESP32 alone
5. Try different USB port

#### ❌ Wrong locker unlocks or no response
**Symptoms:** Different locker ID responds

**Possible Causes:**
- [ ] LOCKER_ID mismatch between code and QR
- [ ] Multiple ESP32s with same ID
- [ ] Backend sending to wrong topic

**Solutions:**
1. Verify LOCKER_ID in code matches QR exactly
2. Ensure each ESP32 has unique ID
3. Monitor MQTT traffic:
   ```bash
   mosquitto_sub -h test.mosquitto.org -t "#" -v
   ```
4. Check backend logs for correct topic

#### ❌ Random unlocking/locking
**Symptoms:** Unpredictable lock behavior

**Possible Causes:**
- [ ] Loose wiring connections
- [ ] Electromagnetic interference
- [ ] Public MQTT broker receiving others' commands
- [ ] Multiple devices with same LOCKER_ID

**Solutions:**
1. Secure all connections with solder
2. Use shielded cables
3. Use private MQTT broker
4. Add MQTT authentication
5. Ensure unique LOCKER_IDs

#### ❌ Solenoid gets very hot
**Symptoms:** Solenoid overheating

**Possible Causes:**
- [ ] Voltage too high (24V instead of 12V)
- [ ] Powered continuously too long
- [ ] Wrong solenoid type (intermittent vs continuous)

**Solutions:**
1. Verify 12V power supply (not 24V!)
2. Check code - should only power when unlocking
3. Use continuous-duty rated solenoid
4. Add heat sink
5. Reduce unlock duration

---

## Integration Checklist

### 🔌 ESP32 Configuration

#### MQTT Topics

Your ESP32 should **subscribe** to:
```
smartlocker/locker/{LOCKER_ID}/unlock
smartlocker/locker/{LOCKER_ID}/lock
```

Example:
```cpp
// ESP32 Arduino Code
client.subscribe("smartlocker/locker/LOCKER_001/unlock");
client.subscribe("smartlocker/locker/LOCKER_001/lock");
```

**Unlock Payload Format (JSON):**
```json
{
  "command": "UNLOCK",
  "lockerId": "LOCKER_001",
  "timestamp": "2025-11-10T15:50:58.217Z",
  "trigger": "QR_SCAN_WITH_TOKEN",
  "token": "9d063412022df67d"
}
```

**Lock Payload Format (JSON):**
```json
{
  "command": "LOCK",
  "lockerId": "LOCKER_001",
  "timestamp": "2025-11-10T15:52:30.123Z",
  "trigger": "VERIFICATION_SUCCESS"
}
```

### ESP32 Connection Detection

**When ESP32 connects, backend console shows:**
```
✅ MQTT connected
```

**When ESP32 is offline, backend shows:**
```
⚠️  MQTT unavailable (ESP32 offline - this is normal)
```

### Testing Checklist When ESP32 is Ready:

#### Before Connecting:
- [ ] ESP32 code uploaded and running
- [ ] ESP32 connected to WiFi
- [ ] MQTT broker running (if using local)
- [ ] ESP32 subscribed to correct topics

#### After Connecting:
- [ ] Backend console shows "✅ MQTT connected"
- [ ] Test unlock: Scan QR → Backend sends MQTT → ESP32 receives → Locker opens
- [ ] Check backend console for unlock confirmations
- [ ] Verify no "MQTT command failed" warnings

#### Debug if MQTT Fails:
- [ ] Check ESP32 Serial Monitor for MQTT connection logs
- [ ] Verify broker URL and port are correct
- [ ] Check WiFi connection on ESP32
- [ ] Verify topic names match exactly (case-sensitive)

---

## MQTT Topics Structure

```
smartlocker/locker/{LOCKER_ID}/unlock  → ESP32 subscribes (receives unlock commands)
smartlocker/locker/{LOCKER_ID}/lock    → ESP32 subscribes (receives lock commands)
smartlocker/locker/{LOCKER_ID}/status  → ESP32 publishes (sends status updates)
```

---

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
  "timestamp": "2025-11-10T08:49:48.693Z"
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
  "timestamp": "2025-11-10T08:51:23.456Z"
}
```

---

## Testing & Debugging Tools

### Monitor All MQTT Traffic
```bash
# Listen to all topics (wildcard)
mosquitto_sub -h test.mosquitto.org -t "smartlocker/#" -v

# Listen to specific locker
mosquitto_sub -h test.mosquitto.org -t "smartlocker/locker/LOCKER_001/#" -v
```

### Manual MQTT Commands
```bash
# Unlock door
mosquitto_pub -h test.mosquitto.org -t "smartlocker/locker/LOCKER_001/unlock" -m '{"command":"UNLOCK"}'

# Lock door
mosquitto_pub -h test.mosquitto.org -t "smartlocker/locker/LOCKER_001/lock" -m '{"command":"LOCK"}'
```

### Test via API
```bash
# Unlock
curl -X PUT http://localhost:3000/api/locker/LOCKER_001/unlock

# Lock
curl -X PUT http://localhost:3000/api/locker/LOCKER_001/lock
```

### Run Backend Test Script
```bash
cd backend
node testMQTT.js
```

---

## 📚 Quick Reference

### GPIO Pins
- **GPIO 26**: Lock control (Relay) - Main control pin
- **GPIO 25**: Status LED (optional) - Visual indicator  
- **GPIO 27**: Door sensor (optional) - Security monitoring

### Lock Behavior
- **GPIO 26 HIGH** = Door UNLOCKED (relay ON, 12V to solenoid, bolt retracts)
- **GPIO 26 LOW** = Door LOCKED (relay OFF, no power, spring extends bolt)

### Updated Flow
1. **QR Scan** → Unlock command sent → Door unlocks immediately
2. **Door stays open** while user enters details and scans package
3. **Verification Success** → Lock command sent → Door locks
4. **No auto-lock timer** - door only locks when commanded

---

## 🎓 Support & Resources

### Helpful Websites
- ESP32 Pinout Reference: https://randomnerdtutorials.com/esp32-pinout-reference-gpios/
- Arduino ESP32 Docs: https://docs.espressif.com/projects/arduino-esp32/
- MQTT Basics: https://mqtt.org/getting-started/
- Mosquitto Download: https://mosquitto.org/download/

### Related Files
- `ESP32_SmartLocker_Code.ino` - Arduino code to upload
- `backend/src/services/mqttService.js` - MQTT service
- `backend/src/server.js` - API endpoints
- `backend/testMQTT.js` - MQTT testing script

---

**Last Updated:** November 10, 2025  
**Version:** 2.0 - Complete integration guide

**Ready to build? Start with [ESP32 Setup](#esp32-setup) section!** 🚀
