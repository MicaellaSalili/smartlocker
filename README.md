# SmartLocker

Monorepo with a Flutter frontend and Node.js/Express + MongoDB backend for the Smart Locker system.

- Frontend: Flutter (Android, iOS, Web, Desktop)
- Backend: Node.js (Express), Mongoose (MongoDB)
- Auth: Email/Username + Password, phone number (E.164) stored and unique

## Repository structure

```
smartlocker/
├─ backend/               # Node.js API (Express + Mongoose)
│  ├─ src/
│  │  ├─ server.js        # App entry
│  │  ├─ models/User.js   # User schema
│  │  └─ routes/auth.js   # /api/auth/signup, /api/auth/login
│  ├─ package.json        # Scripts: start, dev
│  └─ .env.example        # Sample env
└─ frontend/              # Flutter app
   ├─ lib/
   │  ├─ services/api_config.dart  # Backend base URL per platform
   │  ├─ services/auth_service.dart
   │  ├─ screens/login_screen.dart
   │  └─ screens/signup/registration_screen.dart
   └─ pubspec.yaml
```

## Prerequisites

- Node.js 18+ and npm
- MongoDB (local or remote Atlas)
- Flutter SDK 3.22+ (Dart 3.x)
- Git

## 1) Backend setup

1. Copy environment file and configure:
   - From repo root:
     - Copy `backend/.env.example` to `backend/.env` and set:
       - `MONGODB_URI=mongodb://127.0.0.1:27017/smartlocker` (or your Atlas URI)
       - `PORT=3000`
2. Install and run the API:
   - `cd backend`
   - `npm install`
   - Run for development (auto-reload if nodemon available): `npm run dev`
   - Or run once: `npm start`
3. Verify health:
   - GET `http://localhost:3000/health` → `{ ok: true }`

### Auth endpoints

- Signup: `POST /api/auth/signup`
  - Body (JSON):
    ```json
    {
      "firstName": "Jane",
      "lastName": "Doe",
      "username": "janedoe",
      "email": "jane@example.com",
      "phone": "+639171234567",
      "password": "secret123"
    }
    ```
  - Validates phone with libphonenumber-js and stores normalized E.164; email, username, and phone are unique. Password is hashed (bcrypt).
  - Response: `{ id, firstName, lastName, username, email, phone, createdAt }`

- Login: `POST /api/auth/login`
  - Body (JSON): `{ "identifier": "janedoe" or "jane@example.com", "password": "secret123" }`
  - Response (200): user object; (401): error message.

## 2) Frontend setup

1. Install dependencies:
   - `cd frontend`
   - `flutter pub get`
2. Configure backend URL if needed (defaults are sensible):
   - `lib/services/api_config.dart` picks a base URL by platform:
     - Web: `http://localhost:3000`
     - Android emulator: `http://10.0.2.2:3000`
     - iOS simulator/desktop: `http://127.0.0.1:3000`
   - For physical devices or different machines, set your host machine IP and port.
3. Run the app:
   - `flutter run` (pick a device: Android emulator, iOS simulator, Chrome, Windows, etc.)

### App flow

- Registration: `registration_screen.dart`
  - Collects First/Last name, Email, Country code + Phone, Username, Password.
  - Sends signup to backend; on success shows a toast and redirects to Login.
- Login: `login_screen.dart`
  - Uses identifier (username or email) + password. On success redirects to Home. Invalid creds are rejected by API.

## Troubleshooting

- Backend cannot connect to MongoDB
  - Ensure MongoDB is running and `MONGODB_URI` is correct.
  - For Atlas, allow your IP and use the SRV/standard URI.
- CORS issues
  - `server.js` enables CORS (`app.use(cors())`). If you host frontend elsewhere, you may restrict/adjust origins.
- Android emulator cannot reach host `localhost`
  - Use `10.0.2.2` (already handled by `api_config.dart`). For Genymotion, use `10.0.3.2`.
- iOS simulator vs physical device
  - Simulator can use `127.0.0.1`. Physical device must point to your computer’s LAN IP.
- Unique phone constraint
  - Phone is validated to E.164 and must be unique. If you have legacy data, you may need to normalize or remove duplicates before enabling unique index.

## Scripts

- Backend
  - Dev: `npm run dev`
  - Start: `npm start`

## Contributing

- Create a feature branch from `main`.
- Open a PR with a clear description. Include screenshots for UI changes when helpful.
- Keep secrets out of the repo. Use `.env` locally and share only `.env.example`.

## License

MIT
