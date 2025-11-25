const axios = require('axios');

/**
 * Send OTP via Semaphore SMS API
 * @param {string} phone - Recipient phone number (E.164 format recommended)
 * @param {string} otp - OTP code to send
 * @returns {Promise} - Semaphore API response
 */
async function sendOTP(phone, otp) {
  const apiKey = process.env.SEMAPHORE_API_KEY;
  const senderName = process.env.SEMAPHORE_SENDER_NAME || 'SmartLocker';
  const message = `Your SmartLocker OTP is: ${otp}. Valid for 5 minutes.`;

  if (!apiKey) {
    throw new Error('SEMAPHORE_API_KEY is not configured');
  }

  const url = 'https://api.semaphore.co/api/v4/messages';
  const payload = {
    apikey: apiKey,
    number: phone,
    message: message,
    sendername: senderName
  };

  try {
    const res = await axios.post(url, payload);
    console.log(`✅ SMS sent to ${phone}: ${res.data.message || 'Success'}`);
    return res.data;
  } catch (error) {
    console.error('❌ SMS sending failed:', error.response?.data || error.message);
    throw new Error('Failed to send SMS');
  }
}

module.exports = { sendOTP };
