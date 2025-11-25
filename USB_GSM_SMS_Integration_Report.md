# USB GSM Modem SMS Integration Report for SmartLocker

## Overview
This report explains how to integrate SMS OTP sending using a USB GSM modem in your Node.js backend. This method supports all mobile networks in the Philippines and only requires a prepaid SIM with SMS load.

---

## 1. Why Use USB GSM Modem?
- Works with any PH network (Globe, Smart, Sun, TM, GOMO, DITO, etc.)
- No API provider restrictions or per-message fees (just SIM load)
- Good for unlimited, local, and offline SMS sending

---

## 2. Hardware & Software Requirements
- USB GSM modem (e.g., Huawei E220, ZTE MF190, etc.)
- Prepaid SIM card with SMS load
- Node.js installed
- [Gammu](https://wammu.eu/gammu/) or [node-gsm](https://www.npmjs.com/package/node-gsm) library

---

## 3. Setup Steps

### A. Install Gammu (Recommended)
1. Plug in your USB GSM modem and insert SIM.
2. Install Gammu:
   - On Windows: Download from https://wammu.eu/download/
   - On Linux: `sudo apt-get install gammu gammu-smsd`
3. Configure Gammu (see docs for modem port settings).

### B. Install Node.js Library
- For Gammu: Use [gammu-smsd](https://www.npmjs.com/package/gammu-smsd) or call Gammu CLI from Node.js.
- For node-gsm: `npm install node-gsm`

---

## 4. Sample Node.js Code (using Gammu CLI)

Create `backend/src/services/smsService.js`:
```js
const { exec } = require('child_process');

async function sendOTP(phone, otp) {
  const message = `Your SmartLocker OTP is: ${otp}. Valid for 5 minutes.`;
  // Gammu command to send SMS
  const cmd = `gammu-smsd-inject TEXT ${phone} -text "${message}"`;
  return new Promise((resolve, reject) => {
    exec(cmd, (error, stdout, stderr) => {
      if (error) {
        console.error('❌ SMS sending failed:', stderr);
        return reject(new Error('Failed to send SMS'));
      }
      console.log(`✅ SMS sent to ${phone}: ${stdout}`);
      resolve(stdout);
    });
  });
}

module.exports = { sendOTP };
```

---

## 5. Integration Flow
- Replace the Semaphore API code in `smsService.js` with the above.
- All other OTP logic (generation, expiry, verification) remains unchanged.
- Ensure your backend server has permission to run Gammu commands.

---

## 6. Testing
- Use your own phone number to test SMS sending.
- Check modem and SIM status if SMS fails.
- Monitor logs for errors.

---

## 7. Notes & Tips
- You can use any SIM/network; just keep SMS load topped up.
- For production, use a reliable modem and check for driver compatibility.
- Gammu can also receive SMS if you want two-way communication.
- For advanced use, explore [node-gsm](https://www.npmjs.com/package/node-gsm) for direct AT command control.

---

## 8. Summary
Using a USB GSM modem allows SmartLocker to send SMS OTPs to any network in the Philippines, with no API restrictions. Just update your `smsService.js` and keep your SIM loaded for reliable delivery.

---

## 9. LCD Screen Logic & Node.js Code Example

**Note:**
When the user enters a tracking code (waybill_id) on the LCD screen, the backend verifies it in the database. If found, it fetches the recipient's phone number (inputted by the courier), generates a 6-digit OTP, and sends it via SMS using the USB GSM modem. The OTP is valid for 5 minutes.

**Sample Node.js Endpoint:**
```js
// POST /api/claim/verify-tracking - LCD requests OTP for parcel claim
app.post('/api/claim/verify-tracking', async (req, res) => {
  try {
    const { waybill_id } = req.body;
    if (!waybill_id) {
      return res.status(400).json({ error: 'Waybill ID is required' });
    }
    // Find parcel by waybill_id
    const parcel = await Parcel.findOne({ waybill_id: waybill_id.trim() });
    if (!parcel) {
      return res.status(404).json({ error: 'Waybill ID not found' });
    }
    // Check if parcel is already claimed
    if (parcel.status === 'CLAIMED') {
      return res.status(400).json({ error: 'This parcel has already been claimed' });
    }
    // Generate 6-digit OTP
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    // Save OTP and expiry (5 minutes from now)
    parcel.otp = otp;
    parcel.otpExpires = new Date(Date.now() + 5 * 60 * 1000);
    await parcel.save();
    // Send OTP via SMS using USB GSM modem
    try {
      await smsService.sendOTP(parcel.recipient_phone, otp);
      res.json({
        message: 'Waybill ID verified. OTP sent to registered phone number.',
        transaction_id: parcel._id,
        waybill_id: parcel.waybill_id,
        recipient_name: `${parcel.recipient_first_name} ${parcel.recipient_last_name}`,
        phone_masked: parcel.recipient_phone.replace(/(\d{3})\d{4}(\d{4})/, '$1****$2'),
        otp_expires_in: '5 minutes'
      });
    } catch (smsError) {
      parcel.otp = null;
      parcel.otpExpires = null;
      await parcel.save();
      return res.status(500).json({ error: 'Failed to send OTP via SMS. Please try again.', details: smsError.message });
    }
  } catch (error) {
    res.status(500).json({ error: 'Failed to verify waybill ID', details: error.message });
  }
});
```
