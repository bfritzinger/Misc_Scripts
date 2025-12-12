# Ollama Model Updater

This Python script checks for updates to available models on ollama.ai and installs them automatically. It also generates a log file of any updates installed, including the date and time.

## Requirements

- Python 3
- The `ollama` command line tool installed and configured

## Installation

1. Save the script to a file called `ollama-updater.py`.
2. Make sure you have Python 3 installed on your system.
3. Install the `ollama` command line tool by following the instructions [here](https://github.com/jmorganca/ollama).

## Usage

1. Run the script with Python:
    ```sh
    python ollama-updater.py
    ```
2. The script will check for updates to available models on ollama.ai and install them automatically if any are found.
3. If new updates were installed, a log entry will be added to the `ollama-update.log` file in the same directory as the script. The log entry includes the date and time, as well as the names of the updated models.
4. To view the log entries, you can open the `ollama-update.log` file with a text editor.