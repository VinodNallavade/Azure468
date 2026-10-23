import os
import time
from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def read_root():
    return {
        "message": "Hello from Python inside Azure Container Registry!",
        "environment": os.getenv("ENV", "production")
    }

@app.get("/health")
def health_check():
    return {
        "status": "UP",
        "timestamp": time.time()
    }