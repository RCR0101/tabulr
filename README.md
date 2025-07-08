# Timetable Maker

A Flutter desktop application for creating and managing academic timetables with automatic clash detection.

## Features

- **Course Management**: Add courses with sections, instructors, rooms, and schedules
- **Clash Detection**: Automatically detects conflicts between:
  - Regular class timings
  - MidSem and EndSem exam schedules
  - Mixed class and exam conflicts
- **Visual Timetable**: Clean grid view of your weekly schedule
- **Warning System**: Clear alerts for scheduling conflicts
- **Data Persistence**: Saves your timetable data locally

## How to Use

### 1. Running the Application

```bash
cd timetable_maker
flutter run -d macos
```

### 2. Adding Courses

1. Click the "+" button in the top-right corner
2. Fill in course details:
   - **Course Code**: e.g., CS101
   - **Course Title**: e.g., Introduction to Computer Science
   - **Credits**: Lecture (L), Practical (P), and Total (U) credits
3. Add sections for each course:
   - **Section ID**: e.g., L1, P1, T1 (Lecture/Practical/Tutorial + number)
   - **Type**: L (Lecture), P (Practical), T (Tutorial)
   - **Instructor**: Professor's name
   - **Room**: Classroom/Lab location
   - **Days**: Select days of the week (M,T,W,Th,F,S)
   - **Hours**: Enter comma-separated hour slots (e.g., 1,2,3)

### 3. Building Your Timetable

- Toggle sections on/off using the switches in the course list
- The app will prevent you from adding conflicting sections
- View your complete timetable in the grid on the right

### 4. Understanding Time Slots

**Regular Classes:**
- Hour 1: 8:00AM-8:50AM
- Hour 2: 9:00AM-9:50AM
- Hour 3: 10:00AM-10:50AM
- ... and so on

**Exam Slots:**
- FN (Forenoon): 9:30AM-12:30PM
- AN (Afternoon): 2:00PM-5:00PM

### 5. Clash Detection

The app automatically detects and warns about:
- **Regular Class Clashes**: Same time slot conflicts
- **Exam Clashes**: MidSem/EndSem scheduling conflicts
- **Mixed Conflicts**: Classes and exams at conflicting times

## Data Format

The app expects course data in the format described:
- **Course Code**: Unique identifier (e.g., CS101)
- **Sections**: L/P/T + number format
- **Days**: M,T,W,Th,F,S (Monday through Saturday)
- **Hours**: 1-10 representing hourly slots
- **Exams**: DD/MM format with FN/AN time slots

## Technical Details

- Built with Flutter for cross-platform desktop support
- Uses local storage for data persistence
- Implements real-time clash detection algorithms
- Clean, intuitive Material Design UI

## Sample Data

The app includes sample course data to help you get started. You can modify or delete this data and add your own courses.

## Troubleshooting

If you encounter issues:
1. Ensure Flutter is properly installed
2. Check that all dependencies are installed with `flutter pub get`
3. Verify the app has permission to write to local storage
4. Check the console for any error messages

## Future Enhancements

- CSV import functionality for bulk course data
- PDF export of timetables
- Integration with calendar applications
- Advanced scheduling algorithms
- Multi-semester support