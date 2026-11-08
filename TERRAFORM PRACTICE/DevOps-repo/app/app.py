from flask import Flask, jsonify
import time, os

app = Flask(__name__)
START = time.time()

@app.route("/")
def index():
    return jsonify(service="releaseops-orders-api", env=os.getenv("APP_ENV", "dev"))

@app.route("/health")
def health():
    return jsonify(status="ok"), 200

@app.route("/metrics")
def metrics():
    return jsonify(uptime_seconds=round(time.time() - START, 2))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)