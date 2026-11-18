from datetime import datetime
import os

# Get meeting title
meeting_title = input("Enter meeting title: ").strip()

# Get save location
print("\nWhere would you like to save the file?")
print("  (Press Enter for current directory, or enter a path)")
save_path = input("Save location: ").strip()

# Validate/create the save path
if save_path:
    save_path = os.path.normpath(os.path.expanduser(save_path))  # Normalize and handle ~
    if not os.path.exists(save_path):
        create_dir = input("Directory doesn't exist. Create it? (y/n): ").strip().lower()
        if create_dir == 'y':
            os.makedirs(save_path)
        else:
            print("Using current directory instead.")
            save_path = ""
    elif not os.path.isdir(save_path):
        print("Path exists but is not a directory. Using current directory instead.")
        save_path = ""

# Get format choice
print("\nSelect output format:")
print("  1. Markdown (.md)")
print("  2. Word Document (.docx)")
print("  3. Plain Text (.txt)")
format_choice = input("Enter choice (1/2/3): ").strip()

# Sanitize the title for use in filename
safe_title = meeting_title.replace(" ", "_")
safe_title = "".join(c for c in safe_title if c.isalnum() or c in "_-")

date_str = datetime.now().strftime('%Y-%m-%d')
date_display = datetime.now().strftime('%B %d, %Y')
base_filename = f"{safe_title}_Meeting_{date_str}"

# Combine save path with filename
if save_path:
    base_filename = os.path.normpath(os.path.join(save_path, base_filename))

if format_choice == "2":
    # Word Document
    try:
        from docx import Document
    except ImportError:
        print("Error: python-docx not installed. Run: pip install python-docx")
        exit(1)

    doc = Document()
    doc.add_heading(f"Meeting Notes - {date_display}", level=0)

    doc.add_heading(f"Subject: {meeting_title}", level=2)

    doc.add_heading("Attendees:", level=2)
    for _ in range(4):
        doc.add_paragraph("", style="List Bullet")

    doc.add_heading("Topics:", level=2)
    for _ in range(4):
        doc.add_paragraph("", style="List Bullet")

    doc.add_heading("Action Items:", level=2)
    for _ in range(4):
        doc.add_paragraph("", style="List Bullet")

    doc.add_heading("Notes:", level=2)
    for _ in range(4):
        doc.add_paragraph("", style="List Bullet")

    filename = f"{base_filename}.docx"
    doc.save(filename)

else:
    # Text-based formats (Markdown or Plain Text)
    if format_choice == "3":
        # Plain Text
        h1, h2, bullet = "", "", "  -"
        filename = f"{base_filename}.txt"
    else:
        # Default to Markdown
        h1, h2, bullet = "# ", "## ", "-"
        filename = f"{base_filename}.md"

    template = f"""{h1}Meeting Notes - {date_display}

{h2}Subject: {meeting_title}

{h2}Attendees:
{bullet}
{bullet}
{bullet}
{bullet}

{h2}Topics:
{bullet}
{bullet}
{bullet}
{bullet}

{h2}Action Items:
{bullet}
{bullet}
{bullet}
{bullet}

{h2}Notes:
{bullet}
{bullet}
{bullet}
{bullet}

"""
    with open(filename, "w") as f:
        f.write(template)

print(f"Created: {filename}")
