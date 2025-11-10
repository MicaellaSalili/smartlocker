# Locker Database System

## Overview
The locker system now uses a MongoDB collection to track each locker's status, current token, and occupancy.

## Database Schema

### Locker Model
```javascript
{
  locker_id: String,              // e.g., "LOCKER_001"
  status: String,                  // "AVAILABLE", "OCCUPIED", "MAINTENANCE"
  current_token: String,           // Active token (null if none)
  token_expires_at: Date,          // Token expiration timestamp
  occupied_by_parcel: ObjectId,    // Reference to Parcel
  last_opened_at: Date,            // Last unlock timestamp
  created_at: Date,
  updated_at: Date
}
```

## Setup Instructions

### 1. Initialize Lockers in Database
Run this command **once** to create the 5 lockers in MongoDB:
```bash
cd backend
npm run init-lockers
```

This will create:
- LOCKER_001
- LOCKER_002
- LOCKER_003
- LOCKER_004
- LOCKER_005

All will start with status "AVAILABLE".

### 2. Start the Backend
```bash
npm start
```

## API Endpoints

### Get All Lockers
```
GET /api/lockers
```
Returns all lockers with their current status, token info, and statistics.

**Response:**
```json
{
  "lockers": [
    {
      "locker_id": "LOCKER_001",
      "status": "AVAILABLE",
      "current_token": "a7f3d9e2b8c4",
      "token_expires_at": "2025-11-10T12:00:00.000Z",
      "occupied_by_parcel": null,
      "last_opened_at": null
    }
  ],
  "total": 5,
  "available": 4,
  "occupied": 1,
  "maintenance": 0
}
```

### Get Specific Locker
```
GET /api/lockers/:lockerId
```

**Example:**
```
GET /api/lockers/LOCKER_001
```

### Update Locker Status
```
PUT /api/lockers/:lockerId/status
Body: { "status": "AVAILABLE" | "OCCUPIED" | "MAINTENANCE" }
```

**Example:**
```bash
curl -X PUT http://localhost:3000/api/lockers/LOCKER_001/status \
  -H "Content-Type: application/json" \
  -d '{"status": "AVAILABLE"}'
```

### Get Available Locker (Auto-assign)
```
GET /api/locker/available
```
Automatically finds the first available locker, generates a token, and broadcasts QR to LCD.

### Unlock Locker (with token validation)
```
PUT /api/locker/:lockerId/unlock
Body: { "token": "hex_string" }
```

## Workflow

1. **Courier enters details** → App calls `GET /api/locker/available`
2. **Backend**:
   - Finds first AVAILABLE locker
   - Generates token (5 min expiry)
   - Saves token to locker in DB
   - Broadcasts QR to LCD via SSE
3. **LCD displays QR code** automatically
4. **Courier scans QR** → App calls `PUT /api/locker/:lockerId/unlock` with token
5. **Backend**:
   - Validates token from DB
   - Changes locker status to OCCUPIED
   - Sends unlock command via MQTT
   - Clears token

## Monitoring Lockers

You can monitor locker status in real-time using MongoDB Compass:
- Collection: `lockers`
- Watch for changes in `status`, `current_token`, `token_expires_at`

Or use the API:
```bash
# Get all lockers
curl http://localhost:3000/api/lockers

# Get specific locker
curl http://localhost:3000/api/lockers/LOCKER_001
```

## Notes

- Although you have only 1 physical locker unit, the database tracks 5 lockers for scalability
- Tokens automatically expire after 5 minutes
- Expired tokens are cleared when querying lockers
- When a locker is unlocked, it automatically changes to OCCUPIED status
- To reset a locker to AVAILABLE, use the status update endpoint
