# Environment Setup Guide

This guide will help you set up the environment variables needed for the Tabulr app.

## Quick Setup

1. **Copy the environment template:**
   ```bash
   cp .env.example .env
   ```

2. **Edit the `.env` file with your Firebase configuration values**

## Firebase Console Configuration

### 1. Create a Firebase Project
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Create a project" or select an existing project
3. Follow the setup wizard

### 2. Enable Authentication
1. In your Firebase project, go to **Authentication** > **Sign-in method**
2. Enable **Google** sign-in provider
3. Add your domain to authorized domains (for web deployment)

### 3. Get Firebase Configuration
1. Go to **Project Settings** > **General**
2. In "Your apps" section, click the web icon `</>`
3. Register your app with a nickname
4. Copy the configuration values to your `.env` file

### 4. Get Google Web Client ID
1. In Firebase Console, go to **Authentication** > **Sign-in method**
2. Click on **Google** provider
3. Copy the **Web client ID** from the Web SDK configuration
4. Add it to your `.env` file as `GOOGLE_WEB_CLIENT_ID`

### 5. Enable Firestore
1. Go to **Firestore Database**
2. Click "Create database"
3. Choose "Start in test mode" for development
4. Select a location for your database

## Environment Variables

### Required Variables
```env
# Google Sign-In Web Client ID (from Firebase Console)
GOOGLE_WEB_CLIENT_ID=your-client-id.apps.googleusercontent.com

# Firebase Project Configuration (from Firebase Config)
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_API_KEY=your-api-key
FIREBASE_AUTH_DOMAIN=your-project-id.firebaseapp.com
FIREBASE_STORAGE_BUCKET=your-project-id.appspot.com
FIREBASE_MESSAGING_SENDER_ID=123456789012
FIREBASE_APP_ID=1:123456789012:web:abcdef1234567890
```

### Optional Variables
```env
# Firestore Collection Names (default: user_timetables)
FIRESTORE_TIMETABLES_COLLECTION=user_timetables

# App Configuration
APP_NAME=Tabulr
APP_VERSION=1.0.0

# Debug Settings
DEBUG_MODE=false
ENABLE_ANALYTICS=true
```

## Security Notes

- **Never commit your `.env` file to version control**
- The `.env` file is already added to `.gitignore`
- Use different Firebase projects for development, staging, and production
- Regularly rotate your API keys and client secrets

## Troubleshooting

### Missing Configuration Error
If you see an error about missing configuration:
1. Check that your `.env` file exists
2. Verify all required variables are set
3. Ensure values don't have quotes or extra spaces
4. Restart your app after making changes

### Google Sign-In Issues
1. Verify the `GOOGLE_WEB_CLIENT_ID` is correct
2. Check that your domain is authorized in Firebase Console
3. For localhost development, ensure `localhost` is in authorized domains

### Firestore Permission Issues
1. Check Firestore security rules
2. Verify user authentication is working
3. Ensure the collection name matches your configuration

## Deployment

For production deployment:
1. Create a production Firebase project
2. Set up environment variables in your deployment platform
3. Update Firestore security rules for production
4. Enable Firebase hosting or your preferred hosting solution

## Support

If you need help with configuration:
1. Check the Firebase documentation
2. Verify your Firebase project settings
3. Test with a minimal configuration first