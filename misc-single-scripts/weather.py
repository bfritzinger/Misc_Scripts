import os
import sys

import requests

def get_weather(api_key, city):
    base_url = "http://api.openweathermap.org/data/2.5/weather"
    params = {
        'q': city,
        'appid': api_key,
        'units': 'imperial'
    }
    response = requests.get(base_url, params=params)
    if response.status_code == 200:
        data = response.json()
        weather = {
            'city': data['name'],
            'temperature': data['main']['temp'],
            'description': data['weather'][0]['description'],
            'humidity': data['main']['humidity'],
            'wind_speed': data['wind']['speed']
        }
        return weather
    else:
        return None

# Example usage:
api_key = os.environ.get('OPENWEATHER_API_KEY') or sys.exit('set OPENWEATHER_API_KEY')
city = 'Dover'
weather_info = get_weather(api_key, city)
if weather_info:
    print(f"City: {weather_info['city']}")
    print(f"Temperature: {weather_info['temperature']}°F")
    print(f"Description: {weather_info['description']}")
    print(f"Humidity: {weather_info['humidity']}%")
    print(f"Wind Speed: {weather_info['wind_speed']} MPH")
else:
    print("Error retrieving weather data.")

