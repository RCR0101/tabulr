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
                transfer: bool = False
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
        pd.DataFrame(): The timetable as a pandas dataframe.
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
        print("Usage: python goa-conv.py <input_pdf_path> [output_csv_path]")
        sys.exit(1)
    
    input_pdf = sys.argv[1]
    output_csv = sys.argv[2] if len(sys.argv) > 2 else "output-goa.csv"
    
    # Check if input file exists
    if not os.path.exists(input_pdf):
        print(f"Error: Input PDF file not found: {input_pdf}")
        sys.exit(1)
    
    print(f"Converting Goa PDF {input_pdf} to {output_csv}")
    
    # Goa-specific headers to remove from the table
    headers: list[str] = [
        "BIRLA INSTITUTE OF TECHNOLOGY AND SCIENCE, PILANI- K. K. BIRLA GOA CAMPUS",
        "TIMETABLE FIRST SEMESTER 2025- 2026", 
        "BIRLA INSTITUTE",  # Keep this as fallback for partial matches
        "COMCODE",  # Remove repeated header rows
        "COURSE NO",
        "TIMETABLE SECOND SEMESTER 2025- 2026" # Remove column header rows
    ]

    # Goa page range to extract the timetable from
    # TODO: Update these page numbers based on actual Goa PDF structure
    page_range: list[int] = [3,35]  # Extract all pages for now

    try:
        pdf: pdfplumber.pdf.PDF = pdfplumber.open(input_pdf)
        
        # Use all pages if page_range[1] is -1, otherwise use specified range
        total_pages = len(pdf.pages)
        print(f"Total PDF pages: {total_pages}")
        print(f"Requested page range: {page_range[0]} to {page_range[1]}")
        
        if page_range[1] == -1:
            pages: list[pdfplumber.page.Page] = pdf.pages[page_range[0] - 1:]
            print(f"Extracting pages {page_range[0]} to end (indices {page_range[0] - 1} to {total_pages - 1})")
        else:
            end_page = min(page_range[1], total_pages)
            pages: list[pdfplumber.page.Page] = pdf.pages[page_range[0] - 1 : end_page]
            print(f"Extracting pages {page_range[0]} to {end_page} (indices {page_range[0] - 1} to {end_page - 1})")

        data: pd.DataFrame = convert_timetable_to_csv(pages, headers)

        # output the dataframe to csv
        data.to_csv(output_csv, index=False)
        
        print(f"Successfully converted Goa PDF to CSV: {output_csv}")
        print(f"Processed {len(data)} rows")
        
    except Exception as e:
        print(f"Error converting Goa PDF: {e}")
        sys.exit(1)