# Secure QR Code Implementation Guide

## Overview
This document describes the secure token-based QR code system implemented for the Smart Locker project.

## Security Features Implemented

### 1. **Fixed Locker IDs**
- Predefined locker IDs: `LOCKER_001`, `LOCKER_002`, `LOCKER_003`, `LOCKER_004`, `LOCKER_005`
- Cannot be guessed or generated arbitrarily
- Validated on backend before token generation

### 2. **Dynamic Time-Limited Tokens**
- Each transaction generates a unique random token (16-character hex)
- Tokens expire after 5 minutes
- Tokens are single-use only (cannot be reused)
- Format: `LOCKER_ID:TOKEN_xxx:EXP_timestamp`

### 3. **Token Validation**
- Validates locker ID matches the selected locker
- Checks token hasn't expired
- Verifies token hasn't been used before
- Backend validates all security checks before unlocking

## New App Flow

### Previous Flow (Insecure):
1. Scan QR Code
2. Input Details
3. Scan Package
4. Live Detection

### New Secure Flow:
1. **Input Recipient Details** - Enter name and phone number
2. **Auto-Assign Locker** - System automatically assigns next available locker
3. **Scan QR Code** - Scan the secure QR code with token validation
4. **Scan Package** - Capture package barcode and details
5. **Live Detection** - Verify package placement

## QR Code Format

### Structure:
```
LOCKER_ID:TOKEN_xxx:EXP_timestamp
```

### Example:
```
LOCKER_001:TOKEN_a7f3d9e2b8c4:EXP_1731234567890
```

### Components:
- **LOCKER_ID**: Fixed locker identifier (e.g., `LOCKER_001`)
- **TOKEN_xxx**: Random 16-character hex token
- **EXP_timestamp**: Unix timestamp in milliseconds when token expires

## Backend API Endpoints

### 1. Get Available Locker (AUTO-ASSIGN)
**GET** `/api/locker/available`

**Response (Success):**
```json
{
  "message": "Available locker assigned successfully",
  "locker_id": "LOCKER_001",
  "token": "a7f3d9e2b8c4",
  "expires_at": "2025-11-10T10:30:00.000Z",
  "expires_in_seconds": 300,
  "qr_content": "LOCKER_001:TOKEN_a7f3d9e2b8c4:EXP_1731234567890",
  "available_count": 4,
  "total_lockers": 5
}
```

**Response (No Available Lockers):**
```json
{
  "error": "No available lockers",
  "message": "All lockers are currently occupied. Please try again later.",
  "total_lockers": 5,
  "occupied_lockers": 5
}
```

### 2. Generate Token (Manual - Not Used in Current Flow)
**POST** `/api/locker/generate-token`

**Request:**
```json
{
  "lockerId": "LOCKER_001"
}
```

**Response:**
```json
{
  "message": "Access token generated successfully",
  "locker_id": "LOCKER_001",
  "token": "a7f3d9e2b8c4",
  "expires_at": "2025-11-10T10:30:00.000Z",
  "expires_in_seconds": 300,
  "qr_content": "LOCKER_001:TOKEN_a7f3d9e2b8c4:EXP_1731234567890"
}
```

### 3. Unlock with Token
**PUT** `/api/locker/:lockerId/unlock`

**Request:**
```json
{
  "token": "a7f3d9e2b8c4"
}
```

**Response (Success):**
```json
{
  "message": "Unlock command sent successfully",
  "locker_id": "LOCKER_001",
  "status": "UNLOCKED",
  "timestamp": "2025-11-10T10:25:00.000Z"
}
```

**Response (Error - Invalid Token):**
```json
{
  "error": "Invalid or expired token"
}
```

**Response (Error - Token Mismatch):**
```json
{
  "error": "Token does not match locker ID"
}
```

**Response (Error - Already Used):**
```json
{
  "error": "Token has already been used"
}
```

## Flutter Screens

### 1. Input Details Screen (UPDATED)
- **Path**: `lib/screens/input_details_screen.dart`
- **Purpose**: Collect recipient information and auto-assign locker
- **Features**:
  - Collect first name, last name, phone number
  - Automatically call backend to get available locker
  - Show assigned locker in dialog
  - Display available locker count
- **Next**: Scan QR Code Screen

### 2. Scan QR Code Screen (UPDATED)
- **Path**: `lib/screens/scan_qr_code_screen.dart`
- **Purpose**: Scan and validate QR code with token
- **Features**:
  - Parse QR code format
  - Validate token matches expected
  - Check expiration
  - Send unlock command with token
  - Show success/error feedback
- **Next**: Scan Package Screen

### 3. Scan Package Screen
- **Path**: `lib/screens/scan_screen.dart`
- **Purpose**: Capture package details
- **Next**: Live Detection Screen

### 4. Live Detection Screen
- **Path**: `lib/screens/live_screen.dart`
- **Purpose**: Verify package placement
- **Next**: Success/Home

## Security Benefits

### Before (Insecure):
❌ Predictable locker IDs  
❌ No authentication  
❌ QR codes can be reused  
❌ No expiration  
❌ Anyone can unlock any locker  

### After (Secure):
✅ Fixed locker IDs  
✅ Token-based authentication  
✅ Single-use tokens  
✅ Time-limited access (5 minutes)  
✅ Backend validation required  
✅ Token tied to specific locker  
✅ Protection against replay attacks  

## Testing the Implementation

### 1. Start Backend Server
```bash
cd backend
npm start
```

### 2. Run Flutter App
```bash
cd frontend
flutter run
```

### 3. Test Flow
1. Click the scan FAB button on home screen
2. Enter recipient details (name, phone)
3. System automatically assigns next available locker (e.g., LOCKER_001)
4. Dialog shows assigned locker and available count
5. Proceed to scan QR code
6. Scan the QR code displayed on the locker LCD screen
7. System validates token and unlocks locker
8. Continue with package scanning and placement

### 4. Test Security Features

**Test Expired Token:**
- Wait 5 minutes after token generation
- Try to scan QR code
- Should show "QR code has expired" error

**Test Wrong Locker:**
- Select LOCKER_001
- Scan QR for LOCKER_002
- Should show "Locker ID mismatch" error

**Test Reused Token:**
- Scan QR code successfully
- Try to scan same QR code again
- Should show "Token has already been used" error

## Production Considerations

### Current Implementation (Development):
- Tokens stored in memory (`global.lockerTokens`)
- Tokens lost on server restart

### Production Recommendations:
1. **Use Redis** for token storage
2. **Use Database** for token audit trail
3. **Add Rate Limiting** to prevent brute force
4. **Add HTTPS** for encrypted communication
5. **Add JWT** for user authentication
6. **Implement Token Cleanup** job to remove expired tokens
7. **Add Logging** for all token operations

## Future Enhancements

1. **Push Notifications**: Notify user when locker is unlocked
2. **Biometric Verification**: Add fingerprint/face recognition
3. **Multi-Factor Auth**: Require PIN + QR code
4. **Real-time Locker Status**: Show which lockers are available
5. **Booking System**: Reserve lockers in advance
6. **Admin Dashboard**: Monitor all transactions and tokens

## Troubleshooting

### Token Generation Fails
- Check backend is running
- Verify locker ID is valid (LOCKER_001-005)
- Check network connection

### QR Scan Fails
- Ensure camera permissions granted
- Check QR code is not expired
- Verify correct format: `LOCKER_ID:TOKEN_xxx:EXP_timestamp`

### Unlock Fails
- Verify token is valid and not expired
- Check MQTT connection to ESP32
- Ensure backend can communicate with hardware

## Contact
For questions or issues, please contact the development team.
