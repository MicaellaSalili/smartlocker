# SmartLocker Backend (Signup Only)

A minimal Node.js + Express + MongoDB backend to support the signup flow for the SmartLocker app.

## Quick start

1. Install dependencies (already installed if you followed the automated setup):

   - `npm install`

2. Copy env template and configure:

   - Copy `.env.example` to `.env` and adjust if needed (default local MongoDB works out of the box).

3. Start the server:

   - Dev: `npm run dev`
   - Prod: `npm start`

Server listens on `http://localhost:3000` by default.

Health check: `GET /health` should return `{ ok: true }`.

## API

- `POST /api/auth/signup`
  - Body JSON: `{ firstName, lastName, username, email, password }`
  - Responses:
    - 201 Created: returns the created user (without password)
    - 400 Bad Request: missing fields
    - 409 Conflict: email or username already in use

