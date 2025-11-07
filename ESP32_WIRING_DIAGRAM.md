# ESP32 Wiring Diagram - Smart Locker System v2.0

## 🔌 Complete Wiring Setup

### Components List:
1. **ESP32 DevKit** (30-pin or 38-pin) - Microcontroller
2. **5V Relay Module** (1-channel) - High voltage switch
3. **12V Solenoid Door Lock** - Electric door lock mechanism
4. **12V Power Supply** (2A minimum, 3A recommended) - Powers solenoid
5. **Jumper wires** (Male-to-Female, ~20 pieces) - Connections
6. **USB cable** (Micro-USB or USB-C) - For ESP32 programming & power
7. **LED + 220Ω resistor** (optional) - Status indicator
8. **Magnetic door sensor** (optional) - Security monitoring

**Estimated Total Cost: $30-70 USD**

---

## 📐 Wiring Connections (Step-by-Step)

### Step 1: ESP32 → Relay Module

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

---

### Step 2: Relay Module → Solenoid Lock

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

---

### Step 3: Power Connections

| Component | Power Source | Voltage | Notes |
|-----------|-------------|---------|-------|
| ESP32     | USB cable   | 5V      | From computer or USB adapter |
| Relay     | ESP32 5V pin | 5V     | Low power consumption |
| Solenoid  | 12V Power Supply | 12V | High current (1-2A) |

**⚠️ Never connect 12V directly to ESP32! This will destroy it!**

---

### Step 4: Optional - Status LED

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
- Blinking 3x = WiFi connected

---

### Step 5: Optional - Door Sensor

```
ESP32                    Magnetic Door Sensor
────────────────────────────────────────────────
GPIO 27           →      Sensor Signal (usually white/yellow)
GND               →      Sensor GND (black)
3.3V              →      Sensor VCC (red) - if active sensor

Or for passive (switch-type) sensor:
GPIO 27           →      One terminal
GND               →      Other terminal
```

**Sensor Behavior:**
- HIGH = Door closed
- LOW = Door open
- Alert triggered if door opens while locked

---

## 🎨 Visual Diagram

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

---

## 🔧 Pin Mapping Reference

### ESP32 Pinout:
```
                   ESP32 DevKit
         ┌─────────────────────────┐
         │                         │
    3V3  │ [1]           [30] GPIO23
    GND  │ [2]           [29] GPIO22
GPIO15  │ [3]           [28] TX0
GPIO2   │ [4]           [27] RX0
GPIO4   │ [5]           [26] GPIO21
GPIO16  │ [6]           [25] GND
GPIO17  │ [7]           [24] GPIO19
GPIO5   │ [8]           [23] GPIO18
GPIO18  │ [9]           [22] GPIO5
GPIO19  │ [10]          [21] GPIO17
GND     │ [11]          [20] GPIO16
GPIO21  │ [12]          [19] GPIO4
RX2     │ [13]          [18] GPIO0
TX2     │ [14]          [17] GPIO2
GPIO22  │ [15]          [16] GPIO15
         │                         │
    3V3  │ [1]           [14] GND
GPIO26  │ [2] ← Lock    [13] GPIO14
GPIO27  │ [3] ← Door    [12] GPIO12
GPIO14  │ [4]           [11] GPIO13
GPIO12  │ [5]           [10] GPIO9
GND     │ [6]           [9]  GPIO10
GPIO13  │ [7]           [8]  CMD
         │                         │
         └─────────────────────────┘

Key Pins Used:
• GPIO 26 → Relay IN (Lock Control)
• GPIO 25 → LED (Status Indicator)
• GPIO 27 → Door Sensor (optional)
```

---

## ⚡ How It Works - Detailed Explanation

### System Architecture:
```
QR Scan → Backend API → MQTT Broker → ESP32 → Relay → Solenoid Lock
```

### UNLOCKED State (GPIO 26 = HIGH):
```
Step-by-step process:

1. User scans QR code
   ↓
2. Backend sends MQTT unlock command
   ↓
3. ESP32 receives message on unlock topic
   ↓
4. ESP32 sets GPIO 26 to HIGH (3.3V output)
   ↓
5. Relay module detects signal on IN pin
   ↓
6. Relay coil energizes → Internal switch closes
   ↓
7. Relay COM connects to NO (Normally Open contact)
   ↓
8. 12V flows: Power Supply → COM → NO → Solenoid+
   ↓
9. Solenoid coil energizes → Magnetic field created
   ↓
10. Bolt retracts against spring tension
    ↓
11. 🔓 Door is UNLOCKED and STAYS UNLOCKED
    ↓
12. No timer! Door remains open until lock command received
```

**Visual Flow:**
```
ESP32          Relay                Solenoid
GPIO26=HIGH → [Coil ON] → 12V→Lock → [Bolt IN] → UNLOCKED
```

---

### LOCKED State (GPIO 26 = LOW):

```
Step-by-step process:

1. Verification succeeds
   ↓
2. Backend sends MQTT lock command
   ↓
3. ESP32 receives message on lock topic
   ↓
4. ESP32 sets GPIO 26 to LOW (0V output)
   ↓
5. Relay module loses signal on IN pin
   ↓
6. Relay coil de-energizes → Internal switch opens
   ↓
7. Relay COM disconnects from NO contact
   ↓
8. No 12V flows to solenoid
   ↓
9. Solenoid coil de-energizes → Magnetic field collapses
   ↓
10. Spring pushes bolt out
    ↓
11. 🔒 Door is LOCKED
```

**Visual Flow:**
```
ESP32          Relay                Solenoid
GPIO26=LOW  → [Coil OFF] → No 12V  → [Bolt OUT] → LOCKED
```

---

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

**Key Point:** Time between unlock and lock varies - it's based on user actions, not a timer!

---

## 🧪 Testing Steps (In Order!)

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

---

#### 2. Test Relay (Hardware verification)
- Wire ESP32 to relay module (GPIO 26 → IN, 5V → VCC, GND → GND)
- Upload test code above
- **Expected Results:**
  - Relay clicks every 2 seconds (audible click!)
  - Red/Blue LED on relay module blinks
  - You can hear the mechanical switch inside

**Troubleshooting:**
- No click? Check 5V and GND connections
- Continuous click? Check GPIO 26 connection

---

#### 3. Test Solenoid Independently (Before connecting to relay)
- **Disconnect everything from solenoid**
- Use separate 12V power supply
- **Briefly** touch 12V+ to solenoid+ (red wire)
- Touch 12V GND to solenoid- (black wire)

**Expected Results:**
- Solenoid makes a "thunk" sound
- Bolt retracts visibly
- When you disconnect, spring pushes bolt back out

**⚠️ Warning:** Don't leave 12V connected continuously - solenoid will overheat!

---

### Phase 2: Full System Integration

#### 4. Test Relay + Solenoid (No ESP32 control yet)
- Wire relay to solenoid (COM → 12V+, NO → Solenoid+)
- Connect 12V GND to Solenoid-
- Manually trigger relay by connecting 5V to IN pin

**Expected Results:**
- Relay clicks when IN is powered
- Solenoid retracts when relay activates
- Solenoid extends when relay deactivates

---

#### 5. Test Complete System (ESP32 + Relay + Solenoid)
- Upload ESP32_SmartLocker_Code.ino
- Open Serial Monitor (115200 baud)
- Check for WiFi and MQTT connection
- Send test unlock command:
  ```bash
  curl -X PUT http://localhost:3000/api/locker/LOCKER_001/unlock
  ```

**Expected Serial Monitor Output:**
```
📨 Message received!
Topic: smartlocker/locker/LOCKER_001/unlock
🔓 UNLOCK COMMAND RECEIVED
⚡ Activating relay...
✅ Door UNLOCKED
⏳ Waiting for LOCK command...
```

**Expected Physical Results:**
- Relay clicks
- Solenoid bolt retracts
- LED turns ON (if connected)
- Door stays unlocked

---

#### 6. Test Lock Command
- Send lock command:
  ```bash
  curl -X PUT http://localhost:3000/api/locker/LOCKER_001/lock
  ```

**Expected Serial Monitor Output:**
```
📨 Message received!
Topic: smartlocker/locker/LOCKER_001/lock
🔒 LOCK COMMAND RECEIVED
⚡ Deactivating relay...
✅ Door LOCKED
```

**Expected Physical Results:**
- Relay clicks
- Solenoid bolt extends
- LED turns OFF (if connected)

---

### Phase 3: Full Application Test

#### 7. Test Complete User Flow
1. Start backend: `cd backend && npm run dev`
2. Start Flutter app
3. Scan QR code → Door should unlock
4. Enter details and scan package
5. Complete verification → Door should lock

**Success Criteria:**
- ✅ Door unlocks after QR scan
- ✅ Door stays unlocked during verification
- ✅ Door locks after verification succeeds
- ✅ Backend logs show MQTT commands
- ✅ ESP32 Serial Monitor shows received commands

---

## ⚠️ Safety Warnings

1. **Never connect 12V to ESP32 pins!**
   - ESP32 pins are 3.3V max
   - Use relay to isolate high voltage

2. **Check polarity before powering on**
   - Wrong polarity can damage components
   - Red = Positive (+), Black = Negative (-)

3. **Use appropriate wire gauge**
   - 12V power: Use 18-22 AWG wire
   - ESP32 signals: Use 22-26 AWG wire

4. **Prevent short circuits**
   - Keep wires organized
   - Use heat shrink or electrical tape
   - Don't let bare wires touch

5. **Power supply ratings**
   - Use 12V 2A minimum for solenoid
   - Don't power ESP32 from 12V supply directly
   - Use USB or 5V regulator for ESP32

---

## 🔍 Troubleshooting Guide

### Problem: Relay clicks but solenoid doesn't move

**Possible Causes:**
- [ ] 12V power supply not connected or faulty
- [ ] Wrong relay terminal used (using NC instead of NO)
- [ ] Solenoid wires reversed (shouldn't matter but try swapping)
- [ ] Solenoid is broken/burned out
- [ ] Voltage too low (need 12V, not 9V or 5V)

**Solutions:**
1. Test 12V supply with multimeter (should show 12V)
2. Verify COM → 12V+ and NO → Solenoid+
3. Test solenoid directly with 12V (bypass relay)
4. Try a different solenoid lock

---

### Problem: Relay doesn't click at all

**Possible Causes:**
- [ ] GPIO 26 not connected to Relay IN
- [ ] 5V or GND not connected to relay
- [ ] ESP32 not running code
- [ ] Relay module is faulty
- [ ] GPIO 26 stuck LOW

**Solutions:**
1. Check all three connections: GPIO 26, 5V, GND
2. Upload blink test code and check Serial Monitor
3. Measure voltage on GPIO 26 (should be 3.3V when HIGH)
4. Test relay with direct 5V to IN pin
5. Try different GPIO pin (update code accordingly)

---

### Problem: ESP32 keeps resetting/rebooting

**Possible Causes:**
- [ ] Insufficient power from USB cable
- [ ] Trying to power solenoid from ESP32 5V pin
- [ ] Short circuit somewhere
- [ ] Brown-out detector triggering

**Solutions:**
1. Use quality USB cable and power adapter (2A minimum)
2. **Never power solenoid from ESP32** - use separate 12V supply
3. Check all wiring for shorts
4. Power ESP32 from computer USB port temporarily
5. Disconnect relay and test ESP32 alone

---

### Problem: Lock activates but won't lock again

**Possible Causes:**
- [ ] Solenoid overheating and stuck
- [ ] Mechanical obstruction in door
- [ ] Spring in solenoid is broken
- [ ] Bolt misaligned with door frame

**Solutions:**
1. Let solenoid cool down (don't leave powered continuously)
2. Check door alignment and bolt path
3. Manually push/pull bolt to check spring
4. Test solenoid outside of door assembly

---

### Problem: Solenoid stays locked/won't unlock

**Possible Causes:**
- [ ] Relay stuck in OFF position
- [ ] No 12V power
- [ ] GPIO 26 stuck at LOW
- [ ] Code not running unlock command

**Solutions:**
1. Check Serial Monitor for "UNLOCK COMMAND RECEIVED"
2. Verify 12V power supply is on
3. Manually bridge COM to NO on relay to test
4. Upload blink test code to force GPIO HIGH

---

### Problem: Wrong locker unlocks or no response

**Possible Causes:**
- [ ] LOCKER_ID mismatch (code vs QR code)
- [ ] MQTT not connected
- [ ] WiFi not connected
- [ ] Backend not sending to correct topic

**Solutions:**
1. Verify LOCKER_ID in code matches QR code exactly
2. Check Serial Monitor for "MQTT Connected"
3. Check Serial Monitor for "WiFi Connected"
4. Monitor MQTT traffic: `mosquitto_sub -h test.mosquitto.org -t "#" -v`
5. Check backend logs for topic name

---

### Problem: Random unlocking/locking

**Possible Causes:**
- [ ] Loose wiring connections
- [ ] Electromagnetic interference
- [ ] Multiple ESP32s with same LOCKER_ID
- [ ] Public MQTT broker receiving commands from others

**Solutions:**
1. Secure all wire connections with solder or crimps
2. Use shielded cables for long wire runs
3. Ensure each ESP32 has unique LOCKER_ID
4. Use private MQTT broker for production
5. Add authentication to MQTT

---

### Problem: Solenoid gets very hot

**Possible Causes:**
- [ ] Voltage too high (using 24V instead of 12V)
- [ ] Solenoid powered continuously too long
- [ ] Wrong solenoid type (intermittent vs continuous duty)

**Solutions:**
1. Verify 12V power supply (not 24V!)
2. Check code - should only power when unlocking
3. Use continuous-duty rated solenoid for smart locks
4. Add heat sink to solenoid body
5. Reduce unlock duration if possible

---

## 📦 Shopping List with Recommendations

### Required Components:

| Item | Specs | Price Range | Recommended Brands | Notes |
|------|-------|-------------|-------------------|-------|
| ESP32 DevKit | 30-pin or 38-pin | $5-10 | DOIT, Espressif, HiLetgo | Get CH340 USB chip version |
| 5V Relay Module | 1-channel, 10A | $2-5 | SainSmart, Elegoo, HiLetgo | Get "active high" trigger |
| 12V Solenoid Lock | 12V DC, 1-2A | $10-20 | Generic, Uxcell | Get "electric door lock" type |
| 12V Power Supply | 12V 2-3A | $5-10 | Mean Well, ALITOVE | Get UL/CE certified |
| Jumper Wires | M-F, 20cm, 40pcs | $3-5 | Elegoo, EDGELEC | Get assorted colors |
| USB Cable | Micro-USB or USB-C | $3-5 | Anker, AmazonBasics | Match your ESP32 type |

**Subtotal: ~$28-55**

---

### Optional Components:

| Item | Specs | Price Range | Purpose |
|------|-------|-------------|---------|
| LED Pack | 5mm, assorted colors | $2-5 | Status indicator |
| Resistor Pack | 220Ω, 1/4W | $2-5 | For LED (get assortment) |
| Door Sensor | Magnetic, NC or NO | $2-5 | Security monitoring |
| Breadboard | 830 points | $3-8 | Prototyping |
| Enclosure Box | IP65 rated | $5-15 | Weather protection |
| Heat Shrink Tubing | Assorted sizes | $5-10 | Wire insulation |
| Cable Ties | 100pcs, various sizes | $3-7 | Cable management |
| Multimeter | Digital, basic | $10-20 | Testing & debugging |

**Optional Total: ~$32-75**

---

### Where to Buy:

**Online (Worldwide):**
- 🌐 **AliExpress** - Cheapest, 2-4 weeks shipping
- 🌐 **Amazon** - Fast shipping (1-2 days), higher prices
- 🌐 **eBay** - Good for bulk/used components
- 🌐 **DigiKey/Mouser** - High quality, reliable, expensive

**US:**
- Adafruit, SparkFun, Micro Center

**Philippines:**
- e-Gizmo, Lazada, Shopee

---

### Cost Summary:

| Configuration | Components | Estimated Cost |
|---------------|-----------|----------------|
| **Minimal** | Required only | $30-55 USD |
| **Standard** | Required + LED + resistors | $35-65 USD |
| **Full** | All components | $60-130 USD |
| **Per Additional Locker** | ESP32 + Relay + Solenoid only | $17-35 USD |

**💡 Tip:** Buy in bulk for multiple lockers to save money!

---

## 🎓 Additional Resources

**Documentation:**
- ESP32_SETUP_CHECKLIST.md - Complete setup guide
- ESP32_INTEGRATION_GUIDE.md - System architecture
- ESP32_UPDATE_SUMMARY.md - Recent changes
- LOCK_MECHANISM_EXPLAINED.md - How locks work

**Testing Tools:**
```bash
# Monitor all MQTT messages
mosquitto_sub -h test.mosquitto.org -t "smartlocker/#" -v

# Test unlock
curl -X PUT http://localhost:3000/api/locker/LOCKER_001/unlock

# Test lock  
curl -X PUT http://localhost:3000/api/locker/LOCKER_001/lock

# Backend test script
cd backend && node testMQTT.js
```

**Helpful Websites:**
- ESP32 Pinout Reference: https://randomnerdtutorials.com/esp32-pinout-reference-gpios/
- Arduino ESP32 Docs: https://docs.espressif.com/projects/arduino-esp32/
- MQTT Basics: https://mqtt.org/getting-started/

---

**Ready to build? Follow ESP32_SETUP_CHECKLIST.md for step-by-step instructions!**

**Last Updated:** November 7, 2025  
**Version:** 2.0 (Updated flow - unlock after QR scan, lock after verification)
