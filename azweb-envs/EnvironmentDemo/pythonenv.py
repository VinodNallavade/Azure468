import os
from flask import Flask

app = Flask(__name__)

@app.route("/")
def home():
    app_name = os.getenv("APP_NAME", "Local App")
    environment = os.getenv("ENVIRONMENT", "Development")
    message = os.getenv("WELCOME_MESSAGE", "Hello!")

    return f"""
        <h1>{message}</h1>
        <p>App Name: {app_name}</p>
        <p>Environment: {environment}</p>
    """

if __name__ == "__main__":
    app.run()