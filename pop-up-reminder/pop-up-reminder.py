import ctypes
import time

def popup_message_box(title, message):
    ctypes.windll.user32.MessageBoxW(0, message, title, 0)

def main():
    interval_minutes = 45
    interval_seconds = interval_minutes * 60

    title = "Reminder"
    message = "Stretch and take a break!"

    # Initial popup on launch
    popup_message_box(title, message)

    while True:
        time.sleep(interval_seconds)
        popup_message_box(title, message)

if __name__ == "__main__":
    main()
