# SMS OTP Integration Report for SmartLocker

## Overview
This report documents the integration of Semaphore SMS OTP for parcel claiming in the SmartLocker system. It covers the implementation steps, database changes, API flow, and testing results.

---

## 1. Provider Selection
- **Semaphore** was chosen for SMS delivery due to its support for all PH networks and developer-friendly API.
- Free credits were used for initial testing.

---

## 2. Implementation Steps

### Backend
- Installed `axios` for HTTP requests.
- Created `smsService.js` to send OTP via Semaphore API.
- Updated `Parcel` model to include `otp` and `otpExpires` fields.
- Modified parcel claim flow:
  - Generate OTP when claim is requested.
  - Save OTP and expiry in database.
  - Send OTP to recipient's phone via SMS.
  - Verify OTP on user input before allowing claim.

### Frontend
- Added OTP input screen for parcel claiming.
- Updated API calls to request and verify OTP.

---

## 3. Database Changes
- `Parcel` model now includes:
  - `otp: String`
  - `otpExpires: Date`

---

## 4. API Flow
- **Request OTP:**
  - User initiates claim.
  - Backend generates and sends OTP.
- **Verify OTP:**
  - User enters OTP.
  - Backend checks OTP and expiry.
  - If valid, parcel is released.

---

## 5. Testing Results
- SMS successfully sent to PH mobile numbers using Semaphore free credits.
- OTP received within seconds.
- OTP verification logic works as expected (valid/expired/invalid cases tested).
- No major errors encountered; handled edge cases for phone validation and expiry.

---

## 6. Recommendations
- Monitor SMS delivery rates and failures in Semaphore dashboard.
- Use environment variables for API keys.
- Implement rate limiting and retry logic for production.
- Clean up expired OTPs regularly.

---

## 7. References
- [Semaphore API Documentation](https://semaphore.co/docs/)
- `backend/src/services/smsService.js`
- `backend/src/models/Parcel.js`
- `backend/controllers/parcelController.js`

---

## 8. Summary
Semaphore SMS OTP integration enables secure parcel claiming for SmartLocker users. The system is tested and ready for production, pending sufficient SMS credits.

---

## 9. Sample Integration Code


### Updated Backend Logic: Automatic OTP via waybill_id

**Explanation:**
When the user enters a tracking number (waybill_id) on the LCD screen, the backend verifies it against the database. If found, it fetches the recipient's phone number and sends a 6-digit OTP via SMS using Semaphore. The OTP is valid for 5 minutes and stored in the database. No separate request for OTP is needed.

**Sample Endpoint Implementation:**

```js
// POST /api/claim/verify-tracking - Verify waybill_id and send OTP automatically
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

    // Send OTP via SMS to recipient_phone
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

**How it works:**
- User enters waybill_id (tracking number)
- System verifies and fetches recipient_phone
- Sends OTP via SMS (valid for 5 minutes)
- OTP is stored in database for verification

---

## 10. Node.js File Connections & Explanation

**Explanation:**
The SMS OTP integration is implemented across several Node.js files in the backend:

- `src/server.js`: Defines the main API endpoint `/api/claim/verify-tracking` that receives the waybill_id, verifies it, and triggers the OTP sending logic.
- `src/models/Parcel.js`: Parcel schema includes `waybill_id` (tracking number), `recipient_phone`, and new fields `otp` and `otpExpires` for OTP management.
- `src/services/smsService.js`: Contains the `sendOTP` function that connects to Semaphore API and sends the SMS to the recipient's phone number.
- `.env`: Stores the Semaphore API key and sender name for secure access.

**Connection Flow:**
1. The LCD or frontend sends a POST request with `waybill_id` to `/api/claim/verify-tracking`.
2. `server.js` looks up the parcel in MongoDB using `waybill_id`.
3. If found and not claimed, it generates an OTP, saves it in the parcel document, and calls `smsService.sendOTP()`.
4. `smsService.js` uses the Semaphore API to send the OTP SMS to the `recipient_phone`.
5. The OTP and expiry are stored in MongoDB for later verification.
6. The frontend or LCD can then prompt the user for the OTP and verify it using the `/api/transaction/:id/verify-otp` endpoint.

This modular approach keeps the code maintainable and secure, with clear separation of concerns between database, business logic, and external API integration.
