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

async function main() {
  try {
    const projectRoot = path.join(__dirname, '..');
    const scriptsDir = __dirname;
    
    // Look for timetable.pdf in the project root
    const pdfPath = path.join(projectRoot, 'timetable.pdf');
    
    if (!fs.existsSync(pdfPath)) {
      console.error('❌ timetable.pdf not found in the project root');
      console.log('Please place your timetable PDF file as "timetable.pdf" in the timetable_maker folder');
      process.exit(1);
    }
    
    console.log('📄 Found timetable.pdf');
    
    // Step 1: Convert PDF to CSV
    console.log('\n=== Step 1: Converting PDF to CSV ===');
    const csvPath = path.join(scriptsDir, 'output.csv');
    
    await runCommand('python', [
      path.join(scriptsDir, 'converter.py'),
      pdfPath,
      csvPath
    ]);
    
    if (!fs.existsSync(csvPath)) {
      throw new Error('CSV file was not created');
    }
    
    console.log('✅ PDF converted to CSV successfully');
    
    // Step 2: Upload CSV to Firestore
    console.log('\n=== Step 2: Uploading to Firestore ===');
    
    await runCommand('node', [
      path.join(scriptsDir, 'upload-timetable.js'),
      csvPath
    ], scriptsDir);
    
    console.log('\n🎉 Timetable processing completed successfully!');
    console.log('📊 Your timetable data has been uploaded to Firestore');
    
    // Optional: Clean up the CSV file
    if (fs.existsSync(csvPath)) {
      console.log('🧹 Cleaning up temporary CSV file...');
      fs.unlinkSync(csvPath);
    }
    
  } catch (error) {
    console.error('❌ Error processing timetable:', error.message);
    process.exit(1);
  }
}

main().catch(console.error);