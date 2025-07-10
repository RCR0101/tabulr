# Tabulr

A Flutter desktop application for creating and managing academic timetables with automatic clash detection.

**Dark Theme** | **Timetable Generator** | **Excel Integration** | **Cross-Platform**

## Features

- **Excel Integration**: Import course data from XLSX files with 380+ courses
- **Modern Dark Theme**: Professional dark UI with clean design
- **Timetable Generator**: Generate multiple timetable options with constraints:
  - Avoid specific instructors or time slots
  - Set max hours per day
  - Prefer certain instructors
  - Multiple MidSem time slots (9:30-11AM, 11:30-1PM, 1:30-3PM, 3:30-5PM)
- **⚠Smart Clash Detection**: Automatically detects conflicts between:
  - Regular class timings
  - MidSem and EndSem exam schedules
  - Multiple MidSem time slots
- **Visual Timetable**: Clean grid view with gradient-filled time slots
- **Export Options**: 
  - ICS calendar files for calendar apps
  - PNG images with custom save locations
- **Advanced Search & Filtering**: Filter by course code, instructor, credits, days, exam dates
- **Exam Schedule View**: Separate tab showing all exam dates and times
- **Data Persistence**: Saves your timetable data locally

## Installation & Setup

### Prerequisites

1. **Install Flutter**: Download from [flutter.dev](https://docs.flutter.dev/get-started/install)
2. **Enable Desktop Support**: 
   ```bash
   flutter config --enable-windows-desktop
   flutter config --enable-macos-desktop
   flutter config --enable-linux-desktop
   ```

### For Windows Users

#### Option 1: Quick Setup (Recommended)
1. **Install Flutter** using the Windows installer from [flutter.dev](https://docs.flutter.dev/get-started/install/windows)
2. **Open Command Prompt or PowerShell** as Administrator
3. **Enable Windows desktop support**:
   ```cmd
   flutter config --enable-windows-desktop
   ```
4. **Navigate to the project directory**:
   ```cmd
   cd "path\to\timetable_maker"
   ```
5. **Install dependencies**:
   ```cmd
   flutter pub get
   ```
6. **Run the application**:
   ```cmd
   flutter run -d windows
   ```

#### Option 2: Development Setup
1. **Install Visual Studio 2022** with "Desktop development with C++" workload
2. **Install Git for Windows** from [git-scm.com](https://git-scm.com/download/win)
3. **Install Flutter SDK**:
   - Download Flutter SDK zip
   - Extract to `C:\flutter`
   - Add `C:\flutter\bin` to your PATH environment variable
4. **Verify installation**:
   ```cmd
   flutter doctor
   ```
5. **Clone/download this project** and follow steps 4-6 from Option 1

#### Windows-Specific Notes:
- **Antivirus**: Some antivirus software may slow down Flutter builds. Consider adding Flutter directories to exclusions
- **Firewall**: Windows Firewall may prompt when running the app - allow access for full functionality
- **File Permissions**: Run Command Prompt as Administrator if you encounter permission issues
- **Long Path Support**: Enable long path support in Windows 10/11 for better compatibility

### For macOS Users

```bash
cd timetable_maker
flutter run -d macos
```

### For Linux Users

```bash
cd timetable_maker
flutter run -d linux
```

## How to Use

### 1. Course Data

The app comes with **380+ courses** pre-loaded from an Excel file. You can:
- **Search & Filter**: Use the search bar to find courses by code, name, or instructor
- **Advanced Filters**: Filter by credits, days, exam dates, etc.
- **Course Selection**: Browse courses in a clean interface with selected courses at the top

### 2. Building Your Timetable

#### Manual Selection:
- **Browse Courses**: Use the "Courses" tab to see all available courses
- **Toggle Sections**: Use switches to add L (Lecture), T (Tutorial), P (Practical) sections
- **Smart Constraints**: App prevents selecting multiple sections of same type per course
- **Real-time Clash Detection**: Warnings appear for scheduling conflicts

#### TT Generator (Recommended):
1. **Click the "TT Generator" floating button**
2. **Select Required Courses**: Search and add courses you want to take
3. **Set Constraints**:
   - **Max Hours/Day**: Limit daily class hours
   - **Avoid Time Slots**: Block specific days and hours
   - **Avoid Instructors**: Exclude specific professors from your timetable
   - **Prefer Instructors**: Favor certain professors
   - **Avoid Back-to-Back**: Prevent consecutive classes
4. **Generate**: Get 20-30 optimized timetable options
5. **Select**: Choose your preferred timetable

### 3. Viewing Your Schedule

- **Timetable Grid**: Visual weekly schedule with gradient-filled time slots
- **Exam Schedule**: Separate tab showing MidSem and EndSem dates/times
- **Clear Display**: Course codes, sections, and room numbers clearly visible

### 4. Understanding Time Slots

**Regular Classes:**
- Hour 1: 8:00AM-8:50AM
- Hour 2: 9:00AM-9:50AM
- Hour 3: 10:00AM-10:50AM
- Hour 4: 11:00AM-11:50AM
- Hour 5: 12:00PM-12:50PM
- Hour 6: 1:00PM-1:50PM
- Hour 7: 2:00PM-2:50PM
- Hour 8: 3:00PM-3:50PM
- Hour 9: 4:00PM-4:50PM
- Hour 10: 5:00PM-5:50PM
- Hour 11: 6:00PM-6:50PM
- Hour 12: 7:00PM-7:50PM

**MidSem Exam Slots:**
- MS1: 9:30AM-11:00AM
- MS2: 11:30AM-1:00PM
- MS3: 1:30PM-3:00PM
- MS4: 3:30PM-5:00PM

**EndSem Exam Slots:**
- FN (Forenoon): 9:30AM-12:30PM
- AN (Afternoon): 2:00PM-5:00PM

### 5. Export Features

- **📅 ICS Calendar**: Export to Google Calendar, Outlook, Apple Calendar
- **🖼️ PNG Image**: Save timetable as image with custom location
- **🗂️ File Management**: Choose where to save your exports

### 6. Smart Clash Detection

The app automatically detects and prevents:
- **Regular Class Clashes**: Same time slot conflicts between courses
- **Exam Clashes**: MidSem/EndSem scheduling conflicts
- **Mixed Conflicts**: Classes and exams at conflicting times
- **Section Type Conflicts**: Multiple L/T/P sections of same course

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

### Common Issues

#### Windows-Specific:
- **"flutter: command not found"**:
  - Ensure Flutter is added to your PATH environment variable
  - Restart Command Prompt/PowerShell after installation
  - Try running `where flutter` to verify installation

- **Visual Studio Build Tools missing**:
  - Install Visual Studio 2022 with "Desktop development with C++" workload
  - Or install "Build Tools for Visual Studio 2022" (lighter option)

- **Slow builds**:
  - Add Flutter directories to antivirus exclusions
  - Close unnecessary programs during builds
  - Use SSD storage for better performance

- **Permission errors**:
  - Run Command Prompt as Administrator
  - Check Windows UAC settings
  - Ensure you have write permissions to the project directory

#### General Issues:
1. **Dependencies**: Run `flutter pub get` to install packages
2. **Doctor Check**: Run `flutter doctor` to diagnose setup issues
3. **Clean Build**: Try `flutter clean` then `flutter pub get`
4. **Storage Permissions**: Verify app can write to local storage
5. **Console Logs**: Check terminal/console for error messages

#### Platform-Specific Commands:
```bash
# Windows
flutter run -d windows
flutter build windows

# macOS  
flutter run -d macos
flutter build macos

# Linux
flutter run -d linux
flutter build linux
```

## Created by
- Aryan Dalmia
