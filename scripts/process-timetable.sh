#!/bin/bash

# Script to convert PDF timetable to CSV and upload to Firestore
# Usage: ./process-timetable.sh [pdf-file-path]

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}🚀 Starting timetable processing pipeline...${NC}"

# Check if PDF file is provided
if [ "$#" -eq 0 ]; then
    # Look for timetable.pdf in project root
    PDF_FILE="$PROJECT_ROOT/timetable.pdf"
    if [ ! -f "$PDF_FILE" ]; then
        echo -e "${RED}❌ Error: No PDF file provided and timetable.pdf not found in project root${NC}"
        echo -e "${YELLOW}Usage: $0 [pdf-file-path]${NC}"
        echo -e "${YELLOW}Or place your PDF file as 'timetable.pdf' in the timetable_maker folder${NC}"
        exit 1
    fi
    echo -e "${GREEN}📄 Found timetable.pdf in project root${NC}"
else
    PDF_FILE="$1"
    if [ ! -f "$PDF_FILE" ]; then
        echo -e "${RED}❌ Error: PDF file not found: $PDF_FILE${NC}"
        exit 1
    fi
fi

# Set output CSV path
CSV_FILE="$PROJECT_ROOT/scripts/output.csv"

echo -e "${BLUE}📋 Step 1: Converting PDF to CSV...${NC}"
echo -e "   Input:  $PDF_FILE"
echo -e "   Output: $CSV_FILE"

# Change to scripts directory to run Python script
cd "$SCRIPT_DIR"

# Run the Python converter
if command -v python3 &> /dev/null; then
    python3 converter.py "$PDF_FILE" "$CSV_FILE"
elif command -v python &> /dev/null; then
    python converter.py "$PDF_FILE" "$CSV_FILE"
else
    echo -e "${RED}❌ Error: Python not found. Please install Python 3.${NC}"
    exit 1
fi

# Check if CSV was created successfully
if [ ! -f "$CSV_FILE" ]; then
    echo -e "${RED}❌ Error: CSV conversion failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ PDF to CSV conversion completed${NC}"

echo -e "${BLUE}📤 Step 2: Uploading to Firestore...${NC}"

# Run the Node.js upload script
if command -v node &> /dev/null; then
    node upload-timetable.js "$CSV_FILE"
else
    echo -e "${RED}❌ Error: Node.js not found. Please install Node.js.${NC}"
    exit 1
fi

echo -e "${GREEN}🎉 Pipeline completed successfully!${NC}"
echo -e "${BLUE}📊 Timetable data has been processed and uploaded to Firestore${NC}"