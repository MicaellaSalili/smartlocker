# ESP32 & Raspberry Pi Integration Guide (Node.js Backend)

This document explains how to connect your ESP32-based smart locker to a Raspberry Pi running a Node.js backend using MQTT. It includes setup, configuration, and testing instructions.

---

## 1. Overview
- **ESP32**: Controls the lock, connects to WiFi, communicates via MQTT.
- **Raspberry Pi**: Runs Node.js backend, acts as MQTT broker, sends commands to ESP32.
- **MQTT**: Lightweight messaging protocol for IoT devices.

---

## 2. Prerequisites
- Raspberry Pi (with Raspbian OS)
- ESP32 development board
- WiFi network
- Node.js installed on Raspberry Pi
- Mosquitto MQTT broker installed on Raspberry Pi

---

## 3. Step-by-Step Setup

### Step 1: Set Up MQTT Broker on Raspberry Pi
1. Open terminal on Raspberry Pi.
2. Install Mosquitto:
   ```sh
   sudo apt-get update
   sudo apt-get install mosquitto mosquitto-clients
   sudo systemctl start mosquitto
   ```
3. Confirm broker is running:
   ```sh
   sudo systemctl status mosquitto
   ```

### Step 2: Configure ESP32
1. In your ESP32 code (`ESP32_SmartLocker_Code.ino`):
   - Set WiFi credentials:
     ```cpp
     const char* ssid = "YOUR_WIFI_SSID";
     const char* password = "YOUR_WIFI_PASSWORD";
     ```
   - Set MQTT broker IP (Raspberry Pi’s LAN IP):
     ```cpp
     const char* mqtt_server = "<raspi-ip>";
     const int mqtt_port = 1883;
     ```
   - Subscribe to topics:
     - `smartlocker/locker/{LOCKER_ID}/unlock`
     - `smartlocker/locker/{LOCKER_ID}/lock`
   - Publish status to:
     - `smartlocker/locker/{LOCKER_ID}/status`

### Step 3: Configure Node.js Backend
1. In your backend (`backend/src/services/mqttService.js`):
   - Set broker URL to Raspberry Pi’s IP:
     ```js
     this.brokerUrl = 'mqtt://<raspi-ip>:1883';
     ```
   - Update `.env` if used:
     ```
     MQTT_BROKER_URL=mqtt://<raspi-ip>:1883
     ```
2. Ensure backend sends commands to correct topics and listens for status updates.

### Step 4: Connect Devices to Same Network
- Ensure both ESP32 and Raspberry Pi are connected to the same WiFi network.
- Find Raspberry Pi’s IP with:
  ```sh
  hostname -I
  ```

---

## 4. Testing the Integration

### Test 1: MQTT Broker
- On Raspberry Pi, open two terminals:
  1. Subscribe to a topic:
     ```sh
     mosquitto_sub -h localhost -t "smartlocker/locker/1/unlock"
     ```
  2. Publish a message:
     ```sh
     mosquitto_pub -h localhost -t "smartlocker/locker/1/unlock" -m "unlock"
     ```
- You should see the message in the subscriber terminal.

### Test 2: ESP32 Connection
- Power on ESP32 and check serial monitor for successful WiFi and MQTT connection.
- Publish a test message from Raspberry Pi:
  ```sh
  mosquitto_pub -h <raspi-ip> -t "smartlocker/locker/1/unlock" -m "unlock"
  ```
- ESP32 should receive the message and unlock the locker.

### Test 3: Node.js Backend
- Start your backend server:
  ```sh
  cd backend
  npm install
  node src/server.js
  ```
- Use backend API or UI to send unlock/lock commands.
- ESP32 should respond and update status.

---

## 5. Troubleshooting
- **ESP32 not connecting**: Check WiFi credentials and broker IP.
- **No MQTT messages**: Ensure broker is running and topics match.
- **Node.js errors**: Check broker URL and dependencies.
- **Network issues**: Confirm both devices are on the same LAN.

---

## 6. References
- [`ESP32_SmartLocker_Code.ino`](../ESP32_SmartLocker_Code.ino)
- [`backend/src/services/mqttService.js`](../backend/src/services/mqttService.js)
- [ESP32_COMPLETE_GUIDE.md](../ESP32_COMPLETE_GUIDE.md)

---

## 7. Summary
This guide covers setting up MQTT communication between ESP32 and Raspberry Pi, configuring both devices, and testing the integration using Node.js backend. For further customization, refer to the provided code files and documentation.
