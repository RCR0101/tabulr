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
) -> pd.DataFrame():
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
        print("Usage: python converter.py <input_pdf_path> [output_csv_path]")
        sys.exit(1)
    
    input_pdf = sys.argv[1]
    output_csv = sys.argv[2] if len(sys.argv) > 2 else "output.csv"
    
    # Check if input file exists
    if not os.path.exists(input_pdf):
        print(f"Error: Input PDF file not found: {input_pdf}")
        sys.exit(1)
    
    print(f"Converting {input_pdf} to {output_csv}")
    
    # headers to remove from the table
    headers: list[str] = ["COMP\nCODE", "DRAFT TIMETABLE I SEM 2025 - 26", "TIMETABEL I SEM 2025 -26"]

    # page range to extract the timetable from
    # [from, to] - extracting all pages
    page_range: list[int] = [7, 59]

    try:
        pdf: pdfplumber.pdf.PDF = pdfplumber.open(input_pdf)
        
        # Use all pages or specified range
        total_pages = len(pdf.pages)
        end_page = min(page_range[1], total_pages)
        
        pages: list[pdfplumber.page.Page] = pdf.pages[page_range[0] - 1 : end_page]

        data: pd.DataFrame = convert_timetable_to_csv(pages, headers)

        # output the dataframe to csv
        data.to_csv(output_csv, index=False)
        
        print(f"Successfully converted PDF to CSV: {output_csv}")
        print(f"Processed {len(data)} rows")
        
    except Exception as e:
        print(f"Error converting PDF: {e}")
        sys.exit(1)