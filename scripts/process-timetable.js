#!/usr/bin/env node

import { spawn } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function runCommand(command, args, cwd = process.cwd()) {
  return new Promise((resolve, reject) => {
    console.log(`🔄 Running: ${command} ${args.map(arg => `"${arg}"`).join(' ')}`);
    
    const proc = spawn(command, args, {
      cwd,
      stdio: 'inherit',
      shell: false
    });

    proc.on('close', (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`Command failed with exit code ${code}`));
      }
    });

    proc.on('error', (error) => {
      reject(error);
    });
  });
}

// Helper function to detect campus from filename
function detectCampusFromFilename(filename) {
  const name = filename.toLowerCase();
  if (name.includes('hyd') || name.includes('hyderabad')) {
    return { campus: 'hyderabad', displayName: 'Hyderabad' };
  } else if (name.includes('pil') || name.includes('pilani')) {
    return { campus: 'pilani', displayName: 'Pilani' };
  }
  return { campus: 'default', displayName: 'Default' };
}

// Helper function to find campus-specific timetable files
function findCampusTimetables(projectRoot) {
  const files = fs.readdirSync(projectRoot);
  const timetableFiles = [];
  
  // Look for campus-specific files first
  for (const file of files) {
    if (file.toLowerCase().includes('timetable') && file.toLowerCase().endsWith('.pdf')) {
      const campusInfo = detectCampusFromFilename(file);
      timetableFiles.push({
        path: path.join(projectRoot, file),
        filename: file,
        campus: campusInfo.campus,
        displayName: campusInfo.displayName
      });
    }
  }
  
  // If no campus-specific files found, look for generic timetable.pdf
  if (timetableFiles.length === 0) {
    const genericPath = path.join(projectRoot, 'timetable.pdf');
    if (fs.existsSync(genericPath)) {
      timetableFiles.push({
        path: genericPath,
        filename: 'timetable.pdf',
        campus: 'default',
        displayName: 'Default'
      });
    }
  }
  
  return timetableFiles;
}

async function processTimetableFile(timetableInfo, scriptsDir) {
  const { path: pdfPath, filename, campus, displayName } = timetableInfo;
  
  console.log(`\n📄 Processing ${filename} for ${displayName} campus`);
  
  // Determine converter and upload script based on campus
  let converterScript, uploadScript, csvFileName;
  
  if (campus === 'hyderabad' || campus === 'default') {
    converterScript = 'converter.py';
    uploadScript = 'upload-timetable.js';
    csvFileName = `output-${campus}.csv`;
  } else if (campus === 'pilani') {
    converterScript = 'pilani_conv.py';
    uploadScript = 'upload-timetable-pilani.js';
    csvFileName = 'pilani_courses.csv'; // Expected by the Pilani upload script
  } else {
    throw new Error(`Unknown campus: ${campus}`);
  }
  
  // Step 1: Convert PDF to CSV
  console.log(`\n=== Step 1: Converting ${filename} to CSV using ${converterScript} ===`);
  const csvPath = path.join(scriptsDir, csvFileName);
  
  await runCommand('python', [
    path.join(scriptsDir, converterScript),
    pdfPath,
    csvPath
  ]);
  
  if (!fs.existsSync(csvPath)) {
    throw new Error(`CSV file was not created for ${filename}`);
  }
  
  console.log(`✅ ${filename} converted to CSV successfully`);
  
  // Step 2: Upload CSV to Firestore
  console.log(`\n=== Step 2: Uploading ${displayName} data to Firestore using ${uploadScript} ===`);
  
  if (campus === 'pilani') {
    // Pilani upload script doesn't need extra parameters
    await runCommand('node', [
      path.join(scriptsDir, uploadScript)
    ], scriptsDir);
  } else {
    // Hyderabad upload script needs CSV path and campus parameter
    await runCommand('node', [
      path.join(scriptsDir, uploadScript),
      csvPath,
      campus
    ], scriptsDir);
  }
  
  console.log(`✅ ${displayName} campus data uploaded successfully`);
  
  // Clean up the CSV file
  if (fs.existsSync(csvPath)) {
    console.log(`🧹 Cleaning up temporary CSV file for ${displayName}...`);
    fs.unlinkSync(csvPath);
  }
}

async function main() {
  try {
    const projectRoot = path.join(__dirname, '..');
    const scriptsDir = __dirname;
    
    // Find all campus timetable files
    const timetableFiles = findCampusTimetables(projectRoot);
    
    if (timetableFiles.length === 0) {
      console.error('❌ No timetable PDF files found in the project root');
      console.log('Please place your timetable PDF files in the timetable_maker folder:');
      console.log('  - timetable-hyd.pdf (for Hyderabad campus)');
      console.log('  - timetable-pilani.pdf (for Pilani campus)');
      console.log('  - or timetable.pdf (for default/single campus)');
      process.exit(1);
    }
    
    console.log(`📋 Found ${timetableFiles.length} timetable file(s):`);
    timetableFiles.forEach(file => {
      console.log(`  - ${file.filename} → ${file.displayName} campus`);
    });
    
    // Process each timetable file
    for (const timetableInfo of timetableFiles) {
      await processTimetableFile(timetableInfo, scriptsDir);
    }
    
    console.log('\n🎉 All timetable processing completed successfully!');
    console.log(`📊 Data for ${timetableFiles.length} campus(es) has been uploaded to Firestore`);
    
  } catch (error) {
    console.error('❌ Error processing timetable:', error.message);
    process.exit(1);
  }
}

main().catch(console.error);