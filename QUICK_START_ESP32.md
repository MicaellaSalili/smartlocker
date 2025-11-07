# Quick Start Guide - ESP32 Smart Locker

> **Version 2.0** - Updated flow: Unlock after QR scan, lock after verification (no auto-timer)

## Overview

This guide walks you through setting up the ESP32-controlled smart locker system where:
1. 📱 **QR Scan** → 🔓 Door unlocks immediately
2. 👤 **User deposits package** (door stays unlocked)
3. 📸 **Live Verification** → 🔒 Door locks automatically

**No auto-lock timer** - Door stays unlocked until verification succeeds!

---

## Step-by-Step Implementation

### 1️⃣ Install MQTT Broker (Choose One)

**Option A: Local Mosquitto (Recommended for Development)**
```bash
# Windows: Download from https://mosquitto.org/download/
# After install:
net start mosquitto

# macOS:
brew install mosquitto
brew services start mosquitto

# Linux:
sudo apt install mosquitto
sudo systemctl start mosquitto
```

**Option B: Cloud MQTT (Recommended for Production)**
- Sign up at https://www.hivemq.com/mqtt-cloud-broker/
- Get your broker URL, username, password

**Option C: Public Test Broker (Testing Only)**
- Use `test.mosquitto.org` (already configured in code)

---

### 2️⃣ Backend Setup (Already Done ✅)

Files created:
- ✅ `backend/src/services/mqttService.js` - MQTT communication service
- ✅ `backend/src/server.js` - Unlock/lock endpoints
- ✅ `backend/testMQTT.js` - Test script

What it does:
- Connects to MQTT broker when server starts
- **Sends UNLOCK** command after QR scan (PUT /api/locker/:lockerId/unlock)
- **Sends LOCK** command after verification success (PUT /api/locker/:lockerId/lock)
- Topics: 
  - `smartlocker/locker/{LOCKER_ID}/unlock`
  - `smartlocker/locker/{LOCKER_ID}/lock`

---

### 3️⃣ Test Backend MQTT

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

### 4️⃣ ESP32 Setup

**Install Arduino IDE + Libraries:**
1. Download Arduino IDE: https://www.arduino.cc/en/software
2. Add ESP32 board: File → Preferences → Additional Board URLs:
   ```
   https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
   ```
3. Install boards: Tools → Board → Boards Manager → Search "ESP32" → Install
4. Install libraries: Tools → Manage Libraries:
   - Search "PubSubClient" → Install

**Configure & Upload:**
1. Open `ESP32_SmartLocker_Code.ino`
2. Update WiFi credentials:
   ```cpp
   const char* ssid = "YOUR_WIFI_NAME";
   const char* password = "YOUR_WIFI_PASSWORD";
   ```
3. Update MQTT broker:
   ```cpp
   const char* mqtt_server = "192.168.1.100";  // Your computer's IP
   ```
4. Set unique locker ID:
   ```cpp
   const char* LOCKER_ID = "LOCKER_001";
   ```
5. Connect ESP32 via USB
6. Select: Tools → Board → ESP32 Dev Module
7. Select: Tools → Port → (your ESP32 port)
8. Click Upload ⬆️
9. Open Serial Monitor (115200 baud)

---

### 5️⃣ Hardware Wiring

```
Components Needed:
- ESP32 board
- 5V Relay module
- 12V Solenoid lock
- 12V power supply

Connections:
ESP32 GPIO26 → Relay IN
ESP32 5V     → Relay VCC
ESP32 GND    → Relay GND

Relay COM    → 12V+ (power supply)
Relay NO     → Solenoid + (lock)
12V GND      → Solenoid - (lock)
```

---

### 6️⃣ Test Complete Flow

#### **Phase 1: Test MQTT Communication**

1. **Start backend:**
   ```bash
   cd backend
   npm run dev
   ```
   Should see: `✅ MQTT Client connected to broker`

2. **Check ESP32 Serial Monitor:**
   Should see:
   ```
   ================================
   🔐 Smart Locker Controller v2.0
   ================================
   Locker ID: LOCKER_001
   WiFi SSID: YourWiFiName
   MQTT Broker: test.mosquitto.org
   ================================
   
   ✅ WiFi Connected! IP: 192.168.1.XXX
   ✅ MQTT Connected!
   📡 Subscribed to: smartlocker/locker/LOCKER_001/unlock
   📡 Subscribed to: smartlocker/locker/LOCKER_001/lock
   ```

#### **Phase 2: Test Manual Commands**

3. **Test UNLOCK from terminal:**
   ```bash
   # Install mosquitto-clients if needed
   mosquitto_pub -h test.mosquitto.org -t "smartlocker/locker/LOCKER_001/unlock" -m '{"command":"UNLOCK"}'
   ```
   
   ESP32 should print:
   ```
   ================================
   🔓 UNLOCK COMMAND RECEIVED
   ================================
   🔓 Door is now UNLOCKED
   ⏳ Waiting for LOCK command...
   ```
   
   **Door unlocks and STAYS unlocked!**

4. **Test LOCK from terminal:**
   ```bash
   mosquitto_pub -h test.mosquitto.org -t "smartlocker/locker/LOCKER_001/lock" -m '{"command":"LOCK"}'
   ```
   
   ESP32 should print:
   ```
   ================================
   🔒 LOCK COMMAND RECEIVED
   ================================
   🔒 Door is now LOCKED
   ✅ Locker secured
   ```

#### **Phase 3: Test Full App Flow**

5. **Complete user journey:**
   - ✅ Open Flutter app
   - ✅ Scan QR code with `LOCKER_001`
   - ✅ **Door unlocks immediately!** 🔓
   - ✅ Input recipient details (door stays unlocked)
   - ✅ Scan package barcode (door stays unlocked)
   - ✅ Complete live verification
   - ✅ **Door locks automatically!** 🔒 🎉

Expected Serial Monitor output:
```
🔓 UNLOCK COMMAND RECEIVED (from QR scan)
🔓 Door is now UNLOCKED
⏳ Waiting for LOCK command...
[User deposits package...]
🔒 LOCK COMMAND RECEIVED (from verification)
🔒 Door is now LOCKED
```

---

## Troubleshooting

### ❌ "MQTT Connection failed"
- Check if broker is running: `mosquitto -v`
- Check broker port: `netstat -an | grep 1883`
- Try public broker: Change to `test.mosquitto.org`

### ❌ ESP32 won't connect to WiFi
- Use 2.4GHz WiFi (ESP32 doesn't support 5GHz)
- Check SSID and password are correct
- Ensure WiFi has internet access

### ❌ ESP32 won't connect to MQTT
- Check `mqtt_server` IP is your computer's local IP
- Windows: `ipconfig` | macOS/Linux: `ifconfig`
- Disable firewall temporarily to test
- Try public broker: `test.mosquitto.org`

### ❌ Door unlocks but won't lock
- Check if verification completed successfully
- Look for LOCK command in Serial Monitor
- Verify lock endpoint is being called
- Test manual lock: `mosquitto_pub -h test.mosquitto.org -t "smartlocker/locker/LOCKER_001/lock" -m '{"command":"LOCK"}'`

### ❌ Door doesn't unlock after QR scan
- Check wiring (especially relay connections)
- Listen for relay click sound
- Verify QR code contains correct LOCKER_ID
- Check backend logs for unlock API call
- Test manual unlock: `mosquitto_pub -h test.mosquitto.org -t "smartlocker/locker/LOCKER_001/unlock" -m '{"command":"UNLOCK"}'`
- Verify 12V power supply works

### ❌ Door locks too quickly
- **This should NOT happen in v2.0!**
- Check ESP32 code - should have NO timer logic
- Verify you uploaded the latest code version
- Serial Monitor should say "v2.0" on boot

---

## Production Checklist

### Security & Authentication
- [ ] Use private MQTT broker (not public test broker)
- [ ] Enable MQTT authentication (username/password)
- [ ] Use MQTT over TLS/SSL (port 8883)
- [ ] Implement API authentication for unlock/lock endpoints
- [ ] Add rate limiting to prevent spam unlock attempts

### Hardware & Configuration
- [ ] Unique locker ID for each ESP32
- [ ] QR codes match locker IDs exactly
- [ ] Add door sensors for security (detect if door opened without unlock)
- [ ] Add backup power (UPS/battery) for power outages
- [ ] Use quality relay modules (rated for continuous operation)
- [ ] Weatherproof enclosure for outdoor installations

### Monitoring & Logging
- [ ] Log all unlock/lock events to database with timestamps
- [ ] Set up monitoring for ESP32 online/offline status
- [ ] Alert system for failed unlock attempts
- [ ] Dashboard to view locker status in real-time
- [ ] Track door open duration (unlock to lock time)

### User Experience
- [ ] Test complete flow with real users
- [ ] Handle edge cases (network loss, verification failure)
- [ ] Add manual override mechanism (emergency unlock)
- [ ] Provide user notifications (SMS/email on unlock/lock)
- [ ] Add timeout safety (auto-lock after X hours if verification never happens)

---

## Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     SMART LOCKER FLOW v2.0                      │
└─────────────────────────────────────────────────────────────────┘

1️⃣  User scans QR code → Gets LOCKER_ID (e.g., LOCKER_001)
     ↓
2️⃣  App calls: PUT /api/locker/LOCKER_001/unlock
     ↓
3️⃣  Backend sends MQTT → smartlocker/locker/LOCKER_001/unlock
     ↓
4️⃣  ESP32 receives UNLOCK command
     ↓
5️⃣  ESP32 sets GPIO26 HIGH → 🔓 DOOR UNLOCKS
     ↓
6️⃣  Door STAYS UNLOCKED (no timer!)
     ↓
7️⃣  User inputs recipient details (door still unlocked)
     ↓
8️⃣  User scans package barcode (door still unlocked)
     ↓
9️⃣  User deposits package and closes door (door still unlocked)
     ↓
🔟  App performs live verification
     ↓
1️⃣1️⃣  Verification SUCCESS
     ↓
1️⃣2️⃣  App calls: PUT /api/locker/LOCKER_001/lock
     ↓
1️⃣3️⃣  Backend sends MQTT → smartlocker/locker/LOCKER_001/lock
     ↓
1️⃣4️⃣  ESP32 receives LOCK command
     ↓
1️⃣5️⃣  ESP32 sets GPIO26 LOW → 🔒 DOOR LOCKS
     ↓
1️⃣6️⃣  Transaction complete! ✅
```

### Key Differences from Old Flow

| Aspect | ❌ Old Flow | ✅ New Flow (v2.0) |
|--------|------------|-------------------|
| **Unlock Trigger** | After verification | **After QR scan** |
| **Lock Trigger** | Auto-timer (5s) | **After verification** |
| **Door Open Time** | Fixed 5 seconds | **Indefinite until verified** |
| **User Experience** | Rush to deposit | **Relaxed, no time pressure** |
| **Safety** | Timer-based | **Verification-based** |

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

### Check ESP32 System Info
The ESP32 code includes a `printSystemInfo()` function that shows:
- Firmware version (should be v2.0)
- Locker ID
- WiFi status and IP address
- MQTT connection status
- Current door state
- Uptime

Look for this in Serial Monitor on boot!

### Debug Checklist
1. ✅ Check Serial Monitor for ESP32 debug output
2. ✅ Check backend console for MQTT connection status
3. ✅ Use `mosquitto_sub` to monitor all MQTT messages
4. ✅ Test unlock/lock manually with `mosquitto_pub`
5. ✅ Verify WiFi and MQTT broker connectivity
6. ✅ Test components individually before full integration
7. ✅ Check wiring with multimeter (verify 12V on solenoid when unlocked)
8. ✅ Review ESP32_WIRING_DIAGRAM.md for troubleshooting steps

---

## Additional Resources

📖 **Detailed Documentation:**
- `ESP32_SETUP_CHECKLIST.md` - Complete setup guide with testing phases
- `ESP32_WIRING_DIAGRAM.md` - Hardware connections and troubleshooting
- `ESP32_INTEGRATION_GUIDE.md` - System architecture and API details
- `ESP32_UPDATE_SUMMARY.md` - Summary of v2.0 changes

🔧 **Source Code:**
- `ESP32_SmartLocker_Code.ino` - ESP32 firmware (v2.0)
- `backend/src/services/mqttService.js` - MQTT service
- `backend/src/server.js` - API endpoints
- `backend/testMQTT.js` - MQTT testing script

---