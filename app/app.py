# app/app.py

from flask import Flask

# Flask 인스턴스 생성
app = Flask(__name__)

# 루트 경로 ("/") 라우트 설정
@app.route("/")
def main():
    # Load Balancer를 통해 접속 시 사용자에게 보일 메시지
    return "<h1>🎉 증시 분석 페이지가 EKS에 성공적으로 배포되었습니다! 🎉</h1>"

# 🌟 중요: 로컬 개발 환경용 실행 코드입니다. 🌟
# Gunicorn 같은 WSGI 서버를 사용할 경우 이 블록은 EKS 환경에서 무시됩니다.
if __name__ == "__main__":
    # Dockerfile에 EXPOSE 8080으로 설정했으므로, 8080 포트를 사용합니다.
    # host='0.0.0.0'은 외부 접속을 허용합니다.
    app.run(host='0.0.0.0', port=8080)

# (실제 증시 데이터를 가져오는 로직은 이 main() 함수 내부 또는 다른 라우트에 추가되어야 합니다.)