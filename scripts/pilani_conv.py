import pdfplumber
import pandas as pd

def remove_headers(
    table: list[list[str]], remove_rows_containing_any_of: list[str]
) -> list[list[str]]:
    """
    Function to remove headers from the table. I.e. remove rows that contain any of the strings in the list which do not contribute to the content of the timetable.
    Args:
        table (list[list[str]]): The table to remove the headers from.
        remove_rows_containing_any_of (list[str]): The list of strings to check for in the table, and remove the row if any of the strings are found.
    Returns:
        list[list[str]]: The table with the headers removed.
    """
    new_table: list[list[str]] = []
    for row in table:
        transfer: bool = True
        for string in remove_rows_containing_any_of:
            if string in row:
                transfer = False
                break
        if transfer:
            new_table.append(row)
    return new_table

def convert_timetable_to_csv(
    pages: list[pdfplumber.page.Page], headers: list[str]
) -> pd.DataFrame:
    """
    Function to convert the timetable to a pandas dataframe.
    Args:
        pages (list[pdfplumber.page.Page]): The pages to extract the timetable from.
        headers (list[str]): The headers to remove from the table.
    Returns:
        pd.DataFrame: The timetable as a pandas dataframe.
    """
    df = pd.DataFrame()
    for page in pages:
        table = page.extract_table()
        table = remove_headers(
            table,
            headers,
        )
        df = pd.concat([df, pd.DataFrame(table)])
    return df

if __name__ == "__main__":
    import sys
    import os
    
    # Get command line arguments
    if len(sys.argv) < 2:
        print("Usage: python coursewise_converter.py <input_pdf_path> [output_csv_path]")
        sys.exit(1)
    
    input_pdf = sys.argv[1]
    output_csv = sys.argv[2] if len(sys.argv) > 2 else "coursewise_timetable.csv"
    
    # Check if input file exists
    if not os.path.exists(input_pdf):
        print(f"Error: Input PDF file not found: {input_pdf}")
        sys.exit(1)
    
    print(f"Converting {input_pdf} to {output_csv}")
    
    # Headers to remove from the table - updated for coursewise timetable
    headers: list[str] = [
        "COURSEWISE TIMETABLE",
        "FIRST SEMESTER 2024-2025", 
        "COM\nCOD",
        "COURSE NO.",
        "COURSE TITLE",
        "CREDIT",
        "INSTRUCTOR-IN-CHARGE",
        "DAYS &\nHOURS",
        "MIDSEM\nDATE &\nSESSION",
        "COMPRE\nDATE &\nSESSION",
        "*Sections ending with",
        "L", "P", "U",
        "*There will be changes"
    ]
    
    # Page range to extract the timetable from
    # Update this range based on your PDF structure
    page_range: list[int] = [10, 74]  # Updated to 70 pages as mentioned
    
    try:
        with pdfplumber.open(input_pdf) as pdf:
            # Use all pages or specified range
            total_pages = len(pdf.pages)
            end_page = min(page_range[1], total_pages)
            pages: list[pdfplumber.page.Page] = pdf.pages[page_range[0] - 1 : end_page]
            
            data: pd.DataFrame = convert_timetable_to_csv(pages, headers)
            
            # Set column names to numbers 0-11
            if len(data.columns) > 0:
                data.columns = range(len(data.columns))
            
            # Output the dataframe to csv
            data.to_csv(output_csv, index=False)
            print(f"Successfully converted PDF to CSV: {output_csv}")
            print(f"Processed {len(data)} rows")
                
    except Exception as e:
        print(f"Error converting PDF: {e}")
        sys.exit(1)