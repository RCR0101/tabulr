# Timetable Data Uploader

This script parses XLSX timetable files and uploads the data to Firestore, making the app much faster by eliminating client-side parsing.

## Setup

1. **Install dependencies:**
   ```bash
   cd scripts
   npm install
   ```

2. **Create Firebase Service Account:**
   - Go to Firebase Console → Project Settings → Service Accounts
   - Click "Generate New Private Key"
   - Download the JSON file

3. **Configure environment variables:**
   ```bash
   cp .env.example .env
   ```
   
   Fill in the values from your service account JSON file:
   - `FIREBASE_PROJECT_ID`: Your Firebase project ID
   - `FIREBASE_PRIVATE_KEY`: The private key (with \n escaped)
   - `FIREBASE_CLIENT_EMAIL`: The service account email
   - Other fields from the service account JSON

## Usage

```bash
# Upload a timetable XLSX file
npm run upload path/to/your/timetable.xlsx

# Test the parser without uploading
npm run test path/to/your/timetable.xlsx
```

## What it does

1. **Parses XLSX**: Converts the Excel file to JSON using the same logic as the Flutter app
2. **Clears old data**: Removes existing course data from Firestore
3. **Uploads new data**: Stores all courses in the `courses` collection
4. **Updates metadata**: Tracks when the data was last updated

## Collections Created

- `courses`: One document per course with course code as document ID
- `timetable_metadata`: Metadata about the upload (last updated, total courses, etc.)

## Benefits

- **Faster app**: No more client-side XLSX parsing
- **Better UX**: Instant course data loading
- **Shared data**: All users see the same up-to-date information
- **Easy updates**: Just run the script when you have new timetable data