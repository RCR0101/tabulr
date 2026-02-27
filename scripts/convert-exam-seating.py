import pdfplumber
import pandas as pd
import sys
import os


def remove_headers(
    table: list[list[str]], remove_rows_containing_any_of: list[str]
) -> list[list[str]]:
    """
    Remove rows that contain any of the specified header strings.
    """
    new_table: list[list[str]] = []
    for row in table:
        if row is None:
            continue
        transfer: bool = True
        for string in remove_rows_containing_any_of:
            if string in row:
                transfer = False
                break
        if transfer:
            new_table.append(row)
    return new_table


def convert_exam_seating_to_csv(
    pages: list[pdfplumber.page.Page], headers: list[str]
) -> pd.DataFrame:
    """
    Convert exam seating PDF pages to a pandas dataframe.
    """
    df = pd.DataFrame()
    for page in pages:
        table = page.extract_table()
        if table:
            table = remove_headers(table, headers)
            df = pd.concat([df, pd.DataFrame(table)], ignore_index=True)
    return df


if __name__ == "__main__":
    # Get command line arguments
    if len(sys.argv) < 2:
        print("Usage: python convert-exam-seating.py <input_pdf_path> [output_csv_path]")
        print("Example: python convert-exam-seating.py ../ExamSA.pdf exam_seating.csv")
        sys.exit(1)

    input_pdf = sys.argv[1]
    output_csv = sys.argv[2] if len(sys.argv) > 2 else "exam_seating.csv"

    # Check if input file exists
    if not os.path.exists(input_pdf):
        print(f"Error: Input PDF file not found: {input_pdf}")
        sys.exit(1)

    print(f"Converting {input_pdf} to {output_csv}")

    # Headers to remove from the table (common header row values)
    headers: list[str] = [
        "Course Code",
        "Course Title",
        "Date of exam",
        "Room No",
        "ID From - To",
        "No. of stu.",
        "S.No",
        "SEATING ARRANGEMENT",
        "Seating Arrangement",
        "SEATING ARRANGEMENT FOR THE I SEMESTER 2025 -26",
        "COMPREHENSIVE EXAMINATION",
        "MIDSEMESTER EXAMINATION"
    ]

    try:
        pdf: pdfplumber.pdf.PDF = pdfplumber.open(input_pdf)

        # Process all pages
        total_pages = len(pdf.pages)
        print(f"Processing {total_pages} pages...")

        pages: list[pdfplumber.page.Page] = pdf.pages

        data: pd.DataFrame = convert_exam_seating_to_csv(pages, headers)

        # Set column names based on expected format
        # Course Code | Course Title | Date of exam | Room No | ID From - To | No. of stu.
        if len(data.columns) >= 6:
            data.columns = ["course_code", "course_title", "exam_date", "room_no", "id_range", "student_count"] + list(data.columns[6:])

        # Clean up empty rows
        data = data.dropna(how='all')

        # Output the dataframe to csv
        data.to_csv(output_csv, index=False)

        print(f"Successfully converted PDF to CSV: {output_csv}")
        print(f"Processed {len(data)} rows")

        # Show sample
        print("\nSample data:")
        print(data.head(10).to_string())

    except Exception as e:
        print(f"Error converting PDF: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
