from flask import Flask
app = Flask(__name__)

@app.route('/')
def hello():
    return "Hello from Flask (Dynamic API)! Use /api/ endpoint for API calls."

@app.route('/api/status')
def api_status():
    return '{"status": "UP", "service": "Flask API"}'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
