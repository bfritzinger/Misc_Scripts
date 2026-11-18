# Meeting Note Template Generator

A simple Python script that generates meeting note templates in your preferred format.

## Features

- Prompts for a meeting title (used in filename and document header)
- Choose your save location or use the current directory
- Three output formats:
  - **Markdown (.md)** - For use with markdown editors or plain text
  - **Word Document (.docx)** - For Microsoft Word or compatible editors
  - **Plain Text (.txt)** - Opens with any text editor

## Requirements

- Python 3.x
- `python-docx` library (only required for Word document output)

## Installation

1. Download `Meeting_Note_Template_generator.py` to your computer

2. (Optional) Install the Word document library if you want .docx support:
   ```
   pip install python-docx
   ```

## Usage

1. Open a command prompt or terminal

2. Navigate to the folder containing the script:
   ```
   cd C:\path\to\script
   ```

3. Run the script:
   ```
   python Meeting_Note_Template_generator.py
   ```

4. Follow the prompts:
   ```
   Enter meeting title: Weekly Team Standup

   Where would you like to save the file?
     (Press Enter for current directory, or enter a path)
   Save location: C:\Users\YourName\Documents\Meetings

   Select output format:
     1. Markdown (.md)
     2. Word Document (.docx)
     3. Plain Text (.txt)
   Enter choice (1/2/3): 2

   Created: C:\Users\YourName\Documents\Meetings\Meeting_2025-12-13_Weekly_Team_Standup.docx
   ```

## Output Template

Each generated file includes the following sections:

- **Subject** - Pre-filled with your meeting title
- **Attendees** - Blank list for participant names
- **Topics** - Blank list for discussion items
- **Action Items** - Blank list for tasks and follow-ups
- **Notes** - Blank list for meeting notes

## Troubleshooting

**"python-docx not installed" error when selecting Word format:**
```
pip install python-docx
```

**"No module named 'typing_extensions'" error:**
```
pip install typing_extensions
```

**Still having issues with Word output?** Try a clean reinstall:
```
pip uninstall python-docx
pip install python-docx
```

## Notes

- The filename is automatically sanitized (spaces become underscores, special characters are removed)
- If the save directory doesn't exist, you'll be prompted to create it
- Markdown and Plain Text formats work without any additional librarie














































