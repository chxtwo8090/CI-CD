# app/Dockerfile
# Python 기반 웹 애플리케이션을 위한 경량 이미지
FROM python:3.11-slim

# 작업 디렉터리 설정
WORKDIR /app

# 필요한 패키지 복사 및 설치
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 애플리케이션 코드 복사
COPY . .

# 애플리케이션이 실행될 포트 (예: Gunicorn, Flask 등)
EXPOSE 8080

# 애플리케이션 실행 명령어 (실제 프로젝트에 맞게 수정 필요)
CMD ["python", "app.py"]