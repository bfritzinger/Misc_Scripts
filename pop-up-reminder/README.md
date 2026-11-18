# POP - UP Reminder

A lightweight Windows utility that displays a popup reminder every 45 minutes prompting you to take a break.

## Features

- Simple popup notification every 45 minutes (configurable in .py file)
- Initial reminder on launch
- No admin privileges required
- Runs silently in the background (no console window)
- Single executable file with no dependencies

## Requirements

### For Running the Executable
- Windows OS

### For Building from Source
- Python 3.x
- PyInstaller

## Usage

### Running the Script Directly
```bash
python pop-up-reminderreminder.py
```

### Building the Executable
```bash
pip install pyinstaller
pyinstaller --onefile --noconsole pop-up-reminder-.py
```

The compiled executable will be located in the `dist/` folder.

## Auto-Start on Login (No Admin Required)

To have the reminder start automatically when you log in:

1. Press `Win + R`
2. Type `shell:startup` and press Enter
3. Copy a shortcut to `pop-up-reminder.exe` into this folder

## Customization

To modify the reminder interval or message, edit the following variables in `pop-up-reminder.py`:

```python
interval_minutes = 45  # Change the interval (in minutes)
title = "Reminder"
message = "Stretch and take a break!" #(input uyour reminder here)
```

Rebuild the executable after making changes.

## License

This project is provided as-is for personal use.
